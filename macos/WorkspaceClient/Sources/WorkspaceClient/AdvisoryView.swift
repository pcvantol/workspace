import SwiftUI

enum AdvisoryCopy {
    static func text(_ key:String, language:String) -> String {
        let index=["en","nl","de","fr","es"].firstIndex(of:language) ?? 0
        let values:[String:[String]] = [
            "adviceNew":["No Forge transcript exists yet. Explicit send may start the first turn under current access.","Nog geen Forge-transcript. Expliciet verzenden kan de eerste beurt onder actuele toegang starten.","Noch kein Forge-Verlauf. Explizites Senden kann den ersten Beitrag unter aktuellem Zugang starten.","Aucun historique Forge pour le moment. Un envoi explicite peut démarrer le premier tour avec l’accès actuel.","Aún no existe historial Forge. El envío explícito puede iniciar el primer turno con el acceso actual."],
            "conversation":["Conversation","Gesprek","Gespräch","Conversation","Conversación"],
            "budget":["Retained / maximum","Behouden / maximum","Beibehalten / Maximum","Conservé / maximum","Conservado / máximo"],
            "tokens":["Observed tokens","Waargenomen tokens","Beobachtete Tokens","Jetons observés","Tokens observados"],
            "model":["Observed model / effort","Waargenomen model / effort","Beobachtetes Modell / Aufwand","Modèle / effort observé","Modelo / esfuerzo observado"],
            "title":["Business / Architect advice","Business-/Architectadvies","Business-/Architekturberatung","Conseil Business / Architecte","Consejo Business / Arquitectura"],
            "boundary":["Advice finishes advice only. It does not create a Candidate, approval, Mission or repository change.","Advies voltooit alleen advies. Het maakt geen Candidate, goedkeuring, Mission of repositorywijziging.","Beratung beendet nur Beratung. Kein Candidate, keine Genehmigung, Mission oder Repositoryänderung.","Le conseil termine seulement le conseil. Aucun Candidate, accord, Mission ou changement de dépôt.","El consejo completa solo el consejo. No crea Candidate, aprobación, Mission ni cambio de repositorio."],
            "draftBoundary":["Sending freezes a copy. Your editor text stays available for explicit save/discard and later edits.","Verzenden bevriest een kopie. Je editortekst blijft beschikbaar voor opslaan/verwerpen en latere edits.","Senden friert eine Kopie ein. Der Editor bleibt zum Speichern, Verwerfen und Bearbeiten verfügbar.","L’envoi fige une copie. Le texte de l’éditeur reste disponible pour enregistrer, annuler et modifier.","Enviar fija una copia. El editor conserva el texto para guardar, descartar y editar."],
            "grant":["Separate advice access","Aparte adviestoegang","Gesonderter Beratungszugang","Accès distinct au conseil","Acceso separado al consejo"],
            "saveGrant":["Save advice access","Adviestoegang bewaren","Beratungszugang speichern","Enregistrer l’accès au conseil","Guardar acceso al consejo"],
            "forgetGrant":["Forget advice access","Adviestoegang vergeten","Beratungszugang vergessen","Oublier l’accès au conseil","Olvidar acceso al consejo"],
            "refresh":["Refresh authorized advice","Geautoriseerd advies verversen","Autorisierte Beratung aktualisieren","Actualiser le conseil autorisé","Actualizar consejo autorizado"],
            "send":["Send this text for advice","Deze tekst voor advies verzenden","Diesen Text zur Beratung senden","Envoyer ce texte pour conseil","Enviar este texto para consejo"],
            "resume":["Read back and explicitly recover same turn","Teruglezen en dezelfde beurt expliciet herstellen","Rücklesen und denselben Beitrag explizit wiederherstellen","Relire et récupérer explicitement le même tour","Consultar y recuperar explícitamente el mismo turno"],
            "cancel":["Request cancellation intent","Annuleringsintentie aanvragen","Abbruchabsicht anfordern","Demander l’intention d’annulation","Solicitar intención de cancelación"],
            "cancelBoundary":["Cancellation records intent only; provider_stopped is false. Consumption and uncertainty remain.","Annuleren legt alleen intentie vast; provider_stopped is false. Verbruik en onzekerheid blijven.","Abbruch speichert nur die Absicht; provider_stopped ist false. Verbrauch und Ungewissheit bleiben.","L’annulation enregistre une intention ; provider_stopped est false. Consommation et incertitude restent.","Cancelar registra intención; provider_stopped es false. Consumo e incertidumbre permanecen."],
            "history":["Canonical authorized history","Canonieke geautoriseerde historie","Kanonischer autorisierter Verlauf","Historique canonique autorisé","Historial canónico autorizado"],
            "submitted":["Submitted immutable text","Ingestuurde onveranderlijke tekst","Eingereichter unveränderlicher Text","Texte envoyé immuable","Texto enviado inmutable"],
            "result":["Validated Forge advice","Gevalideerd Forge-advies","Validierte Forge-Beratung","Conseil Forge validé","Consejo Forge validado"],
            "empty":["No authorized turns returned on this page.","Geen geautoriseerde beurten teruggelezen op deze pagina.","Keine autorisierten Beiträge auf dieser Seite.","Aucun tour autorisé retourné sur cette page.","No hay turnos autorizados en esta página."],
            "more":["Next history page","Volgende historiepagina","Nächste Verlaufsseite","Page d’historique suivante","Siguiente página de historial"],
            "context":["Permitted context before send","Toegestane context vóór verzenden","Erlaubter Kontext vor dem Senden","Contexte autorisé avant envoi","Contexto permitido antes de enviar"],
            "pins":["Sources are pinned observations, not proof of the current repository head. At most two sources; at most 1000 text characters.","Bronnen zijn gepinde observaties, geen bewijs van de actuele repository-head. Hoogstens twee bronnen en 1000 teksttekens.","Quellen sind fixierte Beobachtungen, kein Nachweis des aktuellen Repositorystands. Höchstens zwei Quellen und 1000 Textzeichen.","Les sources sont des observations fixées, pas une preuve du dépôt actuel. Deux sources et 1000 caractères maximum.","Las fuentes son observaciones fijadas, no prueba del repositorio actual. Máximo dos fuentes y 1000 caracteres."],
            "unsupportedUX":["UX drafts remain usable; UX generation is unsupported.","UX-concepten blijven bruikbaar; UX-generatie is unsupported.","UX-Entwürfe bleiben nutzbar; UX-Generierung ist nicht unterstützt.","Les brouillons UX restent utilisables ; génération UX non prise en charge.","Los borradores UX siguen disponibles; generación UX no compatible."],
            "quality":["Live commercial advice quality: not qualified. Unreported model/effort stays NOT_REPORTED.","Live commerciële advieskwaliteit: niet gekwalificeerd. Niet gerapporteerd model/effort blijft NOT_REPORTED.","Live-Beratungsqualität: nicht qualifiziert. Nicht gemeldetes Modell/Aufwand bleibt NOT_REPORTED.","Qualité commerciale en direct : non qualifiée. Modèle/effort non déclaré reste NOT_REPORTED.","Calidad comercial en vivo: no calificada. Modelo/esfuerzo no informado permanece NOT_REPORTED."],
            "observation":["Last authorized observation; refresh checks current access.","Laatste geautoriseerde observatie; verversen controleert actuele toegang.","Letzte autorisierte Beobachtung; Aktualisieren prüft den Zugang.","Dernière observation autorisée ; actualiser vérifie l’accès.","Última observación autorizada; actualizar comprueba el acceso."],
            "adviceReadOnly":["No separate advisory capability bound to this existing conversation.","Geen aparte adviescapability gekoppeld aan dit bestaande gesprek.","Keine gesonderte Beratungscapability für dieses bestehende Gespräch.","Aucune capacité distincte liée à cette conversation existante.","No hay capacidad separada vinculada a esta conversación existente."],
            "adviceCurrent":["Authorized history and context read back; no generation requested.","Geautoriseerde historie en context teruggelezen; geen generatie gevraagd.","Autorisierter Verlauf und Kontext gelesen; keine Generierung angefordert.","Historique et contexte autorisés relus ; aucune génération demandée.","Historial y contexto autorizados consultados; no se solicitó generación."],
            "adviceSending":["Sending the persisted exact turn; execution not yet proven.","De exact opgeslagen beurt wordt verstuurd; uitvoering nog niet bewezen.","Gespeicherten genauen Beitrag senden; Ausführung noch unbewiesen.","Envoi du tour exact enregistré ; exécution non prouvée.","Enviando el turno exacto guardado; ejecución aún no probada."],
            "adviceComplete":["Advice COMPLETE verified by exact turn readback.","Advies-COMPLETE geverifieerd via exacte beurtreadback.","Beratung COMPLETE durch genaue Beitragsrücklesung bestätigt.","Conseil COMPLETE vérifié par lecture du tour exact.","Consejo COMPLETE verificado consultando el turno exacto."],
            "adviceFailed":["Recorded turn has no validated complete advice; consumption is retained.","Vastgelegde beurt heeft geen gevalideerd volledig advies; verbruik blijft behouden.","Gespeicherter Beitrag ohne vollständige validierte Beratung; Verbrauch bleibt.","Tour enregistré sans conseil complet validé ; consommation conservée.","Turno registrado sin consejo completo validado; consumo conservado."],
            "adviceDenied":["Advice or source access denied, revoked or expired; transcript cleared.","Advies-/brontoegang geweigerd, ingetrokken of verlopen; transcript gewist uit beeld.","Beratungs-/Quellenzugang verweigert, widerrufen oder abgelaufen; Anzeige geleert.","Accès au conseil/source refusé, révoqué ou expiré ; affichage vidé.","Acceso al consejo/fuente denegado, revocado o vencido; vista limpiada."],
            "adviceUncertain":["Pending or MAY_HAVE_HAPPENED. No automatic resend or regeneration.","Pending of MAY_HAVE_HAPPENED. Geen automatische herverzending of regeneratie.","Ausstehend oder MAY_HAVE_HAPPENED. Kein automatisches erneutes Senden.","En attente ou MAY_HAVE_HAPPENED. Aucun renvoi ou régénération automatique.","Pendiente o MAY_HAVE_HAPPENED. Sin reenvío ni regeneración automática."],
            "adviceCancelIntent":["Cancellation intent recorded or awaiting readback; provider stop is not guaranteed.","Annuleringsintentie vastgelegd of wacht op readback; providerstop niet gegarandeerd.","Abbruchabsicht gespeichert oder wartet auf Rücklesung; Providerstopp ungesichert.","Intention d’annulation enregistrée ou attendue ; arrêt du fournisseur non garanti.","Intención de cancelación registrada o pendiente; parada del proveedor no garantizada."],
            "adviceBusy":["Forge reports an existing busy conversation; no replacement turn sent.","Forge meldt een bezet gesprek; geen vervangende beurt verstuurd.","Forge meldet ein belegtes Gespräch; kein Ersatzbeitrag gesendet.","Forge signale une conversation occupée ; aucun tour de remplacement envoyé.","Forge informa de conversación ocupada; no se envió turno de reemplazo."],
            "adviceBudget":["Turn or retention capacity reached. Do not replace the grant/conversation or erase history to reset it.","Beurt-/retentiecapaciteit bereikt. Vervang grant/gesprek of wis historie niet om dit te resetten.","Beitrags-/Aufbewahrungskapazität erreicht. Kein Zugangstausch oder Verlaufsreset.","Capacité de tours/rétention atteinte. Aucun remplacement d’accès ou effacement pour réinitialiser.","Capacidad de turnos/retención agotada. No reemplazar acceso ni borrar historial para reiniciar."],
            "adviceStale":["Scope, revision or context conflict. Original intent stays frozen; refresh before explicit recovery.","Scope-, revisie- of contextconflict. Oorspronkelijke intentie blijft bevroren; ververs vóór expliciet herstel.","Bereichs-, Versions- oder Kontextkonflikt. Originalabsicht bleibt fixiert; vor Wiederherstellung aktualisieren.","Conflit de portée, version ou contexte. Intention originale figée ; actualiser avant récupération.","Conflicto de alcance, revisión o contexto. Intención original fija; actualizar antes de recuperar."],
            "adviceUnsupported":["Advisory capability or selected lens unavailable.","Adviescapability of gekozen lens niet beschikbaar.","Beratungscapability oder ausgewählte Sicht nicht verfügbar.","Capacité de conseil ou perspective indisponible.","Capacidad de consejo o perspectiva no disponible."],
            "adviceOffline":["Advice source offline/unavailable; local draft stays intact.","Adviesbron offline/onbeschikbaar; lokaal concept blijft intact.","Beratungsquelle offline/nicht verfügbar; lokaler Entwurf bleibt erhalten.","Source de conseil hors ligne/indisponible ; brouillon local conservé.","Fuente de consejo sin conexión/no disponible; borrador local intacto."],
            "adviceInvalid":["Request/result is unverified; no authoritative advice shown.","Verzoek/resultaat niet geverifieerd; geen gezaghebbend advies getoond.","Anfrage/Ergebnis unbestätigt; keine maßgebliche Beratung angezeigt.","Demande/résultat non vérifié ; aucun conseil faisant foi affiché.","Solicitud/resultado sin verificar; no se muestra consejo autorizado."],
            "adviceOtherPending":["Another scoped turn intent remains unresolved. It cannot be reused here.","Een andere scopegebonden beurtintentie blijft onopgelost. Die kan hier niet worden hergebruikt.","Eine andere bereichsgebundene Absicht bleibt offen und kann hier nicht verwendet werden.","Une autre intention liée à sa portée reste ouverte et ne peut être réutilisée ici.","Otra intención vinculada a su alcance sigue sin resolver y no puede reutilizarse aquí."]
        ]
        return values[key]?[index] ?? key
    }
}
struct AdvisoryView: View {
    @ObservedObject var state:AdvisoryState
    @ObservedObject var candidates:CandidateState
    @ObservedObject var drafts:ConversationState
    let connection:() async -> AdvisoryConnection?
    @Environment(\.locale) private var locale
    @State private var grant=""
    @FocusState private var inspectorEntry:String?
    @FocusState private var candidateEntry:String?
    private func copy(_ key:String) -> String { AdvisoryCopy.text(key,language:locale.language.languageCode?.identifier ?? "en") }
    var body: some View {
        GroupBox(copy("title")) {
            VStack(alignment:.leading,spacing:12) {
                Text(copy("boundary")).font(.caption)
                Text(copy("draftBoundary")).font(.caption)
                Text(copy(state.phase)).accessibilityIdentifier("advisory.status")
                if let conversation=drafts.selectedConversation {
                    LabeledContent(ConversationCopy.text("title"),value:conversation.title)
                    LabeledContent(ConversationCopy.text("project"),value:conversation.project_id)
                    LabeledContent(copy("conversation"),value:conversation.id)
                    LabeledContent(ConversationCopy.text("mode"),value:modeLabel(drafts.mode))
                }
                if !state.hasGrant {
                    SecureField(copy("grant"),text:$grant).textFieldStyle(.roundedBorder)
                    Button(copy("saveGrant")) { let value=grant;grant="";Task { await state.saveGrant(value,connection:connection()) } }
                        .disabled(grant.isEmpty || state.busy || state.pending != nil).accessibilityIdentifier("advisory.grant.save")
                } else {
                    Button(copy("forgetGrant")) { state.forgetGrant() }.disabled(state.busy || state.pending != nil)
                }
                Button(copy("refresh")) { Task { await state.refresh(connection()) } }.disabled(state.busy).accessibilityIdentifier("advisory.refresh")
                if candidates.hasOwnDraft {
                    Button(CandidateCopy.text("form",locale:locale.language.languageCode?.identifier ?? "en")) {
                        Task { await candidates.openOwnDraft(connection()) }
                    }.disabled(candidates.busy).accessibilityIdentifier("candidate.open-own-draft")
                }
                if let cap=state.capability {
                    GroupBox(copy("context")) {
                        VStack(alignment:.leading,spacing:8) {
                            Text(copy("pins")).font(.caption)
                            Text(verbatim:cap.context_revision).font(.caption)
                            ForEach(cap.available_sources,id:\.version) { source in
                                Toggle(isOn:Binding(get:{state.selectedSources.contains(AdvisorySource(source_id:source.source_id,version:source.version))},set:{ included in
                                    Task { await state.select(AdvisorySource(source_id:source.source_id,version:source.version),include:included,connection:connection()) }
                                })) { Text(verbatim:"\(source.source_id) · \(source.revision) · \(source.path)").font(.caption) }
                                .disabled(state.busy || state.pending != nil).accessibilityIdentifier("advisory.source."+source.source_id)
                            }
                            ForEach(cap.context.missing_sources,id:\.self) { Text(verbatim:$0).font(.caption) }
                            ForEach(cap.context.limitations,id:\.self) { Text(verbatim:$0).font(.caption) }
                            LabeledContent(copy("budget"),value:"\(cap.retained_principal_consumed_turns) / \(cap.maximum_turns)")
                        }
                    }
                    Text(copy("quality")).font(.caption)
                }
                if drafts.mode=="UX" { Text(copy("unsupportedUX")) }
                Button(copy("send")) {
                    let text=drafts.draft,mode=drafts.mode
                    Task { await state.send(text:text,mode:mode,connection:connection()) }
                }.disabled(candidates.open || !drafts.canEdit || !state.canSend(text:drafts.draft,mode:drafts.mode))
                    .keyboardShortcut(.return,modifiers:.command).accessibilityIdentifier("advisory.send")
                if let pending=state.pending,state.pendingForSelection {
                    Text(verbatim:pending.request.turn_id).font(.caption)
                    Button(copy("resume")) { Task { await state.resume(connection()) } }.disabled(state.busy).accessibilityIdentifier("advisory.resume")
                    Button(copy("cancel")) { Task { await state.cancel(connection()) } }.disabled(pending.cancel != nil).accessibilityIdentifier("advisory.cancel")
                    Text(copy("cancelBoundary")).font(.caption)
                }
                if let latest=state.latest,!state.history.contains(where:{$0.request.turn_id==latest.turn.request.turn_id}) { turn(latest.turn) }
                Text(copy("history")).font(.headline)
                Text(copy("observation")).font(.caption)
                if state.history.isEmpty { Text(copy("empty")) }
                ForEach(state.history,id:\.request.turn_id) { turn($0) }
                if state.nextCursor != nil {
                    Button(copy("more")) { Task { await state.more(connection()) } }.disabled(state.busy).accessibilityIdentifier("advisory.history.next")
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
        .sheet(isPresented:Binding(get:{state.inspectorOpen},set:{ if !$0 { state.closeInspector() } })) {
            AdvisoryInspectorView(state:state)
        }
        .sheet(isPresented:$candidates.open) { CandidateView(state:candidates) }
        .onChange(of:candidates.open) { _,isOpen in if !isOpen { candidateEntry=candidates.local.turnID } }
        .onChange(of:state.inspectedTurnID) { old,new in if new==nil { inspectorEntry=old } }
    }
    private func modeLabel(_ mode:String) -> String { ConversationCopy.text(mode=="BUSINESS" ? "business":mode=="ARCHITECTURE" ? "architect":"ux") }
    @ViewBuilder private func turn(_ t:AdvisoryTurnRecord) -> some View {
        GroupBox(modeLabel(t.request.advisor_kind)+" · "+t.status) {
            VStack(alignment:.leading,spacing:6) {
                Text(verbatim:t.request.turn_id).font(.caption)
                Text(copy("submitted")).font(.caption.bold())
                Text(verbatim:t.request.objective).textSelection(.enabled)
                if t.hasValidatedAdvice {
                    Button(CandidateCopy.text("title",locale:locale.language.languageCode?.identifier ?? "en")) {
                        candidateEntry=t.request.turn_id;Task { await candidates.begin(t,connection:connection()) }
                    }.disabled(state.busy || candidates.busy).accessibilityIdentifier("advisory.candidate."+t.request.turn_id).focused($candidateEntry,equals:t.request.turn_id)
                }
                if t.hasValidatedAdvice,let output=t.outcome?.output {
                    Text(copy("result")).font(.caption.bold())
                    Text(verbatim:output.summary).textSelection(.enabled)
                    ForEach(AdvisoryAnswerCategory.allCases.filter{$0 != .summary}) { category in
                        Text(AdvisoryInspectorCopy.text(category.rawValue,language:locale.language.languageCode?.identifier ?? "en")).font(.caption.bold())
                        ForEach(Array(category.items(t).enumerated()),id:\.offset) { Text(verbatim:$0.element).textSelection(.enabled) }
                    }
                    ForEach(Array(output.evidence_references.enumerated()),id:\.offset) { Text(verbatim:$0.element).font(.caption) }
                    if let usage=t.outcome?.usage { LabeledContent(copy("tokens"),value:"\(usage.input_tokens) / \(usage.output_tokens)") }
                    LabeledContent(copy("model"),value:"NOT_REPORTED / NOT_REPORTED")
                }
                Button(AdvisoryInspectorCopy.text("inspect",language:locale.language.languageCode?.identifier ?? "en")) { state.inspect(t.request.turn_id) }
                    .disabled(state.busy || !state.hasGrant || state.capability==nil)
                    .focused($inspectorEntry,equals:t.request.turn_id)
                    .accessibilityIdentifier("advisory.inspect."+t.request.turn_id)
                Text(verbatim:t.execution).font(.caption)
                Text(verbatim:t.admitted_at).font(.caption)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.accessibilityIdentifier("advisory.turn."+t.request.turn_id)
    }
}
