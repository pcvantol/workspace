import SwiftUI

enum WorklistControlCopy {
    static let values: [String: [String]] = [
        "controlTitle": ["Workset waiting control", "Werkset-wachtstand", "Wartesteuerung des Arbeitssatzes", "Mise en attente de l’ensemble", "Espera del conjunto"],
        "controlBoundary": ["Hold blocks only new future Mission admission. Already admitted Missions, including execution not yet started, continue under their own conditions.", "Wachtstand blokkeert alleen nieuwe Mission-admission. Reeds opgenomen Missions, ook met nog niet gestarte uitvoering, lopen onder hun eigen voorwaarden door.", "Warten blockiert nur neue Mission-Aufnahmen. Bereits aufgenommene Missions, auch vor dem Ausführungsstart, laufen nach eigenen Bedingungen weiter.", "L’attente bloque uniquement les nouvelles admissions. Les Missions déjà admises, même avant exécution, continuent selon leurs conditions.", "La espera solo bloquea nuevas admisiones. Las Missions ya admitidas, incluso antes de ejecutar, continúan bajo sus condiciones."],
        "controlUnholdBoundary": ["Removing your exact hold does not approve/start work or clear other acceptance, release, evidence, authority or budget conditions.", "Opheffen verwijdert alleen uw exacte wachtstand. Het keurt of start geen werk en wist geen andere acceptatie-, vrijgave-, bewijs-, bevoegdheids- of budgetvoorwaarden.", "Aufheben entfernt nur Ihre genaue Sperre. Es genehmigt/startet keine Arbeit und löscht keine weiteren Abnahme-, Freigabe-, Nachweis-, Berechtigungs- oder Budgetbedingungen.", "La levée retire uniquement votre attente exacte. Elle n’approuve/démarre aucun travail et ne supprime aucune autre condition d’acceptation, libération, preuve, autorité ou budget.", "Levantar elimina solo su espera exacta. No aprueba/inicia trabajo ni elimina otras condiciones de aceptación, liberación, pruebas, autoridad o presupuesto."],
        "controlHold": ["Put in hold", "In wachtstand zetten", "In Wartestellung setzen", "Mettre en attente", "Poner en espera"],
        "controlUnhold": ["Remove my hold", "Mijn wachtstand opheffen", "Meine Wartestellung aufheben", "Lever mon attente", "Levantar mi espera"],
        "controlGrant": ["Separate control access token", "Aparte commandotoegang", "Separater Steuerungszugang", "Accès de commande distinct", "Acceso de control separado"],
        "controlSave": ["Save control access", "Commandotoegang bewaren", "Steuerungszugang speichern", "Enregistrer l’accès", "Guardar acceso"],
        "controlForget": ["Forget control access", "Commandotoegang vergeten", "Steuerungszugang vergessen", "Oublier l’accès", "Olvidar acceso"],
        "controlReadOnly": ["Read-only: no separate command access.", "Alleen lezen: geen aparte commandotoegang.", "Nur Lesen: kein separater Steuerungszugang.", "Lecture seule : aucun accès de commande distinct.", "Solo lectura: sin acceso de control separado."],
        "controlCurrent": ["Verified current control state", "Geverifieerde actuele wachtstand", "Verifizierter aktueller Steuerungszustand", "État de commande actuel vérifié", "Estado actual de control verificado"],
        "controlPending": ["Execution unknown or pending. Read back the original operation before explicit recovery.", "Uitvoering onbekend of pending. Lees de oorspronkelijke operatie terug vóór expliciet herstel.", "Ausführung unbekannt oder ausstehend. Ursprünglichen Vorgang vor expliziter Wiederherstellung rücklesen.", "Exécution inconnue ou en attente. Relire l’opération initiale avant reprise explicite.", "Ejecución desconocida o pendiente. Consultar la operación original antes de recuperar explícitamente."],
        "controlSending": ["Sending the persisted operation", "De bewaarde operatie verzenden", "Gespeicherten Vorgang senden", "Envoi de l’opération enregistrée", "Enviando la operación guardada"],
        "controlApplied": ["Original receipt verified; current state is shown separately.", "Oorspronkelijke receipt geverifieerd; actuele toestand staat apart.", "Ursprünglicher Beleg verifiziert; aktueller Zustand separat angezeigt.", "Reçu initial vérifié ; état actuel affiché séparément.", "Recibo original verificado; estado actual mostrado por separado."],
        "controlConflict": ["Stale/CAS, lease or bounded command-history conflict. Refresh; do not change revisions or silently create another operation.", "Verouderde/CAS-intentie, lease of begrensde commandogeschiedenis. Ververs; wijzig geen revisies en maak niet stil een nieuwe operatie.", "Veraltete/CAS-Absicht, Sperre oder begrenzte Vorgangshistorie. Aktualisieren; keine Revisionen ändern oder still einen neuen Vorgang erzeugen.", "Conflit de révision/CAS, verrou ou historique borné. Actualiser sans modifier les révisions ni créer discrètement une autre opération.", "Conflicto de revisión/CAS, bloqueo o historial limitado. Actualizar sin cambiar revisiones ni crear otra operación silenciosamente."],
        "controlDenied": ["Control access denied, expired or revoked.", "Commandotoegang geweigerd, verlopen of ingetrokken.", "Steuerungszugang verweigert, abgelaufen oder widerrufen.", "Accès de commande refusé, expiré ou révoqué.", "Acceso de control denegado, vencido o revocado."],
        "controlOffline": ["Control source offline or unavailable; no automatic resend.", "Commandobron offline of niet beschikbaar; geen automatische herverzending.", "Steuerungsquelle offline oder nicht verfügbar; kein automatisches erneutes Senden.", "Source de commande hors ligne ou indisponible ; aucun renvoi automatique.", "Fuente de control sin conexión o no disponible; sin reenvío automático."],
        "controlInvalid": ["Unverified control response; current result unknown.", "Niet geverifieerd commandantwoord; actueel resultaat onbekend.", "Unverifizierte Steuerungsantwort; aktuelles Ergebnis unbekannt.", "Réponse de commande non vérifiée ; résultat actuel inconnu.", "Respuesta de control no verificada; resultado actual desconocido."],
        "controlUnsupported": ["This control capability is unavailable.", "Deze commandocapability is niet beschikbaar.", "Diese Steuerungsfähigkeit ist nicht verfügbar.", "Cette capacité de commande est indisponible.", "Esta capacidad de control no está disponible."],
        "controlHeld": ["Currently held", "Actueel in wachtstand", "Aktuell angehalten", "Actuellement en attente", "Actualmente en espera"],
        "controlNotHeld": ["Not currently held", "Actueel niet in wachtstand", "Aktuell nicht angehalten", "Actuellement hors attente", "Actualmente sin espera"],
        "controlForeign": ["Foreign or local-owner hold: this grant cannot remove it.", "Andere of lokale eigenaarshold: deze grant kan die niet opheffen.", "Fremde oder lokale Eigentümersperre: dieser Zugang kann sie nicht aufheben.", "Attente étrangère ou du propriétaire local : cet accès ne peut la lever.", "Espera ajena o del propietario local: este acceso no puede levantarla."],
        "controlLegacy": ["Legacy hold: ownership and exact target are unknown.", "Legacy-wachtstand: eigendom en exacte target zijn onbekend.", "Alte Sperre: Eigentümer und genaues Ziel unbekannt.", "Ancienne attente : propriétaire et cible exacte inconnus.", "Espera heredada: propietario y objetivo exacto desconocidos."],
        "controlReason": ["Reason", "Reden", "Grund", "Motif", "Motivo"],
        "USER_REQUEST": ["User request", "Gebruikersverzoek", "Benutzerwunsch", "Demande utilisateur", "Solicitud del usuario"],
        "TEMPORARY_WAIT": ["Temporary wait", "Tijdelijke wachtstand", "Vorübergehendes Warten", "Attente temporaire", "Espera temporal"],
        "controlConfirm": ["Confirm this exact command", "Bevestig dit exacte commando", "Diesen genauen Befehl bestätigen", "Confirmer cette commande exacte", "Confirmar este comando exacto"],
        "controlCancel": ["Cancel confirmation", "Bevestiging annuleren", "Bestätigung abbrechen", "Annuler la confirmation", "Cancelar confirmación"],
        "controlResume": ["Read back and explicitly resume same operation", "Teruglezen en dezelfde operatie expliciet hervatten", "Rücklesen und denselben Vorgang explizit fortsetzen", "Relire et reprendre explicitement la même opération", "Consultar y reanudar explícitamente la misma operación"],
        "controlOperation": ["Operation ID", "Operatie-ID", "Vorgangs-ID", "ID d’opération", "ID de operación"],
        "controlAdmitted": ["Already admitted Missions", "Reeds opgenomen Missions", "Bereits aufgenommene Missions", "Missions déjà admises", "Missions ya admitidas"],
        "controlDefinition": ["Workset definition revision", "Werksetdefinitierevisie", "Arbeitssatz-Definitionsrevision", "Révision de définition de l’ensemble", "Revisión de definición del conjunto"],
        "controlRevision": ["Control revision", "Wachtstandrevisie", "Steuerungsrevision", "Révision de commande", "Revisión de control"],
        "controlDiscard": ["Resolve or abandon only an unrecorded local intent", "Teruglezen of alleen een niet vastgelegde lokale intentie verlaten", "Rücklesen oder nur eine ungespeicherte lokale Absicht verwerfen", "Résoudre ou abandonner uniquement une intention locale non enregistrée", "Resolver o abandonar solo una intención local no registrada"],
        "controlOriginal": ["Original effect; not current state", "Oorspronkelijk effect; niet de actuele toestand", "Ursprüngliche Wirkung; nicht aktueller Zustand", "Effet initial ; pas l’état actuel", "Efecto original; no estado actual"]
    ]
    static func text(_ key: String, language: String) -> String {
        guard let values = values[key] else { return WorklistCopy.text(key, language: language) }
        return values[["en", "nl", "de", "fr", "es"].firstIndex(of: language) ?? 0]
    }
}

