import { Worker } from 'node:worker_threads';
import { createInterface } from 'node:readline';

// This bridge only transports requests. The existing desktop worker owns models and inference.
const workerPath = process.argv[2];
const cacheDir = process.argv[3];
const embeddingModel = 'Xenova/bge-small-en-v1.5';
const rerankerModel = 'Xenova/ms-marco-MiniLM-L-6-v2';
process.env.ORT_DISABLE_TELEMETRY = '1';
const worker = new Worker(workerPath, {
  workerData: { cacheDir },
  stdout: true,
  stderr: true,
});
worker.stdout.on('data', (data) => process.stderr.write(data));
worker.stderr.on('data', (data) => process.stderr.write(data));

let sequence = 0;
let initialized = false;
let rerankerInitialized = false;
let workerFailure;
const pending = new Map();
const cancelled = new Set();
const activeIDs = new Set();

function failWorker(error) {
  workerFailure = error;
  for (const promise of pending.values()) promise.reject(error);
  pending.clear();
}

worker.on('error', failWorker);
worker.on('exit', (code) => failWorker(new Error(`Desktop model worker exited (${code})`)));
worker.on('message', (message) => {
  // ready/downloadProgress have no id; they are not JSON RPC responses.
  if (typeof message?.id !== 'string') return;
  const promise = pending.get(message.id);
  if (!promise) return;
  pending.delete(message.id);
  if (message.success === true) promise.resolve(message.data);
  else promise.reject(new Error(message.error || 'Desktop model request failed'));
});

function request(type, fields = {}) {
  if (workerFailure) return Promise.reject(workerFailure);
  return new Promise((resolve, reject) => {
    const id = `worker-${++sequence}`;
    pending.set(id, { resolve, reject });
    worker.postMessage({ type, id, ...fields });
  });
}

async function execute(message) {
  if (message.type === 'embed') {
    if (!initialized) {
      const info = await request('init');
      if (info?.model !== embeddingModel || info?.dims !== 384) {
        throw new Error('Desktop embedding model is incompatible with the note database');
      }
      initialized = true;
    }
    if (cancelled.has(message.id)) return;
    return request('embed', { text: message.text });
  }
  if (message.type === 'rerank') {
    if (!rerankerInitialized) {
      const info = await request('initReranker');
      if (info?.model !== rerankerModel) throw new Error('Unexpected desktop reranking model');
      rerankerInitialized = true;
    }
    if (cancelled.has(message.id)) return;
    return request('rerank', { query: message.query, texts: message.texts });
  }
  throw new Error('Unsupported model request');
}

function reply(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

// The worker's async message listener permits concurrent initialization. Serialize complete jobs here.
let queue = Promise.resolve();
const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on('line', (line) => {
  let message;
  try { message = JSON.parse(line); } catch { return; }
  if (typeof message?.id !== 'string') return;
  if (message.type === 'cancel') {
    if (activeIDs.has(message.id)) cancelled.add(message.id);
    return;
  }
  if (activeIDs.has(message.id)) return;
  activeIDs.add(message.id);
  queue = queue.then(async () => {
    try {
      if (cancelled.has(message.id)) return;
      const data = await execute(message);
      if (!cancelled.has(message.id)) reply({ id: message.id, success: true, data });
    } catch (error) {
      if (!cancelled.has(message.id)) {
        reply({ id: message.id, success: false, error: error instanceof Error ? error.message : String(error) });
      }
    } finally {
      cancelled.delete(message.id);
      activeIDs.delete(message.id);
    }
  });
});
input.on('close', () => { void worker.terminate().finally(() => process.exit(0)); });
