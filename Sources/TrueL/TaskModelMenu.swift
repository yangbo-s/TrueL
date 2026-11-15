import AppKit
import SwiftUI

struct TaskModelMenu: NSViewRepresentable {
    @Bindable var service: ServiceConfiguration
    var mode: WorkMode
    var onSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        service.selection(for: mode)?.modelID ?? (service.availableSelections.isEmpty ? "配置 AI 服务" : "选择模型")
    }
    private var width: CGFloat {
        min(220, ceil((title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: TypeScale.control)]).width) + 28)
    }
    func makeNSView(context: Context) -> SettingsMenuButton {
        SettingsMenuButton(frame: NSRect(x: 0, y: 0, width: width, height: SurfaceMetrics.controlHeight))
    }
    func updateNSView(_ view: SettingsMenuButton, context: Context) {
        view.compact = true
        view.reduceMotion = reduceMotion
        view.title = title
        view.selection = service.selection(for: mode)?.id ?? ""
        view.choices = service.availableSelections.map {
            SettingsMenuChoice(value: $0.id, title: $0.modelID, group: $0.provider.displayName)
        } + [SettingsMenuChoice(value: "settings", title: "管理模型…", group: "设置")]
        view.onSelect = { value in
            if value == "settings" { onSettings() }
            else if let selection = service.availableSelections.first(where: { $0.id == value }) {
                service.selectModel(selection, for: mode)
            }
        }
        view.toolTip = title
        view.setAccessibilityLabel(mode == .translation ? "翻译模型" : "改写模型")
        view.setAccessibilityValue(title)
        view.refreshPalette(animated: false)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SettingsMenuButton, context: Context) -> CGSize? {
        CGSize(width: width, height: SurfaceMetrics.controlHeight)
    }
}
