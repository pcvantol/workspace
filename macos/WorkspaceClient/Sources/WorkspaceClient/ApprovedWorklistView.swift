import SwiftUI

enum WorklistCopy {
    private static let languages = ["en", "nl", "de", "fr", "es"]
    private static let values: [String: [String]] = [
        "nav": ["Approved worklist", "Goedgekeurde werklijst", "Genehmigte Arbeitsliste", "Liste de travail approuvée", "Lista de trabajo aprobada"],
        "subtitle": ["Committed order and verified reasons for waiting", "Vastgelegde volgorde en geverifieerde wachtredenen", "Festgelegte Reihenfolge und verifizierte Wartegründe", "Ordre fixé et raisons d’attente vérifiées", "Orden establecido y motivos de espera verificados"],
        "workset": ["Authorized workset", "Geautoriseerde werkset", "Autorisierter Arbeitssatz", "Ensemble de travail autorisé", "Conjunto de trabajo autorizado"],
        "actor": ["Read actor", "Leesactor", "Leseakteur", "Acteur de lecture", "Actor de lectura"],
        "project": ["Verified project", "Geverifieerd project", "Verifiziertes Projekt", "Projet vérifié", "Proyecto verificado"],
        "noProject": ["No verified project attribution", "Geen geverifieerde projecttoeschrijving", "Keine verifizierte Projektzuordnung", "Aucune attribution de projet vérifiée", "Sin atribución de proyecto verificada"],
        "member": ["Worklist member", "Werklijstitem", "Arbeitslisteneintrag", "Élément de la liste", "Elemento de la lista"],
        "subject": ["Workset subject", "Werksetonderwerp", "Gegenstand des Arbeitssatzes", "Objet de l’ensemble", "Objeto del conjunto"],
        "subjectRevision": ["Subject revision", "Onderwerprevisie", "Gegenstandsrevision", "Révision de l’objet", "Revisión del objeto"],
        "mission": ["Canonical Mission", "Canonieke Mission", "Kanonische Mission", "Mission canonique", "Mission canónica"],
        "unverifiedMissionRef": ["Mission reference — current allocation readback unavailable", "Missionreferentie — actuele allocatiereadback ontbreekt", "Missionreferenz — aktuelle Zuordnungsrücklesung nicht verfügbar", "Référence de Mission — lecture d’allocation actuelle indisponible", "Referencia de Mission — lectura actual de asignación no disponible"],
        "noMission": ["No verified Mission reference", "Geen geverifieerde Missionreferentie", "Keine verifizierte Missionreferenz", "Aucune référence de Mission vérifiée", "Sin referencia de Mission verificada"],
        "committedPosition": ["Committed position", "Vastgelegde positie", "Festgelegte Position", "Position fixée", "Posición establecida"],
        "membershipRevision": ["Membership revision", "Lidmaatschapsrevisie", "Mitgliedschaftsrevision", "Révision des membres", "Revisión de miembros"],
        "selectorRevision": ["Selector revision", "Selectorrevisie", "Selektorrevision", "Révision du sélecteur", "Revisión del selector"],
        "snapshotRevision": ["Snapshot revision", "Snapshotrevisie", "Snapshotrevision", "Révision de l’instantané", "Revisión de la instantánea"],
        "sourceRevision": ["Source observation revision", "Bronobservatierevisie", "Quellbeobachtungsrevision", "Révision d’observation de source", "Revisión de observación de origen"],
        "observedAt": ["Observed at", "Waargenomen op", "Beobachtet am", "Observé le", "Observado el"],
        "search": ["Search this workset", "Doorzoek deze werkset", "Diesen Arbeitssatz durchsuchen", "Rechercher dans cet ensemble", "Buscar en este conjunto"],
        "focusSearch": ["Focus search", "Focus op zoeken", "Suche fokussieren", "Activer la recherche", "Enfocar búsqueda"],
        "filter": ["Filter", "Filter", "Filter", "Filtre", "Filtro"],
        "sort": ["Display order", "Weergavevolgorde", "Anzeigereihenfolge", "Ordre d’affichage", "Orden de visualización"],
        "sortHint": ["Display sorting does not change committed execution order.", "Sorteren verandert de vastgelegde uitvoeringsvolgorde niet.", "Die Anzeigesortierung ändert die festgelegte Ausführungsreihenfolge nicht.", "Le tri d’affichage ne modifie pas l’ordre d’exécution fixé.", "El orden visual no cambia el orden de ejecución establecido."],
        "all": ["All", "Alles", "Alle", "Tous", "Todos"],
        "eligible": ["Eligible", "Uitvoerbaar", "Ausführbar", "Éligible", "Elegible"],
        "active": ["Active", "Actief", "Aktiv", "Actif", "Activo"],
        "blocked": ["Blocked", "Geblokkeerd", "Blockiert", "Bloqué", "Bloqueado"],
        "completed": ["Completed", "Afgerond", "Abgeschlossen", "Terminé", "Completado"],
        "unknown": ["Unknown", "Onbekend", "Unbekannt", "Inconnu", "Desconocido"],
        "committed": ["Committed order", "Vastgelegde volgorde", "Festgelegte Reihenfolge", "Ordre fixé", "Orden establecido"],
        "title": ["Title", "Titel", "Titel", "Titre", "Título"],
        "identifier": ["Identifier", "Identificatie", "Kennung", "Identifiant", "Identificador"],
        "approved": ["Approved", "Goedgekeurd", "Genehmigt", "Approuvé", "Aprobado"],
        "released": ["Released", "Vrijgegeven", "Freigegeben", "Libéré", "Liberado"],
        "engineeringComplete": ["Engineering result proven", "Engineeringresultaat bewezen", "Engineeringergebnis nachgewiesen", "Résultat d’ingénierie prouvé", "Resultado de ingeniería probado"],
        "reviewAccepted": ["Review accepted", "Review geaccepteerd", "Review akzeptiert", "Revue acceptée", "Revisión aceptada"],
        "finalAccepted": ["Final acceptance", "Finale acceptatie", "Endgültige Abnahme", "Acceptation finale", "Aceptación final"],
        "facts": ["Separate observed facts", "Afzonderlijke waargenomen feiten", "Getrennte beobachtete Fakten", "Faits observés distincts", "Hechos observados separados"],
        "blockers": ["Verified reasons for waiting", "Geverifieerde wachtredenen", "Verifizierte Wartegründe", "Raisons d’attente vérifiées", "Motivos de espera verificados"],
        "noBlockers": ["No blocker was reported in this observation.", "Deze observatie vermeldt geen blokkade.", "In dieser Beobachtung wurde keine Blockade gemeldet.", "Aucun blocage n’est signalé dans cette observation.", "No se informó de bloqueos en esta observación."],
        "choose": ["Select a worklist member to inspect its facts.", "Selecteer een werklijstitem om de feiten te bekijken.", "Wählen Sie einen Eintrag, um seine Fakten zu prüfen.", "Sélectionnez un élément pour examiner ses faits.", "Seleccione un elemento para examinar sus hechos."],
        "hidden": ["The selection is hidden by the current display filter.", "De selectie is verborgen door het huidige filter.", "Die Auswahl wird vom aktuellen Filter verborgen.", "La sélection est masquée par le filtre actuel.", "La selección está oculta por el filtro actual."],
        "openReviews": ["Open Mission & review detail", "Open Mission- en reviewdetail", "Mission- und Reviewdetail öffnen", "Ouvrir le détail de Mission et revue", "Abrir detalle de Mission y revisión"],
        "unavailable": ["No qualified worklist read connection is available.", "Geen gekwalificeerde leesverbinding voor de werklijst beschikbaar.", "Keine qualifizierte Arbeitslisten-Leseverbindung verfügbar.", "Aucune connexion de lecture de liste qualifiée disponible.", "No hay conexión de lectura de lista cualificada."],
        "denied": ["No access to this workset.", "Geen toegang tot deze werkset.", "Kein Zugriff auf diesen Arbeitssatz.", "Aucun accès à cet ensemble.", "Sin acceso a este conjunto."],
        "offline": ["The current workset cannot be read while offline.", "De actuele werkset kan offline niet worden gelezen.", "Der aktuelle Arbeitssatz kann offline nicht gelesen werden.", "L’ensemble actuel ne peut pas être lu hors ligne.", "El conjunto actual no puede leerse sin conexión."],
        "partial": ["Partial observation; missing members have not been inferred.", "Gedeeltelijke observatie; ontbrekende items zijn niet afgeleid.", "Teilbeobachtung; fehlende Einträge wurden nicht abgeleitet.", "Observation partielle ; aucun membre manquant n’est déduit.", "Observación parcial; no se deducen miembros ausentes."],
        "stale": ["This observation is stale or inconsistent; resync is required.", "Deze observatie is verouderd of inconsistent; opnieuw lezen vereist.", "Diese Beobachtung ist veraltet oder inkonsistent; erneutes Lesen erforderlich.", "Cette observation est périmée ou incohérente ; resynchronisation requise.", "La observación está desactualizada o es incoherente; debe resincronizarse."],
        "emptyGrantedWorkset": ["No members in this authorized workset.", "Geen items in deze geautoriseerde werkset.", "Keine Einträge in diesem autorisierten Arbeitssatz.", "Aucun membre dans cet ensemble autorisé.", "Sin miembros en este conjunto autorizado."],
        "noMatches": ["No members match this display filter.", "Geen items passen bij dit weergavefilter.", "Keine Einträge entsprechen diesem Anzeigefilter.", "Aucun membre ne correspond à ce filtre.", "Ningún miembro coincide con este filtro."],
        "cachedObservation": ["Cached observation — current authority and execution state are unconfirmed.", "Bewaarde observatie — actuele bevoegdheid en uitvoeringsstatus zijn niet bevestigd.", "Gespeicherte Beobachtung — aktuelle Berechtigung und Ausführung sind unbestätigt.", "Observation en cache — autorité et exécution actuelles non confirmées.", "Observación en caché — autoridad y ejecución actuales sin confirmar."],
        "yes": ["Yes", "Ja", "Ja", "Oui", "Sí"],
        "no": ["No", "Nee", "Nein", "Non", "No"],
        "notRequired": ["Not required", "Niet vereist", "Nicht erforderlich", "Non requis", "No requerido"],
        "current": ["Current", "Actueel", "Aktuell", "Actuel", "Actual"],
        "freshness": ["Freshness", "Versheid", "Aktualität", "Fraîcheur", "Actualidad"],
        "continuation": ["Next-work readback", "Readback volgend werk", "Rücklesung der nächsten Arbeit", "Lecture du travail suivant", "Lectura del siguiente trabajo"],
        "nextMember": ["Next selected member", "Volgend geselecteerd item", "Nächster ausgewählter Eintrag", "Membre suivant sélectionné", "Siguiente miembro seleccionado"],
        "ready": ["Ready under the current Forge conditions", "Gereed onder de actuele Forge-voorwaarden", "Bereit unter den aktuellen Forge-Bedingungen", "Prêt selon les conditions Forge actuelles", "Listo según las condiciones actuales de Forge"],
        "idle": ["No remaining work reported in this workset", "Geen resterend werk gemeld in deze werkset", "Keine verbleibende Arbeit in diesem Arbeitssatz gemeldet", "Aucun travail restant signalé dans cet ensemble", "No se informa de trabajo restante en este conjunto"],
        "dependency": ["Dependency", "Afhankelijkheid", "Abhängigkeit", "Dépendance", "Dependencia"],
        "hold": ["Hold", "Wachtstand", "Haltezustand", "Suspension", "Retención"],
        "evidence": ["Evidence", "Bewijs", "Nachweis", "Preuve", "Evidencia"],
        "review": ["Review", "Review", "Review", "Revue", "Revisión"],
        "finalAcceptance": ["Final acceptance", "Finale acceptatie", "Endgültige Abnahme", "Acceptation finale", "Aceptación final"],
        "authority": ["Authority", "Bevoegdheid", "Berechtigung", "Autorité", "Autoridad"],
        "dependencyExplanation": ["Forge has no proven completion for a required predecessor.", "Forge heeft geen bewezen voltooiing van een vereiste voorganger.", "Forge hat keinen Abschlussnachweis für einen erforderlichen Vorgänger.", "Forge n’a pas de preuve de fin pour un prédécesseur requis.", "Forge no tiene finalización probada del predecesor requerido."],
        "holdExplanation": ["Forge reports that this workset is held.", "Forge meldt dat deze werkset in wachtstand staat.", "Forge meldet einen angehaltenen Arbeitssatz.", "Forge signale que cet ensemble est suspendu.", "Forge informa de que este conjunto está retenido."],
        "evidenceExplanation": ["Forge cannot prove the required current subject or completion evidence.", "Forge kan het vereiste actuele onderwerp of voltooiingsbewijs niet aantonen.", "Forge kann den aktuellen Gegenstand oder Abschlussnachweis nicht belegen.", "Forge ne peut prouver l’objet actuel ou la fin requise.", "Forge no puede probar el objeto actual o la evidencia de finalización requerida."],
        "reviewExplanation": ["Forge reports a required progression review.", "Forge meldt een vereiste voortgangsreview.", "Forge meldet eine erforderliche Fortschrittsprüfung.", "Forge signale une revue de progression requise.", "Forge informa de una revisión de progresión requerida."],
        "finalAcceptanceExplanation": ["Forge reports that final Business acceptance is required.", "Forge meldt dat finale Businessacceptatie vereist is.", "Forge meldet eine erforderliche finale Business-Abnahme.", "Forge signale qu’une acceptation Business finale est requise.", "Forge informa de que se requiere aceptación Business final."],
        "authorityExplanation": ["Forge reports an approval, release or runtime-generation condition preventing continuation.", "Forge meldt een goedkeurings-, vrijgave- of runtimegeneratievoorwaarde die voortzetting verhindert.", "Forge meldet eine Genehmigungs-, Freigabe- oder Laufzeitbedingung, die Fortsetzung verhindert.", "Forge signale une condition d’approbation, de libération ou de génération empêchant la suite.", "Forge informa de una condición de aprobación, liberación o generación que impide continuar."],
        "budgetExplanation": ["Forge reports that the activation limit is exhausted.", "Forge meldt dat de activatielimiet is bereikt.", "Forge meldet eine ausgeschöpfte Aktivierungsgrenze.", "Forge signale que la limite d’activation est atteinte.", "Forge informa de que se agotó el límite de activación."],
        "reviewRequired": ["Separate review access for this actor and Mission is required.", "Aparte reviewtoegang voor deze actor en Mission vereist.", "Gesonderter Prüfungszugang für diesen Akteur und diese Mission erforderlich.", "Accès distinct aux revues requis pour cet acteur et cette Mission.", "Se requiere acceso independiente para este actor y Mission."],
        "refresh": ["Refresh worklist", "Werklijst verversen", "Arbeitsliste aktualisieren", "Actualiser la liste", "Actualizar lista"],
        "grant": ["Worklist access token", "Werklijsttoegang", "Arbeitslistenzugang", "Accès à la liste", "Acceso a la lista"],
        "saveGrant": ["Save worklist access", "Werklijsttoegang bewaren", "Arbeitslistenzugang speichern", "Enregistrer l’accès", "Guardar acceso"],
        "forgetGrant": ["Forget worklist access", "Werklijsttoegang vergeten", "Arbeitslistenzugang vergessen", "Oublier l’accès", "Olvidar acceso"],
        "executionState": ["Execution state", "Uitvoeringsstatus", "Ausführungszustand", "État d’exécution", "Estado de ejecución"],
        "reviewState": ["Review state", "Reviewstatus", "Prüfungszustand", "État de revue", "Estado de revisión"],
        "effectMode": ["Effect mode", "Effectmodus", "Wirkungsmodus", "Mode d’effet", "Modo de efecto"],
        "dependencies": ["Verified dependency references", "Geverifieerde afhankelijkheden", "Verifizierte Abhängigkeiten", "Dépendances vérifiées", "Dependencias verificadas"],
        "activationSupport": ["Activation qualification", "Activatiekwalificatie", "Aktivierungsqualifikation", "Qualification d’activation", "Calificación de activación"],
        "installation": ["Forge installation", "Forge-installatie", "Forge-Installation", "Installation Forge", "Instalación Forge"],
        "worksetRevision": ["Workset revision", "Werksetrevisie", "Arbeitssatzrevision", "Révision d’ensemble", "Revisión de conjunto"],
        "budget": ["Budget", "Budget", "Budget", "Budget", "Presupuesto"]
    ]

