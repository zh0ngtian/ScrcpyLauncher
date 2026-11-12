import Foundation
import Observation

@MainActor @Observable
public final class LauncherModel {
    public private(set) var defaultDevice: SavedDevice?
    public private(set) var devices: [ADBDevice] = []
    public var selectedSerial: String? {
        didSet { notice = nil }
    }
    public private(set) var isRefreshing = false
    public private(set) var tools: ToolPaths?
    public private(set) var scanError: String?
    public private(set) var launchError: String?
    public private(set) var notice: String?
    public let session: ScrcpySession
    @ObservationIgnored private let preferences: DevicePreferences

    public init(preferences: DevicePreferences = DevicePreferences(), session: ScrcpySession = ScrcpySession()) {
        self.preferences = preferences
        self.session = session
        defaultDevice = preferences.defaultDevice
        selectedSerial = preferences.defaultDevice?.serial
    }

    public var selectedDevice: ADBDevice? {
        devices.first { $0.serial == selectedSerial && $0.isAuthorized }
    }

    public var displayedError: String? { launchError ?? session.lastError ?? scanError }

    public var statusText: String {
        if session.isStopping { return "正在停止投屏…" }
        if let device = session.runningDevice { return "正在投屏：\(device.name)" }
        if displayedError != nil { return "投屏需要处理" }
        return defaultDevice == nil ? "请选择默认设备" : "投屏已停止"
    }

    public func refreshDevices() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        scanError = nil
        defer { isRefreshing = false }
        do {
            let resolved = try ToolPaths.resolve()
            tools = resolved
            let result = try await CommandRunner.run(executable: resolved.adb, arguments: ["devices", "-l"], environment: resolved.environment)
            try Task.checkCancellation()
            guard result.status == 0 else {
                throw LauncherError("ADB 无法读取设备：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            devices = ADBDevice.parse(result.output)
        } catch is CancellationError {
            // Closing the settings window cancels its scan without showing an error.
        } catch {
            devices = []
            scanError = error.localizedDescription
        }
    }

    @discardableResult
    public func saveSelection() -> Bool {
        guard let selectedDevice else { return false }
        let saved = SavedDevice(serial: selectedDevice.serial, name: selectedDevice.displayName)
        preferences.save(saved)
        defaultDevice = saved
        launchError = nil
        session.clearError()
        notice = "已保存，下次打开 App 会直接连接此设备。"
        return true
    }

    @discardableResult
    public func startDefault() -> Bool {
        guard let defaultDevice else { return false }
        launchError = nil
        session.clearError()
        do {
            let resolved = try ToolPaths.resolve()
            tools = resolved
            // Launch the saved serial directly. Never substitute another connected device.
            try session.launch(device: defaultDevice, tools: resolved)
            return true
        } catch {
            launchError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func saveAndLaunch() -> Bool {
        guard saveSelection() else { return false }
        return startDefault()
    }
}
