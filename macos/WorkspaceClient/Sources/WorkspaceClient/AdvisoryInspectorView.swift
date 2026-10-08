import SwiftUI

enum AdvisoryInspectorCopy {
    static func text(_ key:String,language:String) -> String {
        let index=["en","nl","de","fr","es"].firstIndex(of:language) ?? 0
        let words:[String:[String]] = [
            "inspect":["Inspect this turn","Deze beurt inspecteren","Diesen Beitrag prüfen","Inspecter ce tour","Inspeccionar este turno"],
            "title":["Advice inspector","Adviesinspecteur","Beratungsinspektor","Inspection du conseil","Inspector de consejo"],
            "backHistory":["Back to history","Terug naar historie","Zurück zum Verlauf","Retour à l’historique","Volver al historial"],
            "backAnswer":["Back to answer","Terug naar antwoord","Zurück zur Antwort","Retour à la réponse","Volver a la respuesta"],
            "summary":["Summary","Samenvatting","Zusammenfassung","Résumé","Resumen"],
            "alternatives":["Alternatives","Alternatieven","Alternativen","Alternatives","Alternativas"],
            "questions":["Open questions","Open vragen","Offene Fragen","Questions ouvertes","Preguntas abiertas"],
            "suggestions":["Recommendations","Aanbevelingen","Empfehlungen","Recommandations","Recomendaciones"],
            "emptyCategory":["No items supplied for this category.","Geen items geleverd voor deze categorie.","Für diese Kategorie wurden keine Einträge geliefert.","Aucun élément fourni pour cette catégorie.","No se proporcionaron elementos en esta categoría."],
            "integrity":["Validated transport is not live content verification. Advice is not a decision or applied change.","Gevalideerd transport is geen live inhoudscontrole. Advies is geen besluit of toegepaste wijziging.","Validierter Transport ist keine Live-Inhaltsprüfung. Beratung ist keine Entscheidung oder angewandte Änderung.","Un transport validé ne vérifie pas le contenu en direct. Un conseil n’est pas une décision ni une modification appliquée.","El transporte validado no verifica el contenido en vivo. El consejo no es una decisión ni un cambio aplicado."],
            "frozen":["Context used for this turn","Context gebruikt voor deze beurt","Für diesen Beitrag verwendeter Kontext","Contexte utilisé pour ce tour","Contexto usado para este turno"],
            "nextContext":["Current source choices apply to a future send; they do not rewrite this turn.","Actuele bronkeuzes gelden voor een volgende verzending; ze herschrijven deze beurt niet.","Aktuelle Quellen gelten für ein künftiges Senden; sie ändern diesen Beitrag nicht.","Les sources actuelles concernent un prochain envoi ; elles ne réécrivent pas ce tour.","Las fuentes actuales se aplican a un envío futuro; no reescriben este turno."],
            "lens":["Original lens","Oorspronkelijke lens","Ursprüngliche Perspektive","Perspective originale","Perspectiva original"],
            "objective":["Submitted text","Ingestuurde tekst","Eingereichter Text","Texte envoyé","Texto enviado"],
            "conversation":["Conversation","Gesprek","Gespräch","Conversation","Conversación"],
            "turn":["Turn","Beurt","Beitrag","Tour","Turno"],
            "session":["Session","Sessie","Sitzung","Session","Sesión"],
            "contextRevision":["Frozen context revision","Bevroren contextrevisie","Fixierte Kontextversion","Version du contexte figé","Revisión del contexto fijado"],
            "dataset":["Recorded dataset generation","Vastgelegde datasetgeneratie","Erfasste Datensatzgeneration","Génération des données enregistrée","Generación de datos registrada"],
            "freshness":["Recorded freshness","Vastgelegde actualiteit","Erfasste Aktualität","Actualité enregistrée","Vigencia registrada"],
            "selected":["Selected source versions","Geselecteerde bronversies","Ausgewählte Quellversionen","Versions des sources sélectionnées","Versiones de fuentes seleccionadas"],
            "included":["Included sources","Opgenomen bronnen","Einbezogene Quellen","Sources incluses","Fuentes incluidas"],
            "missing":["Missing sources","Ontbrekende bronnen","Fehlende Quellen","Sources manquantes","Fuentes ausentes"],
            "limitations":["Recorded limitations","Vastgelegde beperkingen","Erfasste Einschränkungen","Limites enregistrées","Limitaciones registradas"],
            "references":["Inspect source references","Bronverwijzingen inspecteren","Quellverweise prüfen","Inspecter les références","Inspeccionar referencias"],
            "source":["Source metadata","Bronmetadata","Quellmetadaten","Métadonnées de la source","Metadatos de la fuente"],
            "sourceUnavailable":["Source metadata unavailable under current access.","Bronmetadata niet beschikbaar onder actuele toegang.","Quellmetadaten unter aktuellem Zugang nicht verfügbar.","Métadonnées indisponibles avec l’accès actuel.","Metadatos no disponibles con el acceso actual."],
            "sourceUnlinked":["No verifiable source-version link is supplied for this reference.","Geen verifieerbare bronversiekoppeling geleverd voor deze verwijzing.","Für diesen Verweis ist keine prüfbare Quellversion geliefert.","Aucun lien vérifiable vers une version de source n’est fourni.","No se proporcionó un enlace verificable a una versión de fuente."],
            "sourceVersionMissing":["Metadata for this exact source version is missing; a newer version cannot fill it.","Metadata voor deze exacte bronversie ontbreekt; een nieuwere versie vult dit niet aan.","Metadaten dieser exakten Quellversion fehlen; eine neuere Version ersetzt sie nicht.","Les métadonnées de cette version exacte manquent ; une version récente ne les remplace pas.","Faltan metadatos de esta versión exacta; una versión nueva no los sustituye."],
            "sourceAmbiguous":["Multiple metadata records match; the reference cannot be verified.","Meerdere metadatarecords passen; de verwijzing is niet verifieerbaar.","Mehrere Metadaten passen; der Verweis ist nicht prüfbar.","Plusieurs métadonnées correspondent ; référence non vérifiable.","Coinciden varios registros; la referencia no puede verificarse."],
            "sourceUnverifiable":["Supplied metadata cannot be safely verified or displayed.","Geleverde metadata is niet veilig verifieerbaar of toonbaar.","Gelieferte Metadaten sind nicht sicher prüfbar oder darstellbar.","Métadonnées fournies non vérifiables ou affichables en sécurité.","Los metadatos proporcionados no pueden verificarse o mostrarse de forma segura."],
            "pins":["Pinned observation only, not proof of current repository head. Inspection downloads nothing.","Alleen een gepinde observatie, geen bewijs van actuele repository-head. Inspectie downloadt niets.","Nur fixierte Beobachtung, kein Beleg des aktuellen Repositorystands. Prüfung lädt nichts herunter.","Observation figée, pas une preuve de la tête actuelle du dépôt. Aucun téléchargement.","Solo una observación fijada, no una prueba del estado actual del repositorio. No se descarga nada."],
            "repository":["Repository","Repository","Repository","Dépôt","Repositorio"],
            "revision":["Repository revision","Repositoryrevisie","Repositoryversion","Révision du dépôt","Revisión del repositorio"],
            "path":["Repository path","Repositorypad","Repositorypfad","Chemin du dépôt","Ruta del repositorio"],
            "digest":["Content digest","Inhoudsdigest","Inhaltsdigest","Empreinte du contenu","Huella del contenido"],
            "technical":["Provenance and execution details","Herkomst en uitvoeringsdetails","Herkunft und Ausführungsdetails","Provenance et détails d’exécution","Procedencia y detalles de ejecución"],
            "requestDigest":["Request digest","Verzoekdigest","Anfragedigest","Empreinte de la demande","Huella de la solicitud"],
            "resultDigest":["Result digest","Resultaatdigest","Ergebnisdigest","Empreinte du résultat","Huella del resultado"],
            "recordedTime":["Recorded time","Vastgelegde tijd","Erfasste Zeit","Heure enregistrée","Hora registrada"],
            "execution":["Recorded execution state","Vastgelegde uitvoeringsstatus","Erfasster Ausführungsstatus","État d’exécution enregistré","Estado de ejecución registrado"],
            "requestedModel":["Requested model / effort","Aangevraagd model / effort","Angefordertes Modell / Aufwand","Modèle / effort demandé","Modelo / esfuerzo solicitado"],
            "observedModel":["Observed model / effort","Waargenomen model / effort","Beobachtetes Modell / Aufwand","Modèle / effort observé","Modelo / esfuerzo observado"],
            "usage":["Recorded usage status","Vastgelegde verbruikstatus","Erfasster Verbrauchsstatus","État d’usage enregistré","Estado de consumo registrado"],
            "unknown":["Not reported","Niet gemeld","Nicht gemeldet","Non signalé","No informado"],
            "unavailable":["No currently authorized turn is selected.","Geen actueel geautoriseerde beurt geselecteerd.","Kein aktuell autorisierter Beitrag ausgewählt.","Aucun tour actuellement autorisé sélectionné.","No se ha seleccionado un turno autorizado actualmente."]
        ]
        return words[key]?[index] ?? key
    }
}