    static var keys: [String] { values.keys.sorted() }

    static func text(_ key: String, language: String? = nil) -> String {
        guard let translations = values[key] else { return key }
        let index = languages.firstIndex(of: language ?? "en") ?? 0
        return translations[index]
    }
}

struct ApprovedWorklistView: View {
    let cache: WorklistObservationCache
    let onOpenReviews: ((ApprovedWorklistItem) -> Void)?
    @Environment(\.locale) private var locale
    @State private var selectedKey: ApprovedWorklistKey?
    @State private var search: String
    @State private var filter: WorklistFilter
    @State private var sort: WorklistSort
    @FocusState private var searchFocused: Bool

    init(cache: WorklistObservationCache = WorklistObservationCache(),
         selected: ApprovedWorklistKey? = nil, search: String = "",
         filter: WorklistFilter = .all, sort: WorklistSort = .committed,
         onOpenReviews: ((ApprovedWorklistItem) -> Void)? = nil) {
        self.cache = cache
        self.onOpenReviews = onOpenReviews
        _selectedKey = State(initialValue: selected)
        _search = State(initialValue: search)
        _filter = State(initialValue: filter)
        _sort = State(initialValue: sort)
    }

    private func copy(_ key: String) -> String {
        WorklistCopy.text(key, language: locale.language.languageCode?.identifier)
    }

