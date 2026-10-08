import XCTest
import SwiftUI
import AppKit
@testable import WorkspaceClient

@MainActor
final class WorkspaceLocalizationTests:XCTestCase {
    func testFiveCompleteCataloguesAndPreferenceFallback() {
        XCTAssertEqual(WorkspaceLanguage.supported,["en","nl","de","fr","es"])
        let keys=Set(WorkspaceCopy.values["en"]!.keys)
        for language in WorkspaceLanguage.supported {
            XCTAssertEqual(Set(WorkspaceCopy.values[language]!.keys),keys)
            XCTAssertFalse(WorkspaceLanguage.names[language]!.isEmpty)
            for key in keys { XCTAssertFalse(WorkspaceCopy.text(key,language:language).isEmpty) }
            XCTAssertEqual(WorkspaceLanguage.resolve(language,system:Locale(identifier:"ja")),language)
            XCTAssertEqual(WorkspaceLanguage.resolve("system",system:Locale(identifier:language)),language)
            XCTAssertEqual(WorkspaceCopy.detail("Fresh Server read at 2026-10-08",language:language),WorkspaceCopy.text("Fresh Server read",language:language))
        }
        XCTAssertEqual(WorkspaceLanguage.resolve(nil,system:Locale(identifier:"ja")),"en")
        XCTAssertEqual(WorkspaceCopy.text("Version",language:"xx"),"Version")
        XCTAssertEqual(WorkspaceCopy.detail("The Server returned HTTP 503.",language:"nl"),"De Server gaf HTTP 503.")
        XCTAssertEqual(WorkspaceCopy.detail("The Server rejected the token. Last successful read: exact-time; displayed data is cached.",language:"nl"),"De Server heeft het token geweigerd. Laatste geslaagde weergave: exact-time; De getoonde gegevens komen uit cache.")
        XCTAssertEqual(WorkspaceCopy.detail("synthetic canonical text",language:"nl"),"synthetic canonical text")
    }
    func testPersistedSelectionUpdatesAllNativeRootsWithoutChangingState() {
        let defaults=UserDefaults.standard
        let original=defaults.object(forKey:WorkspaceLanguage.key)
        defer {
            if let original { defaults.set(original,forKey:WorkspaceLanguage.key) }
            else { defaults.removeObject(forKey:WorkspaceLanguage.key) }
        }
        let client=ClientState()
        let drafts=ConversationState()
        let phase=client.phase
        for language in WorkspaceLanguage.supported {
            defaults.set(language,forKey:WorkspaceLanguage.key)
            XCTAssertEqual(WorkspaceLanguage.current,language)
            XCTAssertEqual(WorkspaceLanguage.locale.identifier,language)
            XCTAssertEqual(ConversationCopy.text("nav"),ConversationCopy.text("nav",language:language))
            XCTAssertEqual(MissionReviewCopy.text("nav"),MissionReviewCopy.text("nav",language:language))
            XCTAssertEqual(WorklistCopy.text("nav"),WorklistCopy.text("nav",language:language))
            for theme in [ColorScheme.light,.dark] {
                let overview=NSHostingView(rootView:ServerOverviewView(client:client).environment(\.locale,WorkspaceLanguage.locale).environment(\.colorScheme,theme))
                overview.frame=NSRect(x:0,y:0,width:640,height:700)
                overview.layoutSubtreeIfNeeded()
                let settings=NSHostingView(rootView:SettingsView(client:client,conversations:drafts).environment(\.locale,WorkspaceLanguage.locale).environment(\.colorScheme,theme))
                settings.frame=NSRect(x:0,y:0,width:490,height:600)
                settings.layoutSubtreeIfNeeded()
            }
        }
        XCTAssertEqual(client.phase,phase)
        XCTAssertNil(client.snapshot)
        defaults.set("invalid",forKey:WorkspaceLanguage.key)
        XCTAssertTrue(WorkspaceLanguage.supported.contains(WorkspaceLanguage.current))
    }
}
