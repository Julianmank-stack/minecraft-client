import XCTest
@testable import MetalCraftLauncher

final class CoreTests: XCTestCase {
    func testJavaMajorVersionTable() {
        XCTAssertEqual(JavaRuntimeManager.requiredMajor(forMinecraft: "1.16.5"), 8)
        XCTAssertEqual(JavaRuntimeManager.requiredMajor(forMinecraft: "1.17.1"), 16)
        XCTAssertEqual(JavaRuntimeManager.requiredMajor(forMinecraft: "1.18.2"), 17)
        XCTAssertEqual(JavaRuntimeManager.requiredMajor(forMinecraft: "1.20.4"), 17)
        XCTAssertEqual(JavaRuntimeManager.requiredMajor(forMinecraft: "1.20.5"), 21)
        XCTAssertEqual(JavaRuntimeManager.requiredMajor(forMinecraft: "1.21.4"), 21)
    }

    func testRendererFallbackChainTerminates() {
        for mode in RendererMode.allCases {
            var current: RendererMode? = mode
            var steps = 0
            while let m = current, steps < 10 {
                current = m.fallback
                steps += 1
            }
            XCTAssertLessThan(steps, 10, "Fallback chain for \(mode) must terminate")
        }
    }

    func testExperimentalMetalFallsBackToAppleSiliconMax() {
        XCTAssertEqual(RendererMode.metalExperimental.fallback, .appleSiliconMax)
        XCTAssertNil(RendererMode.safe.fallback)
    }

    func testMavenPath() {
        XCTAssertEqual(
            LoaderProfileService.mavenPath("net.fabricmc:fabric-loader:0.16.9"),
            "net/fabricmc/fabric-loader/0.16.9/fabric-loader-0.16.9.jar"
        )
        XCTAssertEqual(
            LoaderProfileService.mavenPath("org.ow2.asm:asm:9.6:natives"),
            "org/ow2/asm/asm/9.6/asm-9.6-natives.jar"
        )
        XCTAssertNil(LoaderProfileService.mavenPath("bad-coordinate"))
    }

    func testSHA1() {
        XCTAssertEqual(SHA1.hex(of: Data("abc".utf8)), "a9993e364706816aba3e25717850c26c9cd0d89d")
    }

    func testInstanceCodableRoundTrip() throws {
        var instance = Instance(
            id: UUID(),
            name: "Test",
            minecraftVersion: "1.21.4",
            loader: .init(type: .fabric, version: "0.16.9")
        )
        instance.renderer.crashCounts["metalExperimental"] = 1

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Instance.self, from: encoder.encode(instance))
        XCTAssertEqual(decoded, instance)
    }
}
