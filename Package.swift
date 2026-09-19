// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Experimental commands are never enabled by ordinary or release builds.
let experimentalCommands = ProcessInfo.processInfo.environment["STUDIO_EXPERIMENTAL_COMMANDS"] == "1"

let package = Package(
    name: "Prompter",
    platforms: [.macOS("13.3")],
    products: [.executable(name: "Prompter", targets: ["Prompter"])],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0")
    ],
    targets: [
        .binaryTarget(name: "llama", url: "https://github.com/ggml-org/llama.cpp/releases/download/b11053/llama-b11053-xcframework.zip", checksum: "f76d70daa0bc84b9fdb46e3fbf0ac8e8ed2301b8b2c3b67533ed4ba0f195e9cb"),
        .target(name: "PrompterCommands", dependencies: ["PrompterCore", "llama"]),
        .executableTarget(name: "CommandCheck", dependencies: ["PrompterCommands", "PrompterCore"], path: "Tests/CommandCheck"),
        .target(name: "PrompterCore"),
        .target(name: "PrompterLayout", dependencies: ["PrompterCore"]),
        .target(name: "PrompterSpeech", dependencies: [.product(name: "WhisperKit", package: "argmax-oss-swift")]),
        .executableTarget(name: "Prompter", dependencies: ["PrompterCore", "PrompterSpeech", "PrompterLayout", .product(name: "Sparkle", package: "Sparkle")] + (experimentalCommands ? [.target(name: "PrompterCommands")] : []),
            swiftSettings: experimentalCommands ? [.define("EXPERIMENTAL_COMMANDS")] : [],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "WhisperCheck", dependencies: ["PrompterSpeech", "PrompterCore", "PrompterCommands", .product(name: "WhisperKit", package: "argmax-oss-swift")], path: "Tests/WhisperCheck"),
        .executableTarget(name: "PrompterChecks", dependencies: ["PrompterCore", "PrompterLayout"], path: "Tests/PrompterCoreTests")
    ]
)
