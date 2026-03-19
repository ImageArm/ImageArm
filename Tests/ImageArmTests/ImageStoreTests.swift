import XCTest
@testable import ImageArm

/// Tests pour ImageStore — addFiles, filtrage, propriétés calculées
@MainActor
final class ImageStoreTests: XCTestCase {

    private var store: ImageStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        store = ImageStore()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - addFiles

    func testAddFilesWithSupportedExtensions() throws {
        let png = tempDir.appendingPathComponent("image.png")
        let jpg = tempDir.appendingPathComponent("photo.jpg")
        try "fake".write(to: png, atomically: true, encoding: .utf8)
        try "fake".write(to: jpg, atomically: true, encoding: .utf8)

        store.addFiles(urls: [png, jpg])
        XCTAssertEqual(store.files.count, 2)
    }

    func testAddFilesFiltersUnsupported() throws {
        let png = tempDir.appendingPathComponent("image.png")
        let txt = tempDir.appendingPathComponent("readme.txt")
        let pdf = tempDir.appendingPathComponent("doc.pdf")
        for url in [png, txt, pdf] {
            try "fake".write(to: url, atomically: true, encoding: .utf8)
        }

        store.addFiles(urls: [png, txt, pdf])
        XCTAssertEqual(store.files.count, 1, "Seul le PNG devrait être accepté")
    }

    func testAddFilesNoDuplicates() throws {
        let png = tempDir.appendingPathComponent("image.png")
        try "fake".write(to: png, atomically: true, encoding: .utf8)

        store.addFiles(urls: [png])
        store.addFiles(urls: [png]) // doublon
        XCTAssertEqual(store.files.count, 1, "Pas de doublons")
    }

    func testAddFilesHEIFSupported() throws {
        let heic = tempDir.appendingPathComponent("photo.heic")
        let heif = tempDir.appendingPathComponent("photo.heif")
        try "fake".write(to: heic, atomically: true, encoding: .utf8)
        try "fake".write(to: heif, atomically: true, encoding: .utf8)

        store.addFiles(urls: [heic, heif])
        XCTAssertEqual(store.files.count, 2)
    }

    // MARK: - Propriétés calculées

    func testInitialState() {
        XCTAssertTrue(store.files.isEmpty)
        XCTAssertFalse(store.isProcessing)
        XCTAssertEqual(store.totalSavings, 0)
        XCTAssertEqual(store.completedCount, 0)
    }

    func testCompletedCount() throws {
        let png1 = tempDir.appendingPathComponent("a.png")
        let png2 = tempDir.appendingPathComponent("b.png")
        try "fake".write(to: png1, atomically: true, encoding: .utf8)
        try "fake".write(to: png2, atomically: true, encoding: .utf8)

        store.addFiles(urls: [png1, png2])
        XCTAssertEqual(store.completedCount, 0)

        store.files[0].status = .done(savedBytes: 100)
        XCTAssertEqual(store.completedCount, 1)

        store.files[1].status = .alreadyOptimal
        XCTAssertEqual(store.completedCount, 2)
    }

    // MARK: - clearAll / clearCompleted

    func testClearAll() throws {
        let png = tempDir.appendingPathComponent("test.png")
        try "fake".write(to: png, atomically: true, encoding: .utf8)
        store.addFiles(urls: [png])
        XCTAssertEqual(store.files.count, 1)

        store.clearAll()
        XCTAssertTrue(store.files.isEmpty)
    }

    func testClearCompleted() throws {
        let a = tempDir.appendingPathComponent("a.png")
        let b = tempDir.appendingPathComponent("b.png")
        try "fake".write(to: a, atomically: true, encoding: .utf8)
        try "fake".write(to: b, atomically: true, encoding: .utf8)

        store.addFiles(urls: [a, b])
        store.files[0].status = .done(savedBytes: 50)
        // files[1] reste .pending

        store.clearCompleted()
        XCTAssertEqual(store.files.count, 1, "Seul le fichier pending devrait rester")
    }

    // MARK: - removeFiles

    func testRemoveFiles() throws {
        let a = tempDir.appendingPathComponent("a.png")
        let b = tempDir.appendingPathComponent("b.png")
        try "fake".write(to: a, atomically: true, encoding: .utf8)
        try "fake".write(to: b, atomically: true, encoding: .utf8)

        store.addFiles(urls: [a, b])
        let idToRemove = store.files[0].id
        store.removeFiles(Set([idToRemove]))
        XCTAssertEqual(store.files.count, 1)
    }

    // MARK: - supportedExtensions

    func testSupportedExtensions() {
        let expected = Set(["png", "jpg", "jpeg", "heic", "heif", "svg", "webp"])
        XCTAssertEqual(ImageStore.supportedExtensions, expected)
    }

    func testGIFNotSupported() {
        XCTAssertFalse(ImageStore.supportedExtensions.contains("gif"))
    }
}
