import AppKit
import ScrcpyLauncherCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: LauncherModel
    var onLaunch: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    defaultDeviceCard
                    devicePicker
                    diagnostics
                    messages
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.teal)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Scrcpy Launcher").font(.title2.weight(.semibold))
                Text("选好设备，下次打开即可投屏。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var defaultDeviceCard: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("默认设备", systemImage: "pin.fill").font(.caption).foregroundStyle(.secondary)
                if let device = model.defaultDevice {
                    Text(device.name).font(.headline)
                    Text(device.serial).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                } else {
                    Text("尚未设置").font(.headline)
                    Text("从下方列表选择一台设备。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            if model.session.isRunning {
                Button(model.session.isStopping ? "正在停止…" : "停止投屏", systemImage: "stop.fill") {
                    model.session.stop()
                }
                .disabled(model.session.isStopping)
            } else if model.defaultDevice != nil {
                Button("启动投屏", systemImage: "play.fill") { model.startDefault() }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var devicePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选择设备").font(.headline)
                Spacer()
                if model.isRefreshing { ProgressView().controlSize(.small) }
                Button("刷新设备", systemImage: "arrow.clockwise") {
                    Task { await model.refreshDevices() }
                }
                .disabled(model.isRefreshing)
            }
            if model.devices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cable.connector").font(.largeTitle).foregroundStyle(.tertiary)
                    Text(model.isRefreshing ? "正在查找设备…" : "尚未发现设备").font(.headline)
                    Text("连接 Android 设备，开启 USB 调试并允许此电脑。")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.devices) { device in
                            DeviceRow(device: device, isSelected: model.selectedSerial == device.serial,
                                      isDefault: model.defaultDevice?.serial == device.serial) {
                                model.selectedSerial = device.serial
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(model.devices.count) * 84, 210))
            }
            Text("只会连接你保存的序列号；连接其他设备不会改变默认选择。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var diagnostics: some View {
        DisclosureGroup("本机工具") {
            VStack(alignment: .leading, spacing: 6) {
                if let tools = model.tools {
                    Text("scrcpy：App 内置客户端 4.1")
                    Text("ADB：\(tools.adb.path)")
                } else {
                    Text("scrcpy 客户端随 App 提供；ADB 使用本机安装版本。")
                }
                Text("运行日志：\(model.session.logURL.path)")
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
        .font(.caption)
    }

    @ViewBuilder private var messages: some View {
        if let error = model.displayedError {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(error).textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.callout).foregroundStyle(.orange)
                if !model.session.errorDetails.isEmpty {
                    DisclosureGroup("查看错误详情") {
                        Text(model.session.errorDetails)
                            .font(.caption.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                }
            }
        } else if let notice = model.notice {
            Label(notice, systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Label("设置保存在此 Mac，按 ⌘, 可随时更换。", systemImage: "keyboard")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(model.session.isRunning ? model.statusText : "Scrcpy Launcher 2.0")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            Button("保存默认设备") { model.saveSelection() }
                .disabled(model.selectedDevice == nil)
            Button(model.session.isRunning && model.session.runningDevice?.serial != model.selectedSerial ? "保存并切换投屏" : "保存并投屏") {
                if model.saveAndLaunch() { onLaunch() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(model.selectedDevice == nil || model.session.isStopping)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }
}
