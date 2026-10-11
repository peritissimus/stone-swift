import Foundation
import StoneDomain

/// Reuses Stone desktop's exact worker and model cache in a lazy, isolated Node process.
public actor DesktopModelService: ITextEmbedder, ITextReranker {
    public nonisolated let modelIdentifier = "Xenova/bge-small-en-v1.5"
    private let nodeURL: URL
    private let workerURL: URL
    private let cacheURL: URL
    private let bridgeURL: URL
    private let requestTimeout: Duration
    private let idleTimeout: Duration
    private let retryDelay: Duration
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var processGeneration = 0
    private var outputBuffer = Data()
    private var pending: [String: PendingRequest] = [:]
    private var idleTask: Task<Void, Never>?
    private var readerTask: Task<Void, Never>?
    private var outputContinuation: AsyncStream<Data>.Continuation?
    private var retryAfter: ContinuousClock.Instant?
    private var closed = false
    private nonisolated let writeQueue = DispatchQueue(label: "stone.desktop-model.stdin", qos: .utility)

    public enum Failure: Error, Equatable, Sendable {
        case missingNode
        case missingWorker
        case missingBridge
        case unavailable
        case timedOut
        case invalidResponse
        case requestTooLarge
        case worker(String)
    }

    private struct PendingRequest {
        let continuation: CheckedContinuation<[Double], any Error>
        let timeout: Task<Void, Never>
    }

    private struct Request: Encodable {
        let id: String
        let type: String
        var text: String?
        var query: String?
        var texts: [String]?
    }

    private struct Response: Decodable {
        let id: String
        let success: Bool
        let data: [Double]?
        let error: String?
    }

    public init(nodeURL: URL, workerURL: URL, cacheURL: URL) throws {
        guard let bridgeURL = Bundle.module.url(
            forResource: "desktop-model-bridge", withExtension: "mjs", subdirectory: "Resources")
        else { throw Failure.missingBridge }
        try self.init(nodeURL: nodeURL, workerURL: workerURL, cacheURL: cacheURL, bridgeURL: bridgeURL)
    }

    init(
        nodeURL: URL, workerURL: URL, cacheURL: URL, bridgeURL: URL,
        requestTimeout: Duration = .seconds(45), idleTimeout: Duration = .seconds(120),
        retryDelay: Duration = .seconds(30)
    ) throws {
        guard FileManager.default.isExecutableFile(atPath: nodeURL.path) else { throw Failure.missingNode }
        guard FileManager.default.isReadableFile(atPath: workerURL.path) else { throw Failure.missingWorker }
        guard FileManager.default.isReadableFile(atPath: bridgeURL.path) else { throw Failure.missingBridge }
        self.nodeURL = nodeURL
        self.workerURL = workerURL
        self.cacheURL = cacheURL
        self.bridgeURL = bridgeURL
        self.requestTimeout = requestTimeout
        self.idleTimeout = idleTimeout
        self.retryDelay = retryDelay
    }

    deinit {
        idleTask?.cancel()
        readerTask?.cancel()
        outputContinuation?.finish()
        output?.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
        try? input?.close()
    }

    public func embed(_ text: String) async throws -> TextEmbedding? {
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let vector = try await send(Request(id: UUID().uuidString, type: "embed", text: text))
        guard vector.count == 384, vector.allSatisfy(\.isFinite), vector.contains(where: { $0 != 0 })
        else { throw Failure.invalidResponse }
        return TextEmbedding(modelIdentifier: modelIdentifier, vector: vector)
    }

    public func rerank(query: String, texts: [String]) async throws -> [Double] {
        try Task.checkCancellation()
        guard !texts.isEmpty else { return [] }
        let scores = try await send(Request(id: UUID().uuidString, type: "rerank", query: query, texts: texts))
        guard scores.count == texts.count, scores.allSatisfy(\.isFinite) else { throw Failure.invalidResponse }
        return scores
    }

    public func shutdown() {
        closed = true
        stopProcess(failingWith: Failure.unavailable, shouldBackOff: false)
    }

    private func send(_ request: Request) async throws -> [Double] {
        try Task.checkCancellation()
        let encoded = try JSONEncoder().encode(request) + Data([0x0a])
        guard encoded.count <= 1_048_576 else { throw Failure.requestTooLarge }
        try startProcessIfNeeded()
        defer { scheduleIdleShutdownIfNeeded() }
        idleTask?.cancel()
        idleTask = nil
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let result: [Double] = try await withCheckedThrowingContinuation { continuation in
                let timeout = Task { [weak self, requestTimeout] in
                    do { try await Task.sleep(for: requestTimeout) }
                    catch { return }
                    await self?.requestTimedOut(request.id)
                }
                pending[request.id] = PendingRequest(continuation: continuation, timeout: timeout)
                enqueueWrite(encoded)
            }
            try Task.checkCancellation()
            return result
        } onCancel: {
            Task { await self.cancelRequest(request.id) }
        }
    }

    private func startProcessIfNeeded() throws {
        guard !closed else { throw Failure.unavailable }
        if process?.isRunning == true { return }
        if let retryAfter, ContinuousClock.now < retryAfter { throw Failure.unavailable }
        processGeneration += 1
        let generation = processGeneration
        let child = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        child.executableURL = nodeURL
        child.arguments = [bridgeURL.path, workerURL.path, cacheURL.path]
        child.standardInput = inputPipe
        child.standardOutput = outputPipe
        child.standardError = FileHandle.nullDevice
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        outputContinuation = continuation
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            // read(upToCount:) can wait to fill its count on a pipe; availableData returns this frame now.
            let data = handle.availableData
            if data.isEmpty { continuation.finish() }
            else { continuation.yield(data) }
        }
        // A single consumer preserves byte order when a JSON response spans multiple pipe reads.
        readerTask = Task { [weak self] in
            for await data in stream { await self?.receive(data, generation: generation) }
            await self?.processExited(generation: generation)
        }
        process = child
        input = inputPipe.fileHandleForWriting
        // A worker may exit during a queued write; report EPIPE rather than signaling the app.
        _ = fcntl(inputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        output = outputPipe.fileHandleForReading
        do { try child.run() }
        catch {
            stopProcess(failingWith: Failure.unavailable, shouldBackOff: true)
            throw Failure.unavailable
        }
    }

    private func receive(_ data: Data, generation: Int) {
        guard generation == processGeneration, process != nil else { return }
        guard !data.isEmpty else { return }
        outputBuffer.append(data)
        guard outputBuffer.count <= 1_048_576 else {
            stopProcess(failingWith: Failure.invalidResponse, shouldBackOff: true)
            return
        }
        while let newline = outputBuffer.firstIndex(of: 0x0a) {
            let line = Data(outputBuffer[..<newline])
            outputBuffer.removeSubrange(...newline)
            guard let response = try? JSONDecoder().decode(Response.self, from: line) else {
                stopProcess(failingWith: Failure.invalidResponse, shouldBackOff: true)
                return
            }
            guard let waiting = pending.removeValue(forKey: response.id) else { continue }
            waiting.timeout.cancel()
            if response.success, let values = response.data {
                waiting.continuation.resume(returning: values)
            } else {
                let failure = Failure.worker(response.error ?? "Invalid worker response")
                waiting.continuation.resume(throwing: failure)
                stopProcess(failingWith: failure, shouldBackOff: true)
                return
            }
        }
        scheduleIdleShutdownIfNeeded()
    }

    private func cancelRequest(_ id: String) {
        guard let waiting = pending.removeValue(forKey: id) else { return }
        waiting.timeout.cancel()
        waiting.continuation.resume(throwing: CancellationError())
        if let message = try? JSONEncoder().encode(Request(id: id, type: "cancel")) {
            enqueueWrite(message + Data([0x0a]))
        }
        scheduleIdleShutdownIfNeeded()
    }

    private func requestTimedOut(_ id: String) {
        guard pending[id] != nil else { return }
        stopProcess(failingWith: Failure.timedOut, shouldBackOff: true)
    }

    private func enqueueWrite(_ data: Data) {
        guard let input else {
            stopProcess(failingWith: Failure.unavailable, shouldBackOff: true)
            return
        }
        let generation = processGeneration
        // Pipe backpressure must never block this actor's cancellation and timeout handlers.
        writeQueue.async { [weak self] in
            do { try input.write(contentsOf: data) }
            catch { Task { await self?.writeFailed(generation: generation) } }
        }
    }

    private func writeFailed(generation: Int) {
        guard generation == processGeneration else { return }
        stopProcess(failingWith: Failure.unavailable, shouldBackOff: true)
    }

    private func processExited(generation: Int) {
        guard generation == processGeneration else { return }
        stopProcess(failingWith: Failure.unavailable, shouldBackOff: true)
    }

    private func scheduleIdleShutdownIfNeeded() {
        guard pending.isEmpty, process != nil else { return }
        idleTask?.cancel()
        let generation = processGeneration
        idleTask = Task { [weak self, idleTimeout] in
            do { try await Task.sleep(for: idleTimeout) }
            catch { return }
            await self?.shutDownIfIdle(generation: generation)
        }
    }

    private func shutDownIfIdle(generation: Int) {
        guard processGeneration == generation, pending.isEmpty else { return }
        stopProcess(failingWith: Failure.unavailable, shouldBackOff: false)
    }

    private func stopProcess(failingWith failure: Failure, shouldBackOff: Bool) {
        processGeneration += 1
        idleTask?.cancel()
        idleTask = nil
        readerTask?.cancel()
        readerTask = nil
        outputContinuation?.finish()
        outputContinuation = nil
        output?.readabilityHandler = nil
        // Terminating first releases a writer blocked on a full stdin pipe before handles are closed.
        if process?.isRunning == true { process?.terminate() }
        process = nil
        try? input?.close()
        try? output?.close()
        input = nil
        output = nil
        outputBuffer.removeAll(keepingCapacity: false)
        if shouldBackOff { retryAfter = ContinuousClock.now.advanced(by: retryDelay) }
        for waiting in pending.values {
            waiting.timeout.cancel()
            waiting.continuation.resume(throwing: failure)
        }
        pending.removeAll()
    }
}
