import AppKit
import SwiftUI

extension AppDelegate {
    private func selectPreviewModels() {
        guard let model = service.models.first else { return }
        for mode in WorkMode.allCases {
            service.selectModel(ModelSelection(provider: service.selectedProvider, modelID: model.id), for: mode)
        }
    }

    func takeSnapshots(directory: String) async {
        if ProcessInfo.processInfo.environment["APP_SNAPSHOT_SCOPE"] == "credentials" {
            await takeCredentialSnapshots(directory: directory)
            return
        }
        service.draftKey = "snapshot-only-placeholder"
        await service.saveKey()
        selectPreviewModels()
        // Let configuration observers settle before starting a fixture request.
        await pause(milliseconds: 150)
        if ProcessInfo.processInfo.environment["APP_SNAPSHOT_SCOPE"] == "alignment" {
            await takeAlignmentSnapshots(directory: directory)
            return
        }
        if ProcessInfo.processInfo.environment["APP_SNAPSHOT_SCOPE"] == "workflows" {
            await takeWorkflowSnapshots(directory: directory)
            return
        }
        preferences.alwaysOnTop = false
        let folder = URL(fileURLWithPath: directory)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { fputs("SNAPSHOT ERROR \(error)\n", stderr); NSApp.terminate(nil); return }
        var results: [[String: String]] = []
        for scheme in ["light", "dark"] {
            preferences.appearance = scheme
            NSApp.appearance = NSAppearance(named: scheme == "dark" ? .darkAqua : .aqua)
            settings?.orderOut(nil)
            if ProcessInfo.processInfo.environment["APP_SNAPSHOT_SCOPE"] == "icons" {
                showSettings(page: .icons)
                for style in AppIconStyle.allCases {
                    preferences.appIcon = style
                    await pause()
                    results.append(capture(settings!, name: "settings-icon-\(style.rawValue)-\(scheme)", folder: folder))
                }
                preferences.appIcon = .defaultStyle
                await pause()
                results.append(capture(settings!, name: "settings-icon-default-\(scheme)", folder: folder))
                continue
            }
            if ProcessInfo.processInfo.environment["APP_SNAPSHOT_SCOPE"] == "about" {
                showSettings(page: .about)
                await pause()
                results.append(capture(settings!, name: "settings-about-\(scheme)", folder: folder))
                continue
            }
            if ProcessInfo.processInfo.environment["APP_SNAPSHOT_SCOPE"] == "toolbar" {
                model.mode = .grammar
                model.loadSample(0)
                showPanel()
                model.showPreviewResult()
                for provider in AIProvider.allCases {
                    service.switchProvider(provider)
                    service.draftKey = "snapshot-only-placeholder"
                    await service.saveKey()
                    selectPreviewModels()
                    await pause()
                    results.append(capture(panel, name: "toolbar-\(provider.rawValue)-\(scheme)", folder: folder))
                }
                service.draftKey = ""
                await pause()
                results.append(capture(panel, name: "toolbar-unconfigured-\(scheme)", folder: folder))
                continue
            }
            setPresentation(.workspace)
            model.mode = .grammar
            model.reset()
            showPanel()
            await pause()
            results.append(capture(panel, name: "popup-empty-\(scheme)", folder: folder))
            model.input = "输入或粘贴原文"
            await pause()
            results.append(capture(panel, name: "popup-placeholder-match-\(scheme)", folder: folder))
            model.loadSample(0)
            showPanel()
            await pause()
            results.append(capture(panel, name: "popup-input-\(scheme)", folder: folder))
            preferences.alwaysOnTop = true
            await pause()
            results.append(capture(panel, name: "popup-pinned-\(scheme)", folder: folder))
            preferences.alwaysOnTop = false
            model.submit()
            await pause(milliseconds: 120)
            results.append(capture(panel, name: "popup-processing-\(scheme)", folder: folder))
            model.showPreviewResult()
            await pause()
            results.append(capture(panel, name: "popup-result-\(scheme)", folder: folder))
            model.copyResult()
            await pause()
            results.append(capture(panel, name: "popup-copied-\(scheme)", folder: folder))
            // Cancel the timed copy feedback before capturing the next resting state.
            model.showPreviewResult()
            panel.setContentSize(NSSize(width: PopupLayout.wideWidth, height: panel.frame.height))
            await pause()
            results.append(capture(panel, name: "popup-wide-\(scheme)", folder: folder))
            windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification, object: panel))
            var resized = panel.frame
            resized.size = NSSize(width: 960, height: 560)
            panel.setFrame(resized, display: true)
            windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification, object: panel))
            await pause()
            results.append(capture(panel, name: "popup-resized-\(scheme)", folder: folder))
            userPanelHeight = nil
            panel.setContentSize(NSSize(width: PopupPresentation.workspace.initialSize.width, height: panel.frame.height))
            resize(height: desiredHeight)
            model.mode = .translation
            model.showPreviewResult()
            await pause()
            results.append(capture(panel, name: "popup-translation-\(scheme)", folder: folder))
            model.input = Array(repeating: "阅读是一种缓慢的理解过程。好的翻译保留文字的意思，也让句子自然地连接起来。原文与译文应该有清楚的层级，让阅读可以从容继续。", count: 10).joined(separator: "\n\n")
            model.showPreviewResult()
            await pause()
            results.append(capture(panel, name: "popup-translation-long-\(scheme)", folder: folder))
            model.mode = .grammar
            model.input = "Your sentence is already clear."
            model.showPreviewResult()
            await pause()
            results.append(capture(panel, name: "popup-perfect-\(scheme)", folder: folder))
            model.loadSample(1)
            model.showPreviewResult()
            await pause()
            results.append(capture(panel, name: "popup-multiple-\(scheme)", folder: folder))
            model.input = Array(repeating: "Haha, enjoy~\n\nYou not the last one.", count: 8).joined(separator: "\n\n")
            model.showPreviewResult()
            await pause()
            results.append(capture(panel, name: "popup-long-\(scheme)", folder: folder))
            model.input = "Intro\n" + String(repeating: " ", count: 20)
                + String(repeating: "word", count: 30) + " You not the last one."
            model.showPreviewResult()
            await pause()
            results.append(capture(panel, name: "popup-indented-\(scheme)", folder: folder))
            model.loadSample(0)
            setPresentation(.quick)
            model.mode = .translation
            selectionContext.bind(canReplace: true)
            model.showPreviewResult()
            await pause()
            results.append(capture(panel, name: "selection-result-\(scheme)", folder: folder))
            model.copyResult()
            await pause()
            results.append(capture(panel, name: "selection-copied-\(scheme)", folder: folder))
            model.reset()
            await pause()
            results.append(capture(panel, name: "selection-empty-\(scheme)", folder: folder))
            model.loadSample(0)
            model.submit()
            await pause(milliseconds: 120)
            results.append(capture(panel, name: "selection-processing-\(scheme)", folder: folder))
            model.reportInputError("未能读取选区。请先复制文字，使用“翻译剪贴板”，或在设置中开启辅助功能权限。")
            await pause()
            results.append(capture(panel, name: "selection-error-\(scheme)", folder: folder))
            for page in SettingsPage.allCases {
                showSettings(page: page)
                await pause()
                results.append(capture(settings!, name: "settings-\(page.rawValue)-\(scheme)", folder: folder))
            }
            service.setDraftModel(ModelSelection(provider: .gemini, modelID: "preview-model-with-a-deliberately-long-context-window-name"), for: .translation)
            showSettings(page: .service)
            await pause()
            results.append(capture(settings!, name: "settings-long-model-\(scheme)", folder: folder))
            service.setDraftModel(ModelSelection(provider: .gemini, modelID: "preview-model"), for: .translation)
            service.switchProvider(.deepSeek)
            await pause()
            results.append(capture(settings!, name: "settings-unconfigured-\(scheme)", folder: folder))
            await service.saveKey()
            await pause()
            results.append(capture(settings!, name: "settings-service-error-\(scheme)", folder: folder))
            service.switchProvider(.gemini)
            await pause()
            selectPreviewModels()

            showSettings(page: .shortcuts)
            shortcuts.beginRecording(action: .selectionTranslation)
            shortcuts.record(ShortcutStroke(keyCode: 8, modifiers: [.control]), timestamp: 1)
            shortcuts.record(ShortcutStroke(keyCode: 8, modifiers: [.control]), timestamp: 1.2)
            await pause()
            results.append(capture(settings!, name: "settings-recording-\(scheme)", folder: folder))
            shortcuts.beginRecording(action: .selectionTranslation)
            if let stroke = ShortcutBinding.defaults[.translation]?.strokes.first {
                shortcuts.record(stroke, timestamp: 2)
            }
            await pause()
            results.append(capture(settings!, name: "settings-shortcut-error-\(scheme)", folder: folder))
            shortcuts.cancelRecording()

            showSettings(page: .service)
            settings?.setContentSize(NSSize(width: 900, height: SettingsLayout.height))
            await pause()
            results.append(capture(settings!, name: "settings-wide-\(scheme)", folder: folder))
            settings?.setContentSize(NSSize(width: SettingsLayout.width, height: SettingsLayout.height))
        }
        let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: folder.appendingPathComponent("captures.json"))
        fputs("SNAPSHOT done \(directory)\n", stderr)
        if ProcessInfo.processInfo.environment["APP_SNAPSHOT_REVIEW"] == "1" {
            snapshotRunning = false
            model.loadSample(0)
            handleShortcut(.translation)
            model.showPreviewResult()
        } else {
            NSApp.terminate(nil)
        }
    }

    private func takeWorkflowSnapshots(directory: String) async {
        let folder = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var records: [[String: String]] = []
        for scheme in ["light", "dark"] {
            preferences.appearance = scheme
            NSApp.appearance = NSAppearance(named: scheme == "dark" ? .darkAqua : .aqua)
            for mode in WorkMode.allCases {
                beginInput("Haha, enjoy~\n\nYou not the last one.", mode: mode,
                           canReplaceSelection: true, presentation: .quick)
                await pause(milliseconds: 120)
                records.append(capture(panel, name: "quick-\(mode.rawValue)-loading-\(scheme)", folder: folder))
                model.showPreviewResult()
                await pause()
                records.append(capture(panel, name: "quick-\(mode.rawValue)-result-\(scheme)", folder: folder))
                session.focus = .followUp
                model.followUp = "更简洁一些，保留轻松的语气"
                await pause()
                records.append(capture(panel, name: "quick-\(mode.rawValue)-refine-\(scheme)", folder: folder))
                panel.makeFirstResponder(nil)
                session.focus = .result
                model.followUp = ""
                selectionContext.clear()
                await pause()
                records.append(capture(panel, name: "quick-\(mode.rawValue)-readonly-\(scheme)", folder: folder))
                handleShortcut(mode == .translation ? .translation : .grammar)
                model.showPreviewResult()
                await pause()
                records.append(capture(panel, name: "workspace-\(mode.rawValue)-result-\(scheme)", folder: folder))
                session.focus = .followUp
                model.followUp = "使用更自然的表达"
                await pause()
                records.append(capture(panel, name: "workspace-\(mode.rawValue)-refine-\(scheme)", folder: folder))
            }
            beginInput("", mode: .translation, presentation: .quick)
            await pause()
            records.append(capture(panel, name: "quick-empty-\(scheme)", folder: folder))
            beginInput("A selected sentence.", mode: .translation, presentation: .quick)
            model.showPreviewError("请求未完成，请检查网络连接后重试。")
            await pause()
            records.append(capture(panel, name: "quick-error-\(scheme)", folder: folder))
        }
        let data = try? JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: folder.appendingPathComponent("captures.json"))
        fputs("SNAPSHOT done \(directory)\n", stderr)
        NSApp.terminate(nil)
    }

    private func takeAlignmentSnapshots(directory: String) async {
        let folder = URL(fileURLWithPath: directory)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { NSApp.terminate(nil); return }
        var results: [[String: String]] = []
        let source = "More performance work.\n• 42% less memory at startup\n• 40% less memory per chat\n• CPU usage: 20% → 8%\n每个聊天的内存占用减少 40%，阅读和输入保持相同字号。"
        for scheme in ["light", "dark"] {
            preferences.appearance = scheme
            NSApp.appearance = NSAppearance(named: scheme == "dark" ? .darkAqua : .aqua)
            for mode in WorkMode.allCases {
                model.mode = mode
                model.input = Array(repeating: mode == .translation ? source : "Haha, enjoy~\n\nYou not the last one.", count: 8).joined(separator: "\n\n")
                showPanel()
                model.showPreviewResult()
                for width in [PopupPresentation.workspace.minimumWidth, CGFloat(960)] {
                    userPanelHeight = 520
                    panel.setContentSize(NSSize(width: width, height: 520))
                    await pause()
                    let positions: [CGFloat] = width == PopupPresentation.workspace.minimumWidth ? [0, 0.5, 1] : [0]
                    for fraction in positions {
                        let scrolls = panel.contentView.map { scrollViews(in: $0) } ?? []
                        for scroll in scrolls {
                            guard let document = scroll.documentView else { continue }
                            // NSTextView lays out lazily. Resolve the full document before
                            // calculating a programmatic scroll fraction for the screenshot.
                            if let text = document as? NSTextView, let container = text.textContainer {
                                text.layoutManager?.ensureLayout(for: container)
                            }
                            let travel = max(0, document.bounds.height - scroll.contentView.bounds.height)
                            let y = travel * (document.isFlipped ? fraction : 1 - fraction)
                            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                            scroll.reflectScrolledClipView(scroll.contentView)
                            scroll.flashScrollers()
                        }
                        await pause(milliseconds: 80)
                        let size = width == PopupPresentation.workspace.minimumWidth ? "compact" : "wide"
                        let position = fraction == 0 ? "top" : fraction == 1 ? "bottom" : "middle"
                        var record = capture(panel, name: "alignment-\(mode.rawValue)-\(size)-\(position)-\(scheme)", folder: folder)
                        record["scrollStyles"] = scrolls.map { $0.scrollerStyle == .overlay ? "overlay" : "legacy" }.joined(separator: ",")
                        results.append(record)
                    }
                }
            }
        }
        let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: folder.appendingPathComponent("captures.json"))
        fputs("SNAPSHOT done \(directory)\n", stderr)
        NSApp.terminate(nil)
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func takeCredentialSnapshots(directory: String) async {
        let folder = URL(fileURLWithPath: directory)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { NSApp.terminate(nil); return }
        var results: [[String: String]] = []
        for scheme in ["light", "dark"] {
            preferences.appearance = scheme
            NSApp.appearance = NSAppearance(named: scheme == "dark" ? .darkAqua : .aqua)
            service.switchProvider(.openAI)
            service.switchProvider(.gemini)
            showSettings(page: .service)
            await pause()
            results.append(capture(settings!, name: "credentials-locked-\(scheme)", folder: folder))
            service.authorizeSavedKey()
            await pause()
            results.append(capture(settings!, name: "credentials-restored-\(scheme)", folder: folder))
        }
        let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: folder.appendingPathComponent("captures.json"))
        fputs("SNAPSHOT done \(directory)\n", stderr)
        NSApp.terminate(nil)
    }

    private func pause(milliseconds: Int = 650) async {
        // Keep screenshots in a stable desktop area without persisting window placement.
        if let screen = panel.screen ?? NSScreen.main {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.frame.minX + 450, y: screen.frame.maxY - 130))
        }
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    private func capture(_ window: NSWindow, name: String, folder: URL) -> [String: String] {
        // Observe actual focus; never hide a lifecycle failure by refocusing for the screenshot.
        let file = folder.appendingPathComponent(name + ".png")
        // Never mistake a previous run's image for a successful new capture.
        if FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.removeItem(at: file)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), file.path]
        var method = "window-screencapture"
        var captured = false
        do {
            try process.run(); process.waitUntilExit()
            captured = process.terminationStatus == 0
        } catch { fputs("capture: \(error)\n", stderr) }
        if !captured || !FileManager.default.fileExists(atPath: file.path) {
            method = "view-bitmap-fallback-material-incomplete"
            if let view = window.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: file)
            }
        }
        fputs("SNAPSHOT \(file.path) [\(method)]\n", stderr)
        let header = window.contentView.flatMap { root in
            dragRegion(in: root).map { $0.convert($0.bounds, to: root) }
        }
        let headerWithinWindow = header.map {
            guard let root = window.contentView else { return false }
            return $0.height > 0 && root.bounds.insetBy(dx: -1, dy: -1).contains($0)
        } ?? false
        return ["name": name, "method": method, "path": file.path,
                "width": String(format: "%.1f", window.frame.width),
                "height": String(format: "%.1f", window.frame.height),
                "keyWindow": String(window.isKeyWindow),
                "presentation": session.presentation.rawValue,
                "returnAction": String(describing: session.returnAction(model: model)),
                "focus": String(describing: session.focus),
                "isProcessing": String(model.isProcessing),
                "hasResult": String(model.hasResult),
                "canSubmit": String(model.canSubmit),
                "scrollCount": String(window.contentView.map { scrollViews(in: $0).count } ?? 0),
                "windowNumber": String(window.windowNumber),
                "visibleContentWindows": String([panel, settings].compactMap { $0 }.filter { $0.isVisible }.count),
                "nativeWindowControls": String([NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
                    .compactMap { window.standardWindowButton($0) }.filter { !$0.isHidden && $0.isEnabled }.count),
                "headerWithinWindow": String(headerWithinWindow),
                "selectedAppIcon": preferences.appIcon.rawValue,
                "appliedAppIcon": appIconController.appliedStyle?.rawValue ?? "none",
                "backingScale": String(format: "%.1f", window.backingScaleFactor),
                "screen": window.screen?.localizedName ?? "unknown"]
    }

    private func dragRegion(in view: NSView) -> WindowDragView? {
        if let drag = view as? WindowDragView { return drag }
        for child in view.subviews {
            if let drag = dragRegion(in: child) { return drag }
        }
        return nil
    }
}
