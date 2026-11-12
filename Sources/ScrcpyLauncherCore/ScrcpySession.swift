import Foundation
import Observation

@MainActor @Observable
public final class ScrcpySession {
    public private(set) var runningDevice: SavedDevice?
    public private(set) var isStopping = false
    public private(set) var lastError: String?
    public private(set) var errorDetails = ""
    @ObservationIgnored public var onFailure: (() -> Void)?
    @ObservationIgnored public var onStopped: (() -> Void)?
    @ObservationIgnored public var onFinished: (() -> Void)?
    @ObservationIgnored public var onWillStart: (() -> Void)?
    @ObservationIgnored private let client: any ScrcpyClient
    @ObservationIgnored private var startTimer: Timer?
    @ObservationIgnored private var isExecuting = false
    @ObservationIgnored private var pendingLaunch: (SavedDevice, ToolPaths)?
    @ObservationIgnored private var requestedStop = false

    public var isRunning: Bool { runningDevice != nil }
    public let logURL: URL

    public init(logURL: URL? = nil, client: any ScrcpyClient = EmbeddedScrcpyClient()) {
        self.client = client
        let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.playphone.ScrcpyLauncher")
        self.logURL = logURL ?? directory.appendingPathComponent("scrcpy.log")
    }

    public func launch(device: SavedDevice, tools: ToolPaths) throws {
        if isRunning {
            guard runningDevice?.serial != device.serial || isStopping else { return }
            pendingLaunch = (device, tools)
            terminateCurrent()
            return
        }
        try client.prepare()
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        clearError()
        runningDevice = device
        requestedStop = false
        onWillStart?()
        // Use a run-loop callback, not a Swift task/main-queue block: SDL pumps
        // Cocoa while running, and settings scans must remain free to execute.
        let timer = Timer(timeInterval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.run(device: device, tools: tools) }
        }
        startTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func stop() {
        pendingLaunch = nil
        terminateCurrent()
    }

    public func pressPower() {
        guard isExecuting, !isStopping else { return }
        client.pressPower()
    }

    public func clearError() {
        lastError = nil
        errorDetails = ""
    }

    private func run(device: SavedDevice, tools: ToolPaths) {
        startTimer = nil
        isExecuting = true
        let status = client.run(device: device, tools: tools, logURL: logURL)
        isExecuting = false
        didExit(status: status)
    }

    private func terminateCurrent() {
        guard isRunning else { return }
        requestedStop = true
        isStopping = true
        if isExecuting {
            client.stop()
        } else {
            startTimer?.invalidate()
            startTimer = nil
            didExit(status: 0)
        }
    }

    private func didExit(status: Int32) {
        let wasRequested = requestedStop
        runningDevice = nil
        isStopping = false
        requestedStop = false
        if let (device, tools) = pendingLaunch {
            pendingLaunch = nil
            do { try launch(device: device, tools: tools) }
            catch {
                lastError = error.localizedDescription
                onFailure?()
            }
        } else if status != 0 && !wasRequested {
            lastError = "投屏未能继续（退出码 \(status)）。请检查设备连接和调试授权，或在设置中更换默认设备。"
            if let handle = try? FileHandle(forReadingFrom: logURL) {
                defer { try? handle.close() }
                if let length = try? handle.seekToEnd() {
                    try? handle.seek(toOffset: length > 8_192 ? length - 8_192 : 0)
                    errorDetails = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
                }
            }
            onFailure?()
        } else if status == 0 && !wasRequested {
            // A user-closed scrcpy window finishes the app. A requested stop or
            // device switch must keep the settings/app alive.
            onFinished?()
        }
        onStopped?()
    }
}
