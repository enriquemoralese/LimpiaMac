// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "iClear",
    platforms: [.macOS(.v14)],
    targets: [
        // Reglas, escaneo y Papelera, sin interfaz, para poder probarlo.
        .target(name: "iClearNucleo"),
        // AVKit se enlaza explícito: Swift no lo enlaza solo y el reproductor tronaba al abrirse.
        .executableTarget(name: "iClear", dependencies: ["iClearNucleo"],
                          linkerSettings: [.linkedFramework("AVKit")]),
        .testTarget(name: "iClearNucleoTests", dependencies: ["iClearNucleo"]),
    ]
)