    private var visible: [ApprovedWorklistItem] {
        ApprovedWorklistPresentation.visible(cache.snapshot?.items ?? [], search: search,
                                             filter: filter, sort: sort)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(copy("nav")).font(.largeTitle.bold())
                Text(copy("subtitle")).foregroundStyle(.secondary)
                if cache.usingLastObservation {
                    Text(copy("cachedObservation")).foregroundStyle(.orange)
                        .accessibilityIdentifier("worklist.cached")
                }
                if let snapshot = cache.snapshot {
                    LabeledContent(copy("workset"), value: snapshot.scope.worksetID)
                    LabeledContent(copy("actor"), value: snapshot.scope.actorID)
                    HStack {
                        TextField(copy("search"), text: $search)
                            .textFieldStyle(.roundedBorder).focused($searchFocused)
                            .accessibilityLabel(copy("search"))
                            .accessibilityIdentifier("worklist.search")
                        Button(copy("focusSearch")) { searchFocused = true }
                            .keyboardShortcut("f", modifiers: .command)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack { filterPicker; sortPicker }
                        VStack(alignment: .leading) { filterPicker; sortPicker }
                    }
                    Text(copy("sortHint")).font(.caption).foregroundStyle(.secondary)
                    LabeledContent(copy("membershipRevision"), value: snapshot.membershipRevision)
                    LabeledContent(copy("selectorRevision"), value: snapshot.selectorRevision)
                    LabeledContent(copy("snapshotRevision"), value: snapshot.snapshotRevision)
                    LabeledContent(copy("observedAt"), value: snapshot.observedAt)
                    LabeledContent(copy("installation"), value: snapshot.installationID)
                    LabeledContent(copy("worksetRevision"), value: String(snapshot.worksetRevision))
                    LabeledContent(copy("activationSupport"), value: snapshot.activationSupport)
                    ForEach(snapshot.continuationReasons, id: \.self) { Text($0).font(.caption) }
                    LabeledContent(copy("freshness"), value: copy(cache.usingLastObservation ? "stale" : freshnessKey(snapshot.freshness)))
                    LabeledContent(copy("continuation"), value: copy(continuationKey(snapshot.continuation)))
                    if let next = snapshot.nextMemberID {
                        LabeledContent(copy("nextMember"), value: next)
                    }
                }
                emptyMessage
                ForEach(visible, id: \.key) { item in
                    Button { selectedKey = item.key } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.displayTitle).font(.headline)
                            Text("\(copy("committedPosition")): \(item.committedPosition + 1) · \(item.key.memberID)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(copy("eligible")): \(copy(item.facts.eligible.rawValue)) · \(copy("active")): \(copy(item.facts.active.rawValue))")
                                .font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.displayTitle) · \(copy("committedPosition")) \(item.committedPosition + 1)")
                    .accessibilityIdentifier("worklist.member.\(item.key.memberID)")
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                        selectedKey == item.key ? Color.accentColor : Color.clear, lineWidth: 2))
                }
                if let item = ApprovedWorklistPresentation.selected(selectedKey, in: cache.snapshot) {
                    Divider()
                    if !visible.contains(where: { $0.key == item.key }) {
                        Text(copy("hidden")).foregroundStyle(.secondary)
                    }
                    detail(item)
                } else if cache.snapshot != nil {
                    Text(copy("choose")).foregroundStyle(.secondary)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var filterPicker: some View {
        Picker(copy("filter"), selection: $filter) {
            ForEach(WorklistFilter.allCases, id: \.rawValue) { Text(copy($0.rawValue)).tag($0) }
        }.accessibilityIdentifier("worklist.filter")
    }

    private var sortPicker: some View {
        Picker(copy("sort"), selection: $sort) {
            ForEach(WorklistSort.allCases, id: \.rawValue) { Text(copy($0.rawValue)).tag($0) }
        }.accessibilityIdentifier("worklist.sort")
    }

    @ViewBuilder private var emptyMessage: some View {
        switch ApprovedWorklistPresentation.emptyState(cache, visible: visible) {
        case .hasItems: EmptyView()
        case .noMatches: Text(copy("noMatches")).foregroundStyle(.secondary)
        case .emptyGrantedWorkset: Text(copy("emptyGrantedWorkset")).foregroundStyle(.secondary)
        case .unavailable: Text(copy("unavailable")).foregroundStyle(.orange)
        case .denied: Text(copy("denied")).foregroundStyle(.orange)
        case .offline: Text(copy("offline")).foregroundStyle(.orange)
        case .partial: Text(copy("partial")).foregroundStyle(.orange)
        case .stale: Text(copy("stale")).foregroundStyle(.orange)
        }
    }

    private func detail(_ item: ApprovedWorklistItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent(copy("member"), value: item.key.memberID)
            LabeledContent(copy("subject"), value: item.subjectID)
            LabeledContent(copy("subjectRevision"), value: item.subjectRevision)
            LabeledContent(copy("sourceRevision"), value: item.sourceRevision)
            LabeledContent(copy("project"), value: item.projectID ?? copy("noProject"))
            LabeledContent(copy(item.missionBindingVerified ? "mission" : "unverifiedMissionRef"), value: item.missionID ?? copy("noMission"))
            LabeledContent(copy("executionState"), value: item.executionState)
            LabeledContent(copy("reviewState"), value: item.reviewState)
            LabeledContent(copy("effectMode"), value: item.effectMode)
            Text(copy("dependencies")).font(.headline)
            ForEach(item.dependencies, id: \.self) { Text($0) }
            ForEach(item.evidence, id: \.self) { reference in
                VStack(alignment: .leading) {
                    Text("\(reference.kind) · \(reference.subjectID)")
                    Text(reference.digest).font(.caption)
                }
            }
            Text(copy("facts")).font(.headline)
            ForEach(factRows(item), id: \.0) { key, fact in
                LabeledContent(copy(key), value: copy(fact.rawValue))
            }
            Text(copy("blockers")).font(.headline)
            if item.blockers.isEmpty { Text(copy("noBlockers")).foregroundStyle(.secondary) }
            ForEach(Array(item.blockers.enumerated()), id: \.offset) { _, reason in
                VStack(alignment: .leading) {
                    Text("\(copy(reason.kind.rawValue)) · \(reason.code)").font(.subheadline)
                    if let explanation = reason.explanation { Text(explanation) }
                    else if reason.kind != .unknown { Text(copy(reason.kind.rawValue + "Explanation")) }
                }
            }
            if item.reviewDetailAvailable {
                Button(copy("openReviews")) { onOpenReviews?(item) }
                    .disabled(cache.availability != .available || onOpenReviews == nil)
                    .accessibilityIdentifier("worklist.open-reviews")
            }
        }.textSelection(.enabled)
    }

    private func factRows(_ item: ApprovedWorklistItem) -> [(String, WorklistFact)] {
        [("approved", item.facts.approved), ("released", item.facts.released),
         ("eligible", item.facts.eligible), ("active", item.facts.active),
         ("engineeringComplete", item.facts.engineeringComplete),
         ("reviewAccepted", item.facts.reviewAccepted), ("finalAccepted", item.facts.finalAccepted),
         ("completed", item.facts.completed)]
    }

    private func freshnessKey(_ value: WorklistFreshness) -> String {
        switch value { case .current: "current"; case .stale: "stale"; case .unknown: "unknown" }
    }

    private func continuationKey(_ value: WorklistContinuation) -> String {
        switch value { case .ready: "ready"; case .blocked: "blocked"; case .idle: "idle"; case .unknown: "unknown" }
    }
}
