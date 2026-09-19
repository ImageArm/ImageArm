import XCTest
@testable import ImageArm

/// Les identifiants de la barre d'outils sont un contrat de persistance :
/// AppKit enregistre sous ces chaînes la disposition choisie par l'utilisateur.
/// Un échec ici signifie « la personnalisation de tous les utilisateurs
/// existants va être perdue ».
final class ToolbarItemIDTests: XCTestCase {

    // MARK: - Valeurs épinglées

    func testToolbarIdentifierIsStable() {
        XCTAssertEqual(ToolbarItemID.toolbarID, "mainToolbar")
    }

    func testItemIdentifiersAreStable() {
        XCTAssertEqual(ToolbarItemID.level.rawValue, "level")
        XCTAssertEqual(ToolbarItemID.console.rawValue, "console")
        XCTAssertEqual(ToolbarItemID.donate.rawValue, "donate")
        XCTAssertEqual(ToolbarItemID.add.rawValue, "add")
        XCTAssertEqual(ToolbarItemID.run.rawValue, "run")
        XCTAssertEqual(ToolbarItemID.clear.rawValue, "clear")
        XCTAssertEqual(ToolbarItemID.clearCompleted.rawValue, "clearCompleted")
        XCTAssertEqual(ToolbarItemID.settings.rawValue, "settings")
    }

    /// Figé volontairement : ajouter un item force à relire ce fichier, donc à
    /// relire le contrat de persistance.
    func testItemCountIsPinned() {
        XCTAssertEqual(ToolbarItemID.allCases.count, 8)
    }

    // MARK: - Invariants

    func testIdentifiersAreUnique() {
        let raws = ToolbarItemID.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count,
                       "Deux items partagent un identifiant : disposition corrompue")
    }

    func testIdentifiersAreNonEmptyAndWhitespaceFree() {
        for id in ToolbarItemID.allCases.map(\.rawValue) + [ToolbarItemID.toolbarID] {
            XCTAssertFalse(id.isEmpty, "Identifiant vide")
            XCTAssertFalse(id.contains(" "), "« \(id) » contient une espace")
        }
    }

    /// Le nom de la barre ne doit pas collisionner avec un identifiant d'item :
    /// ce sont deux espaces de noms distincts dans les préférences.
    func testToolbarIdentifierIsNotAlsoAnItemIdentifier() {
        XCTAssertFalse(ToolbarItemID.allCases.map(\.rawValue).contains(ToolbarItemID.toolbarID))
    }
}
