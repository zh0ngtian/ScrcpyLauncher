import Darwin
import Foundation

@MainActor
public protocol ScrcpyClient: AnyObject {
    func prepare() throws
    func run(device: SavedDevice, tools: ToolPaths, logURL: URL) -> Int32
    func stop()
    func pressPower()
}

/// Runs the scrcpy SDL client in the host process, on Cocoa's main thread.
/// Its SDL event loop pumps the existing NSApplication and preserves its delegate/menu.
@MainActor
public final class EmbeddedScrcpyClient: ScrcpyClient {
    private typealias RunFunction = @convention(c) (
        UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>,
        UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>
    ) -> Int32
    private typealias StopFunction = @convention(c) () -> Void
    private var handle: UnsafeMutableRawPointer?
    private var runFunction: RunFunction?
    private var stopFunction: StopFunction?
    private var powerFunction: StopFunction?
    private let bundle: Bundle

    public init(bundle: Bundle = .main) { self.bundle = bundle }

    public func prepare() throws {
        guard handle == nil else { return }
        let library = bundle.bundleURL.appendingPathComponent("Contents/Frameworks/libscrcpy-client.dylib")
        guard let server = bundle.url(forResource: "scrcpy-server", withExtension: nil),
              FileManager.default.isReadableFile(atPath: server.path) else {
            throw LauncherError("App 内的 scrcpy server 资源缺失，请重新构建或安装 App。")
        }
        guard let loaded = dlopen(library.path, RTLD_NOW | RTLD_LOCAL) else {
            let detail = dlerror().map { String(cString: $0) } ?? "未知错误"
            throw LauncherError("无法载入 App 内的 scrcpy 客户端：\(detail)")
        }
        guard let run = dlsym(loaded, "sc_launcher_run"), let stop = dlsym(loaded, "sc_launcher_stop"),
              let power = dlsym(loaded, "sc_launcher_press_power") else {
            dlclose(loaded)
            throw LauncherError("App 内的 scrcpy 客户端接口不完整，请重新构建 App。")
        }
        handle = loaded
        runFunction = unsafeBitCast(run, to: RunFunction.self)
        stopFunction = unsafeBitCast(stop, to: StopFunction.self)
        powerFunction = unsafeBitCast(power, to: StopFunction.self)
        // Keep the library loaded for the app lifetime, including FFmpeg callbacks.
    }

    public func run(device: SavedDevice, tools: ToolPaths, logURL: URL) -> Int32 {
        guard let runFunction, let resources = bundle.resourceURL,
              let server = bundle.url(forResource: "scrcpy-server", withExtension: nil) else { return -1 }
        return device.serial.withCString { serial in
            tools.adb.path.withCString { adb in
                server.path.withCString { serverPath in
                    resources.path.withCString { icons in
                        logURL.path.withCString { log in
                            device.name.withCString { title in
                                runFunction(serial, adb, serverPath, icons, log, title)
                            }
                        }
                    }
                }
            }
        }
    }

    public func stop() { stopFunction?() }
    public func pressPower() { powerFunction?() }
}
