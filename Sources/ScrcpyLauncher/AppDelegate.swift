import AppKit
import ScrcpyLauncherCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = LauncherModel()
    private var settingsWindow: NSWindow?
    private var launchWindow: NSWindow?
    private weak var mirroringWindow: NSWindow?
    private var refreshTask: Task<Void, Never>?
    private var isQuitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey(_:)),
                                               name: NSWindow.didBecomeKeyNotification, object: nil)
        model.session.onWillStart = { [weak self] in
            self?.mirroringWindow = nil
            self?.showLaunchWindow()
        }
        model.session.onFailure = { [weak self] in
            guard let self, !self.isQuitting else { return }
            self.showLaunchWindow()
        }
        model.session.onFinished = { [weak self] in
            self?.isQuitting = true
            self?.refreshTask?.cancel()
        }
        model.session.onStopped = { [weak self] in
            guard let self else { return }
            if self.isQuitting {
                // terminateLater enters a Cocoa modal wait that prevents SDL's
                // loop from consuming the quit event. Finish this session first.
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            else if !self.model.session.isRunning && self.model.session.lastError == nil {
                self.launchWindow?.orderOut(nil)
            }
        }
        startOrShowWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        startOrShowWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        refreshTask?.cancel()
        guard model.session.isRunning else { return .terminateNow }
        isQuitting = true
        model.session.stop()
        return .terminateCancel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === launchWindow else { return true }
        NSApp.terminate(nil)
        return false
    }

    private func startOrShowWindow() {
        if model.session.isRunning {
            if let window = mirroringWindow {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else { showLaunchWindow() }
        } else if model.defaultDevice == nil {
            showSettings()
        } else {
            showLaunchWindow()
            _ = model.startDefault()
        }
    }

    @objc private func windowBecameKey(_ notification: Notification) {
        guard model.session.isRunning, let window = notification.object as? NSWindow,
              window !== settingsWindow, window !== launchWindow,
              String(describing: type(of: window)).contains("SDL") else { return }
        if mirroringWindow !== window { addPowerButton(to: window) }
        mirroringWindow = window
        launchWindow?.orderOut(nil)
    }

    private func addPowerButton(to window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.fullScreenMinHeight = 28
        accessory.view = NSView(frame: NSRect(x: 0, y: 0, width: 44, height: 28))

        let button = NSButton(frame: NSRect(x: 4, y: 0, width: 32, height: 28))
        button.image = NSImage(systemSymbolName: "power", accessibilityDescription: "电源键")
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.toolTip = "电源键：锁屏／唤醒"
        button.setAccessibilityLabel("电源键：锁屏或唤醒设备")
        button.identifier = NSUserInterfaceItemIdentifier("mirroring.power")
        button.target = self
        button.action = #selector(pressPower)
        accessory.view.addSubview(button)
        window.addTitlebarAccessoryViewController(accessory)
    }

    @objc private func pressPower() { model.session.pressPower() }

    private func configureMainMenu() {
        let menu = NSMenu()
        let application = NSMenu(title: "Scrcpy Launcher")
        application.addItem(withTitle: "关于 Scrcpy Launcher", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        application.addItem(.separator())
        let settings = application.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        application.addItem(.separator())
        application.addItem(withTitle: "隐藏 Scrcpy Launcher", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = application.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        application.addItem(withTitle: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        application.addItem(.separator())
        application.addItem(withTitle: "退出 Scrcpy Launcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let applicationItem = NSMenuItem()
        applicationItem.submenu = application
        menu.addItem(applicationItem)

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(.separator())
        let show = windowMenu.addItem(withTitle: "显示投屏", action: #selector(showMirroring), keyEquivalent: "1")
        show.target = self
        windowMenu.addItem(withTitle: "全部置于顶层", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openSettings() { showSettings() }
    @objc private func showMirroring() { startOrShowWindow() }

    private func showLaunchWindow() {
        if launchWindow == nil {
            let view = LaunchView(model: model, onRetry: { [weak self] in self?.startOrShowWindow() },
                                  onSettings: { [weak self] in self?.showSettings() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Scrcpy Launcher"
            window.delegate = self
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 480, height: 330))
            window.isReleasedWhenClosed = false
            window.center()
            launchWindow = window
        }
        launchWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(model: model, onLaunch: { [weak self] in
                self?.settingsWindow?.close()
            })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Scrcpy Launcher 设置"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 600, height: 560))
            window.minSize = NSSize(width: 560, height: 520)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        if settingsWindow?.isMiniaturized == true { settingsWindow?.deminiaturize(nil) }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !model.isRefreshing { refreshTask = Task { await model.refreshDevices() } }
    }
}