struct AdvisoryInspectorView:View {
    @ObservedObject var state:AdvisoryState
    @Environment(\.locale) private var locale
    @FocusState private var backFocused:Bool
    @State private var technicalExpanded=false
    private func copy(_ key:String) -> String { AdvisoryInspectorCopy.text(key,language:locale.language.languageCode?.identifier ?? "en") }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(copy("title")).font(.title2)
                Spacer()
                Button(copy(state.inspectedReference==nil ? "backHistory":"backAnswer")) { state.inspectorBack() }
                    .keyboardShortcut(.cancelAction).focused($backFocused).accessibilityIdentifier("inspector.back")
            }
            if let turn=state.inspectedTurn {
                ScrollView {
                    VStack(alignment:.leading,spacing:14) {
                        if let reference=state.inspectedReference { source(reference,turn:turn) }
                        else { answer(turn) }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(2)
                }.accessibilityIdentifier("inspector.scroll")
            } else { Text(copy("unavailable")) }
        }.padding(20).frame(minWidth:420,idealWidth:640,minHeight:420,idealHeight:620)
            .onAppear { backFocused=true }
    }
    private func literal(_ text:String) -> some View { Text(verbatim:text).textSelection(.enabled).fixedSize(horizontal:false,vertical:true) }
    private func field(_ label:String,_ value:String) -> some View {
        VStack(alignment:.leading,spacing:2) { Text(copy(label)).font(.caption.bold());literal(value) }
    }
    @ViewBuilder private func answer(_ t:AdvisoryTurnRecord) -> some View {
        Text(copy("integrity")).font(.caption)
        ViewThatFits(in:.horizontal) {
            HStack { categories }
            VStack(alignment:.leading) { categories }
        }
        GroupBox(copy(state.inspectorCategory.rawValue)) {
            VStack(alignment:.leading,spacing:8) {
                let items=state.inspectorCategory.items(t)
                if items.isEmpty { Text(copy("emptyCategory")) }
                ForEach(Array(items.enumerated()),id:\.offset) { literal($0.element) }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.accessibilityIdentifier("inspector.answer."+state.inspectorCategory.rawValue)
        GroupBox(copy("frozen")) {
            VStack(alignment:.leading,spacing:8) {
                Text(copy("nextContext")).font(.caption)
                field("lens",t.request.advisor_kind)
                field("objective",t.request.objective)
                field("conversation",t.request.conversation_id)
                field("turn",t.request.turn_id)
                field("session",t.session_id)
                field("contextRevision",t.request.context_revision)
                field("dataset",String(t.context.dataset_generation))
                field("freshness",t.context.freshness)
                Text(copy("selected")).font(.headline)
                if t.request.selected_sources.isEmpty { Text(copy("emptyCategory")) }
                ForEach(Array(t.request.selected_sources.enumerated()),id:\.offset) { literal($0.element.source_id+" · "+$0.element.version) }
                lines("included",t.context.included_sources)
                lines("missing",t.context.missing_sources)
                lines("limitations",t.context.limitations)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
        Text(copy("references")).font(.headline)
        let references=t.hasValidatedAdvice ? t.outcome?.output?.evidence_references ?? []:t.context.evidence_references
        if references.isEmpty { Text(copy("emptyCategory")) }
        ForEach(Array(references.enumerated()),id:\.offset) { index,reference in
            Button { state.inspectReference(reference) } label: { Text(verbatim:reference).fixedSize(horizontal:false,vertical:true) }
                .accessibilityIdentifier("inspector.reference.\(index)")
        }
        DisclosureGroup(copy("technical"),isExpanded:$technicalExpanded) {
            VStack(alignment:.leading,spacing:8) {
                field("requestDigest",t.request_digest)
                field("resultDigest",t.outcome?.result_digest ?? copy("unknown"))
                field("recordedTime",t.admitted_at);field("execution",t.execution)
                field("requestedModel",(t.provider.requested_model ?? copy("unknown"))+" / "+t.provider.requested_effort)
                field("observedModel",(t.outcome?.observed_model ?? copy("unknown"))+" / "+(t.outcome?.observed_effort ?? copy("unknown")))
                field("usage",t.outcome?.usage_status ?? copy("unknown"))
                if t.outcome?.usage_status=="OBSERVED",let usage=t.outcome?.usage { literal("\(usage.input_tokens) / \(usage.output_tokens)") }
                else { Text(copy("unknown")) }
            }
        }.accessibilityIdentifier("inspector.technical")
    }
    private var categories:some View {
        ForEach(AdvisoryAnswerCategory.allCases) { category in
            Button(copy(category.rawValue)) { state.inspectCategory(category) }
                .accessibilityIdentifier("inspector.category."+category.rawValue)
                .accessibilityValue(state.inspectorCategory==category ? ConversationCopy.text("selected"):"")
        }
    }
    private func lines(_ label:String,_ values:[String]) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(copy(label)).font(.headline)
            if values.isEmpty { Text(copy("emptyCategory")) }
            ForEach(Array(values.enumerated()),id:\.offset) { literal($0.element) }
        }
    }
    @ViewBuilder private func source(_ reference:String,turn:AdvisoryTurnRecord) -> some View {
        Text(copy("source")).font(.headline);literal(reference)
        switch AdvisoryInspector.source(reference,turn:turn,capability:state.capability) {
        case .unavailable(let reason):Text(copy(reason)).accessibilityIdentifier("inspector.source.unavailable")
        case .metadata(let metadata):
            Text(copy("pins")).font(.caption)
            literal(metadata.source_id);literal(metadata.version)
            field("repository",metadata.repository)
            field("revision",metadata.revision)
            field("path",metadata.path)
            field("digest",metadata.content_digest)
        }
    }
}
