// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LimpiaMac",
    platforms: [.macOS(.v14)],
    targets: [
        // Reglas, escaneo y Papelera, sin interfaz, para poder probarlo.
        .target(name: "LimpiaNucleo"),
        .executableTarget(name: "LimpiaMac", dependencies: ["LimpiaNucleo"]),
        .testTarget(name: "LimpiaNucleoTests", dependencies: ["LimpiaNucleo"]),
    ]
)
