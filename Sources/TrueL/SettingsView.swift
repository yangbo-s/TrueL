import SwiftUI

private typealias SettingsState<Value> = SwiftUI.State<Value>
private typealias SettingsFocus<Value: Hashable> = SwiftUI.FocusState<Value>

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, service, shortcuts, icons, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "通用"
        case .service: "AI 服务"
        case .shortcuts: "快捷键"
        case .icons: "图标"
        case .about: "关于"
        }
    }
}

struct SettingsView: View {
    @Bindable var preferences: Preferences
    @Bindable var service: ServiceConfiguration
    @Bindable var shortcuts: ShortcutStore
    @Bindable var permissions: SystemPermissions
    @Bindable var updater: AppUpdater
    @SettingsState<SettingsPage> private var page: SettingsPage

    init(preferences: Preferences, service: ServiceConfiguration, shortcuts: ShortcutStore,
         permissions: SystemPermissions, updater: AppUpdater = AppUpdater(enabled: false), initialPage: SettingsPage = .service) {
        self.preferences = preferences
        self.service = service
        self.shortcuts = shortcuts
        self.permissions = permissions
        self.updater = updater
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            WindowChrome(title: "TrueL 设置", dragIdentifier: "TrueL.settings.drag") { EmptyView() }
            HStack(spacing: 4) {
                ForEach(SettingsPage.allCases) { item in
                    Button { page = item } label: {
                        Text(item.title).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TrueLTabStyle(selected: page == item))
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }
            .padding(4)
            .modifier(TrueLIsland())
            .frame(maxWidth: 640)
            .padding(.horizontal, SurfaceMetrics.edge)
            .padding(.top, WindowChromeMetrics.contentGap)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: SurfaceMetrics.islandGap) {
                    switch page {
                    case .general: general
                    case .service: ServiceSettings(service: service)
                    case .shortcuts: shortcutsPage
                    case .icons: iconsPage
                    case .about: about
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SurfaceMetrics.edge)
                .padding(.top, SurfaceMetrics.islandGap)
                .padding(.bottom, SurfaceMetrics.edge)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .font(.system(size: TypeScale.value))
        .foregroundStyle(Theme.text)
        .frame(minWidth: SettingsLayout.width, minHeight: SettingsLayout.height)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: SurfaceMetrics.islandGap) {
            SettingsSection(title: "文字") {
                SettingsRow(title: "翻译目标") {
                    NativeSettingsMenu(selection: $preferences.language, choices: Preferences.supportedLanguages.map {
                        SettingsMenuChoice(value: $0, title: $0)
                    }, width: 144)
                    .frame(width: 144, height: 28)
                    .accessibilityLabel("翻译目标语言")
                }
                SettingsRow(title: "写作风格") {
                    NativeSettingsMenu(selection: $preferences.writingScene, choices: [
                        SettingsMenuChoice(value: "standard", title: "标准"),
                        SettingsMenuChoice(value: "professional", title: "专业"),
                        SettingsMenuChoice(value: "social", title: "社交"),
                    ], width: 144)
                    .frame(width: 144, height: 28)
                    .accessibilityLabel("写作风格")
                }
            }
            SettingsSection(title: "系统权限") {
                permissionRow("辅助功能", granted: permissions.accessibilityGranted,
                              action: permissions.openAccessibilitySettings)
                permissionRow("输入监控", granted: permissions.inputMonitoringGranted,
                              action: permissions.openInputMonitoringSettings)
            }
        }
        .onAppear { permissions.refresh() }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        SettingsRow(title: title) {
            Label(granted ? "已授权" : "未授权", systemImage: granted ? "checkmark.circle" : "circle")
                .font(.system(size: 12))
                .foregroundStyle(granted ? Theme.success : Theme.secondary)
            Button("打开设置", action: action)
                .buttonStyle(TrueLButtonStyle())
                .accessibilityLabel("打开\(title)权限设置")
        }
    }

    private var shortcutsPage: some View {
        VStack(alignment: .leading, spacing: SurfaceMetrics.rowGap) {
            shortcutRow(.clipboardTranslation)
            shortcutRow(.translation)
            shortcutRow(.grammar)
            shortcutRow(.selectionTranslation)
            shortcutRow(.selectionGrammar)
            TrueLInlineStatus(text: shortcuts.status, symbol: "keyboard")
                .padding(.top, 4)
        }
        .padding(SurfaceMetrics.inset)
        .modifier(TrueLIsland())
    }

