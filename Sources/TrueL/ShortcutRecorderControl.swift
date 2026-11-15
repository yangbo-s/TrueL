import SwiftUI

struct ShortcutRecorderControl: View {
    @Bindable var store: ShortcutStore
    let action: ShortcutAction

    private var recording: Bool { store.recordingAction == action }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                if recording {
                    Text(store.recordingStrokes.isEmpty ? "按下快捷键…" : ShortcutDisplay.binding(.init(strokes: store.recordingStrokes)))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 80, alignment: .trailing)
                        .accessibilityIdentifier("TrueL.shortcut.recording.\(action.rawValue)")
                        .accessibilityValue(ShortcutDisplay.binding(.init(strokes: store.recordingStrokes)))
                    Button("保存") { store.commitRecording() }
                        .buttonStyle(TrueLButtonStyle(role: .primary))
                        .fixedSize()
                        .disabled(store.recordingStrokes.isEmpty || store.recordingError != nil)
                    Button("取消") { store.cancelRecording() }
                        .buttonStyle(TrueLButtonStyle())
                        .fixedSize()
                } else {
                    HStack(spacing: 4) {
                        Button { store.beginRecording(action: action) } label: {
                            Text(store.display(for: action))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                                .padding(.leading, 4)
                                .frame(maxWidth: .infinity, minHeight: SurfaceMetrics.embeddedSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(QuietIconStyle(isIconOnly: false, embedded: true))
                        .accessibilityLabel("录制\(action.title)快捷键")
                        .accessibilityValue(store.display(for: action))
                        .accessibilityIdentifier("TrueL.shortcut.\(action.rawValue)")
                        if store.bindings[action] != nil {
                            Button { store.clearBinding(for: action) } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                                    .frame(width: SurfaceMetrics.embeddedSize, height: SurfaceMetrics.embeddedSize).contentShape(Rectangle())
                            }
                            .buttonStyle(QuietIconStyle(embedded: true))
                            .foregroundStyle(Theme.secondary)
                            .accessibilityLabel("清除\(action.title)快捷键")
                        }
                    }
                    .padding(4)
                    .frame(width: 144, height: SurfaceMetrics.controlHeight)
                    .modifier(TrueLField())
                    .help(store.display(for: action))
                }
            }
        }
        .tint(Theme.resultBlue)
        .onDisappear { if recording { store.cancelRecording() } }
        .help("点击后按下组合键或连续按键，再点保存。连续按键间隔不超过 1 秒；Esc 取消。")
    }
}
