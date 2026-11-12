import AppKit
import ScrcpyLauncherCore
import SwiftUI

struct LaunchView: View {
    @Bindable var model: LauncherModel
    var onRetry: () -> Void
    var onSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 72, height: 72).accessibilityHidden(true)
            Text(model.session.isRunning ? "正在连接设备…" : "暂时无法投屏")
                .font(.title2.weight(.semibold))
            if let device = model.defaultDevice {
                Text("\(device.name) · \(device.serial)")
                    .font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if model.session.isRunning {
                ProgressView().controlSize(.small)
                Button("设置…", action: onSettings)
            } else {
                Text(model.displayedError ?? "连接 Android 设备后即可重新投屏。")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    Button("设置…", action: onSettings)
                    Button("重新连接", action: onRetry).buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.teal)
    }
}
