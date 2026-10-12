import SwiftUI

struct WorkspaceDestination: Identifiable, Equatable {
    let id: Int
    let title: String
    let symbol: String
    static func items(language: String) -> [Self] {
        [Self(id:5,title:ProjectConceptCopy.text("nav",language:language),symbol:"lightbulb"),
         Self(id:4,title:MissionWorkspaceCopy.text("missions",language:language),symbol:"bubble.left.and.text.bubble.right"),
         Self(id:0,title:ConversationCopy.text("nav",language:language),symbol:"bubble.left.and.bubble.right"),
         Self(id:1,title:MissionReviewCopy.text("nav",language:language),symbol:"checkmark.seal"),
         Self(id:2,title:WorklistCopy.text("nav",language:language),symbol:"list.bullet.rectangle"),
         Self(id:3,title:WorkspaceCopy.text("Server",language:language),symbol:"server.rack")]
    }
    static func finite(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        value.isFinite && value > 0 ? value : fallback
    }
}

// One visible detail owns its commands. Native columns receive a finite viewport,
// independently of a page's intrinsic editor/list size or sidebar reparenting.
struct WorkspaceNavigationShell<Detail: View>: View {
    @Binding var selected: Int
    let language: String
    @ViewBuilder let detail: (Int) -> Detail
    private var selection: Binding<Int?> {
        Binding(get: { selected }, set: { value in
            if let value, WorkspaceDestination.items(language:language).contains(where: { $0.id == value }) {
                selected = value
            }
        })
    }
    var body: some View {
        GeometryReader { viewport in
            NavigationSplitView {
                List(WorkspaceDestination.items(language:language),selection:selection) { item in
                    Label(item.title,systemImage:item.symbol).tag(item.id)
                        .accessibilityIdentifier("workspace-destination-\(item.id)")
                }
                .navigationTitle("Workspace")
                .navigationSplitViewColumnWidth(min:180,ideal:220,max:280)
            } detail: {
                detail(selected)
                    .frame(minWidth:0,maxWidth:.infinity,minHeight:0,maxHeight:.infinity,alignment:.topLeading)
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth:0,maxWidth:.infinity,minHeight:0,maxHeight:.infinity)
            .frame(width:WorkspaceDestination.finite(viewport.size.width,fallback:560),
                   height:WorkspaceDestination.finite(viewport.size.height,fallback:520))
        }
    }
}
