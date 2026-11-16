// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TrueL",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "TrueL", targets: ["TrueL"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "CredentialCore"),
        .executableTarget(name: "TrueL", dependencies: ["CredentialCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "TrueLTests", dependencies: ["TrueL", "CredentialCore"])
    ],
    swiftLanguageModes: [.v6]
)
