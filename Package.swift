// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClipAll",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "ClipAll", targets: ["ClipAll"]),
        .executable(name: "ClipAllPluginRunner", targets: ["ClipAllPluginRunner"]),
    ],
    targets: [
        .target(
            name: "ClipAllPluginProtocol",
            path: "ClipAllPluginProtocol"
        ),
        .executableTarget(
            name: "ClipAll",
            dependencies: ["ClipAllPluginProtocol"],
            path: "ClipAll",
            linkerSettings: [
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "ClipAllPluginRunner",
            dependencies: ["ClipAllPluginProtocol"],
            path: "ClipAllPluginRunner",
            linkerSettings: [
                .linkedFramework("JavaScriptCore"),
            ]
        ),
    ]
)
