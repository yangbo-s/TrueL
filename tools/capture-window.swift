#!/usr/bin/env swift
// Inspect an already running app and capture one explicitly selected window.
// Never launches, activates, moves, resizes, closes, or sends input to the app.
import AppKit
import CoreGraphics
import ImageIO

let usage = """
usage:
  swift tools/capture-window.swift --bundle BUNDLE_ID --list
  swift tools/capture-window.swift --app /path/App.app --list
  swift tools/capture-window.swift --bundle BUNDLE_ID --window NUMBER --output /path/window.png
  swift tools/capture-window.swift --app /path/App.app --window NUMBER --output /path/window.png
Output is a native window PNG without shadow plus window.metadata.json. Existing files are refused.
--list only prints JSON. Capturing requires existing screen-recording access; no permission prompt is requested.
"""

struct CaptureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func fail(_ message: String) throws -> Never { throw CaptureError(message: message) }
func canonical(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath()
}
func writeJSON(_ object: Any, to url: URL? = nil) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    if let url { try data.write(to: url, options: .withoutOverwriting) }
    else { print(String(decoding: data, as: UTF8.self)) }
}
func windows() -> [[String: Any]] {
    CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
}
func record(_ window: [String: Any], app: NSRunningApplication) -> [String: Any] {
    [
        "windowNumber": window[kCGWindowNumber as String] ?? NSNull(),
        "ownerPID": app.processIdentifier,
        "bundleIdentifier": app.bundleIdentifier ?? "unknown",
        "appPath": app.bundleURL?.path ?? "unknown",
        "appIsActive": app.isActive,
        "windowIsKey": "unverified; app activation does not establish key-window state",
        "windowTitle": window[kCGWindowName as String] ?? NSNull(),
        "boundsPoints": window[kCGWindowBounds as String] ?? NSNull(),
        "isOnScreen": window[kCGWindowIsOnscreen as String] ?? false,
        "layer": window[kCGWindowLayer as String] ?? NSNull(),
        "alpha": window[kCGWindowAlpha as String] ?? NSNull()
    ]
}

var arguments = Array(CommandLine.arguments.dropFirst())
func take(_ option: String) throws -> String? {
    guard let index = arguments.firstIndex(of: option) else { return nil }
    guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
        try fail("Missing value for \(option)")
    }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return value
}

do {
    if arguments == ["--help"] { print(usage); exit(0) }
    let bundle = try take("--bundle")
    let appPath = try take("--app")
    let numberString = try take("--window")
    let outputPath = try take("--output")
    let list = arguments == ["--list"]
    if list { arguments.removeAll() }
    guard arguments.isEmpty, (bundle != nil) != (appPath != nil),
          (list && numberString == nil && outputPath == nil)
            || (!list && numberString != nil && outputPath != nil) else {
        print(usage); exit(2)
    }

    let appURL = appPath.map(canonical)
    let applications = NSWorkspace.shared.runningApplications.filter { app in
        if let bundle { return app.bundleIdentifier == bundle }
        return app.bundleURL.map { canonical($0.path) } == appURL
    }
    guard !applications.isEmpty else { try fail("No already running app matches the selector") }
    let byPID = Dictionary(uniqueKeysWithValues: applications.map { ($0.processIdentifier, $0) })
    let matching = windows().filter { window in
        guard let pid = window[kCGWindowOwnerPID as String] as? Int32 else { return false }
        return byPID[pid] != nil
    }
    if list {
        try writeJSON([
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "coordinateSpace": "CGWindow screen coordinates in points; origin at top-left of main display",
            "screenCaptureAccessAlreadyGranted": CGPreflightScreenCaptureAccess(),
            "windows": matching.compactMap { window -> [String: Any]? in
                guard let pid = window[kCGWindowOwnerPID as String] as? Int32, let app = byPID[pid] else { return nil }
                return record(window, app: app)
            }
        ])
        exit(0)
    }
    guard let numberString, let number = UInt32(numberString), number > 0,
          let selected = matching.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == number }),
          let pid = selected[kCGWindowOwnerPID as String] as? Int32, let app = byPID[pid] else {
        try fail("The explicit window number does not belong to the selected running app")
    }
    guard selected[kCGWindowIsOnscreen as String] as? Bool == true else {
        try fail("Selected window is not on screen; this tool will not show or activate it")
    }
    guard CGPreflightScreenCaptureAccess() else {
        try fail("Screen-recording access is not already granted; no permission request was made")
    }
    let output = canonical(outputPath!)
    guard output.pathExtension.lowercased() == "png" else { try fail("--output must end in .png") }
    let metadataURL = output.deletingPathExtension().appendingPathExtension("metadata.json")
    guard !FileManager.default.fileExists(atPath: output.path),
          !FileManager.default.fileExists(atPath: metadataURL.path) else {
        try fail("Refusing to overwrite an existing screenshot or metadata file")
    }
    guard FileManager.default.fileExists(atPath: output.deletingLastPathComponent().path) else {
        try fail("Output directory must already exist")
    }

    let beforeRecord = record(selected, app: app)
    let startedAt = Date()
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-o", "-l", String(number), output.path]
    try capture.run()
    capture.waitUntilExit()
    guard capture.terminationStatus == 0,
          let source = CGImageSourceCreateWithURL(output as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        try fail("Window capture failed (exit \(capture.terminationStatus)); no valid image metadata available")
    }
    let bounds = selected[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let width = bounds["Width"] ?? 0
    let height = bounds["Height"] ?? 0
    let after = windows().first { ($0[kCGWindowNumber as String] as? UInt32) == number }
    let afterBounds = after?[kCGWindowBounds as String] as? [String: Double]
    var metadata: [String: Any] = [
        "screenshot": output.path,
        "captureStartedAt": ISO8601DateFormatter().string(from: startedAt),
        "captureFinishedAt": ISO8601DateFormatter().string(from: Date()),
        "captureMethod": "screencapture -x -o -l WINDOW_NUMBER; native window only, no shadow, no cursor requested",
        "resampled": false,
        "pixels": [image.width, image.height],
        "before": beforeRecord,
        "windowBoundsUnchangedDuringCapture": afterBounds == bounds,
        "appearance": "unverified",
        "backdropAndPointerState": "unverified; record manually with comparison evidence",
        "comparisonConditionsMatched": false
    ]
    if let after { metadata["after"] = record(after, app: app) }
    if width > 0, height > 0 {
        let scaleX = Double(image.width) / width
        let scaleY = Double(image.height) / height
        metadata["pixelToPointScale"] = ["x": scaleX, "y": scaleY]
        metadata["uniformKnownScale"] = scaleX == scaleY && [1.0, 2.0].contains(scaleX)
    }
    try writeJSON(metadata, to: metadataURL)
    print("Captured \(output.path)\nMetadata \(metadataURL.path)")
} catch {
    fputs("capture-window: \(error.localizedDescription)\n", stderr)
    exit(1)
}
