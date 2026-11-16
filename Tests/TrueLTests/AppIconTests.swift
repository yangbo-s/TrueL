import AppKit
import Testing
@testable import TrueL

@MainActor
struct AppIconTests {
    @Test func aNewInstallAndAnUnknownSavedIDUse3A() {
        withDefaults { defaults in
            #expect(Preferences(defaults: defaults).appIcon == .compactQuotes)
            defaults.set("removed-style", forKey: "TrueL.appIcon")
            #expect(Preferences(defaults: defaults).appIcon == .compactQuotes)
        }
    }

    @Test(arguments: AppIconStyle.allCases)
    func eachChoiceSurvivesRestart(_ style: AppIconStyle) {
        withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.appIcon = style
            let restarted = Preferences(defaults: defaults)
            #expect(restarted.appIcon == style)
            var applied: NSImage?
            var calls = 0
            let image = validImage()
            let controller = AppIconController(loadImage: { _ in image }, setImage: { applied = $0; calls += 1 })
            #expect(controller.apply(restarted.appIcon) == style)
            #expect(calls == 1)
            #expect(style == .defaultStyle ? applied == nil : applied === image)
        }
    }

    @Test func previewDoesNotReadOrWriteTheSavedIcon() {
        withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.appIcon = .literaryLigature
            let preview = Preferences(persist: false, defaults: defaults)
            #expect(preview.appIcon == .defaultStyle)
            preview.appIcon = .flowingQuotes
            #expect(Preferences(defaults: defaults).appIcon == .literaryLigature)
        }
    }

    @Test func liveChangesApplyImmediatelyAndDefaultRestoresTheBundleIcon() {
        var loaded: [AppIconStyle] = []
        var images: [NSImage?] = []
        let image = validImage()
        let controller = AppIconController(loadImage: { loaded.append($0); return image }, setImage: { images.append($0) })
        for style in AppIconStyle.allCases { #expect(controller.apply(style) == style) }
        #expect(loaded == AppIconStyle.allCases.filter { $0 != .defaultStyle })
        #expect(images.count == 6)
        #expect(images[3] == nil)
        controller.apply(.flowingQuotes)
        #expect(images.count == 6)
        controller.apply(.defaultStyle)
        #expect(images.count == 7)
        #expect(images.last! == nil)
        #expect(controller.appliedStyle == .defaultStyle)
    }

    @Test func missingOrCorruptImagesRecoverToDefault() {
        for image in [nil, NSImage()] as [NSImage?] {
            var applied: [NSImage?] = []
            let controller = AppIconController(loadImage: { _ in image }, setImage: { applied.append($0) })
            #expect(controller.apply(.openLigature) == .defaultStyle)
            #expect(controller.appliedStyle == .defaultStyle)
            #expect(applied.count == 1)
            #expect(applied[0] == nil)
        }
    }

    @Test(arguments: AppIconStyle.allCases)
    func shippedAssetsAreReadableAndHaveDockPadding(_ style: AppIconStyle) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resources = root.appendingPathComponent("Resources")
        let image = try #require(AppIconAssets.image(for: style, resourceURL: resources))
        let preview = try #require(AppIconAssets.image(for: style, preview: true, resourceURL: resources))
        #expect(image.isValid && preview.isValid)
        let rep = try #require(NSBitmapImageRep(data: Data(contentsOf: resources.appendingPathComponent("AppIcons/\(style.rawValue).png"))))
        #expect(rep.pixelsWide == 512 && rep.pixelsHigh == 512)
        #expect(rep.colorAt(x: 0, y: 256)?.alphaComponent == 0)
        #expect(rep.colorAt(x: 256, y: 0)?.alphaComponent == 0)
        #expect((rep.colorAt(x: 256, y: 256)?.alphaComponent ?? 0) > 0.9)
    }

    @Test(arguments: AppIconStyle.allCases)
    func windowMarksHaveTransparentCornersAndVisibleGlyphLayers(_ style: AppIconStyle) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for layer in ["ink", "accent"] {
            let url = root.appendingPathComponent("Resources/AppIcons/\(style.rawValue)-mark-\(layer).svg")
            let image = try #require(NSImage(contentsOf: url))
            let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            for (x, y) in [(0, 0), (0, bitmap.pixelsHigh - 1), (bitmap.pixelsWide - 1, 0),
                           (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)] {
                #expect(try #require(bitmap.colorAt(x: x, y: y)).alphaComponent == 0)
            }
            var visibleSamples = 0
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
                    if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { visibleSamples += 1 }
                }
            }
            #expect(visibleSamples > 5, "\(style.rawValue) \(layer) lost its glyph")
        }
    }

    private func validImage() -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill(); return true
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "TrueL.tests.icons.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }
}
