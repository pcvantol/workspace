// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkspaceClient",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "WorkspaceClient", targets: ["WorkspaceClient"])],
    targets: [
        .executableTarget(name: "WorkspaceClient"),
        .testTarget(name: "WorkspaceClientTests", dependencies: ["WorkspaceClient"], exclude: ["Fixtures"]),
    ]
)
