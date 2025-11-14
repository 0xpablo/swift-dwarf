// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-dwarf",
    products: [
        .library(
            name: "DWARF",
            targets: ["DWARF"]
        ),
        .library(
            name: "DWARFSymbolication",
            targets: ["DWARFSymbolication"]
        )
    ],
    targets: [
        .target(
            name: "CLibdwarf",
            path: "libdwarf/src/lib/libdwarf",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../../../../Sources/CLibdwarf/include"),
                .define("LIBDWARF_BUILD", to: "1")
            ]
        ),
        .target(
            name: "DWARF",
            dependencies: ["CLibdwarf"]
        ),
        .target(
            name: "DWARFSymbolication",
            dependencies: ["DWARF", "CLibdwarf"],
            linkerSettings: [
                .linkedLibrary("stdc++", .when(platforms: [.linux]))
            ]
        ),
        .testTarget(
            name: "DWARFTests",
            dependencies: ["DWARF"],
            resources: [
                .copy("../Fixtures/TestProgram.dSYM")
            ]
        ),
        .testTarget(
            name: "DWARFSymbolicationTests",
            dependencies: [
                "DWARFSymbolication",
                "DWARF"
            ],
            resources: [
                .copy("../Fixtures/TestProgram.dSYM")
            ]
        )
    ]
)
