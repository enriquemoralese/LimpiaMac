// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LimpiaMac",
    platforms: [.macOS(.v14)],
    targets: [
        // Reglas, escaneo y Papelera, sin interfaz, para poder probarlo.
        .target(name: "LimpiaNucleo"),
        // AVKit se enlaza explícito: Swift no lo enlaza solo y el reproductor tronaba al abrirse.
        .executableTarget(name: "LimpiaMac", dependencies: ["LimpiaNucleo"],
                          linkerSettings: [.linkedFramework("AVKit")]),
        .testTarget(name: "LimpiaNucleoTests", dependencies: ["LimpiaNucleo"]),
    ]
)
