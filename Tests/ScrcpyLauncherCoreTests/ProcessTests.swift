import Foundation
import Testing
@testable import ScrcpyLauncherCore

struct ProcessTests {
    @Test func nonzeroStatusAndDiagnosticsRemainAvailable() async throws {
        let result = try await CommandRunner.run(executable: URL(fileURLWithPath: "/bin/ls"),
                                                arguments: ["/nonexistent-scrcpy-test-\(UUID().uuidString)"], environment: [:])
        #expect(result.status != 0)
        #expect(result.output.contains("No such file or directory"))
    }

    @Test func timeoutStopsHungChildAndReportsError() async throws {
        await #expect(throws: LauncherError.self) {
            _ = try await CommandRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"),
                                            arguments: ["30"], environment: [:], timeout: .milliseconds(30))
        }
    }

    @Test func launchFailureCompletesWithoutHanging() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await CommandRunner.run(executable: URL(fileURLWithPath: "/nonexistent/scrcpy"),
                                            arguments: [], environment: [:])
        }
    }

    @MainActor @Test func integratedClientReceivesLiteralSerialAndKeepsFailureLog() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scrcpy-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = TestClient()
        let serial = "phone with spaces; $(touch SHOULD_NOT_EXIST) & 'quoted'"
        client.result = 7
        let session = ScrcpySession(logURL: directory.appendingPathComponent("session.log"), client: client)
        let tools = ToolPaths(adb: URL(fileURLWithPath: "/usr/bin/true"), environment: [:])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            session.onStopped = { continuation.resume() }
            do { try session.launch(device: SavedDevice(serial: serial, name: "Test Phone"), tools: tools) }
            catch { continuation.resume(throwing: error) }
        }
        #expect(client.serials == [serial])
        #expect(session.isRunning == false)
        #expect(session.lastError?.contains("7") == true)
        #expect(session.errorDetails == "test diagnostic")
    }

    @MainActor @Test func switchWaitsForPreviousClientToReturnAndDoesNotDuplicate() async throws {
        let client = TestClient()
        let session = ScrcpySession(client: client)
        let tools = ToolPaths(adb: URL(fileURLWithPath: "/usr/bin/true"), environment: [:])
        var finishCount = 0
        session.onFinished = { finishCount += 1 }
        let first = SavedDevice(serial: "first", name: "One")
        let second = SavedDevice(serial: "second", name: "Two")
        client.onRun = { device in
            if device == first { try! session.launch(device: second, tools: tools) }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            session.onStopped = { if !session.isRunning { continuation.resume() } }
            do {
                try session.launch(device: first, tools: tools)
                try session.launch(device: first, tools: tools)
            } catch { continuation.resume(throwing: error) }
        }
        #expect(client.serials == ["first", "second"])
        #expect(client.stopCount == 1)
        #expect(finishCount == 1) // Only the final user-ended session finishes the app.
        #expect(session.lastError == nil)
    }

    @MainActor @Test func requestedStopDoesNotFinishApplication() async throws {
        let client = TestClient()
        let session = ScrcpySession(client: client)
        let tools = ToolPaths(adb: URL(fileURLWithPath: "/usr/bin/true"), environment: [:])
        var didFinish = false
        session.onFinished = { didFinish = true }
        client.onRun = { _ in session.stop() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            session.onStopped = { continuation.resume() }
            do { try session.launch(device: SavedDevice(serial: "stopped", name: "Phone"), tools: tools) }
            catch { continuation.resume(throwing: error) }
        }
        #expect(!didFinish)
        #expect(!session.isRunning)
        #expect(client.stopCount == 1)
    }

    @MainActor @Test func stoppingBeforeScheduledStartCancelsClient() throws {
        let client = TestClient()
        let session = ScrcpySession(client: client)
        let tools = ToolPaths(adb: URL(fileURLWithPath: "/usr/bin/true"), environment: [:])
        try session.launch(device: SavedDevice(serial: "cancelled", name: "Phone"), tools: tools)
        session.stop()
        #expect(!session.isRunning)
        #expect(!session.isStopping)
        #expect(client.serials.isEmpty)
    }

    @MainActor @Test func powerPressOnlyReachesAnExecutingSession() async throws {
        let client = TestClient()
        let session = ScrcpySession(client: client)
        let tools = ToolPaths(adb: URL(fileURLWithPath: "/usr/bin/true"), environment: [:])
        session.pressPower()
        #expect(client.powerCount == 0)
        client.onRun = { _ in
            session.pressPower()
            #expect(client.powerCount == 1)
            session.stop()
            session.pressPower()
            #expect(client.powerCount == 1)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            session.onStopped = { continuation.resume() }
            do {
                try session.launch(device: SavedDevice(serial: "power", name: "Phone"), tools: tools)
                session.pressPower()
                #expect(client.powerCount == 0)
            } catch { continuation.resume(throwing: error) }
        }
        session.pressPower()
        #expect(client.powerCount == 1)
        #expect(client.stopCount == 1)
    }
}

@MainActor
private final class TestClient: ScrcpyClient {
    var serials: [String] = []
    var result: Int32 = 0
    var stopCount = 0
    var powerCount = 0
    var onRun: ((SavedDevice) -> Void)?
    func prepare() throws {}
    func run(device: SavedDevice, tools: ToolPaths, logURL: URL) -> Int32 {
        serials.append(device.serial)
        try? Data("test diagnostic".utf8).write(to: logURL)
        onRun?(device)
        return result
    }
    func stop() { stopCount += 1 }
    func pressPower() { powerCount += 1 }
}
