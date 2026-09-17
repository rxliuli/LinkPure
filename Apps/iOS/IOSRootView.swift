import SwiftUI

struct IOSRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            IOSRulesView(model: model)
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }

            ShortcutGuideView(model: model)
                .tabItem { Label("How to Use", systemImage: "wand.and.stars") }
        }
    }
}
