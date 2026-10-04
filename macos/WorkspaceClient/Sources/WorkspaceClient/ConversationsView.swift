import SwiftUI

enum ConversationCopy {
    static func text(_ key: String, language chosen: String? = nil) -> String {
        let language = chosen ?? Locale.current.language.languageCode?.identifier ?? "en"
        let index = ["en": 0, "nl": 1, "de": 2, "fr": 3, "es": 4][language] ?? 0
        let lines: [String: [String]] = [
            "nav": ["Conversations", "Gesprekken", "Gespräche", "Conversations", "Conversaciones"],
            "project": ["Project", "Project", "Projekt", "Projet", "Proyecto"],
            "new": ["New conversation", "Nieuw gesprek", "Neues Gespräch", "Nouvelle conversation", "Nueva conversación"],
            "search": ["Find a conversation", "Zoek een gesprek", "Gespräch suchen", "Rechercher une conversation", "Buscar conversación"],
            "title": ["Title", "Titel", "Titel", "Titre", "Título"],
            "focus": ["Focus", "Focus", "Fokus", "Objet", "Enfoque"],
            "mode": ["Advice mode", "Adviesmodus", "Beratungsmodus", "Mode de conseil", "Modo de asesoría"],
            "business": ["Business", "Business", "Business", "Business", "Negocio"],
            "architect": ["Architect", "Architect", "Architekt", "Architecte", "Arquitecto"],
            "ux": ["UX", "UX", "UX", "UX", "UX"],
            "draft": ["Unsent draft", "Niet-verzonden concept", "Ungesendeter Entwurf", "Brouillon non envoyé", "Borrador sin enviar"],
            "save": ["Save draft", "Concept opslaan", "Entwurf speichern", "Enregistrer le brouillon", "Guardar borrador"],
            "discard": ["Discard local changes", "Lokale wijzigingen verwerpen", "Lokale Änderungen verwerfen", "Annuler les modifications locales", "Descartar cambios locales"],
            "reload": ["Reload drafts", "Concepten opnieuw laden", "Entwürfe neu laden", "Recharger les brouillons", "Recargar borradores"],
            "grant": ["Project draft grant", "Concepttoegang voor project", "Projekt-Entwurfsberechtigung", "Accès aux brouillons du projet", "Permiso de borradores del proyecto"],
            "setGrant": ["Save grant", "Toegang bewaren", "Berechtigung speichern", "Enregistrer l'accès", "Guardar permiso"],
            "forgetGrant": ["Forget grant", "Toegang vergeten", "Berechtigung vergessen", "Oublier l'accès", "Olvidar permiso"],
            "context": ["Context and sources", "Context en bronnen", "Kontext und Quellen", "Contexte et sources", "Contexto y fuentes"],
            "sources": ["No verified conversation sources are available.", "Er zijn geen geverifieerde gespreksbronnen beschikbaar.", "Keine verifizierten Gesprächsquellen verfügbar.", "Aucune source de conversation vérifiée n'est disponible.", "No hay fuentes de conversación verificadas disponibles."],
            "ai": ["AI replies and prior advisor history need a qualified Forge connection. Drafts remain usable.", "AI-antwoorden en eerdere advieshistorie vereisen een gekwalificeerde Forge-koppeling. Concepten blijven bruikbaar.", "KI-Antworten und frühere Beratung benötigen eine qualifizierte Forge-Verbindung. Entwürfe bleiben nutzbar.", "Les réponses IA et l'historique des conseils exigent une connexion Forge qualifiée. Les brouillons restent utilisables.", "Las respuestas de IA y el historial de asesoría requieren una conexión Forge calificada. Los borradores siguen disponibles."],
            "saved": ["Saved on Server", "Opgeslagen op Server", "Auf dem Server gespeichert", "Enregistré sur le serveur", "Guardado en el servidor"],
            "unsaved": ["Local changes not saved", "Lokale wijzigingen niet opgeslagen", "Lokale Änderungen nicht gespeichert", "Modifications locales non enregistrées", "Cambios locales sin guardar"],
            "empty": ["Choose or create a conversation. Only your own drafts appear here.", "Kies of maak een gesprek. Hier staan alleen je eigen concepten.", "Gespräch auswählen oder erstellen. Hier stehen nur eigene Entwürfe.", "Choisissez ou créez une conversation. Seuls vos brouillons figurent ici.", "Elige o crea una conversación. Aquí solo aparecen tus borradores."],
            "available": ["Ready for drafts", "Klaar voor concepten", "Bereit für Entwürfe", "Prêt pour les brouillons", "Listo para borradores"],
            "loading": ["Loading drafts", "Concepten laden", "Entwürfe laden", "Chargement des brouillons", "Cargando borradores"],
            "saving": ["Saving draft", "Concept opslaan", "Entwurf wird gespeichert", "Enregistrement du brouillon", "Guardando borrador"],
            "offline": ["Offline: local text stays here until you save it after reconnecting.", "Offline: lokale tekst blijft hier tot je die na herverbinden opslaat.", "Offline: Lokaler Text bleibt hier, bis er nach dem Verbinden gespeichert wird.", "Hors ligne : le texte local reste ici jusqu'à son enregistrement après reconnexion.", "Sin conexión: el texto local permanece aquí hasta que lo guardes al reconectar."],
            "forbidden": ["No access to this project's drafts.", "Geen toegang tot de concepten van dit project.", "Kein Zugriff auf die Entwürfe dieses Projekts.", "Pas d'accès aux brouillons de ce projet.", "Sin acceso a los borradores de este proyecto."],
            "conflict": ["A newer Server draft exists. Compare it with your local text before choosing a version.", "Er staat een nieuwer concept op de Server. Vergelijk het met je lokale tekst voordat je een versie kiest.", "Ein neuerer Entwurf liegt auf dem Server. Vor der Auswahl mit dem lokalen Text vergleichen.", "Un brouillon plus récent est sur le serveur. Comparez-le à votre texte local avant de choisir.", "Hay un borrador más reciente en el servidor. Compáralo con tu texto local antes de elegir."],
            "serverVersion": ["Newer Server version", "Nieuwere Serverversie", "Neuere Serverversion", "Version plus récente du serveur", "Versión más reciente del servidor"],
            "keepLocal": ["Keep my text after review", "Mijn tekst behouden na controle", "Meinen Text nach Prüfung behalten", "Conserver mon texte après examen", "Conservar mi texto tras revisar"],
            "pending": ["Save or discard local changes before switching.", "Sla lokale wijzigingen op of verwerp ze vóór het wisselen.", "Lokale Änderungen vor dem Wechsel speichern oder verwerfen.", "Enregistrez ou annulez les modifications locales avant de changer.", "Guarda o descarta los cambios locales antes de cambiar."],
            "unavailable": ["Drafts are unavailable right now.", "Concepten zijn nu niet beschikbaar.", "Entwürfe sind derzeit nicht verfügbar.", "Les brouillons sont indisponibles pour le moment.", "Los borradores no están disponibles ahora."],
            "stale": ["The project source is outdated. Refresh the Server before saving.", "De projectbron is verouderd. Vernieuw de Server vóór opslaan.", "Die Projektquelle ist veraltet. Server vor dem Speichern aktualisieren.", "La source du projet est périmée. Actualisez le serveur avant d'enregistrer.", "La fuente del proyecto está desactualizada. Actualiza el servidor antes de guardar."],
            "invalid": ["Enter a title and keep the draft within the limits.", "Vul een titel in en houd het concept binnen de limieten.", "Titel eingeben und Entwurf innerhalb der Grenzen halten.", "Saisissez un titre et respectez les limites du brouillon.", "Escribe un título y mantén el borrador dentro de los límites."],
            "grantRequired": ["Select a project and enter its separate draft grant.", "Kies een project en voer de aparte concepttoegang in.", "Projekt wählen und gesonderte Entwurfsberechtigung eingeben.", "Choisissez un projet et saisissez son accès distinct aux brouillons.", "Elige un proyecto e introduce su permiso de borradores."],
        ]
        return lines[key]?[index] ?? key
    }
}

