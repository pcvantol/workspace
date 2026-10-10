import Combine
import SwiftUI

enum MissionReviewCopy {
    static func text(_ key: String, language chosen: String? = nil) -> String {
        let language = chosen ?? WorkspaceLanguage.current
        let index = ["en": 0, "nl": 1, "de": 2, "fr": 3, "es": 4][language] ?? 0
        let lines: [String: [String]] = [
            "nav": ["Missions & reviews", "Missions en reviews", "Missionen und Prüfungen", "Missions et revues", "Misiones y revisiones"],
            "subtitle": ["Authorized Mission scope and review evidence", "Geautoriseerde Missions en reviewbewijs", "Autorisierte Missionen und Prüfungsnachweise", "Missions autorisées et preuves de revue", "Misiones autorizadas y pruebas de revisión"],
            "search": ["Search this Mission scope", "Zoek binnen deze Missions", "Diese Missionen durchsuchen", "Rechercher dans ces missions", "Buscar en estas misiones"],
            "focusSearch": ["Focus search", "Zoekveld openen", "Suche öffnen", "Ouvrir la recherche", "Abrir la búsqueda"],
            "filter": ["Review filter", "Reviewfilter", "Prüfungsfilter", "Filtre des revues", "Filtro de revisiones"],
            "all": ["All", "Alles", "Alle", "Tout", "Todas"],
            "waiting": ["Waiting", "Wachtend", "Wartend", "En attente", "En espera"],
            "recorded": ["Recorded", "Vastgelegd", "Erfasst", "Enregistrées", "Registradas"],
            "unavailable": ["Forge review capability is not qualified for this Server.", "Forge-reviewtoegang is voor deze Server niet gekwalificeerd.", "Forge-Prüfungszugriff ist für diesen Server nicht qualifiziert.", "L'accès aux revues Forge n'est pas qualifié pour ce serveur.", "El acceso a revisiones de Forge no está calificado para este servidor."],
            "denied": ["You do not have access to this Mission scope.", "Je hebt geen toegang tot deze Missions.", "Kein Zugriff auf diese Missionen.", "Vous n'avez pas accès à ces missions.", "No tienes acceso a estas misiones."],
            "offline": ["The current review state is offline. No decision can be sent.", "De actuele reviewstatus is offline. Er kan geen beslissing worden verstuurd.", "Der aktuelle Prüfungsstand ist offline. Keine Entscheidung kann gesendet werden.", "L'état actuel des revues est hors ligne. Aucune décision ne peut être envoyée.", "El estado actual de las revisiones no está disponible. No se puede enviar ninguna decisión."],
            "noItems": ["No Missions are visible in your authorized scope. This does not describe other scopes.", "Geen Missions zichtbaar binnen jouw bevoegdheid. Dit zegt niets over andere scopes.", "Keine Missionen im autorisierten Bereich sichtbar. Andere Bereiche bleiben unbekannt.", "Aucune mission visible dans votre périmètre autorisé. Les autres périmètres sont inconnus.", "No hay misiones visibles en tu ámbito autorizado. Se desconocen otros ámbitos."],
            "noMatches": ["No reviews match these list choices.", "Geen reviews passen bij deze lijstkeuzes.", "Keine Prüfungen passen zu dieser Auswahl.", "Aucune revue ne correspond à ces choix.", "Ninguna revisión coincide con estas opciones."],
            "hidden": ["The selected review is hidden by the list choices; its detail remains open.", "De gekozen review is verborgen door de lijstkeuzes; het detail blijft open.", "Die ausgewählte Prüfung ist ausgeblendet; ihre Details bleiben geöffnet.", "La revue sélectionnée est masquée ; ses détails restent ouverts.", "La revisión seleccionada está oculta; sus detalles siguen abiertos."],
            "choose": ["Select a Mission review to inspect its evidence.", "Kies een Missionreview om het bewijs te bekijken.", "Mission-Prüfung auswählen, um Nachweise zu sehen.", "Sélectionnez une revue de mission pour voir ses preuves.", "Selecciona una revisión de misión para ver sus pruebas."],
            "mission": ["Mission", "Mission", "Mission", "Mission", "Misión"],
            "requirement": ["Review requirement", "Reviewvereiste", "Prüfungsanforderung", "Exigence de revue", "Requisito de revisión"],
            "subject": ["Exact subject", "Exact onderwerp", "Genauer Gegenstand", "Sujet exact", "Objeto exacto"],
            "revision": ["Subject revision", "Onderwerprevisie", "Gegenstandsrevision", "Révision du sujet", "Revisión del objeto"],
            "subjectDigest": ["Subject digest", "Onderwerpdigest", "Gegenstands-Digest", "Empreinte du sujet", "Huella del objeto"],
            "missionRevision": ["Mission state revision", "Missionstatusrevisie", "Missionsstatusrevision", "Révision d'état de mission", "Revisión del estado de misión"],
            "evidenceDigest": ["Evidence digest", "Bewijsdigest", "Nachweis-Digest", "Empreinte de preuve", "Huella de prueba"],
            "project": ["Verified project", "Geverifieerd project", "Verifiziertes Projekt", "Projet vérifié", "Proyecto verificado"],
            "action": ["Action result", "Action-resultaat", "Action-Ergebnis", "Résultat de l'Action", "Resultado de la Action"],
            "reason": ["Why it waits", "Waarom het wacht", "Grund des Wartens", "Raison de l'attente", "Motivo de espera"],
            "role": ["Required role", "Vereiste rol", "Erforderliche Rolle", "Rôle requis", "Rol requerido"],
            "scope": ["Blocking scope", "Blokkerende scope", "Blockierter Bereich", "Périmètre bloqué", "Ámbito bloqueado"],
            "policy": ["Policy source", "Beleidsbron", "Richtlinienquelle", "Source de politique", "Fuente de política"],
            "evidence": ["Evidence references", "Bewijsverwijzingen", "Nachweisreferenzen", "Références de preuve", "Referencias de pruebas"],
            "observed": ["Observed at", "Waargenomen op", "Beobachtet am", "Observé à", "Observado en"],
            "freshness": ["Freshness", "Versheid", "Aktualität", "Actualité", "Vigencia"],
            "authority": ["Review authority", "Reviewbevoegdheid", "Prüfungszuständigkeit", "Autorité de revue", "Autoridad de revisión"],
            "phase": ["State", "Status", "Status", "État", "Estado"],
            "lifecycle": ["Forge lifecycle", "Forge-levenscyclus", "Forge-Lebenszyklus", "Cycle de vie Forge", "Ciclo de vida Forge"],
            "decisionID": ["Decision receipt", "Beslissingsreceipt", "Entscheidungsbeleg", "Reçu de décision", "Recibo de decisión"],
            "decisionDigest": ["Decision digest", "Beslissingsdigest", "Entscheidungs-Digest", "Empreinte de décision", "Huella de decisión"],
            "decisionOutcome": ["Recorded outcome", "Vastgelegde uitkomst", "Erfasstes Ergebnis", "Résultat enregistré", "Resultado registrado"],
            "unknown": ["Unknown", "Onbekend", "Unbekannt", "Inconnu", "Desconocido"],
            "noEvidence": ["No verified evidence references available.", "Geen geverifieerde bewijsverwijzingen beschikbaar.", "Keine verifizierten Nachweisreferenzen verfügbar.", "Aucune référence de preuve vérifiée disponible.", "No hay referencias de pruebas verificadas disponibles."],
            "decisionUnavailable": ["Decisions require a qualified Forge review connection and current authority readback.", "Beslissingen vereisen een gekwalificeerde Forge-reviewverbinding en actuele bevoegdheidscontrole.", "Entscheidungen erfordern eine qualifizierte Forge-Verbindung und aktuelle Berechtigungsprüfung.", "Les décisions exigent une connexion Forge qualifiée et une vérification actuelle des droits.", "Las decisiones requieren una conexión Forge calificada y una verificación actual de permisos."],
            "waitingForReview": ["Waiting for review", "Wacht op review", "Wartet auf Prüfung", "En attente de revue", "En espera de revisión"],
            "decisionRecorded": ["Decision recorded", "Beslissing vastgelegd", "Entscheidung erfasst", "Décision enregistrée", "Decisión registrada"],
            "engineeringResult": ["Engineering result", "Engineeringresultaat", "Engineering-Ergebnis", "Résultat d'ingénierie", "Resultado de ingeniería"],
            "noReview": ["No current review", "Geen actuele review", "Keine aktuelle Prüfung", "Aucune revue actuelle", "Sin revisión actual"],
            "externalGate": ["External gate", "Externe poort", "Externes Gate", "Contrôle externe", "Puerta externa"],
            "finalAcceptance": ["Final acceptance", "Finale acceptatie", "Endabnahme", "Acceptation finale", "Aceptación final"],
            "forge": ["Forge", "Forge", "Forge", "Forge", "Forge"],
            "external": ["External owner", "Externe eigenaar", "Externer Eigentümer", "Responsable externe", "Responsable externo"],
            "current": ["Current", "Actueel", "Aktuell", "Actuel", "Actual"],
            "stale": ["Outdated", "Verouderd", "Veraltet", "Périmé", "Desactualizado"],
            "freshUnavailable": ["Unavailable", "Niet beschikbaar", "Nicht verfügbar", "Indisponible", "No disponible"],
            "actionResultRef": ["Action result", "Action-resultaat", "Action-Ergebnis", "Résultat d'Action", "Resultado de Action"],
            "forgeReceipt": ["Forge receipt", "Forge-receipt", "Forge-Beleg", "Reçu Forge", "Recibo de Forge"],
            "sourceRevision": ["Source revision", "Bronrevisie", "Quellrevision", "Révision source", "Revisión de origen"],
            "grantRequired": ["Enter your separate review access token.", "Voer je aparte reviewtoegang in.", "Gesonderten Prüfungszugang eingeben.", "Saisissez votre accès distinct aux revues.", "Introduce tu acceso independiente a las revisiones."],
            "reviewGrant": ["Review access token", "Reviewtoegang", "Prüfungszugang", "Accès aux revues", "Acceso a revisiones"],
            "saveGrant": ["Save review access", "Reviewtoegang bewaren", "Prüfungszugang speichern", "Enregistrer l'accès aux revues", "Guardar acceso a revisiones"],
            "forgetGrant": ["Forget review access", "Reviewtoegang vergeten", "Prüfungszugang vergessen", "Oublier l'accès aux revues", "Olvidar acceso a revisiones"],
            "refresh": ["Refresh reviews", "Reviews verversen", "Prüfungen aktualisieren", "Actualiser les revues", "Actualizar revisiones"],
            "loading": ["Reading current Forge review state…", "Actuele Forge-reviewstatus lezen…", "Aktuellen Forge-Prüfungsstand lesen…", "Lecture de l'état actuel des revues Forge…", "Leyendo el estado actual de las revisiones Forge…"],
            "available": ["Current authorized Mission scope", "Actuele bevoegde Missions", "Aktuell autorisierte Missionen", "Missions actuellement autorisées", "Misiones autorizadas actuales"],
            "pending": ["Decision status is uncertain. Read the same operation again.", "Beslissingsstatus is onzeker. Lees dezelfde operatie opnieuw.", "Entscheidungsstatus ungewiss. Dieselbe Operation erneut lesen.", "Statut de décision incertain. Relisez la même opération.", "Estado de decisión incierto. Lee de nuevo la misma operación."],
            "pendingMissing": ["No Forge receipt yet. You may retry the same operation and reason.", "Nog geen Forge-receipt. Je kunt dezelfde operatie en reden opnieuw proberen.", "Noch kein Forge-Beleg. Dieselbe Operation und Begründung kann erneut versucht werden.", "Pas encore de reçu Forge. Vous pouvez réessayer la même opération et raison.", "Aún no hay recibo Forge. Puedes reintentar la misma operación y razón."],
            "recordedNotice": ["Forge recorded this decision; the current Mission state was read again.", "Forge heeft dit besluit vastgelegd; de actuele Missionstatus is opnieuw gelezen.", "Forge hat diese Entscheidung erfasst; der aktuelle Missionsstatus wurde erneut gelesen.", "Forge a enregistré cette décision ; l'état actuel de la mission a été relu.", "Forge registró esta decisión; se volvió a leer el estado actual de la misión."],
            "decisionConflict": ["The review changed or this operation conflicts. Refresh the exact requirement.", "De review is gewijzigd of deze operatie conflicteert. Ververs het exacte vereiste.", "Die Prüfung hat sich geändert oder die Operation steht im Konflikt. Genaue Anforderung aktualisieren.", "La revue a changé ou cette opération est en conflit. Actualisez l'exigence exacte.", "La revisión cambió o la operación entra en conflicto. Actualiza el requisito exacto."],
            "readPending": ["Read decision receipt", "Beslissingsreceipt lezen", "Entscheidungsbeleg lesen", "Lire le reçu de décision", "Leer recibo de decisión"],
            "retrySame": ["Retry same operation", "Dezelfde operatie opnieuw proberen", "Dieselbe Operation erneut versuchen", "Réessayer la même opération", "Reintentar la misma operación"],
            "confirmTitle": ["Confirm one Forge decision", "Bevestig één Forge-besluit", "Eine Forge-Entscheidung bestätigen", "Confirmer une décision Forge", "Confirmar una decisión Forge"],
            "confirmBody": ["Forge will check your current authority and exact evidence before recording.", "Forge controleert je actuele bevoegdheid en exact bewijs voordat het vastlegt.", "Forge prüft Berechtigung und genaue Nachweise vor dem Erfassen.", "Forge vérifiera vos droits actuels et les preuves exactes avant d'enregistrer.", "Forge comprobará tus permisos y pruebas exactas antes de registrar."],
            "decisionReason": ["Reason for this decision", "Reden voor dit besluit", "Begründung der Entscheidung", "Motif de cette décision", "Motivo de esta decisión"],
            "confirmDecision": ["Confirm decision", "Besluit bevestigen", "Entscheidung bestätigen", "Confirmer la décision", "Confirmar decisión"],
            "cancelDecision": ["Cancel", "Annuleren", "Abbrechen", "Annuler", "Cancelar"],
            "approveDecision": ["Approve", "Goedkeuren", "Genehmigen", "Approuver", "Aprobar"],
            "rejectDecision": ["Reject", "Afwijzen", "Ablehnen", "Rejeter", "Rechazar"],
            "amendDecision": ["Request amendment", "Aanpassing vragen", "Änderung anfordern", "Demander une modification", "Solicitar modificación"],
            "deferDecision": ["Defer", "Uitstellen", "Zurückstellen", "Différer", "Aplazar"],
            "finalSeparate": ["Final Mission acceptance is a separate owner decision.", "Finale Missionacceptatie is een apart eigenaarsbesluit.", "Die endgültige Missionsabnahme ist eine separate Eigentümerentscheidung.", "L'acceptation finale de la mission relève d'une décision distincte du propriétaire.", "La aceptación final de la misión es una decisión separada del responsable."],
        ]
        return lines[key]?[index] ?? key
    }
}