struct WorklistControlView: View {
    @ObservedObject var state: WorklistControlState
    let connection: () async -> WorklistConnection?
    @Environment(\.locale) private var locale
    @State private var token = ""
    @State private var reason = "USER_REQUEST"
    private func copy(_ key: String) -> String { WorklistControlCopy.text(key, language: locale.language.languageCode?.identifier ?? "en") }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy("controlTitle")).font(.headline)
            Text(copy("controlBoundary")).font(.caption)
            Text(copy("controlUnholdBoundary")).font(.caption)
            Text(copy(state.phase)).accessibilityIdentifier("worklist.control.status")
            if !state.hasGrant {
                SecureField(copy("controlGrant"), text: $token).textFieldStyle(.roundedBorder)
                Button(copy("controlSave")) { let submitted = token; token = ""; Task { await state.saveGrant(submitted, connection: connection(), scope: stateScope) } }
                    .disabled(token.isEmpty || state.busy || state.pending != nil)
            } else {
                Button(copy("controlForget")) { state.forgetGrant() }.disabled(state.busy || state.pending != nil)
            }
            if let current = state.current {
                LabeledContent(copy("workset"), value: current.workset_id)
                Text(copy(current.held ? "controlHeld" : "controlNotHeld")).accessibilityIdentifier("worklist.control.held")
                LabeledContent(copy("worksetRevision"), value: String(current.workset_revision))
                LabeledContent(copy("controlRevision"), value: String(current.control_revision))
                if current.hold_provenance == "LEGACY_UNKNOWN" { Text(copy("controlLegacy")) }
                else if current.held && current.hold?.owned_by_principal != true { Text(copy("controlForeign")) }
                LabeledContent(copy("controlAdmitted"), value: current.admitted_mission_ids.joined(separator: ", "))
                Picker(copy("controlReason"), selection: $reason) {
                    ForEach(["USER_REQUEST", "TEMPORARY_WAIT"], id: \.self) { Text(copy($0)).tag($0) }
                }
                HStack {
                    Button(copy("controlHold")) { state.prepare(intent: "hold", reason: reason) }
                        .disabled(!current.mayHold || state.busy || state.pending != nil)
                        .accessibilityIdentifier("worklist.control.hold")
                    Button(copy("controlUnhold")) { state.prepare(intent: "unhold", reason: reason) }
                        .disabled(!current.mayUnhold || state.busy || state.pending != nil)
                        .accessibilityIdentifier("worklist.control.unhold")
                }
            }
            if let request = state.confirmation {
                Divider()
                Text(copy(request.intent == "hold" ? "controlHold" : "controlUnhold")).font(.headline)
                LabeledContent(copy("workset"), value: request.workset_id)
                LabeledContent(copy("controlOperation"), value: request.operation_id)
                LabeledContent(copy("controlDefinition"), value: request.definition_revision)
                LabeledContent(copy("worksetRevision"), value: String(request.expected_revision))
                LabeledContent(copy("controlReason"), value: copy(request.reason_code))
                if let target = request.hold_operation_id { Text(target + " · " + String(request.expected_hold_revision ?? 0)) }
                Button(copy("controlConfirm")) { Task { await state.confirm(connection: connection()) } }
                    .disabled(state.busy).accessibilityIdentifier("worklist.control.confirm")
                Button(copy("controlCancel")) { state.cancelConfirmation() }.accessibilityIdentifier("worklist.control.cancel")
            }
            if let pending = state.pending {
                LabeledContent(copy("controlOperation"), value: pending.request.operation_id)
                Text(pending.request.workset_id)
                Button(copy("controlResume")) { Task { await state.resume(connection: connection()) } }
                    .disabled(state.busy).accessibilityIdentifier("worklist.control.resume")
                Button(copy("controlDiscard")) { Task { await state.resolveOrDiscardUnrecorded(connection: connection()) } }
                    .disabled(state.busy).accessibilityIdentifier("worklist.control.discard-unrecorded")
            }
            if let receipt = state.receipt {
                Text(copy("controlOriginal")).font(.caption)
                Text(receipt.operation_id + " · " + copy(receipt.request.intent == "hold" ? "controlHold" : "controlUnhold") + " · " + String(receipt.effect.workset_revision))
            }
        }.padding(.horizontal, 18)
    }
    var stateScope: ApprovedWorklistScope?
}
