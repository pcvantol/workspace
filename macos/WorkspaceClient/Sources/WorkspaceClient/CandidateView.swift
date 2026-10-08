import SwiftUI

struct CandidateView:View {
    @ObservedObject var state:CandidateState
    @Environment(\.locale) private var locale
    @State private var grant=""
    @State private var tab="form"
    @FocusState private var focused:String?
    private func copy(_ key:String) -> String { CandidateCopy.text(key,locale:locale.language.languageCode?.identifier ?? "en") }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:12) {
                Text(copy("title")).font(.title2)
                Text(copy("boundary")).font(.caption)
                Text(copy(state.phase)).accessibilityIdentifier("candidate.status")
                if !state.hasGrant {
                    SecureField(copy("grant"),text:$grant).textFieldStyle(.roundedBorder).accessibilityIdentifier("candidate.grant")
                    Button(copy("saveGrant")) { let value=grant;grant="";Task { await state.saveGrantSelection(value) } }.disabled(grant.isEmpty || state.busy)
                    Text(copy("setup")).font(.caption)
                }
                if state.hasGrant {
                    Button(copy("forgetGrant")) { state.forgetGrant() }.disabled(state.busy).accessibilityIdentifier("candidate.grant.forget")
                }
                if let cap=state.capability {
                    Text("\(copy("allowance")): \(cap.maximum_registrations)").font(.caption)
                    Text("\(copy("latestRevision")): ≤ \(cap.maximum_revisions_per_proposal)").font(.caption)
                    Picker(copy("proposalID"),selection:Binding(get:{state.local.proposalID ?? ""},set:{id in Task { await state.chooseProposal(id) }})) {
                        Text(copy("choose")).tag("")
                        ForEach(cap.proposal_ids,id:\.self) { Text(verbatim:$0).tag($0) }
                    }.disabled(state.busy || state.pending).accessibilityIdentifier("candidate.proposal")
                }
                if let s=state.source {
                    GroupBox(copy("advice")) {
                        VStack(alignment:.leading,spacing:6) {
                            Text(verbatim:s.advice_summary).textSelection(.enabled)
                            Text(verbatim:s.advisor_kind+" · "+s.turn_id).font(.caption)
                            Text(verbatim:s.result_digest).font(.caption)
                            Text(copy("adviceOrigin")).font(.caption)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                }
                HStack {
                    Button(copy("form")) { tab="form";focused="title" }.accessibilityIdentifier("candidate.tab.form")
                    Button(copy("preview")) { tab="preview" }.accessibilityIdentifier("candidate.tab.preview")
                    Spacer()
                    Button(copy("refresh")) { Task { await state.refreshSelection() } }.disabled(state.busy).accessibilityIdentifier("candidate.refresh")
                }
                if tab=="form" { form } else { preview }
                if state.pending {
                    Text(copy("pendingBoundary")).font(.caption)
                    if let r=state.local.saveIntent { Text(verbatim:"\(r.proposal_id) · \(r.expected_revision+1)").font(.caption) }
                    if let r=state.local.registrationIntent,state.local.registrationPending { Text(verbatim:r.operation_id).font(.caption) }
                    Button(copy("recover")) { Task { await state.recover() } }.disabled(state.busy).accessibilityIdentifier("candidate.recover")
                }
                if let registered=state.registration {
                    GroupBox(copy("receipt")) {
                        VStack(alignment:.leading,spacing:6) {
                            Text(verbatim:registered.original_receipt.operation_id).font(.caption)
                            Text(verbatim:registered.original_receipt.candidate.id).accessibilityIdentifier("candidate.receipt.id")
                            Text(verbatim:registered.original_receipt.proposal_digest).font(.caption)
                            Text("\(copy("originalRevision")): \(registered.original_receipt.proposal_revision)")
                            Text(verbatim:registered.current.recommendation_status).accessibilityIdentifier("candidate.current.status")
                            Text(verbatim:registered.current.candidate.objective)
                            Text(verbatim:registered.current.candidate_digest).font(.caption)
                            Text(registered.current.source_fresh ? copy("fresh"):copy("stale"))
                            Text(registered.current.mission_allocation ? copy("allocated"):copy("unallocated"))
                            Text(copy("approvalBoundary")).font(.caption)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                }
                Button(copy("close")) { state.open=false }.keyboardShortcut(.cancelAction).accessibilityIdentifier("candidate.close")
            }.padding().frame(maxWidth:.infinity,alignment:.leading)
        }.frame(minWidth:420,idealWidth:620,minHeight:450,idealHeight:700)
        .accessibilityIdentifier("candidate.sheet")
        .onAppear { focused="title" }
        .sheet(isPresented:Binding(get:{state.confirmation != nil},set:{if !$0 { state.cancelConfirmation() }})) {
            confirmation
        }
    }
    private var form:some View {
        VStack(alignment:.leading,spacing:10) {
            Text(copy("userOrigin")).font(.headline)
            Text(copy("lineHint")).font(.caption)
            ForEach(CandidateForm.scalarKeys+CandidateForm.listKeys,id:\.self) { key in
                VStack(alignment:.leading,spacing:4) {
                    Text(copy(key=="title" ? "titleField":key))
                    TextField(copy(key=="title" ? "titleField":key),text:Binding(get:{state.local.form.text[key] ?? ""},set:{state.edit(key,$0)}),axis:.vertical)
                        .lineLimit(1...5).textFieldStyle(.roundedBorder).focused($focused,equals:key)
                        .accessibilityIdentifier("candidate.field."+key).disabled(state.busy)
                }
            }
            Text(copy("effectBoundary")).font(.caption)
            Picker(copy("mode"),selection:Binding(get:{state.local.form.text["mode"] ?? ""},set:{state.edit("mode",$0)})) {
                Text(copy("choose")).tag("")
                ForEach(["READ_ONLY_ASSESSMENT","DOCUMENTATION_ONLY","ARCHITECTURE_DESIGN_ONLY","BOUNDED_REPOSITORY_CHANGE"],id:\.self) { Text(copy($0)).tag($0) }
            }.disabled(state.busy).accessibilityIdentifier("candidate.effect.mode")
            Picker(copy("delivery"),selection:Binding(get:{state.local.form.text["delivery"] ?? ""},set:{state.edit("delivery",$0)})) {
                Text(copy("choose")).tag("")
                Text(copy("EVIDENCE_ONLY")).tag("EVIDENCE_ONLY");Text(copy("GIT")).tag("GIT")
            }.disabled(state.busy).accessibilityIdentifier("candidate.effect.delivery")
            Button(copy("save")) { Task { await state.save() };tab="preview" }.disabled(!state.canSave).accessibilityIdentifier("candidate.save")
            Text(copy("saveBoundary")).font(.caption)
        }
    }
    @ViewBuilder private var preview:some View {
        if let p=state.preview {
            Text("\(copy("selectedRevision")): \(p.proposal.proposal_revision) · \(copy("latestRevision")): \(p.latest_revision)").accessibilityIdentifier("candidate.preview.revisions")
            Text(verbatim:p.proposal.proposal_digest).font(.caption).accessibilityIdentifier("candidate.preview.digest")
            Picker(copy("selectedRevision"),selection:Binding(get:{state.local.revision},set:{r in Task { await state.chooseRevision(r) }})) {
                ForEach(1...p.latest_revision,id:\.self) { Text(String($0)).tag($0) }
            }.disabled(state.busy || state.pending).accessibilityIdentifier("candidate.revision")
            ForEach(CandidateForm.scalarKeys+CandidateForm.listKeys+["mode","delivery"],id:\.self) { key in
                let text=CandidateForm(p.proposal.fields).text[key] ?? ""
                VStack(alignment:.leading,spacing:4) { Text(copy(key=="title" ? "titleField":key)).font(.caption.bold());Text(verbatim:text.isEmpty ? copy("empty"):text).textSelection(.enabled) }
            }
            Text(copy("userOrigin")).font(.caption)
            Button(copy("amend")) { state.loadSelectedFields();tab="form";focused="title" }.disabled(state.busy || state.pending).accessibilityIdentifier("candidate.amend")
            Button(copy("register")) { Task { await state.prepareRegistration() } }.disabled(state.busy || state.pending).accessibilityIdentifier("candidate.register")
        } else { Text(copy("noPreview")) }
    }
    @ViewBuilder private var confirmation:some View {
        if let r=state.confirmation,let p=state.preview {
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    Text(copy("confirmTitle")).font(.title2)
                    Text(verbatim:r.proposal_id+" · \(r.proposal_revision)")
                    Text(verbatim:r.proposal_digest).font(.caption)
                    Text(verbatim:p.proposal.fields.objective)
                    ForEach(["scope","exclusions","read_paths","write_paths","mode","delivery"],id:\.self) { key in
                        Text(copy(key=="title" ? "titleField":key)).font(.caption.bold());Text(verbatim:CandidateForm(p.proposal.fields).text[key] ?? "")
                    }
                    Text(copy("approvalBoundary"))
                    Button(copy("confirm")) { Task { await state.register() } }.accessibilityIdentifier("candidate.confirm")
                    Button(copy("cancel")) { state.cancelConfirmation() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("candidate.confirm.cancel")
                }.padding()
            }.frame(minWidth:420,idealWidth:600,minHeight:450,idealHeight:650).accessibilityIdentifier("candidate.confirmation")
        }
    }
}