struct MissionReviewsView: View {
    let items: [MissionReviewItem]
    let access: MissionReviewListAccess
    let onDecision: ((MissionReviewItem, MissionReviewOutcome) -> Void)?
    let decisionsBusy: Bool
    @Environment(\.locale) private var locale
    @Environment(\.nativeTabCommandsActive) private var commandsActive
    @State private var search = ""
    @State private var filter: MissionReviewFilter = .all
    @State private var localSelectedKey: MissionReviewKey?
    private let externalSelection: Binding<MissionReviewKey?>?
    @FocusState private var searchFocused: Bool

    init(items: [MissionReviewItem] = [], access: MissionReviewListAccess = .unavailable,
         selected: MissionReviewKey? = nil, selection: Binding<MissionReviewKey?>? = nil, search: String = "",
         filter: MissionReviewFilter = .all,
         decisionsBusy: Bool = false,
         onDecision: ((MissionReviewItem, MissionReviewOutcome) -> Void)? = nil) {
        self.items = items
        self.access = access
        self.onDecision = onDecision
        self.decisionsBusy = decisionsBusy
        externalSelection = selection
        _localSelectedKey = State(initialValue: selected)
        _search = State(initialValue: search)
        _filter = State(initialValue: filter)
    }

    private var selectedKey: MissionReviewKey? {
        get { if let externalSelection { return externalSelection.wrappedValue }; return localSelectedKey }
        nonmutating set { if let externalSelection { externalSelection.wrappedValue = newValue } else { localSelectedKey = newValue } }
    }

