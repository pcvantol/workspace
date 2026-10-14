import SwiftUI

enum ProjectLinkCopy {
    static let values: [String: [String]] = [
        "title": ["Projects", "Projecten", "Projekte", "Projets", "Proyectos"],
        "add": ["Link existing project", "Bestaand project koppelen", "Bestehendes Projekt verknüpfen", "Lier un projet existant", "Vincular un proyecto existente"],
        "refresh": ["Refresh", "Verversen", "Aktualisieren", "Actualiser", "Actualizar"],
        "choose": ["Choose an accessible project", "Kies een toegankelijk project", "Zugängliches Projekt wählen", "Choisissez un projet accessible", "Elige un proyecto accesible"],
        "inspect": ["Check the main repository and related repositories", "Controleer de hoofdrepo en bijbehorende repositories", "Hauptrepository und zugehörige Repositories prüfen", "Vérifiez le dépôt principal et les dépôts associés", "Comprueba el repositorio principal y los relacionados"],
        "authority": ["Main repository", "Hoofdrepository", "Hauptrepository", "Dépôt principal", "Repositorio principal"],
        "repositories": ["Repositories", "Repositories", "Repositories", "Dépôts", "Repositorios"],
        "link": ["Link and open", "Koppelen en openen", "Verknüpfen und öffnen", "Lier et ouvrir", "Vincular y abrir"],
        "opened": ["Project opened", "Project geopend", "Projekt geöffnet", "Projet ouvert", "Proyecto abierto"],
        "readiness": ["Engineering readiness has not been assessed.", "Gereedheid voor engineering is niet beoordeeld.", "Engineering-Bereitschaft wurde nicht bewertet.", "La préparation à l’ingénierie n’a pas été évaluée.", "No se ha evaluado la preparación para ingeniería."],
        "empty": ["No accessible projects", "Geen toegankelijke projecten", "Keine zugänglichen Projekte", "Aucun projet accessible", "No hay proyectos accesibles"],
        "denied": ["Project access denied", "Projecttoegang geweigerd", "Projektzugriff verweigert", "Accès au projet refusé", "Acceso al proyecto denegado"],
        "expired": ["Project access expired", "Projecttoegang verlopen", "Projektzugriff abgelaufen", "L’accès au projet a expiré", "El acceso al proyecto ha caducado"],
        "conflict": ["The project changed. Refresh and check again.", "Het project is gewijzigd. Ververs en controleer opnieuw.", "Das Projekt wurde geändert. Aktualisieren und erneut prüfen.", "Le projet a changé. Actualisez et vérifiez à nouveau.", "El proyecto ha cambiado. Actualiza y comprueba de nuevo."],
        "invalid": ["The project source could not be verified.", "De projectbron kon niet worden geverifieerd.", "Die Projektquelle konnte nicht geprüft werden.", "La source du projet n’a pas pu être vérifiée.", "No se pudo verificar la fuente del proyecto."],
        "unsupported": ["Verified project linking is not available from this EP connection yet.", "Deze EP-verbinding biedt geverifieerd projectkoppelen nog niet aan.", "Diese EP-Verbindung bietet noch keine geprüfte Projektverknüpfung.", "Cette connexion EP ne propose pas encore la liaison vérifiée.", "Esta conexión EP todavía no ofrece vinculación verificada."],
        "unavailable": ["Connect to restore current project access. Saved references are retained.", "Verbind opnieuw voor actuele projecttoegang. Opgeslagen verwijzingen blijven behouden.", "Erneut verbinden für aktuellen Projektzugriff. Gespeicherte Verweise bleiben erhalten.", "Reconnectez-vous pour rétablir l’accès. Les références enregistrées sont conservées.", "Vuelve a conectar para recuperar el acceso. Se conservan las referencias guardadas."],
        "child": ["Additional repository", "Aanvullende repository", "Weiteres Repository", "Dépôt supplémentaire", "Repositorio adicional"],
        "unknownAvailability": ["Checkout availability is not shared", "Checkoutbeschikbaarheid is niet gedeeld", "Checkout-Verfügbarkeit wird nicht geteilt", "La disponibilité des copies n’est pas partagée", "No se comparte la disponibilidad de copias"],
        "noneAvailable": ["No available checkout", "Geen beschikbare checkout", "Kein verfügbarer Checkout", "Aucune copie disponible", "Ninguna copia disponible"],
        "available": ["Available checkouts: %@", "Beschikbare checkouts: %@", "Verfügbare Checkouts: %@", "Copies disponibles : %@", "Copias disponibles: %@"],
        "source": ["Technical source details", "Technische brongegevens", "Technische Quelldetails", "Détails techniques de la source", "Detalles técnicos de la fuente"]
    ]
    static func availability(_ count: Int?, language: String) -> String {
        guard let count else { return text("unknownAvailability", language: language) }
        return count == 0 ? text("noneAvailable", language: language) : String(format: text("available", language: language), String(count))
    }
    static func text(_ key: String, language: String = WorkspaceLanguage.current) -> String {
        let index = ["en", "nl", "de", "fr", "es"].firstIndex(of: language) ?? 0
        return values[key]?[index] ?? key
    }
}
struct ProjectLinkView: View {
    @ObservedObject var state: ProjectLinkState
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedProject: String?
    private func copy(_ key: String) -> String { ProjectLinkCopy.text(key, language: locale.language.languageCode?.identifier ?? "en") }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(copy("title")).font(.largeTitle.bold())
                    Spacer()
                    Button(copy("refresh")) { Task { await state.refresh() } }.disabled(state.busy)
                        .keyboardShortcut("r", modifiers: .command)
                }
                Text(copy(state.phase)).foregroundStyle(.secondary).accessibilityIdentifier("project-link-state")
                if state.access == nil {
                    Button(copy("add")) { Task { await state.refresh() } }.disabled(state.busy)
                }
                ForEach(state.projects) { project in
                    Button { Task { await state.select(project.id) } } label: {
                        HStack { Image(systemName: state.selection == project.id ? "checkmark.circle.fill" : "folder"); Text(project.name); Spacer() }
                    }
                    .buttonStyle(.bordered).disabled(state.busy)
                    .focusable().focused($focusedProject, equals: project.id)
                    .onKeyPress(.space) { guard !state.busy else { return .ignored }; Task { await state.select(project.id) }; return .handled }
                    .accessibilityIdentifier("project-choice-" + project.id)
                }
                if let topology = state.topology {
                    Text(topology.name).font(.title2.bold())
                    Text(copy("inspect"))
                    ForEach(topology.repositories) { repository in
                        HStack(alignment: .top) {
                            Image(systemName: repository.role == "authority" ? "house" : "folder")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(repository.name)
                                Text(copy(repository.role == "authority" ? "authority" : "child")).foregroundStyle(.secondary)
                                Text(ProjectLinkCopy.availability(repository.availableAttachments, language: locale.language.languageCode?.identifier ?? "en"))
                                    .foregroundStyle(.secondary).accessibilityIdentifier("project-repository-availability-" + repository.id)
                            }
                        }
                    }
                    Text(copy("readiness")).foregroundStyle(.secondary)
                    DisclosureGroup(copy("source")) {
                        Text(topology.peerID).textSelection(.enabled)
                        Text(topology.projectID).textSelection(.enabled)
                        Text(topology.observedAt, style: .date)
                    }
                    Button(copy("link")) { Task { await state.linkAndOpen() } }
                        .buttonStyle(.borderedProminent).disabled(state.busy || state.opened != nil)
                        .accessibilityIdentifier("project-link-confirm")
                        .keyboardShortcut(.return, modifiers: .command)
                }
                if state.busy { ProgressView() }
            }
            .padding(24).frame(maxWidth: 850, alignment: .leading)
        }
        .task { await state.refresh() }
        .onChange(of: state.phase) { _, phase in
            if phase == "choose" { focusedProject = state.projects.first?.id }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { state.invalidate() } }
        .onDisappear { state.invalidate() }
    }
}