enum CandidateCopy {
    static let values:[String:[String:String]] = [
        "en":["title":"Advice to Candidate","boundary":"Save a user-authored proposal; register separately without approval or execution.","grant":"Candidate access token","saveGrant":"Save Candidate access","forgetGrant":"Forget Candidate access","setup":"Separate owner-issued access is required for this conversation.","allowance":"Maximum registrations; consumed keys remain spent","proposalID":"Authorized proposal identity","choose":"Choose explicitly","advice":"Validated source advice","adviceOrigin":"Advice is source material, not your structured input.","form":"Your proposal","preview":"Saved preview","refresh":"Read current status","userOrigin":"Explicit user input","lineHint":"List fields: one item per line. Empty optional lists are allowed.","titleField":"Title","objective":"Objective","business_value":"Business value","engineering_value":"Engineering value","architectural_value":"Architectural value","rationale":"Rationale","confidence":"Your confidence, 0–100","scope":"Scope","exclusions":"Exclusions","acceptance_criteria":"Substantive acceptance criteria","architecture_constraints":"Architecture constraints","dependencies":"Dependencies","read_paths":"Exact proposed read paths","write_paths":"Exact proposed write paths","mode":"Proposed effect mode","delivery":"Proposed delivery","effectBoundary":"A proposed boundary grants no execution rights. Documentary work does not authorize code changes.","READ_ONLY_ASSESSMENT":"Read-only assessment","DOCUMENTATION_ONLY":"Documentation only","ARCHITECTURE_DESIGN_ONLY":"Architecture design only","BOUNDED_REPOSITORY_CHANGE":"Bounded repository change","EVIDENCE_ONLY":"Evidence only","GIT":"Git delivery proposed","save":"Save proposal revision","saveBoundary":"Saving does not register a Candidate or call a model.","selectedRevision":"Selected revision","latestRevision":"Latest revision","originalRevision":"Originally registered revision","amend":"Load this revision to edit","register":"Register this exact revision","empty":"Empty","noPreview":"No saved preview available.","confirmTitle":"Confirm Candidate registration","confirm":"Confirm this registration","cancel":"Cancel confirmation","receipt":"Original receipt and current Candidate","fresh":"Original source is current","stale":"Original source differs from current context","unallocated":"No Mission allocated","allocated":"Current readback reports a Mission allocation","approvalBoundary":"Registration grants no Business or Architecture approval and starts no Mission. Current status is read back separately.","pendingBoundary":"Recovery retains the original request identity. Reopening reads only.","recover":"Recover the original operation","close":"Close, keep your draft","candidateReadOnly":"Separate Candidate access required","candidateOffline":"Unavailable or offline","candidateDenied":"Access denied, expired or revoked","candidateInvalid":"Invalid request or response","candidateMissing":"Scoped source or proposal unavailable","candidateEditing":"Unsent proposal draft","candidateSaving":"Saving exact revision","candidateSaved":"Saved immutable proposal","candidateRegistering":"Registration awaiting readback","candidateRegistered":"Receipt and current Candidate verified","candidatePending":"Original operation pending","candidateUncertain":"Outcome uncertain; read or recover the original request","candidateConflict":"Revision or context changed; review before choosing again","candidateCapacity":"Producer capacity or budget reached","candidateLocalCapacity":"Local draft could not be safely stored","candidateUnsupported":"Candidate route unsupported"],
        "nl":["title":"Advies naar Candidate","boundary":"Sla een eigen voorstel op; registreer afzonderlijk zonder goedkeuring of uitvoering.","grant":"Candidate-toegangstoken","saveGrant":"Candidate-toegang opslaan","forgetGrant":"Candidate-toegang vergeten","setup":"Afzonderlijke owner-uitgegeven toegang is nodig voor dit gesprek.","allowance":"Maximale registraties; verbruikte sleutels blijven verbruikt","proposalID":"Toegestane voorstelidentiteit","choose":"Kies expliciet","advice":"Gevalideerd bronadvies","adviceOrigin":"Advies is bronmateriaal, niet jouw gestructureerde invoer.","form":"Jouw voorstel","preview":"Opgeslagen preview","refresh":"Actuele status lezen","userOrigin":"Expliciete gebruikersinvoer","lineHint":"Lijstvelden: één item per regel. Optionele lijsten mogen leeg zijn.","titleField":"Titel","objective":"Doel","business_value":"Businesswaarde","engineering_value":"Engineeringwaarde","architectural_value":"Architectuurwaarde","rationale":"Onderbouwing","confidence":"Jouw confidence, 0–100","scope":"Scope","exclusions":"Uitsluitingen","acceptance_criteria":"Inhoudelijke acceptatiecriteria","architecture_constraints":"Architectuurconstraints","dependencies":"Afhankelijkheden","read_paths":"Exacte voorgestelde leespaden","write_paths":"Exacte voorgestelde schrijfpaden","mode":"Voorgestelde effectmodus","delivery":"Voorgestelde levering","effectBoundary":"Een voorgestelde grens verleent geen uitvoeringsrechten. Documentair werk staat geen codewijziging toe.","READ_ONLY_ASSESSMENT":"Alleen-lezenbeoordeling","DOCUMENTATION_ONLY":"Alleen documentatie","ARCHITECTURE_DESIGN_ONLY":"Alleen architectuurontwerp","BOUNDED_REPOSITORY_CHANGE":"Begrensde repositorywijziging","EVIDENCE_ONLY":"Alleen bewijs","GIT":"Git-levering voorgesteld","save":"Voorstelrevisie opslaan","saveBoundary":"Opslaan registreert geen Candidate en roept geen model aan.","selectedRevision":"Geselecteerde revisie","latestRevision":"Laatste revisie","originalRevision":"Oorspronkelijk geregistreerde revisie","amend":"Deze revisie laden voor wijziging","register":"Deze exacte revisie registreren","empty":"Leeg","noPreview":"Geen opgeslagen preview beschikbaar.","confirmTitle":"Candidate-registratie bevestigen","confirm":"Deze registratie bevestigen","cancel":"Bevestiging annuleren","receipt":"Oorspronkelijke receipt en actuele Candidate","fresh":"Oorspronkelijke bron is actueel","stale":"Oorspronkelijke bron wijkt af van actuele context","unallocated":"Geen Mission toegewezen","allocated":"Actuele readback meldt een Missiontoewijzing","approvalBoundary":"Registratie verleent geen Business- of Architectuurgoedkeuring en start geen Mission. Actuele status wordt afzonderlijk teruggelezen.","pendingBoundary":"Herstel behoudt de oorspronkelijke requestidentiteit. Heropenen leest alleen.","recover":"Oorspronkelijke operatie herstellen","close":"Sluiten, eigen draft behouden","candidateReadOnly":"Afzonderlijke Candidate-toegang vereist","candidateOffline":"Niet beschikbaar of offline","candidateDenied":"Toegang geweigerd, verlopen of ingetrokken","candidateInvalid":"Ongeldige request of response","candidateMissing":"Bron of voorstel binnen scope ontbreekt","candidateEditing":"Ongestuurde voorsteldraft","candidateSaving":"Exacte revisie wordt opgeslagen","candidateSaved":"Opgeslagen onveranderlijk voorstel","candidateRegistering":"Registratie wacht op readback","candidateRegistered":"Receipt en actuele Candidate geverifieerd","candidatePending":"Oorspronkelijke operatie in behandeling","candidateUncertain":"Uitkomst onzeker; lees of herstel oorspronkelijke request","candidateConflict":"Revisie of context gewijzigd; bekijken vóór nieuwe keuze","candidateCapacity":"Producercapaciteit of budget bereikt","candidateLocalCapacity":"Eigen draft kon niet veilig worden opgeslagen","candidateUnsupported":"Candidate-route niet ondersteund"],
        "de":["title":"Beratung zu Candidate","boundary":"Eigenen Vorschlag speichern; separat ohne Genehmigung oder Ausführung registrieren.","grant":"Candidate-Zugangstoken","saveGrant":"Candidate-Zugang speichern","forgetGrant":"Candidate-Zugang vergessen","setup":"Separater Zugang vom Eigentümer ist für dieses Gespräch erforderlich.","allowance":"Maximale Registrierungen; verbrauchte Schlüssel bleiben verbraucht","proposalID":"Erlaubte Vorschlagsidentität","choose":"Explizit auswählen","advice":"Validierte Quellberatung","adviceOrigin":"Beratung ist Quellenmaterial, keine strukturierte Benutzereingabe.","form":"Ihr Vorschlag","preview":"Gespeicherte Vorschau","refresh":"Aktuellen Status lesen","userOrigin":"Explizite Benutzereingabe","lineHint":"Listenfelder: ein Eintrag pro Zeile. Optionale Listen dürfen leer sein.","titleField":"Titel","objective":"Ziel","business_value":"Geschäftlicher Wert","engineering_value":"Technischer Wert","architectural_value":"Architektonischer Wert","rationale":"Begründung","confidence":"Ihre Zuversicht, 0–100","scope":"Umfang","exclusions":"Ausschlüsse","acceptance_criteria":"Substantielle Abnahmekriterien","architecture_constraints":"Architekturvorgaben","dependencies":"Abhängigkeiten","read_paths":"Exakte vorgeschlagene Lesepfade","write_paths":"Exakte vorgeschlagene Schreibpfade","mode":"Vorgeschlagener Effektmodus","delivery":"Vorgeschlagene Lieferung","effectBoundary":"Eine vorgeschlagene Grenze gewährt keine Ausführungsrechte. Dokumentation erlaubt keine Codeänderung.","READ_ONLY_ASSESSMENT":"Nur-Lese-Bewertung","DOCUMENTATION_ONLY":"Nur Dokumentation","ARCHITECTURE_DESIGN_ONLY":"Nur Architekturentwurf","BOUNDED_REPOSITORY_CHANGE":"Begrenzte Repositoryänderung","EVIDENCE_ONLY":"Nur Nachweise","GIT":"Git-Lieferung vorgeschlagen","save":"Vorschlagsrevision speichern","saveBoundary":"Speichern registriert keinen Candidate und ruft kein Modell auf.","selectedRevision":"Gewählte Revision","latestRevision":"Neueste Revision","originalRevision":"Ursprünglich registrierte Revision","amend":"Diese Revision zum Bearbeiten laden","register":"Diese exakte Revision registrieren","empty":"Leer","noPreview":"Keine gespeicherte Vorschau verfügbar.","confirmTitle":"Candidate-Registrierung bestätigen","confirm":"Diese Registrierung bestätigen","cancel":"Bestätigung abbrechen","receipt":"Originalbeleg und aktueller Candidate","fresh":"Originalquelle ist aktuell","stale":"Originalquelle weicht vom aktuellen Kontext ab","unallocated":"Keine Mission zugewiesen","allocated":"Aktueller Status meldet eine Missionzuweisung","approvalBoundary":"Registrierung erteilt keine Business- oder Architekturgenehmigung und startet keine Mission. Der aktuelle Status wird separat gelesen.","pendingBoundary":"Wiederherstellung behält die ursprüngliche Anfrageidentität. Erneutes Öffnen liest nur.","recover":"Ursprüngliche Operation wiederherstellen","close":"Schließen, eigenen Entwurf behalten","candidateReadOnly":"Separater Candidate-Zugang erforderlich","candidateOffline":"Nicht verfügbar oder offline","candidateDenied":"Zugang verweigert, abgelaufen oder widerrufen","candidateInvalid":"Ungültige Anfrage oder Antwort","candidateMissing":"Quelle oder Vorschlag im Umfang fehlt","candidateEditing":"Nicht gesendeter Vorschlagsentwurf","candidateSaving":"Exakte Revision wird gespeichert","candidateSaved":"Gespeicherter unveränderlicher Vorschlag","candidateRegistering":"Registrierung wartet auf Rücklesung","candidateRegistered":"Beleg und aktueller Candidate verifiziert","candidatePending":"Ursprüngliche Operation ausstehend","candidateUncertain":"Ergebnis ungewiss; ursprüngliche Anfrage lesen oder wiederherstellen","candidateConflict":"Revision oder Kontext geändert; vor neuer Wahl prüfen","candidateCapacity":"Produzentenkapazität oder Budget erreicht","candidateLocalCapacity":"Eigener Entwurf konnte nicht sicher gespeichert werden","candidateUnsupported":"Candidate-Route nicht unterstützt"],
        "fr":["title":"Conseil vers Candidate","boundary":"Enregistrez votre proposition ; inscription séparée sans approbation ni exécution.","grant":"Jeton d'accès Candidate","saveGrant":"Enregistrer l'accès Candidate","forgetGrant":"Oublier l'accès Candidate","setup":"Un accès distinct délivré par le propriétaire est requis pour cette conversation.","allowance":"Inscriptions maximales ; clés consommées conservées","proposalID":"Identité de proposition autorisée","choose":"Choisir explicitement","advice":"Conseil source validé","adviceOrigin":"Le conseil est une source, pas votre saisie structurée.","form":"Votre proposition","preview":"Aperçu enregistré","refresh":"Lire l'état actuel","userOrigin":"Saisie explicite de l'utilisateur","lineHint":"Listes : un élément par ligne. Les listes facultatives peuvent être vides.","titleField":"Titre","objective":"Objectif","business_value":"Valeur métier","engineering_value":"Valeur technique","architectural_value":"Valeur architecturale","rationale":"Justification","confidence":"Votre confiance, 0–100","scope":"Périmètre","exclusions":"Exclusions","acceptance_criteria":"Critères d'acceptation substantiels","architecture_constraints":"Contraintes architecturales","dependencies":"Dépendances","read_paths":"Chemins de lecture proposés exacts","write_paths":"Chemins d'écriture proposés exacts","mode":"Mode d'effet proposé","delivery":"Livraison proposée","effectBoundary":"Une limite proposée ne donne aucun droit d'exécution. La documentation n'autorise pas de modification de code.","READ_ONLY_ASSESSMENT":"Évaluation en lecture seule","DOCUMENTATION_ONLY":"Documentation uniquement","ARCHITECTURE_DESIGN_ONLY":"Conception architecturale uniquement","BOUNDED_REPOSITORY_CHANGE":"Modification limitée du dépôt","EVIDENCE_ONLY":"Preuves uniquement","GIT":"Livraison Git proposée","save":"Enregistrer la révision","saveBoundary":"L'enregistrement n'inscrit aucun Candidate et n'appelle aucun modèle.","selectedRevision":"Révision sélectionnée","latestRevision":"Dernière révision","originalRevision":"Révision inscrite initialement","amend":"Charger cette révision pour modification","register":"Inscrire cette révision exacte","empty":"Vide","noPreview":"Aucun aperçu enregistré disponible.","confirmTitle":"Confirmer l'inscription Candidate","confirm":"Confirmer cette inscription","cancel":"Annuler la confirmation","receipt":"Reçu original et Candidate actuel","fresh":"La source originale est actuelle","stale":"La source originale diffère du contexte actuel","unallocated":"Aucune Mission attribuée","allocated":"La lecture actuelle signale une attribution de Mission","approvalBoundary":"L'inscription n'accorde aucune approbation métier ou architecture et ne lance aucune Mission. L'état actuel est lu séparément.","pendingBoundary":"La récupération conserve l'identité initiale. La réouverture lit uniquement.","recover":"Récupérer l'opération originale","close":"Fermer et conserver votre brouillon","candidateReadOnly":"Accès Candidate distinct requis","candidateOffline":"Indisponible ou hors ligne","candidateDenied":"Accès refusé, expiré ou révoqué","candidateInvalid":"Requête ou réponse invalide","candidateMissing":"Source ou proposition du périmètre absente","candidateEditing":"Brouillon de proposition non envoyé","candidateSaving":"Enregistrement de la révision exacte","candidateSaved":"Proposition immuable enregistrée","candidateRegistering":"Inscription en attente de lecture","candidateRegistered":"Reçu et Candidate actuel vérifiés","candidatePending":"Opération originale en attente","candidateUncertain":"Résultat incertain ; lire ou récupérer la requête originale","candidateConflict":"Révision ou contexte modifié ; examiner avant de choisir","candidateCapacity":"Capacité ou budget du producteur atteint","candidateLocalCapacity":"Le brouillon n'a pas pu être enregistré en sécurité","candidateUnsupported":"Route Candidate non prise en charge"],
        "es":["title":"Asesoramiento a Candidate","boundary":"Guarde su propuesta; registre por separado sin aprobación ni ejecución.","grant":"Token de acceso Candidate","saveGrant":"Guardar acceso Candidate","forgetGrant":"Olvidar acceso Candidate","setup":"Esta conversación requiere acceso independiente emitido por el propietario.","allowance":"Registros máximos; las claves consumidas siguen consumidas","proposalID":"Identidad de propuesta autorizada","choose":"Elegir explícitamente","advice":"Asesoramiento fuente validado","adviceOrigin":"El consejo es material fuente, no su entrada estructurada.","form":"Su propuesta","preview":"Vista previa guardada","refresh":"Leer estado actual","userOrigin":"Entrada explícita del usuario","lineHint":"Listas: un elemento por línea. Las listas opcionales pueden estar vacías.","titleField":"Título","objective":"Objetivo","business_value":"Valor empresarial","engineering_value":"Valor técnico","architectural_value":"Valor arquitectónico","rationale":"Justificación","confidence":"Su confianza, 0–100","scope":"Alcance","exclusions":"Exclusiones","acceptance_criteria":"Criterios de aceptación sustanciales","architecture_constraints":"Restricciones arquitectónicas","dependencies":"Dependencias","read_paths":"Rutas de lectura propuestas exactas","write_paths":"Rutas de escritura propuestas exactas","mode":"Modo de efecto propuesto","delivery":"Entrega propuesta","effectBoundary":"Un límite propuesto no otorga derechos de ejecución. La documentación no autoriza cambios de código.","READ_ONLY_ASSESSMENT":"Evaluación de solo lectura","DOCUMENTATION_ONLY":"Solo documentación","ARCHITECTURE_DESIGN_ONLY":"Solo diseño arquitectónico","BOUNDED_REPOSITORY_CHANGE":"Cambio limitado del repositorio","EVIDENCE_ONLY":"Solo evidencia","GIT":"Entrega Git propuesta","save":"Guardar revisión de propuesta","saveBoundary":"Guardar no registra un Candidate ni llama a un modelo.","selectedRevision":"Revisión seleccionada","latestRevision":"Última revisión","originalRevision":"Revisión registrada originalmente","amend":"Cargar esta revisión para editar","register":"Registrar esta revisión exacta","empty":"Vacío","noPreview":"No hay vista previa guardada.","confirmTitle":"Confirmar registro Candidate","confirm":"Confirmar este registro","cancel":"Cancelar confirmación","receipt":"Recibo original y Candidate actual","fresh":"La fuente original está actualizada","stale":"La fuente original difiere del contexto actual","unallocated":"Ninguna Mission asignada","allocated":"La lectura actual indica una asignación de Mission","approvalBoundary":"El registro no otorga aprobación empresarial ni arquitectónica y no inicia ninguna Mission. El estado actual se lee por separado.","pendingBoundary":"La recuperación conserva la identidad original. Reabrir solo lee.","recover":"Recuperar la operación original","close":"Cerrar y conservar su borrador","candidateReadOnly":"Se requiere acceso Candidate independiente","candidateOffline":"No disponible o sin conexión","candidateDenied":"Acceso denegado, caducado o revocado","candidateInvalid":"Solicitud o respuesta no válida","candidateMissing":"Falta fuente o propuesta del alcance","candidateEditing":"Borrador de propuesta sin enviar","candidateSaving":"Guardando revisión exacta","candidateSaved":"Propuesta inmutable guardada","candidateRegistering":"Registro pendiente de lectura","candidateRegistered":"Recibo y Candidate actual verificados","candidatePending":"Operación original pendiente","candidateUncertain":"Resultado incierto; leer o recuperar solicitud original","candidateConflict":"Revisión o contexto cambiado; revisar antes de elegir","candidateCapacity":"Capacidad o presupuesto del productor alcanzado","candidateLocalCapacity":"No se pudo guardar el borrador de forma segura","candidateUnsupported":"Ruta Candidate no compatible"],
    ]
    static func text(_ key:String,locale:String) -> String { values[locale]?[key] ?? values["en"]?[key] ?? key }
}
