import SwiftUI

// Five complete native copy sets; concepts never claim configured projects.
enum ProjectConceptCopy {
    static let values:[String:[String]] = [
        "nav":["Project concepts","Projectconcepten","Projektideen","Idées de projet","Ideas de proyecto"],
        "badge":["Concept — not configured yet","Concept — nog niet ingericht","Entwurf — noch nicht eingerichtet","Concept — pas encore configuré","Concepto — aún sin configurar"],
        "new":["New idea","Nieuw idee","Neue Idee","Nouvelle idée","Nueva idea"],
        "default":["New project idea","Nieuw projectidee","Neue Projektidee","Nouvelle idée de projet","Nueva idea de proyecto"],
        "title":["Title","Titel","Titel","Titre","Título"],
        "notes":["Describe your idea in your own words","Beschrijf je idee in je eigen woorden","Beschreibe deine Idee in eigenen Worten","Décrivez votre idée avec vos mots","Describe tu idea con tus propias palabras"],
        "save":["Save concept","Concept bewaren","Entwurf speichern","Enregistrer le concept","Guardar concepto"],
        "refresh":["Refresh","Verversen","Aktualisieren","Actualiser","Actualizar"],
        "empty":["No concepts yet. Start with an idea.","Nog geen concepten. Begin met een idee.","Noch keine Entwürfe. Beginne mit einer Idee.","Aucun concept. Commencez par une idée.","Aún no hay conceptos. Empieza con una idea."],
        "connect":["Connect your paired Workspace account to open concepts.","Verbind je gekoppelde Workspace-account om concepten te openen.","Verbinde dein Workspace-Konto, um Entwürfe zu öffnen.","Connectez votre compte Workspace associé pour ouvrir les concepts.","Conecta tu cuenta Workspace vinculada para abrir conceptos."],
        "ready":["Choose a saved concept or start a new idea.","Kies een bewaard concept of begin een nieuw idee.","Wähle einen gespeicherten Entwurf oder beginne eine neue Idee.","Choisissez un concept ou une nouvelle idée.","Elige un concepto guardado o una nueva idea."],
        "saved":["Saved on Workspace Server","Bewaard op Workspace Server","Auf Workspace Server gespeichert","Enregistré sur Workspace Server","Guardado en Workspace Server"],
        "unsaved":["Changes not saved. Save before switching concepts.","Wijzigingen niet bewaard. Bewaar voordat je van concept wisselt.","Änderungen nicht gespeichert. Vor dem Wechsel speichern.","Modifications non enregistrées. Enregistrez avant de changer.","Cambios sin guardar. Guarda antes de cambiar de concepto."],
        "retry":["Confirm recovery of the original save. Text stays unchanged until resolved.","Bevestig herstel van de oorspronkelijke opslag. De tekst blijft ongewijzigd tot herstel.","Ursprünglichen Speichervorgang wiederholen. Der Text bleibt bis zur Klärung unverändert.","Confirmez la reprise de l’enregistrement initial. Le texte reste inchangé.","Confirma la recuperación del guardado original. El texto no cambia hasta resolverlo."],
        "offline":["Save not confirmed. Your unsaved text is retained; reconnect and retry.","Opslag niet bevestigd. Je niet-bewaarde tekst blijft staan; verbind opnieuw en probeer herstel.","Speichern nicht bestätigt. Ungespeicherter Text bleibt erhalten; erneut verbinden.","Enregistrement non confirmé. Votre texte est conservé ; reconnectez-vous.","Guardado sin confirmar. Se conserva el texto; vuelve a conectar y reintenta."],
        "denied":["Account access was denied. Protected content is hidden.","Accounttoegang geweigerd. Beschermde inhoud is afgeschermd.","Kontozugriff verweigert. Geschützte Inhalte sind verborgen.","Accès refusé. Le contenu protégé est masqué.","Acceso denegado. El contenido protegido está oculto."],
        "conflict":["A newer saved version exists. Your text is retained. Open the saved version explicitly to replace it.","Er is een nieuwere opgeslagen versie. Je tekst blijft staan. Open de opgeslagen versie expliciet om je tekst te vervangen.","Eine neuere Version existiert. Dein Text bleibt erhalten. Gespeicherte Version ausdrücklich öffnen, um ihn zu ersetzen.","Une version plus récente existe. Votre texte est conservé. Ouvrez explicitement la version enregistrée pour le remplacer.","Existe una versión más reciente. Se conserva tu texto. Abre explícitamente la versión guardada para reemplazarlo."],
        "replace":["Open saved version and replace my text","Opgeslagen versie openen en mijn tekst vervangen","Gespeicherte Version öffnen und meinen Text ersetzen","Ouvrir la version enregistrée et remplacer mon texte","Abrir la versión guardada y reemplazar mi texto"],
        "invalid":["Use a title of 1–120 characters and at most 10,000 characters of notes, without control characters.","Gebruik een titel van 1–120 tekens en maximaal 10.000 tekens notities, zonder besturingstekens.","Titel mit 1–120 Zeichen und höchstens 10.000 Zeichen Notizen, ohne Steuerzeichen.","Titre de 1 à 120 caractères et notes de 10 000 caractères maximum, sans caractères de contrôle.","Título de 1–120 caracteres y hasta 10.000 caracteres de notas, sin caracteres de control."],
        "search":["Search titles","Zoeken op titel","Titel durchsuchen","Rechercher un titre","Buscar por título"],
        "library":["Ideas","Ideeën","Ideen","Idées","Ideas"],
        "active":["Active ideas","Actieve ideeën","Aktive Ideen","Idées actives","Ideas activas"],
        "archive":["Archive","Archief","Archiv","Archives","Archivo"],
        "archiveAction":["Archive idea","Idee archiveren","Idee archivieren","Archiver l’idée","Archivar idea"],
        "restoreAction":["Restore idea","Idee terugzetten","Idee wiederherstellen","Restaurer l’idée","Restaurar idea"],
        "activeEmpty":["No active ideas yet.","Nog geen actieve ideeën.","Noch keine aktiven Ideen.","Aucune idée active.","Aún no hay ideas activas."],
        "archiveEmpty":["Archive is empty.","Archief is leeg.","Das Archiv ist leer.","Les archives sont vides.","El archivo está vacío."],
        "noTitles":["No titles found.","Geen titels gevonden.","Keine Titel gefunden.","Aucun titre trouvé.","No se encontraron títulos."],
        "archived":["Archived — restore before editing.","Gearchiveerd — zet terug om te bewerken.","Archiviert — vor dem Bearbeiten wiederherstellen.","Archivée — restaurez avant de modifier.","Archivada — restaura antes de editar."],
        "lifecycleBlocked":["Save or recover your original save before archiving or restoring.","Bewaar of herstel eerst je oorspronkelijke opslag voordat je archiveert of terugzet.","Vor dem Archivieren oder Wiederherstellen zuerst speichern oder ursprüngliches Speichern klären.","Enregistrez ou récupérez l’enregistrement initial avant d’archiver ou de restaurer.","Guarda o recupera el guardado original antes de archivar o restaurar."],
        "lifecycleRetry":["Confirm recovery of the original archive or restore.","Bevestig herstel van de oorspronkelijke archief- of terugzetactie.","Ursprüngliches Archivieren oder Wiederherstellen bestätigen.","Confirmez la reprise de l’archivage ou restauration initiale.","Confirma la recuperación del archivo o restauración original."],
        "lifecycleOffline":["Archive or restore not confirmed. Recover the original action when connected.","Archiveren of terugzetten niet bevestigd. Herstel de oorspronkelijke actie zodra verbonden.","Archivieren oder Wiederherstellen nicht bestätigt. Ursprüngliche Aktion nach Verbindung klären.","Archivage ou restauration non confirmé. Reprenez l’action initiale après connexion.","Archivo o restauración sin confirmar. Recupera la acción original al conectar."],
        "incompatible":["This Server does not support the concept library contract.","Deze Server ondersteunt het conceptenbibliotheekcontract niet.","Dieser Server unterstützt den Ideenbibliothek-Vertrag nicht.","Ce serveur ne prend pas en charge la bibliothèque de concepts.","Este servidor no admite el contrato de biblioteca de ideas."],
        "created":["Created","Aangemaakt","Erstellt","Créé","Creado"],
        "updated":["Updated","Gewijzigd","Geändert","Modifié","Modificado"]
    ]
    static func text(_ key:String, language:String) -> String {
        values[key]?[["en","nl","de","fr","es"].firstIndex(of:language) ?? 0] ?? key
    }
}
struct ProjectConceptView: View {
    @ObservedObject var state: ProjectConceptState
    @ObservedObject var client: ClientState
    let grants: any DraftGrantStore
    @Environment(\.locale) private var locale
    @Environment(\.nativeTabCommandsActive) private var commandsActive
    @FocusState private var titleFocused: Bool
    private var language:String { locale.language.languageCode?.identifier ?? "en" }
    private func text(_ key:String) -> String { ProjectConceptCopy.text(key,language:language) }
    private func current() async throws -> ConceptConnection {
        guard !client.authorizationLost else { throw ConceptError.denied }
        guard client.phase == "CONNECTED" else { throw ConceptError.unavailable }
        let store = grants
        guard let access = try await Task.detached { try store.load() }.value,
              access.endpoint == client.savedEndpoint, access.instanceID == client.savedInstance else { throw ConceptError.denied }
        let token = try await client.draftReadToken()
        let checked = try await Task.detached { try store.load() }.value
        guard client.phase == "CONNECTED", checked == access else { throw ConceptError.denied }
        return ConceptConnection(access:access,bearer:token)
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text(text("nav")).font(.largeTitle.bold())
                Text(text("badge")).foregroundStyle(.secondary).accessibilityIdentifier("concept-badge")
                HStack {
                    Button(text("new")) { state.new(defaultTitle:text("default")); titleFocused = true }
                        .disabled(state.busy || state.pending != nil || state.pendingLifecycle != nil).accessibilityIdentifier("concept-new")
                    Button(text("refresh")) { Task { await state.refresh(current:current) } }.disabled(state.busy)
                }
                TextField(text("search"),text:$state.searchQuery).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("concept-search")
                Picker(text("library"),selection:$state.libraryTab) {
                    Text(text("active")).tag("ACTIVE")
                    Text(text("archive")).tag("ARCHIVED")
                }.pickerStyle(.segmented).accessibilityIdentifier("concept-library-filter")
                if let message = state.libraryEmptyMessage { Text(text(message)).foregroundStyle(.secondary).accessibilityIdentifier("concept-library-empty") }
                Text(text(state.displayPhase)).foregroundStyle(.secondary).accessibilityIdentifier("concept-status")
                if !state.visibleItems.isEmpty {
                    ScrollView {
                        VStack(alignment:.leading,spacing:8) {
                            ForEach(state.visibleItems) { item in
                                Button { Task { await state.open(item.id,current:current); titleFocused = state.selected?.id == item.id } } label: {
                                    HStack { Image(systemName:state.selected?.id == item.id ? "checkmark.circle.fill" : "doc.text"); Text(item.title); Spacer() }
                                }.disabled(state.busy || state.pending != nil || state.pendingLifecycle != nil).accessibilityIdentifier("concept-row-"+item.id)
                            }
                        }
                    }.frame(maxHeight:160)
                }
                TextField(text("title"),text:$state.title).textFieldStyle(.roundedBorder).focused($titleFocused)
                    .disabled(state.busy || state.pending != nil || state.pendingLifecycle != nil || state.selectedIsArchived).accessibilityIdentifier("concept-title")
                Text(text("notes")).font(.headline)
                TextEditor(text:$state.notes).frame(height:180).overlay(RoundedRectangle(cornerRadius:8).stroke(.quaternary))
                    .disabled(state.busy || state.pending != nil || state.pendingLifecycle != nil || state.selectedIsArchived).accessibilityLabel(text("notes")).accessibilityIdentifier("concept-notes")
                Button(text(state.pending == nil ? "save" : "retry")) { Task { await state.save(current:current) } }
                    .buttonStyle(.borderedProminent).disabled(state.busy || state.phase == "conflict" || state.pendingLifecycle != nil || (state.pending == nil && state.selectedIsArchived) || (state.selected != nil && !state.dirty && state.pending == nil)).keyboardShortcut(commandsActive ? KeyboardShortcut("s",modifiers:.command) : nil).accessibilityIdentifier("concept-save")
                if let selected = state.selected {
                    if state.selectedIsArchived { Text(text("archived")).foregroundStyle(.secondary) }
                    Button(text(state.pendingLifecycle != nil ? "lifecycleRetry" : selected.lifecycle == "ARCHIVED" ? "restoreAction" : "archiveAction")) {
                        Task { await state.move(current:current) }
                    }.disabled(state.lifecycleBlocked).accessibilityIdentifier("concept-lifecycle")
                    if state.dirty || state.pending != nil { Text(text("lifecycleBlocked")).foregroundStyle(.secondary) }
                    if let created = WorksetReleaseWire.date(selected.created_at), let updated = WorksetReleaseWire.date(selected.updated_at) {
                        LabeledContent(text("created"),value:created.formatted(date:.abbreviated,time:.shortened))
                        LabeledContent(text("updated"),value:updated.formatted(date:.abbreviated,time:.shortened))
                    }
                    if state.phase == "conflict" {
                        Button(text("replace")) { Task { await state.open(selected.id,discard:true,current:current) } }
                            .disabled(state.busy).accessibilityIdentifier("concept-conflict-reopen")
                    }
                }
                if state.busy { ProgressView() }
            }.padding(24).frame(minWidth:0,maxWidth:850,alignment:.leading)
        }
        .task { state.bindAuthorization(client); await state.refresh(current:current) }
        .onChange(of:client.phase) { _,phase in
            if phase == "CONNECTED" { Task { await state.refresh(current:current) } }
            else if client.authorizationLost { state.concealAuthorization() }
            else { state.clientPhaseChanged(phase) }
        }
        .onDisappear { state.cancelReads() }
    }
}
