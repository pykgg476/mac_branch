// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GitBranchMenuBar",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "GitBranchMenuBar", targets: ["GitBranchMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "GitBranchMenuBar",
            path: "Sources/GitBranchMenuBar"
        )
    ]
)