    var selectedReview: MissionReviewItem? {
        guard access == .available else { return nil }
        return MissionReviewDiscovery.selected(selectedKey, in: items)
    }

    func selectReview(_ key: MissionReviewKey) { selectedKey = key }

    private func copy(_ key: String) -> String {
        MissionReviewCopy.text(key, language: locale.language.languageCode?.identifier)
    }

    private var visible: [MissionReviewItem] {
        MissionReviewDiscovery.visible(items, search: search, filter: filter)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(copy("nav")).font(.largeTitle.bold())
                Text(copy("subtitle")).foregroundStyle(.secondary)
                if case .available = access {
                    HStack {
                        TextField(copy("search"), text: $search)
                            .textFieldStyle(.roundedBorder)
                            .focused($searchFocused)
                            .accessibilityLabel(copy("search"))
                        Button(copy("focusSearch")) { searchFocused = true }
                            .keyboardShortcut(commandsActive ? KeyboardShortcut("f", modifiers: .command) : nil)
                    }
                    Picker(copy("filter"), selection: $filter) {
                        Text(copy("all")).tag(MissionReviewFilter.all)
                        Text(copy("waiting")).tag(MissionReviewFilter.waiting)
                        Text(copy("recorded")).tag(MissionReviewFilter.recorded)
                    }.pickerStyle(.segmented)
                }
                let listState = MissionReviewDiscovery.emptyState(access: access, all: items, visible: visible)
                switch listState {
                case .unavailable: Text(copy("unavailable")).foregroundStyle(.orange)
                case .denied: Text(copy("denied")).foregroundStyle(.orange)
                case .offline: Text(copy("offline")).foregroundStyle(.orange)
                case .noItemsInAuthorizedScope: Text(copy("noItems")).foregroundStyle(.secondary)
                case .noMatches: Text(copy("noMatches")).foregroundStyle(.secondary)
                case .hasItems: EmptyView()
                }
                if case .available = access {
                    ForEach(visible, id: \.key) { item in
                        Button {
                            selectReview(item.key)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.title ?? item.key.missionID).font(.headline)
                                    Text(item.key.requirementID).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(copy(item.phase.rawValue)).font(.caption)
                            }
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.key.missionID), \(item.key.requirementID)")
                        .accessibilityAddTraits(selectedKey == item.key ? .isSelected : [])
                    }
                }
                if let selected = selectedReview,
                   case .available = access {
                    if !visible.contains(selected) {
                        Text(copy("hidden")).foregroundStyle(.secondary)
                    }
                    detail(selected)
                } else if listState == .hasItems {
                    Text(copy("choose")).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    @ViewBuilder private func detailMetadata(_ item: MissionReviewItem) -> some View {
        LabeledContent(copy("mission"), value: item.key.missionID)
        LabeledContent(copy("requirement"), value: item.key.requirementID)
        LabeledContent(copy("subject"), value: item.subjectID)
        LabeledContent(copy("revision"), value: item.subjectRevision)
        LabeledContent(copy("subjectDigest"), value: item.subjectDigest.isEmpty ? copy("unknown") : item.subjectDigest)
        LabeledContent(copy("missionRevision"), value: item.currentMissionRevision > 0 ?
                       String(item.currentMissionRevision) : copy("unknown"))
        LabeledContent(copy("evidenceDigest"), value: item.evidenceDigest.isEmpty ? copy("unknown") : item.evidenceDigest)
        if let projectID = item.projectID { LabeledContent(copy("project"), value: projectID) }
        LabeledContent(copy("action"), value: item.actionResult ?? copy("unknown"))
        LabeledContent(copy("reason"), value: item.waitingReason ?? copy("unknown"))
        LabeledContent(copy("role"), value: item.requiredRole ?? copy("unknown"))
        LabeledContent(copy("scope"), value: item.blockingScope ?? copy("unknown"))
        LabeledContent(copy("policy"), value: item.policySource ?? copy("unknown"))
        LabeledContent(copy("observed"), value: item.observedAt ?? copy("unknown"))
        LabeledContent(copy("freshness"), value: copy(item.freshness == .unavailable ?
                                                       "freshUnavailable" : item.freshness.rawValue))
        LabeledContent(copy("authority"), value: copy(item.authority.rawValue))
        LabeledContent(copy("phase"), value: copy(item.phase.rawValue))
        LabeledContent(copy("lifecycle"), value: item.lifecycleState.isEmpty ? copy("unknown") : item.lifecycleState)
    }

    private func detail(_ item: MissionReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            detailMetadata(item)
            if let outcome = item.decisionOutcome {
                let label = switch outcome {
                case .approve: "approveDecision"
                case .reject: "rejectDecision"
                case .amend: "amendDecision"
                case .deferred: "deferDecision"
                }
                LabeledContent(copy("decisionOutcome"), value: copy(label))
            }
            if let decisionID = item.decisionID { LabeledContent(copy("decisionID"), value: decisionID) }
            if let decisionDigest = item.decisionDigest {
                LabeledContent(copy("decisionDigest"), value: decisionDigest)
            }
            Text(copy("evidence")).font(.headline)
            if item.evidence.isEmpty {
                Text(copy("noEvidence")).foregroundStyle(.secondary)
            } else {
                ForEach(Array(item.evidence.enumerated()), id: \.offset) { _, reference in
                    let kind = reference.kind == .actionResult ? "actionResultRef" : reference.kind.rawValue
                    Text("\(copy(kind)): \(reference.identifier)")
                        .textSelection(.enabled)
                }
            }
            if item.phase == .finalAcceptance {
                Text(copy("finalSeparate")).foregroundStyle(.secondary)
            } else if let onDecision, !item.allowedOutcomes.isEmpty {
                ViewThatFits(in: .horizontal) {
                    decisionButtons(item, onDecision: onDecision)
                    VStack(alignment: .leading) {
                        ForEach(MissionReviewOutcome.allCases, id: \.rawValue) { outcome in
                            if item.mayOffer(outcome) {
                                Button(copy(decisionLabel(outcome))) { onDecision(item, outcome) }
                                    .disabled(decisionsBusy)
                            }
                        }
                    }
                }
            } else {
                Text(copy("decisionUnavailable")).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .textSelection(.enabled)
    }

    private func decisionButtons(_ item: MissionReviewItem,
                                 onDecision: @escaping (MissionReviewItem, MissionReviewOutcome) -> Void) -> some View {
        HStack {
            ForEach(MissionReviewOutcome.allCases, id: \.rawValue) { outcome in
                if item.mayOffer(outcome) {
                    Button(copy(decisionLabel(outcome))) { onDecision(item, outcome) }
                        .disabled(decisionsBusy)
                }
            }
        }
    }

    private func decisionLabel(_ outcome: MissionReviewOutcome) -> String {
        switch outcome {
        case .approve: "approveDecision"
        case .reject: "rejectDecision"
        case .amend: "amendDecision"
        case .deferred: "deferDecision"
        }
    }
}

struct LiveMissionReviewsView: View {
    @ObservedObject var client: ClientState
    @StateObject private var state: MissionReviewState
    @Environment(\.locale) private var locale
    private let requestedSelection: MissionReviewKey?
    private let reviewSelection: Binding<MissionReviewKey?>?
    @State private var grantToken = ""
    @State private var proposedItem: MissionReviewItem?
    @State private var proposedOutcome: MissionReviewOutcome?
    @State private var reason = ""
    @FocusState private var reasonFocused: Bool
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(client: ClientState, state: MissionReviewState = MissionReviewState(), selected: MissionReviewKey? = nil, selection: Binding<MissionReviewKey?>? = nil) {
        reviewSelection = selection
        requestedSelection = selected
        self.client = client
        _state = StateObject(wrappedValue: state)
    }

    private func copy(_ key: String) -> String {
        MissionReviewCopy.text(key, language: locale.language.languageCode?.identifier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(copy(state.statusKey)).foregroundStyle(state.statusKey == "recordedNotice" ? .primary : .secondary)
                Spacer()
                if !state.actorID.isEmpty { Text(state.actorID).font(.caption).foregroundStyle(.secondary) }
                Button(copy("refresh")) { Task { await state.refresh(client: client) } }
                    .disabled(state.isBusy)
            }.padding(.horizontal, 20).padding(.top, 12)
            if state.access == .unavailable || state.access == .denied {
                HStack {
                    SecureField(copy("reviewGrant"), text: $grantToken)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(copy("reviewGrant"))
                    Button(copy("saveGrant")) {
                        let submitted = grantToken
                        grantToken = ""
                        Task { await state.saveGrant(submitted, client: client) }
                    }.disabled(state.isBusy || grantToken.isEmpty || client.phase != "CONNECTED")
                }.padding(.horizontal, 20)
            } else if state.pendingIntent == nil {
                Button(copy("forgetGrant")) { state.forgetGrant() }
                    .disabled(state.isBusy)
                    .padding(.horizontal, 20)
            }
            if state.pendingIntent != nil {
                HStack {
                    Button(copy("readPending")) { Task { await state.readPending(client: client) } }
                        .disabled(state.isBusy)
                    if state.canRetrySameOperation {
                        Button(copy("retrySame")) { Task { await state.retrySameOperation(client: client) } }
                            .disabled(state.isBusy)
                    }
                }.padding(.horizontal, 20)
            }
            MissionReviewsView(items: state.items, access: state.access, selected: requestedSelection, selection: reviewSelection,
                               decisionsBusy: state.isBusy || state.pendingIntent != nil,
                               onDecision: state.pendingIntent == nil ? { item, outcome in
                proposedItem = item
                proposedOutcome = outcome
                reason = ""
            } : nil)
        }
        .onAppear { Task { await state.refresh(client: client) } }
        .onChange(of: client.phase) { _, phase in
            if phase == "CONNECTED" { Task { await state.refresh(client: client) } }
        }
        .onReceive(refreshTimer) { _ in
            if client.phase == "CONNECTED" { Task { await state.refresh(client: client) } }
        }
        .sheet(isPresented: Binding(
            get: { proposedItem != nil && proposedOutcome != nil },
            set: { if !$0 { proposedItem = nil; proposedOutcome = nil } })) {
            VStack(alignment: .leading, spacing: 14) {
                Text(copy("confirmTitle")).font(.title2.bold())
                if let item = proposedItem {
                    Text("\(item.key.missionID) · \(item.key.requirementID)")
                        .font(.caption).textSelection(.enabled)
                }
                Text(copy("confirmBody")).foregroundStyle(.secondary)
                TextField(copy("decisionReason"), text: $reason)
                    .focused($reasonFocused)
                    .accessibilityLabel(copy("decisionReason"))
                HStack {
                    Button(copy("cancelDecision")) {
                        proposedItem = nil
                        proposedOutcome = nil
                    }
                    Spacer()
                    Button(copy("confirmDecision")) {
                        guard let item = proposedItem, let outcome = proposedOutcome else { return }
                        let submittedReason = reason
                        proposedItem = nil
                        proposedOutcome = nil
                        Task { await state.decide(item, outcome: outcome,
                                                  reason: submittedReason, client: client) }
                    }
                    .disabled(reason.isEmpty || reason.count > 512 || state.isBusy)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 440)
            .padding(22)
            .onAppear { reasonFocused = true }
        }
    }
}
