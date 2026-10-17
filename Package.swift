// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OCLPDoctor",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "DoctorCore", targets: ["DoctorCore"]),
        .executable(name: "OCLPDoctor", targets: ["OCLPDoctorApp"]),
        .executable(name: "oclp-doctor", targets: ["DoctorCLI"])
    ],
    targets: [
        .target(name: "DoctorCore"),
        .executableTarget(name: "OCLPDoctorApp", dependencies: ["DoctorCore"]),
        .executableTarget(name: "DoctorCLI", dependencies: ["DoctorCore"]),
        .testTarget(name: "DoctorCoreTests", dependencies: ["DoctorCore"])
    ]
)
