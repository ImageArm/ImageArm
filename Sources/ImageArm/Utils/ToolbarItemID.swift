import Foundation

/// Identifiants des éléments de la barre d'outils personnalisable.
///
/// ⚠️ CONTRAT DE PERSISTANCE — AppKit enregistre dans les préférences la
/// disposition choisie par l'utilisateur (ordre, éléments retirés, mode
/// d'affichage, visibilité) sous **ces chaînes exactes**. Renommer `toolbarID`
/// ou n'importe quel `rawValue` réinitialise silencieusement la barre d'outils
/// de tous les utilisateurs qui l'avaient personnalisée : on ajoute, on ne
/// renomme jamais. `ToolbarItemIDTests` épingle chaque valeur pour rendre un
/// tel renommage visible en revue.
enum ToolbarItemID: String, CaseIterable {
    /// Identifiant de la barre elle-même = nom d'autosauvegarde NSToolbar.
    static let toolbarID = "mainToolbar"

    case level
    case console
    case donate
    case add
    case run
    case clear
    case clearCompleted
    case settings
}
