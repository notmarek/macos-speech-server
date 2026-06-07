import XCTest
import Yams

@testable import speech_server

final class NemotronConfigTests: XCTestCase {
    // MARK: - Engine parsing

    func testParseNemotronEngine() throws {
        let yaml = "stt:\n  engine: nemotron\n"
        let config = try YAMLDecoder().decode(ServerConfig.self, from: yaml)
        XCTAssertEqual(config.stt.engine, .nemotron)
    }

    // MARK: - NemotronSTTSettings defaults

    func testNemotronDefaultSettings() {
        let settings = NemotronSTTSettings()
        XCTAssertEqual(settings.chunkMs, 1120)
        XCTAssertNil(settings.language)
    }

    func testDefaultConfigHasNoNemotronBlock() {
        let config = ServerConfig()
        XCTAssertNil(config.stt.nemotron)
    }

    // MARK: - NemotronSTTSettings YAML parsing

    func testParseNemotronWithCustomChunkMs() throws {
        let yaml = """
            stt:
              engine: nemotron
              nemotron:
                chunk_ms: 560
            """
        let config = try YAMLDecoder().decode(ServerConfig.self, from: yaml)
        XCTAssertEqual(config.stt.engine, .nemotron)
        XCTAssertEqual(config.stt.nemotron?.chunkMs, 560)
        XCTAssertNil(config.stt.nemotron?.language)
    }

    func testParseNemotronWithLanguage() throws {
        let yaml = """
            stt:
              engine: nemotron
              nemotron:
                language: en-US
            """
        let config = try YAMLDecoder().decode(ServerConfig.self, from: yaml)
        XCTAssertEqual(config.stt.nemotron?.language, "en-US")
        XCTAssertEqual(config.stt.nemotron?.chunkMs, 1120)
    }

    func testParseNemotronWithAllSettings() throws {
        let yaml = """
            stt:
              engine: nemotron
              nemotron:
                chunk_ms: 2240
                language: fr-FR
            """
        let config = try YAMLDecoder().decode(ServerConfig.self, from: yaml)
        XCTAssertEqual(config.stt.nemotron?.chunkMs, 2240)
        XCTAssertEqual(config.stt.nemotron?.language, "fr-FR")
    }

    func testMinimalNemotronConfigUsesDefaults() throws {
        let yaml = "stt:\n  engine: nemotron\n"
        let config = try YAMLDecoder().decode(ServerConfig.self, from: yaml)
        let settings = config.stt.nemotron ?? NemotronSTTSettings()
        XCTAssertEqual(settings.chunkMs, 1120)
        XCTAssertNil(settings.language)
    }

    func testEmptyNemotronBlockUsesDefaults() throws {
        let yaml = """
            stt:
              engine: nemotron
              nemotron: {}
            """
        let config = try YAMLDecoder().decode(ServerConfig.self, from: yaml)
        let settings = config.stt.nemotron ?? NemotronSTTSettings()
        XCTAssertEqual(settings.chunkMs, 1120)
        XCTAssertNil(settings.language)
    }

    // MARK: - Coexistence with other engines

    func testParakeetBlockUnaffected() throws {
        let yaml = """
            stt:
              engine: parakeet
              parakeet:
                model_version: v2
            """
        let config = try YAMLDecoder().decode(ServerConfig.self, from: yaml)
        XCTAssertEqual(config.stt.engine, .parakeet)
        XCTAssertEqual(config.stt.parakeet?.modelVersion, "v2")
        XCTAssertNil(config.stt.nemotron)
    }
}
