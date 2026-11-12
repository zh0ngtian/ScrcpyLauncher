import Foundation

public struct ADBDevice: Identifiable, Equatable, Sendable {
    public let serial: String
    public let state: String
    public let model: String?
    public let isUSB: Bool

    public var id: String { serial }
    public var isAuthorized: Bool { state == "device" }
    public var displayName: String { model?.replacingOccurrences(of: "_", with: " ") ?? serial }

    public var stateLabel: String {
        switch state {
        case "device": "可连接"
        case "unauthorized": "请在设备上允许 USB 调试"
        case "offline": "设备离线"
        case "no permissions": "没有访问权限"
        default: "暂不可用（\(state)）"
        }
    }

    public static func parse(_ output: String) -> [ADBDevice] {
        var seen = Set<String>()
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2,
                  fields[0] != "List", !fields[0].hasPrefix("*"),
                  !fields[0].hasSuffix(":"),
                  ["device", "offline", "unauthorized", "recovery", "sideload", "bootloader", "no"].contains(fields[1]),
                  seen.insert(fields[0]).inserted else { return nil }
            let model = fields.first(where: { $0.hasPrefix("model:") }).map { String($0.dropFirst(6)) }
            let state = fields[1] == "no" ? "no permissions" : fields[1]
            return ADBDevice(serial: fields[0], state: state, model: model,
                             isUSB: fields.contains(where: { $0.hasPrefix("usb:") }))
        }.sorted { $0.serial.localizedStandardCompare($1.serial) == .orderedAscending }
    }
}
