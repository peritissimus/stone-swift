// swift-tools-version: 6.0
import PackageDescription

// Each hexagonal layer is its own target, so the dependency rule is enforced by the compiler:
// a forbidden import simply does not resolve.
let package = Package(
    name: "StoneKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "StoneDomain", targets: ["StoneDomain"]),
        .library(name: "StoneApplication", targets: ["StoneApplication"]),
        .library(name: "StoneAdaptersOut", targets: ["StoneAdaptersOut"]),
        .library(name: "StoneUI", targets: ["StoneUI"]),
    ],
    targets: [
        // Pure: Foundation value types only. Decides, never does.
        .target(name: "StoneDomain"),
        // Use cases: orchestrate domain + out ports. No platform code.
        .target(name: "StoneApplication", dependencies: ["StoneDomain"]),
        // Driven adapters: filesystem, Stone's config, clock.
        .target(name: "StoneAdaptersOut", dependencies: ["StoneDomain"]),
        // Driving adapter: the capture panel. Talks to in-ports only.
        .target(name: "StoneUI", dependencies: ["StoneDomain"]),

        .testTarget(name: "StoneDomainTests", dependencies: ["StoneDomain"]),
        .testTarget(name: "StoneApplicationTests", dependencies: ["StoneDomain", "StoneApplication"]),
        .testTarget(name: "StoneAdaptersOutTests", dependencies: ["StoneDomain", "StoneAdaptersOut"]),
        .testTarget(name: "StoneUITests", dependencies: ["StoneDomain", "StoneUI"]),
    ]
)
