import Foundation

public struct LauncherError: LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct ToolPaths: Equatable, Sendable {
    public let adb: URL
    public let environment: [String: String]

    public init(adb: URL, environment: [String: String]) {
        self.adb = adb
        self.environment = environment
    }

    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ToolPaths {
        // Finder launches have a minimal PATH. Include both Apple Silicon and Intel Homebrew locations.
        let directories = searchDirectories(environment: environment)
        func locate(_ name: String) -> URL? {
            directories.lazy.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
                .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        }
        guard let adb = locate("adb") else {
            throw LauncherError("未找到 ADB。请先在本机安装 Android Platform Tools，再点“刷新设备”。")
        }
        var childEnvironment = environment
        childEnvironment["PATH"] = directories.joined(separator: ":")
        childEnvironment["ADB"] = adb.path
        return ToolPaths(adb: adb, environment: childEnvironment)
    }

    public static func searchDirectories(environment: [String: String]) -> [String] {
        let inherited = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let candidates = inherited + ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        return candidates.filter { $0.hasPrefix("/") && seen.insert($0).inserted }
    }

}
