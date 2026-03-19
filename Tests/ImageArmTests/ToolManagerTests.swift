import XCTest
@testable import ImageArm

final class ToolManagerTests: XCTestCase {

    var toolManager: ToolManager!

    override func setUp() {
        super.setUp()
        toolManager = ToolManager()
    }

    // MARK: - find()

    func testFindReturnsStringOrNil() {
        // find() doit retourner un chemin ou nil, jamais crasher
        let result = toolManager.find("pngquant")
        if let path = result {
            XCTAssertFalse(path.isEmpty)
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path))
        }
    }

    func testFindUnknownToolReturnsNil() {
        XCTAssertNil(toolManager.find("outil_inexistant_xyz"))
    }

    func testFindMozJpegTranMatchesFind() {
        XCTAssertEqual(toolManager.findMozJpegTran(), toolManager.find("jpegtran"))
    }

    // MARK: - allTools()

    func testAllToolsCount() {
        let tools = toolManager.allTools()
        XCTAssertEqual(tools.count, 7) // pngquant, oxipng, pngcrush, cjpeg, jpegtran, svgo, cwebp
    }

    func testAllToolsHaveNames() {
        for tool in toolManager.allTools() {
            XCTAssertFalse(tool.name.isEmpty, "Outil sans nom détecté")
        }
    }

    func testAllToolsHaveInstallCommands() {
        for tool in toolManager.allTools() {
            XCTAssertFalse(tool.installCommand.isEmpty, "Outil \(tool.name) sans commande d'installation")
        }
    }

    func testToolInfoIsAvailable() {
        let tool = ToolManager.ToolInfo(name: "test", path: "/usr/bin/true", installCommand: "brew install test")
        XCTAssertTrue(tool.isAvailable)

        let missing = ToolManager.ToolInfo(name: "test", path: nil, installCommand: "brew install test")
        XCTAssertFalse(missing.isAvailable)
    }

    // MARK: - Outils droppés absents

    func testDroppedToolsNotInList() {
        let names = toolManager.allTools().map(\.name)
        XCTAssertFalse(names.contains("advpng"))
        XCTAssertFalse(names.contains("jpegoptim"))
        XCTAssertFalse(names.contains("gifsicle"))
    }

    func testDroppedToolsNotFound() {
        XCTAssertNil(toolManager.find("advpng"))
        XCTAssertNil(toolManager.find("jpegoptim"))
        XCTAssertNil(toolManager.find("gifsicle"))
    }
}