struct ConversationsView: View {
    @ObservedObject var client: ClientState
    @ObservedObject var state: ConversationState
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var editorFocused: Bool

    private var projects: [Project] {
        guard let snapshot = client.snapshot, case .success(let catalogue) = snapshot.projects,
              !catalogue.stale else { return [] }
        return catalogue.projects
    }

    private var stateLabel: String {
        switch state.state {
        case "AVAILABLE": ConversationCopy.text("available")
        case "LOADING": ConversationCopy.text("loading")
        case "SAVING": ConversationCopy.text("saving")
        case "OFFLINE": ConversationCopy.text("offline")
        case "UNAUTHORIZED": ConversationCopy.text("forbidden")
        case "CONFLICT": ConversationCopy.text("conflict")
        case "PENDING": ConversationCopy.text("pending")
        case "STALE": ConversationCopy.text("stale")
        case "INVALID": ConversationCopy.text("invalid")
        case "GRANT_REQUIRED": ConversationCopy.text("grantRequired")
        default: ConversationCopy.text("unavailable")
        }
    }

    private func modeLabel(_ mode: String) -> String {
        switch mode {
        case "BUSINESS": ConversationCopy.text("business")
        case "ARCHITECTURE": ConversationCopy.text("architect")
        case "UX": ConversationCopy.text("ux")
        default: ConversationCopy.text("unavailable")
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Picker(ConversationCopy.text("project"), selection: Binding(
                    get: { state.projectID }, set: { state.selectProject($0) })) {
                    Text("—").tag("")
                    ForEach(projects) { project in Text(project.name).tag(project.id) }
                }
                HStack {
                    Text(ConversationCopy.text("nav")).font(.headline)
                    Spacer()
                    Button { state.newDraft(); editorFocused = true } label: {
                        Label(ConversationCopy.text("new"), systemImage: "plus")
                    }.accessibilityLabel(ConversationCopy.text("new"))
                        .disabled(!state.canEdit)
                }
                TextField(ConversationCopy.text("search"), text: $state.search)
                    .accessibilityLabel(ConversationCopy.text("search"))
                List {
                    ForEach(state.visibleConversations) { conversation in
                        Button {
                            state.select(conversation)
                            editorFocused = true
                        } label: {
                            VStack(alignment: .leading) {
                                Text(conversation.title).font(.body.bold())
                                Text("\(modeLabel(conversation.mode)) · \(ConversationCopy.text("saved"))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(conversation.title), \(modeLabel(conversation.mode))")
                    }
                }
                if state.visibleConversations.isEmpty {
                    Text(ConversationCopy.text("empty")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(minWidth: 220)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(ConversationCopy.text("nav")).font(.largeTitle.bold())
                        Spacer()
                        Button(ConversationCopy.text("reload")) {
                            Task { await state.load(client: client) }
                        }
                    }
                    Label(stateLabel, systemImage: state.state == "AVAILABLE" ? "checkmark.circle" : "exclamationmark.circle")
                        .accessibilityLabel(stateLabel)
                    if state.dirty {
                        Label(ConversationCopy.text("unsaved"), systemImage: "pencil.circle")
                            .foregroundStyle(.orange)
                    } else if state.savedRevision != nil {
                        Label(ConversationCopy.text("saved"), systemImage: "checkmark.circle")
                    }
                    if let newer = state.serverConflict {
                        GroupBox(ConversationCopy.text("serverVersion")) {
                            VStack(alignment: .leading, spacing: 8) {
                                LabeledContent(ConversationCopy.text("title"), value: newer.title)
                                LabeledContent(ConversationCopy.text("focus"), value: newer.focus)
                                LabeledContent(ConversationCopy.text("mode"), value: modeLabel(newer.mode))
                                Text(newer.draft).textSelection(.enabled)
                                    .accessibilityLabel(ConversationCopy.text("serverVersion"))
                                Button(ConversationCopy.text("keepLocal")) { state.keepLocalAfterReview() }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if state.state == "GRANT_REQUIRED" || state.state == "UNAUTHORIZED" {
                        VStack(alignment: .leading) {
                            SecureField(ConversationCopy.text("grant"), text: $state.grantEntry)
                                .accessibilityLabel(ConversationCopy.text("grant"))
                            HStack {
                                Button(ConversationCopy.text("setGrant")) {
                                    Task { await state.saveGrant(client: client) }
                                }
                                Button(ConversationCopy.text("forgetGrant")) { state.forgetGrant() }
                            }
                        }
                    }
                    GroupBox(ConversationCopy.text("context")) {
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent(ConversationCopy.text("project"), value:
                                projects.first(where: { $0.id == state.projectID })?.name ?? "—")
                            LabeledContent(ConversationCopy.text("focus"), value: state.focus.isEmpty ? "—" : state.focus)
                            Text(ConversationCopy.text("sources"))
                            Text(ConversationCopy.text("ai"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    TextField(ConversationCopy.text("title"), text: $state.title)
                        .accessibilityLabel(ConversationCopy.text("title"))
                        .disabled(!state.canEdit)
                    TextField(ConversationCopy.text("focus"), text: $state.focus)
                        .accessibilityLabel(ConversationCopy.text("focus"))
                        .disabled(!state.canEdit)
                    Picker(ConversationCopy.text("mode"), selection: $state.mode) {
                        Text(ConversationCopy.text("business")).tag("BUSINESS")
                        Text(ConversationCopy.text("architect")).tag("ARCHITECTURE")
                        Text(ConversationCopy.text("ux")).tag("UX")
                    }.pickerStyle(.segmented)
                        .accessibilityLabel(ConversationCopy.text("mode"))
                        .disabled(!state.canEdit)
                    Text(ConversationCopy.text("draft")).font(.headline)
                    TextEditor(text: $state.draft)
                        .frame(minHeight: 160)
                        .border(.tertiary)
                        .focused($editorFocused)
                        .accessibilityLabel(ConversationCopy.text("draft"))
                        .disabled(!state.canEdit)
                    }
                    .padding(20)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                Divider()
                HStack {
                    Button(ConversationCopy.text("save")) {
                        Task { await state.save(client: client) }
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!state.canEdit || !state.dirty || state.state == "SAVING")
                    Button(ConversationCopy.text("discard")) { state.discardChanges() }
                        .disabled(!state.dirty)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
        .task { await state.prepare(client: client) }
        .onChange(of: client.phase) { _, phase in
            if phase == "CONNECTED" { Task { await state.prepare(client: client) } }
        }
        .onChange(of: [state.title, state.focus, state.mode, state.draft]) { _, _ in
            state.persistLocal()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                Task { await state.flushLocal() }
            }
        }
    }
}
