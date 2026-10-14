import SwiftUI

// Owning display models. The Server adapter must validate real producer output
// before populating these; this file defines no Forge endpoint or fake response.
struct ConceptChatTurn:Identifiable,Equatable {
    let id:String
    let role:String
    let message:String
    let answer:String
    let sourceRevision:Int
}
struct ConceptChatChange:Identifiable,Equatable {
    let field:String
    let before:String
    let after:String
    let reason:String
    var id:String {field}
}
struct ConceptChatProposal:Equatable {
    let reference:String
    let sourceRevision:Int
    let changes:[ConceptChatChange]
}
struct ConceptChatAccess:Equatable {
    let profile:String
    let recipient:String
    let limits:String
    let maySubmit:Bool
}
enum ConceptChatCopy {
    static let languages=["en","nl","de","fr","es"]
    static let values:[String:[String]]=[
        "open":["Develop with Business or Architect","Uitwerken met Business of Architect","Mit Business oder Architect ausarbeiten","Développer avec Business ou Architect","Desarrollar con Business o Architect"],
        "fullNotes":["Read complete saved description","Volledige bewaarde beschrijving lezen","Vollständige Beschreibung lesen","Lire toute la description enregistrée","Leer la descripción guardada completa"],
        "recipient":["Recipient","Ontvanger","Empfänger","Destinataire","Destinatario"],
        "profile":["Configured model profile","Ingesteld modelprofiel","Eingerichtetes Modellprofil","Profil de modèle configuré","Perfil de modelo configurado"],
        "limits":["Known usage limit","Bekende gebruiksgrens","Bekanntes Nutzungslimit","Limite d’utilisation connue","Límite de uso conocido"],
        "notKnown":["Not established","Niet vastgesteld","Nicht festgestellt","Non établi","No determinado"],
        "costUnknown":["A monetary cost or remaining account credit has not been established here.","Kosten in geld of resterende accountcredits zijn hier niet vastgesteld.","Geldkosten oder verbleibendes Kontoguthaben sind hier nicht festgestellt.","Le coût monétaire et le crédit restant du compte ne sont pas établis ici.","Aquí no se han determinado el coste monetario ni los créditos restantes."],
        "summary":[ "Current saved idea","Huidig bewaard idee","Aktuelle gespeicherte Idee","Idée actuellement enregistrée","Idea guardada actual"],
        "chat":["Develop this idea","Dit idee uitwerken","Diese Idee ausarbeiten","Développer cette idée","Desarrollar esta idea"],
        "message":["What would you like to clarify?","Wat wil je verduidelijken?","Was möchtest du klären?","Que souhaitez-vous préciser ?","¿Qué quieres aclarar?"],
        "role":["Advice role","Adviesrol","Beratungsrolle","Rôle du conseil","Rol del asesoramiento"],
        "review":["Review message before sending","Bericht controleren vóór versturen","Nachricht vor dem Senden prüfen","Vérifier le message avant envoi","Revisar mensaje antes de enviar"],
        "send":["Send this message","Dit bericht versturen","Diese Nachricht senden","Envoyer ce message","Enviar este mensaje"],
        "transfer":["This sends your saved concept and message to the configured advice service.","Dit verstuurt je bewaarde concept en bericht naar de ingestelde adviesdienst.","Dein gespeicherter Entwurf und die Nachricht werden an den eingerichteten Beratungsdienst gesendet.","Votre concept enregistré et votre message seront transmis au service de conseil configuré.","Se envían tu concepto guardado y el mensaje al servicio de asesoramiento configurado."],
        "access":["Advice access is needed. You can still edit your idea and create a document-only baseline proposal.","Adviesrechten nodig. Je kunt je idee blijven bewerken en een basisvoorstel zonder model maken.","Beratungszugriff erforderlich. Idee bearbeiten und Dokumentvorschlag ohne Modell bleiben möglich.","Un accès au conseil est nécessaire. Vous pouvez toujours modifier l’idée et créer un document de base sans modèle.","Se necesita acceso al asesoramiento. Puedes editar la idea y crear una propuesta documental sin modelo."],
        "unsaved":["Save your changes before chatting.","Bewaar je wijzigingen voordat je chat.","Vor dem Chat Änderungen speichern.","Enregistrez vos modifications avant de discuter.","Guarda tus cambios antes de conversar."],
        "archived":["Restore this idea before chatting or accepting changes.","Zet dit idee terug voordat je chat of wijzigingen overneemt.","Idee vor Chat oder Übernahme wiederherstellen.","Restaurez l’idée avant de discuter ou d’accepter des modifications.","Restaura la idea antes de conversar o aceptar cambios."],
        "proposal":["Suggested concept changes","Voorgestelde conceptwijzigingen","Vorgeschlagene Änderungen","Modifications proposées du concept","Cambios propuestos del concepto"],
        "before":["Current","Huidig","Aktuell","Actuel","Actual"],
        "after":["Suggested","Voorgesteld","Vorgeschlagen","Proposé","Propuesto"],
        "accept":["Accept into concept","Neem over in concept","In Entwurf übernehmen","Intégrer au concept","Incorporar al concepto"],
        "notApproval":["Accepting changes your concept. It does not approve or configure a project. Create an updated baseline proposal separately.","Overnemen wijzigt je concept. Het keurt geen project goed en richt niets in. Maak een bijgewerkt basisvoorstel apart.","Übernehmen ändert deinen Entwurf, genehmigt oder konfiguriert kein Projekt. Einen aktualisierten Basisvorschlag separat erstellen.","L’intégration modifie le concept, sans approuver ni configurer un projet. Créez séparément une proposition de base actualisée.","Incorporar modifica el concepto, sin aprobar ni configurar un proyecto. Crea por separado una propuesta de base actualizada."],
        "unknown":["Unspecified information remains unknown.","Niet ingevulde informatie blijft onbekend.","Nicht angegebene Informationen bleiben unbekannt.","Les informations non précisées restent inconnues.","La información no indicada sigue siendo desconocida."],
        "close":["Back to concept","Terug naar concept","Zurück zum Entwurf","Retour au concept","Volver al concepto"],
        "revision":["Saved revision","Bewaarde revisie","Gespeicherte Revision","Révision enregistrée","Revisión guardada"],
        "stale":["This suggestion belongs to an earlier saved revision. It cannot be accepted into the current concept.","Deze suggestie hoort bij een eerdere bewaarde revisie. Je kunt haar niet in het huidige concept overnemen.","Dieser Vorschlag gehört zu einer früheren Revision und kann nicht übernommen werden.","Cette suggestion concerne une révision antérieure et ne peut pas être intégrée au concept actuel.","Esta sugerencia pertenece a una revisión anterior y no se puede incorporar al concepto actual."],
        "length":["Use a nonempty message of at most 4,096 characters.","Gebruik een bericht van 1 tot 4.096 tekens.","Nachricht mit 1 bis 4.096 Zeichen verwenden.","Utilisez un message de 1 à 4 096 caractères.","Usa un mensaje de 1 a 4.096 caracteres."],
        "name":["Name","Naam","Name","Nom","Nombre"],
        "purpose":["Purpose","Doel","Ziel","Objectif","Objetivo"],
        "users":["People served","Doelgroep","Zielgruppe","Public visé","Destinatarios"],
        "non_goals":["Outside scope","Buiten afbakening","Außerhalb des Umfangs","Hors périmètre","Fuera del alcance"],
        "constraints":["Constraints","Randvoorwaarden","Rahmenbedingungen","Contraintes","Condiciones"],
        "open_questions":["Open questions","Open vragen","Offene Fragen","Questions ouvertes","Preguntas abiertas"]
    ]
    static func text(_ key:String,_ language:String)->String {
        values[key]?[languages.firstIndex(of:language) ?? 0] ?? key
    }
    static func validMessage(_ value:String)->Bool {
        !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && value.unicodeScalars.count<=4096 && ProjectConcept.validText(value)
    }
}

