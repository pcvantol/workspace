import SwiftUI

enum ConceptBaselineCopy {
    static let languages=["en","nl","de","fr","es"]
    static let values:[String:[String]]=[
        "refreshAccess":["Check connection","Verbinding controleren","Verbindung prüfen","Vérifier la connexion","Verificar conexión"],
        "sourceRejected":["This request was rejected because the saved source changed. The original request is preserved.","Deze aanvraag is geweigerd omdat de opgeslagen bron veranderde. De oorspronkelijke aanvraag blijft bewaard.","Gespeicherte Quelle geändert; Anfrage abgelehnt. Die ursprüngliche Anfrage bleibt erhalten.","Demande refusée car la source enregistrée a changé. La demande initiale est conservée.","Solicitud rechazada por cambio de fuente. Se conserva la solicitud original."],
        "newAfterRejected":["Check original and start a new request","Controleer origineel en begin een nieuwe aanvraag","Original prüfen und neue Anfrage beginnen","Vérifier l’original et commencer une nouvelle demande","Verificar original e iniciar otra solicitud"],
        "summary":["English template summary","Engelse templatesamenvatting","Englische Vorlagenzusammenfassung","Résumé du modèle en anglais","Resumen de plantilla en inglés"],
        "productDocs":["Project definition","Projectdefinitie","Projektdefinition","Définition du projet","Definición del proyecto"],
        "architectureDocs":["Architecture","Architectuur","Architektur","Architecture","Arquitectura"],
        "roadmapDocs":["Roadmap","Roadmap","Roadmap","Feuille de route","Hoja de ruta"],
        "workingDocs":["Working agreements","Werkafspraken","Arbeitsvereinbarungen","Accords de travail","Acuerdos de trabajo"],
        "otherDocs":["Supporting files","Ondersteunende bestanden","Unterstützende Dateien","Fichiers de support","Archivos de apoyo"],
        "resume":["Resume original request","Oorspronkelijke aanvraag hervatten","Ursprüngliche Anfrage fortsetzen","Reprendre la demande initiale","Reanudar solicitud original"],
        "original":["Original saved source for this request","Oorspronkelijke opgeslagen bron van deze aanvraag","Ursprüngliche gespeicherte Quelle dieser Anfrage","Source enregistrée initiale de cette demande","Fuente guardada original de esta solicitud"],
        "sourceChanged":["This proposal uses an earlier saved revision. Your current idea is preserved.","Dit voorstel gebruikt een eerdere opgeslagen revisie. Je huidige idee blijft bewaard.","Dieser Vorschlag nutzt eine frühere Revision. Die aktuelle Idee bleibt erhalten.","Cette proposition utilise une révision antérieure. L’idée actuelle est conservée.","Esta propuesta usa una revisión anterior. Se conserva la idea actual."],
        "readOnly":["Existing proposals can be read. Creating a new one requires separate access.","Bestaande voorstellen kun je lezen. Een nieuw voorstel maken vereist afzonderlijke toegang.","Bestehende Vorschläge sind lesbar. Neue benötigen gesonderten Zugriff.","Les propositions existantes sont lisibles. En créer une nécessite un accès distinct.","Puedes leer propuestas anteriores. Crear otra requiere acceso independiente."],
        "notFound":["The original proposal is not available with this connection.","Het oorspronkelijke voorstel is niet beschikbaar met deze verbinding.","Ursprünglicher Vorschlag mit dieser Verbindung nicht verfügbar.","La proposition initiale n’est pas disponible avec cette connexion.","La propuesta original no está disponible con esta conexión."],
        "unavailable":["The proposal service could not be read. Refresh this idea.","De voorstelservice kon niet worden gelezen. Vernieuw dit idee.","Vorschlagsdienst nicht lesbar. Idee aktualisieren.","Service de propositions indisponible. Actualisez cette idée.","No se pudo leer el servicio. Actualiza esta idea."],
        "documents":["Proposed documents","Voorgestelde documenten","Vorgeschlagene Dokumente","Documents proposés","Documentos propuestos"],
        "questions":["Open questions","Open vragen","Offene Fragen","Questions ouvertes","Preguntas abiertas"],
        "open":["Read original request result","Resultaat oorspronkelijke aanvraag lezen","Ergebnis der ursprünglichen Anfrage lesen","Lire le résultat de la demande initiale","Leer el resultado de la solicitud original"],
        "ready":["Connected proposal service","Verbonden voorstelservice","Verbundener Vorschlagsdienst","Service de propositions connecté","Servicio de propuestas conectado"],
        "offline":["The result is uncertain. Retry the original request.","De uitkomst is onzeker. Hervat de oorspronkelijke aanvraag.","Das Ergebnis ist ungewiss. Ursprüngliche Anfrage fortsetzen.","Le résultat est incertain. Reprenez la demande initiale.","El resultado es incierto. Reanuda la solicitud original."],
        "conflict":["The saved source or access changed. Refresh this idea.","De opgeslagen bron of toegang is gewijzigd. Vernieuw dit idee.","Quelle oder Zugriff geändert. Idee aktualisieren.","Source ou accès modifié. Actualisez cette idée.","La fuente o el acceso ha cambiado. Actualiza esta idea."],
        "invalid":["The response could not be verified.","Het antwoord kon niet worden gecontroleerd.","Antwort konnte nicht geprüft werden.","La réponse n’a pas pu être vérifiée.","No se pudo verificar la respuesta."],
        "make":["Create baseline proposal","Basisvoorstel maken","Basisvorschlag erstellen","Créer une proposition de base","Crear propuesta de base"],
        "review":["Review saved source","Opgeslagen bron controleren","Gespeicherte Quelle prüfen","Vérifier la source enregistrée","Revisar fuente guardada"],
        "noModel":["No model call is made.","Er wordt geen model aangeroepen.","Es wird kein Modell aufgerufen.","Aucun modèle n’est appelé.","No se llama a ningún modelo."],
        "badge":["Proposal — project not configured","Voorstel — project nog niet ingericht","Vorschlag — Projekt noch nicht eingerichtet","Proposition — projet non configuré","Propuesta — proyecto sin configurar"],
        "about":["Propose baseline documents, without code, repository creation or publication.","Stel basisdocumenten voor, zonder code, repository-aanmaak of publicatie.","Basisdokumente vorschlagen, ohne Code, Repository-Erstellung oder Veröffentlichung.","Proposer des documents de base, sans code, création de dépôt ni publication.","Proponer documentos de base, sin código, creación de repositorio ni publicación."],
        "english":["The document templates are English. Your supplied text stays unchanged.","De documenttemplates zijn Engels. Je aangeleverde tekst blijft ongewijzigd.","Die Dokumentvorlagen sind Englisch. Ihr Text bleibt unverändert.","Les modèles de documents sont en anglais. Votre texte reste inchangé.","Las plantillas están en inglés. Tu texto permanece sin cambios."],
        "source":["Saved source","Opgeslagen bron","Gespeicherte Quelle","Source enregistrée","Fuente guardada"],
        "revision":["Saved revision","Opgeslagen revisie","Gespeicherte Revision","Révision enregistrée","Revisión guardada"],
        "purpose":["Purpose supplied to Forge","Doelbeschrijving naar Forge","Zweckbeschreibung für Forge","Description du but envoyée à Forge","Descripción del propósito para Forge"],
        "shorter":["Choose a purpose of at most 4096 characters. Your full notes are preserved.","Kies een doelbeschrijving van maximaal 4096 tekens. Je volledige notities blijven bewaard.","Wählen Sie eine Zweckbeschreibung mit höchstens 4096 Zeichen. Alle Notizen bleiben erhalten.","Choisissez un but de 4096 caractères maximum. Toutes vos notes sont conservées.","Elige un propósito de hasta 4096 caracteres. Se conservan todas tus notas."],
        "unsaved":["Save your changes before creating a proposal.","Bewaar je wijzigingen voordat je een voorstel maakt.","Speichern Sie Änderungen vor einem Vorschlag.","Enregistrez vos modifications avant de créer une proposition.","Guarda los cambios antes de crear una propuesta."],
        "archived":["Restore this idea before creating a new proposal. Existing proposals remain unchanged.","Zet dit idee terug voordat je een nieuw voorstel maakt. Bestaande voorstellen blijven ongewijzigd.","Stellen Sie die Idee vor einem neuen Vorschlag wieder her. Bestehende Vorschläge bleiben unverändert.","Restaurez cette idée avant une nouvelle proposition. Les propositions existantes restent inchangées.","Restaura esta idea antes de una nueva propuesta. Las propuestas anteriores no cambian."],
        "access":["Access to the connected Forge proposal service is required.","Toegang tot de verbonden Forge-voorstelservice is nodig.","Zugriff auf den verbundenen Forge-Vorschlagsdienst erforderlich.","L’accès au service de propositions Forge connecté est nécessaire.","Se necesita acceso al servicio de propuestas Forge conectado."],
        "unknown":["Users, constraints and non-goals have not been supplied. They remain open questions.","Gebruikers, beperkingen en niet-doelen zijn nog niet ingevuld. Ze blijven open vragen.","Nutzer, Einschränkungen und Nichtziele fehlen noch. Sie bleiben offene Fragen.","Utilisateurs, contraintes et non-objectifs restent des questions ouvertes.","Usuarios, restricciones y objetivos excluidos siguen siendo preguntas abiertas."],
        "request":["Request document proposal","Documentvoorstel aanvragen","Dokumentvorschlag anfordern","Demander la proposition documentaire","Solicitar propuesta documental"],
        "cancel":["Cancel","Annuleren","Abbrechen","Annuler","Cancelar"],
        "notSupplied":["Purpose not supplied yet.","Doelbeschrijving nog niet ingevuld.","Zweck noch nicht angegeben.","But pas encore fourni.","Propósito aún no indicado."]
    ]
    static func text(_ key:String,_ language:String) -> String {values[key]?[languages.firstIndex(of:language) ?? 0] ?? key}
}

