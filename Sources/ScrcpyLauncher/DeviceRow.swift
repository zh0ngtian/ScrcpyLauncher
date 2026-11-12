import ScrcpyLauncherCore
import SwiftUI

struct DeviceRow: View {
    let device: ADBDevice
    let isSelected: Bool
    let isDefault: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Image(systemName: device.isUSB ? "cable.connector" : "wifi")
                    .font(.title2)
                    .foregroundStyle(device.isAuthorized ? Color.accentColor : .secondary)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(device.displayName).font(.headline)
                        if isDefault {
                            Text("默认").font(.caption).padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    Text(device.serial).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(device.stateLabel).font(.caption)
                    .foregroundStyle(device.isAuthorized ? .secondary : Color.orange)
                    .multilineTextAlignment(.trailing)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                    .font(.title3)
                    .accessibilityHidden(true)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!device.isAuthorized)
        .accessibilityLabel("\(device.displayName)，序列号 \(device.serial)，\(device.stateLabel)\(isDefault ? "，默认设备" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
