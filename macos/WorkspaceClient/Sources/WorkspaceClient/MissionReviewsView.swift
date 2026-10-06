import SwiftUI

enum MissionReviewCopy {
    static func text(_ key: String, language chosen: String? = nil) -> String {
        let language = chosen ?? Locale.current.language.languageCode?.identifier ?? "en"
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
            "unknown": ["Unknown", "Onbekend", "Unbekannt", "Inconnu", "Desconocido"],
            "noEvidence": ["No verified evidence references available.", "Geen geverifieerde bewijsverwijzingen beschikbaar.", "Keine verifizierten Nachweisreferenzen verfügbar.", "Aucune référence de preuve vérifiée disponible.", "No hay referencias de pruebas verificadas disponibles."],
            "decisionUnavailable": ["Decisions require a qualified Forge review connection and current authority readback.", "Beslissingen vereisen een gekwalificeerde Forge-reviewverbinding en actuele bevoegdheidscontrole.", "Entscheidungen erfordern eine qualifizierte Forge-Verbindung und aktuelle Berechtigungsprüfung.", "Les décisions exigent une connexion Forge qualifiée et une vérification actuelle des droits.", "Las decisiones requieren una conexión Forge calificada y una verificación actual de permisos."],
            "waitingForReview": ["Waiting for review", "Wacht op review", "Wartet auf Prüfung", "En attente de revue", "En espera de revisión"],
            "decisionRecorded": ["Decision recorded", "Beslissing vastgelegd", "Entscheidung erfasst", "Décision enregistrée", "Decisión registrada"],
            "engineeringResult": ["Engineering result", "Engineeringresultaat", "Engineering-Ergebnis", "Résultat d'ingénierie", "Resultado de ingeniería"],
            "finalAcceptance": ["Final acceptance", "Finale acceptatie", "Endabnahme", "Acceptation finale", "Aceptación final"],
            "forge": ["Forge", "Forge", "Forge", "Forge", "Forge"],
            "external": ["External owner", "Externe eigenaar", "Externer Eigentümer", "Responsable externe", "Responsable externo"],
            "current": ["Current", "Actueel", "Aktuell", "Actuel", "Actual"],
            "stale": ["Outdated", "Verouderd", "Veraltet", "Périmé", "Desactualizado"],
            "freshUnavailable": ["Unavailable", "Niet beschikbaar", "Nicht verfügbar", "Indisponible", "No disponible"],
            "actionResultRef": ["Action result", "Action-resultaat", "Action-Ergebnis", "Résultat d'Action", "Resultado de Action"],
            "forgeReceipt": ["Forge receipt", "Forge-receipt", "Forge-Beleg", "Reçu Forge", "Recibo de Forge"],
            "sourceRevision": ["Source revision", "Bronrevisie", "Quellrevision", "Révision source", "Revisión de origen"],
        ]
        return lines[key]?[index] ?? key
    }
}

struct MissionReviewsView: View {
    let items: [MissionReviewItem]
    let access: MissionReviewListAccess
    @Environment(\.locale) private var locale
    @State private var search = ""
    @State private var filter: MissionReviewFilter = .all
    @State private var selectedKey: MissionReviewKey?
    @FocusState private var searchFocused: Bool

    init(items: [MissionReviewItem] = [], access: MissionReviewListAccess = .unavailable,
         selected: MissionReviewKey? = nil, search: String = "",
         filter: MissionReviewFilter = .all) {
        self.items = items
        self.access = access
        _selectedKey = State(initialValue: selected)
        _search = State(initialValue: search)
        _filter = State(initialValue: filter)
    }

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
                            .keyboardShortcut("f", modifiers: .command)
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
                            selectedKey = item.key
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
                if let selected = MissionReviewDiscovery.selected(selectedKey, in: items),
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

    private func detail(_ item: MissionReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent(copy("mission"), value: item.key.missionID)
            LabeledContent(copy("requirement"), value: item.key.requirementID)
            LabeledContent(copy("subject"), value: item.subjectID)
            LabeledContent(copy("revision"), value: item.subjectRevision)
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
            Text(copy("decisionUnavailable")).foregroundStyle(.orange)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .textSelection(.enabled)
    }
}