struct ConceptBaselineDraftSource: Codable, Equatable {
    let conceptID:String
    let revision:Int
    let title:String
    let originalNotes:String
    let chosenPurpose:String?
    static func capture(_ concept:ProjectConcept,choice:String?,dirty:Bool) throws -> Self {
        try concept.validate(concept.context_id)
        guard !dirty,concept.lifecycle != "ARCHIVED" else {throw ConceptError.conflict}
        let purpose=choice ?? concept.notes
        guard purpose.unicodeScalars.count<=4096,ProjectConcept.validText(purpose),choice==nil || !purpose.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw ConceptError.invalid}
        return .init(conceptID:concept.id,revision:concept.revision,title:concept.title,originalNotes:concept.notes,chosenPurpose:choice)
    }
}

// This is the pre-send review of the saved source, never a local document renderer.
// Actual proposal documents are supplied only by the authorized Server/Forge read.
struct ConceptBaselineDraftView: View {
    let concept:ProjectConcept
    let dirty:Bool
    var showAccessRequirement=true
    var onPrepare:((ConceptBaselineDraftSource)->Void)?=nil
    @Environment(\.locale) private var locale
    @State var reviewing=false
    @State private var shorterPurpose=""
    private var language:String {locale.language.languageCode?.identifier ?? "en"}
    private func text(_ key:String)->String {ConceptBaselineCopy.text(key,language)}
    private var longNotes:Bool {concept.notes.unicodeScalars.count>4096}
    private var source:ConceptBaselineDraftSource? {try? .capture(concept,choice:longNotes ? shorterPurpose:nil,dirty:dirty)}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Divider()
            Button(text("make")) {reviewing=true}
                .disabled(dirty || concept.lifecycle=="ARCHIVED")
                .accessibilityIdentifier("concept-baseline-review")
            if dirty {Text(text("unsaved")).foregroundStyle(.secondary)}
            else if concept.lifecycle=="ARCHIVED" {Text(text("archived")).foregroundStyle(.secondary)}
            if reviewing {
                Text(text("review")).font(.headline)
                Text(text("about"))
                Text(text("noModel"))
                Text(text("english")).foregroundStyle(.secondary)
                LabeledContent(text("revision"),value:String(concept.revision))
                DisclosureGroup(text("source")) {Text(verbatim:concept.notes).textSelection(.enabled)}
                if longNotes {
                    Text(text("shorter"))
                    TextField(text("purpose"),text:$shorterPurpose,axis:.vertical).lineLimit(3...8)
                        .accessibilityIdentifier("concept-baseline-purpose")
                } else {
                    Text(text("purpose")).font(.subheadline.bold())
                    Text(verbatim:concept.notes.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? text("notSupplied"):concept.notes).textSelection(.enabled)
                }
                Text(text("unknown")).foregroundStyle(.secondary)
                if onPrepare==nil && showAccessRequirement {Text(text("access")).foregroundStyle(.secondary)}
                HStack {
                    Button(text("request")) {if let source {onPrepare?(source)}}
                        .disabled(source==nil || onPrepare==nil).accessibilityIdentifier("concept-baseline-request")
                    Button(text("cancel")) {reviewing=false;shorterPurpose=""}
                }
            }
        }
        .onChange(of:concept) {_,_ in reviewing=false;shorterPurpose=""}
        .onChange(of:dirty) {_,value in if value {reviewing=false;shorterPurpose=""}}
    }
}
