import XCTest
@testable import ImageArm

/// Tests pour AppDelegate — ouverture multi-fichiers, pendingURLs, filtrage
@MainActor
final class AppDelegateTests: XCTestCase {

    private var delegate: AppDelegate!
    private var store: ImageStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        delegate = AppDelegate()
        store = ImageStore()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try "fake".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Cas : plusieurs fichiers ouverts en une seule fois

    func testMultipleFilesOpenedInSingleCall() async throws {
        let png1 = try makeFile("a.png")
        let png2 = try makeFile("b.png")
        let png3 = try makeFile("c.png")

        delegate.store = store
        delegate.application(NSApplication.shared, open: [png1, png2, png3])

        // Laisse les Task @MainActor se terminer
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(store.files.count, 3, "Les 3 fichiers doivent être ajoutés en un seul appel")
    }

    // MARK: - Cas : fichiers en attente avant que le store soit prêt

    func testPendingURLsAccumulatedWhenStoreIsNil() async throws {
        let png1 = try makeFile("x.png")
        let jpg1 = try makeFile("y.jpg")

        // Store pas encore assigné — simule le démarrage de l'app
        delegate.application(NSApplication.shared, open: [png1, jpg1])

        await Task.yield()

        // Store nil : rien dans store, mais processPendingFiles doit transférer
        delegate.store = store
        delegate.processPendingFiles()

        await Task.yield()

        XCTAssertEqual(store.files.count, 2, "Les fichiers en attente doivent être transférés au store")
    }

    // MARK: - Cas : processPendingFiles vide la liste

    func testProcessPendingFilesEmptiesQueue() async throws {
        let png = try makeFile("z.png")

        delegate.application(NSApplication.shared, open: [png])
        await Task.yield()

        delegate.store = store
        delegate.processPendingFiles()
        await Task.yield()

        // Un 2e appel ne doit rien ajouter (queue vidée)
        delegate.processPendingFiles()
        await Task.yield()

        XCTAssertEqual(store.files.count, 1, "processPendingFiles ne doit traiter les fichiers qu'une seule fois")
    }

    // MARK: - Cas : filtrage des extensions non supportées

    func testUnsupportedFilesAreIgnored() async throws {
        let png = try makeFile("image.png")
        let txt = try makeFile("readme.txt")
        let pdf = try makeFile("doc.pdf")

        delegate.store = store
        delegate.application(NSApplication.shared, open: [png, txt, pdf])

        await Task.yield()
        await Task.yield()

        XCTAssertEqual(store.files.count, 1, "Seul le PNG doit être accepté")
    }

    // MARK: - Cas : liste vide ou que des fichiers non supportés

    func testAllUnsupportedFilesResultsInNoAddition() async throws {
        let txt = try makeFile("notes.txt")
        let pdf = try makeFile("doc.pdf")

        delegate.store = store
        delegate.application(NSApplication.shared, open: [txt, pdf])

        await Task.yield()

        XCTAssertTrue(store.files.isEmpty, "Aucun fichier non supporté ne doit être ajouté")
    }

    func testEmptyURLListDoesNothing() async {
        delegate.store = store
        delegate.application(NSApplication.shared, open: [])

        await Task.yield()

        XCTAssertTrue(store.files.isEmpty)
    }

    // MARK: - Cas : formats mixtes

    func testMixedFormatsAllAccepted() async throws {
        let png  = try makeFile("a.png")
        let jpg  = try makeFile("b.jpg")
        let heic = try makeFile("c.heic")
        let svg  = try makeFile("d.svg")
        let webp = try makeFile("e.webp")
        let txt  = try makeFile("f.txt")

        delegate.store = store
        delegate.application(NSApplication.shared, open: [png, jpg, heic, svg, webp, txt])

        await Task.yield()
        await Task.yield()

        XCTAssertEqual(store.files.count, 5, "5 formats valides sur 6 doivent être acceptés")
    }

    // MARK: - Cas : Apple Event handler — simulation "Ouvrir avec" fichier par fichier

    func testAppleEventHandlerConsolidatesMultipleSingleFileCalls() async throws {
        // Simule le comportement "Ouvrir avec" : Finder envoie les fichiers un par un
        // Notre handler doit les consolider sans créer de fenêtres supplémentaires
        let png1 = try makeFile("open1.png")
        let png2 = try makeFile("open2.png")
        let png3 = try makeFile("open3.png")

        delegate.store = store

        // Simule 3 appels séparés (comme Finder "Ouvrir avec" pour chaque fichier)
        delegate.application(NSApplication.shared, open: [png1])
        delegate.application(NSApplication.shared, open: [png2])
        delegate.application(NSApplication.shared, open: [png3])

        await Task.yield()
        await Task.yield()

        XCTAssertEqual(store.files.count, 3, "3 fichiers ouverts séparément doivent tous être dans le même store")
    }

    func testAppleEventHandlerWithAppNotYetReady() async throws {
        // Simule le démarrage : store pas encore assigné, fichiers arrivent un par un
        let png1 = try makeFile("startup1.png")
        let png2 = try makeFile("startup2.png")

        // Pas de store encore
        delegate.application(NSApplication.shared, open: [png1])
        delegate.application(NSApplication.shared, open: [png2])
        await Task.yield()

        // Store prêt
        delegate.store = store
        delegate.processPendingFiles()
        await Task.yield()

        XCTAssertEqual(store.files.count, 2, "Les fichiers reçus avant l'init du store doivent arriver après processPendingFiles")
    }

    // MARK: - Cas : appels successifs (simulation Finder fichier par fichier)

    func testSuccessiveCallsDoNotDuplicate() async throws {
        let png = try makeFile("unique.png")

        delegate.store = store

        // Simule deux appels successifs avec le même fichier (comportement Finder pathologique)
        delegate.application(NSApplication.shared, open: [png])
        await Task.yield()
        delegate.application(NSApplication.shared, open: [png])
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(store.files.count, 1, "Un même fichier ne doit pas être ajouté deux fois")
    }
}
