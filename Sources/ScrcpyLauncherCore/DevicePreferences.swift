import Foundation

public struct SavedDevice: Equatable, Sendable {
    public let serial: String
    public let name: String

    public init(serial: String, name: String) {
        self.serial = serial
        self.name = name
    }
}

@MainActor
public struct DevicePreferences {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var defaultDevice: SavedDevice? {
        guard let serial = defaults.string(forKey: "defaultDeviceSerial"), !serial.isEmpty else { return nil }
        return SavedDevice(serial: serial, name: defaults.string(forKey: "defaultDeviceName") ?? serial)
    }

    public func save(_ device: SavedDevice) {
        defaults.set(device.name, forKey: "defaultDeviceName")
        defaults.set(device.serial, forKey: "defaultDeviceSerial")
    }
}
