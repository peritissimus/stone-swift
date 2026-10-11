import Foundation
import Testing
import StoneDomain
@testable import StoneAdaptersOut

private let desktopTestNodeURL = [
        ProcessInfo.processInfo.environment["STONE_TEST_NODE_PATH"],
        ProcessInfo.processInfo.environment["STONE_NODE_PATH"],
        "/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node",
    ].compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }

@Suite(.enabled(if: desktopTestNodeURL != nil, "Requires a local Node runtime"))
struct DesktopModelServiceTests {
    static let nodeURL = desktopTestNodeURL

    @Test(.enabled(if: ProcessInfo.processInfo.environment["STONE_TEST_EMBEDDING_WORKER"] != nil,
                   "Opt-in smoke test against the installed desktop worker and cached models"))
    func actualDesktopWorkerEmbedsAndReranks() async throws {
        let environment = ProcessInfo.processInfo.environment
        let worker = URL(fileURLWithPath: try #require(environment["STONE_TEST_EMBEDDING_WORKER"]))
        let cache = URL(fileURLWithPath: try #require(environment["STONE_TEST_ML_CACHE"]))
        let service = try DesktopModelService(nodeURL: Self.nodeURL!, workerURL: worker, cacheURL: cache)
        do {
            let embedding = try await service.embed("A quiet stone garden with apple trees.")
            #expect(embedding?.vector.count == 384)
            #expect(embedding?.modelIdentifier == "Xenova/bge-small-en-v1.5")
            let scores = try await service.rerank(query: "apple orchard", texts: [
                "The orchard grows apples and pears.", "The spacecraft launches into lunar orbit.",
            ])
            #expect(scores.count == 2)
            #expect(scores[0] > scores[1])
            await service.shutdown()
        } catch {
            await service.shutdown()
            throw error
        }
    }

    @Test func bridgeReusesExactProtocolAndSerializesConcurrentModelLoads() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let worker = try writeWorker(in: directory)
        let service = try DesktopModelService(nodeURL: Self.nodeURL!, workerURL: worker, cacheURL: directory)
        async let first = service.embed("first")
        async let second = service.embed("second")
        let vectors = try await [first, second]
        #expect(vectors.allSatisfy { $0?.vector.count == 384 })
        #expect(Set(vectors.compactMap { $0?.vector.first }) == [1, 2])
        #expect(vectors.allSatisfy { $0?.modelIdentifier == "Xenova/bge-small-en-v1.5" })
        let scores = try await service.rerank(query: "query", texts: ["one", "two", "three"])
        #expect(scores == [-3.5, -2.5, -1.5])
        #expect(try await service.embed(" ") == nil)
        #expect(try await service.rerank(query: "query", texts: []).isEmpty)
        await service.shutdown()
        await #expect(throws: DesktopModelService.Failure.unavailable) { try await service.embed("closed") }
    }

    @Test func bridgeRejectsDifferentEmbeddingModel() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let worker = try writeWorker(in: directory, model: "different-model")
        let service = try DesktopModelService(nodeURL: Self.nodeURL!, workerURL: worker, cacheURL: directory)
        await #expect(throws: DesktopModelService.Failure.worker(
            "Desktop embedding model is incompatible with the note database")) { try await service.embed("test") }
        await service.shutdown()
    }

    @Test func malformedResponseFailsCleanly() async throws {
        let fixture = try helper("process.stdout.write('not-json\\n');")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let service = fixture.service
        await #expect(throws: DesktopModelService.Failure.invalidResponse) { try await service.embed("test") }
        await service.shutdown()
    }

    @Test func timeoutStopsProcessAndBacksOffRepeatedRequests() async throws {
        let fixture = try helper("", timeout: .milliseconds(80))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let service = fixture.service
        await #expect(throws: DesktopModelService.Failure.timedOut) { try await service.embed("test") }
        await #expect(throws: DesktopModelService.Failure.unavailable) { try await service.embed("retry") }
        await service.shutdown()
    }

    @Test func fullInputPipeCannotPreventRequestTimeout() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bridge = directory.appendingPathComponent("stalled-stdin.mjs")
        try "setInterval(() => {}, 1000);".write(to: bridge, atomically: true, encoding: .utf8)
        let service = try DesktopModelService(
            nodeURL: Self.nodeURL!, workerURL: bridge, cacheURL: directory, bridgeURL: bridge,
            requestTimeout: .milliseconds(100))
        await #expect(throws: DesktopModelService.Failure.timedOut) {
            try await service.embed(String(repeating: "x", count: 900_000))
        }
        await service.shutdown()
    }

    @Test func cancelledRequestDoesNotBlockNextRequest() async throws {
        let fixture = try helper("""
            if (request.type === 'embed' && request.text !== 'stall') {
              process.stdout.write(JSON.stringify({ id: request.id, success: true, data: [1, ...Array(383).fill(0)] }) + '\\n');
            }
            """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let service = fixture.service
        let task = Task { try await service.embed("stall") }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await service.embed("next")?.vector.count == 384)
        await service.shutdown()
    }

    @Test func validatesVectorAndRerankLengths() async throws {
        let fixture = try helper("""
            process.stdout.write(JSON.stringify({ id: request.id, success: true, data: [1, 2] }) + '\\n');
            """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let service = fixture.service
        await #expect(throws: DesktopModelService.Failure.invalidResponse) { try await service.embed("bad dimensions") }
        await #expect(throws: DesktopModelService.Failure.invalidResponse) {
            try await service.rerank(query: "test", texts: ["one"])
        }
        await service.shutdown()
    }

    @Test func idleWorkerStopsAndStartsFreshOnDemand() async throws {
        let fixture = try helper("""
            globalThis.calls = (globalThis.calls || 0) + 1;
            process.stdout.write(JSON.stringify({ id: request.id, success: true, data: [globalThis.calls, ...Array(383).fill(0)] }) + '\\n');
            """, idle: .milliseconds(40))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let service = fixture.service
        #expect(try await service.embed("first")?.vector.first == 1)
        try await Task.sleep(for: .milliseconds(150))
        #expect(try await service.embed("after idle")?.vector.first == 1)
        await service.shutdown()
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeWorker(in directory: URL, model: String = "Xenova/bge-small-en-v1.5") throws -> URL {
        let worker = directory.appendingPathComponent("worker.cjs")
        try """
        const { parentPort } = require('node:worker_threads');
        let busy = false, initCount = 0, embedCount = 0;
        parentPort.on('message', (message) => {
          if (busy) {
            parentPort.postMessage({ id: message.id, success: false, error: 'Concurrent model request' });
            return;
          }
          busy = true;
          setTimeout(() => {
            let data;
            if (message.type === 'init') {
              initCount++;
              data = { model: '\(model)', dims: 384 };
            } else if (message.type === 'initReranker') {
              data = { model: 'Xenova/ms-marco-MiniLM-L-6-v2' };
            } else if (message.type === 'embed') {
              data = initCount === 1 ? [++embedCount, ...Array(383).fill(0)] : [];
            } else if (message.type === 'rerank') {
              data = message.texts.map((_, index) => index - 3.5);
            }
            busy = false;
            parentPort.postMessage({ id: message.id, success: true, data });
          }, 10);
        });
        parentPort.postMessage({ type: 'ready' });
        parentPort.postMessage({ type: 'downloadProgress', model: 'embedding', progress: 100 });
        """.write(to: worker, atomically: true, encoding: .utf8)
        return worker
    }

    private func helper(
        _ response: String, timeout: Duration = .seconds(3), idle: Duration = .seconds(30)
    ) throws -> (directory: URL, service: DesktopModelService) {
        let directory = try temporaryDirectory()
        let bridge = directory.appendingPathComponent("helper.mjs")
        try """
        import { createInterface } from 'node:readline';
        const input = createInterface({ input: process.stdin });
        input.on('line', (line) => {
          const request = JSON.parse(line);
          if (request.type === 'cancel') return;
          \(response)
        });
        input.on('close', () => process.exit(0));
        """.write(to: bridge, atomically: true, encoding: .utf8)
        let service = try DesktopModelService(
            nodeURL: Self.nodeURL!, workerURL: bridge, cacheURL: directory, bridgeURL: bridge,
            requestTimeout: timeout, idleTimeout: idle)
        return (directory, service)
    }
}