struct ConceptChatView:View {
    let concept:ProjectConcept
    let dirty:Bool
    var access:ConceptChatAccess?=nil
    var briefingFields:[String:String]=[:]
    var turns:[ConceptChatTurn]=[]
    var proposal:ConceptChatProposal?=nil
    var busy=false
    var onSend:((String,String)->Void)?=nil
    var onAccept:((ConceptChatProposal)->Void)?=nil
    @State var message=""
    @State var role="BUSINESS"
    @State var reviewing=false
    @State private var showingChat=false
    @State private var reviewedMessage:String?
    @State private var reviewedRole:String?
    @State private var reviewedRevision:Int?
    @FocusState private var launchFocused:Bool
    @Environment(\.locale) private var locale
    private var language:String {locale.language.languageCode?.identifier ?? "en"}
    private func text(_ key:String)->String {ConceptChatCopy.text(key,language)}
    private var editable:Bool {!dirty && concept.lifecycle != "ARCHIVED" && !busy}
    private var canSend:Bool {editable && access?.maySubmit==true && onSend != nil && ConceptChatCopy.validMessage(message)}
    private var reviewMatches:Bool {reviewedMessage==message && reviewedRole==role && reviewedRevision==concept.revision}
    private var summary:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(text("summary")).font(.headline)
            Text(verbatim:concept.title).font(.title3)
            LabeledContent(text("revision"),value:String(concept.revision))
            DisclosureGroup(text("fullNotes")) {Text(verbatim:concept.notes).textSelection(.enabled)}
            ForEach(["purpose","users","non_goals","constraints","open_questions"],id:\.self) {field in
                if let value=briefingFields[field],!value.isEmpty {LabeledContent(text(field)) {Text(verbatim:value).textSelection(.enabled)}}
            }
            Text(text("unknown")).foregroundStyle(.secondary)
        }.frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
    }
    private var chat:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(text("chat")).font(.headline)
            if dirty {Text(text("unsaved"))}
            if concept.lifecycle=="ARCHIVED" {Text(text("archived"))}
            if access==nil {Text(text("access")).foregroundStyle(.secondary)}
            ForEach(turns) {turn in
                VStack(alignment:.leading,spacing:6) {
                    Text(verbatim:turn.role=="BUSINESS" ? "Business":"Architect").font(.subheadline.bold())
                    LabeledContent(text("revision"),value:String(turn.sourceRevision))
                    Text(verbatim:turn.message).textSelection(.enabled)
                    Text(verbatim:turn.answer).textSelection(.enabled)
                }.padding().background(.quaternary,in:RoundedRectangle(cornerRadius:10))
            }
            Picker(text("role"),selection:$role) {Text("Business").tag("BUSINESS");Text("Architect").tag("ARCHITECT")}.pickerStyle(.segmented)
            TextField(text("message"),text:$message,axis:.vertical).lineLimit(3...8)
                .disabled(!editable).accessibilityIdentifier("concept-chat-message")
            if !message.isEmpty && !ConceptChatCopy.validMessage(message) {Text(text("length")).foregroundStyle(.secondary)}
            Button(text("review")) {reviewedMessage=message;reviewedRole=role;reviewedRevision=concept.revision;reviewing=true}.disabled(!canSend).accessibilityIdentifier("concept-chat-review")
            if reviewing,let access {
                Text(text("transfer"))
                LabeledContent(text("recipient")) {Text(verbatim:access.recipient.isEmpty ? text("notKnown"):access.recipient).textSelection(.enabled)}
                LabeledContent(text("profile")) {Text(verbatim:access.profile.isEmpty ? text("notKnown"):access.profile).textSelection(.enabled)}
                LabeledContent(text("limits")) {Text(verbatim:access.limits.isEmpty ? text("notKnown"):access.limits).textSelection(.enabled)}
                Text(text("costUnknown")).foregroundStyle(.secondary)
                Button(text("send")) {if reviewMatches,let reviewedRole,let reviewedMessage {onSend?(reviewedRole,reviewedMessage)};reviewing=false}
                    .disabled(!canSend || !reviewMatches).keyboardShortcut(.return,modifiers:.command).accessibilityIdentifier("concept-chat-send")
            }
            if let proposal {
                Divider()
                Text(text("proposal")).font(.headline)
                ForEach(proposal.changes) {change in
                    Text(text(change.field)).font(.subheadline.bold())
                    LabeledContent(text("before")) {Text(verbatim:change.before).textSelection(.enabled)}
                    LabeledContent(text("after")) {Text(verbatim:change.after).textSelection(.enabled)}
                    Text(verbatim:change.reason).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text(text("notApproval")).foregroundStyle(.secondary)
                if proposal.sourceRevision != concept.revision {Text(text("stale"))}
                Button(text("accept")) {onAccept?(proposal)}
                    .disabled(!editable || proposal.sourceRevision != concept.revision || onAccept==nil)
                    .accessibilityIdentifier("concept-chat-accept")
            }
        }.frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
    }
    var body:some View {
        ViewThatFits(in:.horizontal) {
            HStack(alignment:.top,spacing:24) {summary.frame(width:280);chat.frame(minWidth:430)}
            VStack(alignment:.leading,spacing:12) {
                summary
                Button(text("open")) {showingChat=true}.focused($launchFocused).accessibilityIdentifier("concept-chat-open")
                    .keyboardShortcut("j",modifiers:[.command,.option])
            }
        }
        .sheet(isPresented:$showingChat,onDismiss:{launchFocused=true}) {
            ScrollView {VStack(alignment:.leading,spacing:16) {
                Button(text("close")) {showingChat=false}.keyboardShortcut(.escape,modifiers:[])
                summary
                Divider()
                chat
            }.padding(24)}.frame(minWidth:420,idealWidth:620,minHeight:500)
        }
        .onChange(of:concept) {_,_ in reviewing=false;message="";showingChat=false}
        .onChange(of:dirty) {_,_ in reviewing=false}
        .onChange(of:message) {_,_ in reviewing=false}
        .onChange(of:role) {_,_ in reviewing=false}
        .onChange(of:access) {_,_ in reviewing=false}
    }
}