    private var iconsPage: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SurfaceMetrics.relatedGap), count: 3),
                  spacing: SurfaceMetrics.relatedGap) {
            ForEach(AppIconStyle.allCases) { style in
                Button { preferences.appIcon = style } label: {
                    VStack(spacing: SurfaceMetrics.relatedGap) {
                        if let image = AppIconAssets.preview(for: style) {
                            Image(nsImage: image).renderingMode(.original).resizable().interpolation(.high)
                                .frame(width: 64, height: 64)
                        }
                        Text("\(style.rawValue) · \(style.title)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppIconChoiceStyle(selected: preferences.appIcon == style))
                .accessibilityIdentifier("TrueL.icon.\(style.rawValue)")
                .accessibilityLabel("\(style.rawValue)，\(style.title)")
                .accessibilityAddTraits(preferences.appIcon == style ? .isSelected : [])
                .help(style == .defaultStyle ? "默认应用图标" : "切换 Dock 图标")
            }
        }
        .padding(SurfaceMetrics.inset)
        .modifier(TrueLIsland())
    }

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: SurfaceMetrics.relatedGap) {
            SettingsRow(title: action.title) {
                ShortcutRecorderControl(store: shortcuts, action: action)
                    .frame(maxWidth: 368, alignment: .trailing)
            }
            if let error = shortcuts.recordingAction == action ? shortcuts.recordingError : shortcuts.registrationErrors[action] {
                TrueLInlineStatus(text: error, tone: .error, symbol: "exclamationmark.circle")
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: SurfaceMetrics.islandGap) {
            VStack(alignment: .leading, spacing: SurfaceMetrics.inset) {
                HStack(alignment: .firstTextBaseline, spacing: SurfaceMetrics.inset) {
                    TrueLWordmark(size: 24)
                    Text("读懂，再表达。")
                        .font(.system(size: TypeScale.value)).foregroundStyle(Theme.secondary)
                    Spacer(minLength: SurfaceMetrics.inset)
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")
                        .font(.system(size: TypeScale.control)).foregroundStyle(Theme.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SurfaceMetrics.inset)
            .modifier(TrueLIsland())
            SettingsSection(title: "更新") {
                SettingsRow(title: "自动检查更新") {
                    Toggle("自动检查更新", isOn: Binding(get: { updater.automaticallyChecksForUpdates }, set: updater.setAutomaticChecks))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                SettingsRow(title: "软件更新") {
                    Button("检查更新…", action: updater.checkForUpdates)
                        .buttonStyle(TrueLButtonStyle())
                        .disabled(!updater.canCheckForUpdates)
                }
            }
            SettingsSection(title: "隐私与服务") {
                Text("API Key 保存在 macOS 钥匙串。翻译与改写会将当前文本发送给所选模型对应的服务商。")
                    .font(.system(size: TypeScale.value)).foregroundStyle(Theme.secondary)
                    .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

}

private struct ServiceSettings: View {
    @Bindable var service: ServiceConfiguration
    @SettingsState<Bool> private var showsKey = false
    @SettingsFocus<Bool> private var keyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SurfaceMetrics.islandGap) {
            VStack(alignment: .leading, spacing: SurfaceMetrics.relatedGap) {
                SettingsFormRow(title: "模型系列") {
                    GeometryReader { geometry in
                        NativeSettingsMenu(selection: providerBinding, choices: AIProvider.allCases.map {
                            SettingsMenuChoice(value: $0.id, title: $0.displayName)
                        }, width: geometry.size.width)
                        .accessibilityLabel("选择模型系列")
                    }
                    .frame(height: SurfaceMetrics.controlHeight)
                }
                HStack(spacing: SurfaceMetrics.inset) {
                    HStack(spacing: 4) {
                        Text("API Key")
                        SettingsInfo(text: "API Key 保存在 macOS 钥匙串，仅发送给该系列对应的服务商进行验证和请求。")
                    }.frame(width: 96, alignment: .leading)
                    keyField
                }
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        Task { await service.saveKey() }
                    } label: {
                        HStack(spacing: SurfaceMetrics.relatedGap) {
                            if service.isVerifying { ProgressView().controlSize(.mini) }
                            Text("保存")
                        }
                    }
                    .buttonStyle(TrueLButtonStyle(role: service.isKeyVerified ? .secondary : .primary))
                    .disabled(!service.canSaveKey || service.isVerifying)
                    .accessibilityLabel("保存并验证 API Key")
                }
                status
            }
            .padding(SurfaceMetrics.inset)
            .modifier(TrueLIsland())
            VStack(alignment: .leading, spacing: SurfaceMetrics.relatedGap) {
                taskModelRow(.translation, title: "翻译模型")
                taskModelRow(.grammar, title: "改写模型")
                if let message = service.modelStatus {
                    TrueLInlineStatus(text: message, tone: service.modelError ? .error : .success,
                                      symbol: service.modelError ? "exclamationmark.circle" : "checkmark.circle")
                }
            }
            .padding(SurfaceMetrics.inset)
            .modifier(TrueLIsland())
        }
        .onChange(of: service.selectedProvider) { _, _ in
            showsKey = false
            keyFocused = false
        }
    }

    private func taskModelRow(_ mode: WorkMode, title: String) -> some View {
        SettingsFormRow(title: title) {
            GeometryReader { geometry in
                NativeSettingsMenu(selection: Binding(
                    get: { service.draftSelection(for: mode)?.id ?? "" },
                    set: { value in
                        if let selection = service.availableSelections.first(where: { $0.id == value }) {
                            service.setDraftModel(selection, for: mode)
                        }
                    }), choices: modelChoices, width: geometry.size.width)
                    .disabled(service.availableSelections.isEmpty)
                    .accessibilityLabel("选择\(title)")
                    .help(service.draftSelection(for: mode)?.modelID ?? "待载入")
            }
            .frame(height: SurfaceMetrics.controlHeight)
            Button("保存") { service.saveModel(for: mode) }
                .buttonStyle(TrueLButtonStyle(role: service.draftSelection(for: mode) != service.selection(for: mode) ? .primary : .secondary))
                .disabled(!service.canSaveModel(for: mode))
                .accessibilityLabel("保存\(title)")
        }
    }

    @ViewBuilder private var status: some View {
        if let status = service.status, !status.isEmpty {
            TrueLInlineStatus(text: status,
                              tone: service.isError ? .error : service.isVerifying ? .neutral : .success,
                              symbol: service.isError ? "exclamationmark.circle" : service.isVerifying ? "clock" : "checkmark.circle")
        }
    }

    private var providerBinding: Binding<String> {
        Binding(get: { service.selectedProvider.id }, set: { value in
            guard let provider = AIProvider.allCases.first(where: { $0.id == value }) else { return }
            service.switchProvider(provider)
        })
    }

    private var modelChoices: [SettingsMenuChoice] {
        let options = service.availableSelections.map {
            SettingsMenuChoice(value: $0.id, title: $0.modelID, group: $0.provider.displayName)
        }
        return [SettingsMenuChoice(value: "", title: options.isEmpty ? "待载入" : "请选择模型")] + options
    }

    private var keyField: some View {
        HStack(spacing: 8) {
            Group {
                if showsKey { TextField("", text: $service.draftKey) }
                else { SecureField("", text: $service.draftKey) }
            }
            .textFieldStyle(.plain).focused($keyFocused)
            .accessibilityLabel("\(service.selectedProvider.displayName) API Key")
            Button { showsKey.toggle() } label: {
                Image(systemName: showsKey ? "eye.slash" : "eye").font(.system(size: TypeScale.toolSymbol))
            }
            .buttonStyle(QuietIconStyle(embedded: true))
            .help(showsKey ? "隐藏 API Key" : "显示 API Key")
            .accessibilityLabel(showsKey ? "隐藏 API Key" : "显示 API Key")
        }
        .padding(.leading, SurfaceMetrics.inset).padding(.trailing, 4)
        .frame(height: SurfaceMetrics.controlHeight)
        .modifier(TrueLField(focused: keyFocused))
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: SurfaceMetrics.inset) {
            Text(title).lineLimit(1).layoutPriority(1)
            Spacer(minLength: SurfaceMetrics.inset)
            HStack(spacing: SurfaceMetrics.relatedGap) { content }
        }
        .frame(minHeight: SurfaceMetrics.controlHeight)
    }
}

private struct SettingsFormRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: SurfaceMetrics.inset) {
            Text(title).frame(width: 96, alignment: .leading)
            content
        }
        .frame(minHeight: SurfaceMetrics.controlHeight)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: SurfaceMetrics.relatedGap) {
            Text(title).font(.system(size: TypeScale.control, weight: .medium)).foregroundStyle(Theme.secondary)
            VStack(alignment: .leading, spacing: SurfaceMetrics.rowGap) { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SurfaceMetrics.inset)
        .modifier(TrueLIsland())
    }
}

private struct SettingsInfo: View {
    let text: String
    @SettingsState<Bool> private var isPresented = false
    var body: some View {
        Button { isPresented.toggle() } label: {
            Image(systemName: "info.circle").font(.system(size: 12))
        }
        .buttonStyle(QuietIconStyle(embedded: true))
        .accessibilityLabel(text).help(text)
        .popover(isPresented: $isPresented) {
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16).frame(width: 280)
        }
    }
}
