// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Prompter",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Prompter", targets: ["Prompter"])],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0")
    ],
    targets: [
        .target(name: "PrompterCore"),
        .target(name: "PrompterLayout", dependencies: ["PrompterCore"]),
        .target(name: "PrompterSpeech", dependencies: [.product(name: "WhisperKit", package: "argmax-oss-swift")]),
        .executableTarget(name: "Prompter", dependencies: ["PrompterCore", "PrompterSpeech", "PrompterLayout", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "WhisperCheck", dependencies: ["PrompterSpeech", "PrompterCore", .product(name: "WhisperKit", package: "argmax-oss-swift")], path: "Tests/WhisperCheck"),
        .executableTarget(name: "PrompterChecks", dependencies: ["PrompterCore", "PrompterLayout"], path: "Tests/PrompterCoreTests")
    ]
)
