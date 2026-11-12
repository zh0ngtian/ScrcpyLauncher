import Foundation
import Testing
@testable import ScrcpyLauncherCore

struct DeviceTests {
    @Test func parsesUSBWirelessAndUnusableDevices() {
        let output = """
        * daemon not running; starting now at tcp:5037
        * daemon started successfully
        List of devices attached
        USB-123 device usb:123 product:pixel model:Pixel_9_Pro device:caiman transport_id:1
        192.168.1.10:5555 device product:phone model:Test_Phone transport_id:2
        denied unauthorized usb:234 transport_id:3
        disconnected offline transport_id:4
        rootless no permissions (missing udev rules)
        adb: unrelated diagnostic
        """
        let devices = ADBDevice.parse(output)
        #expect(devices.count == 5)
        #expect(devices.first { $0.serial == "USB-123" }?.displayName == "Pixel 9 Pro")
        #expect(devices.first { $0.serial == "USB-123" }?.isUSB == true)
        #expect(devices.first { $0.serial == "192.168.1.10:5555" }?.isUSB == false)
        #expect(devices.filter(\.isAuthorized).count == 2)
        #expect(devices.first { $0.serial == "rootless" }?.state == "no permissions")
    }

    @Test func emptyOrHeaderOnlyListDoesNotInventDevice() {
        #expect(ADBDevice.parse("").isEmpty)
        #expect(ADBDevice.parse("List of devices attached\n\n").isEmpty)
    }

    @Test func duplicateTransportRowsKeepStableSerialIdentity() {
        let devices = ADBDevice.parse("a device model:One\na device model:One\nb offline\n")
        #expect(devices.map(\.id) == ["a", "b"])
    }

    @MainActor @Test func defaultSurvivesRelaunchAndCanBeReplaced() throws {
        let suite = "ScrcpyLauncherTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DevicePreferences(defaults: defaults)
        #expect(preferences.defaultDevice == nil)
        preferences.save(SavedDevice(serial: "USB-123", name: "Pixel"))
        let reopened = LauncherModel(preferences: DevicePreferences(defaults: defaults))
        #expect(reopened.defaultDevice?.serial == "USB-123")
        #expect(reopened.selectedSerial == "USB-123")
        preferences.save(SavedDevice(serial: "192.168.1.10:5555", name: "Wireless"))
        let changed = LauncherModel(preferences: DevicePreferences(defaults: defaults))
        #expect(changed.defaultDevice?.serial == "192.168.1.10:5555")
        #expect(changed.defaultDevice?.name == "Wireless")
    }

    @MainActor @Test func missingSavedDeviceNeverSelectsOtherDeviceOrErasesPreference() throws {
        let suite = "ScrcpyLauncherTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DevicePreferences(defaults: defaults)
        preferences.save(SavedDevice(serial: "saved-but-disconnected", name: "My Phone"))
        let model = LauncherModel(preferences: preferences)
        #expect(model.selectedDevice == nil)
        #expect(model.saveSelection() == false)
        #expect(preferences.defaultDevice?.serial == "saved-but-disconnected")
    }

    @Test func finderPathIncludesHomebrewAndNeverSearchesWorkingDirectory() {
        let paths = ToolPaths.searchDirectories(environment: ["PATH": "/usr/bin:.:/bin:/usr/bin:"])
        #expect(paths.contains("/opt/homebrew/bin"))
        #expect(paths.contains("/usr/local/bin"))
        #expect(paths.contains(".") == false)
        #expect(paths.filter { $0 == "/usr/bin" }.count == 1)
    }
}
