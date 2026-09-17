import SwiftUI

@main
struct LinkPureIOSApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            IOSRootView(model: model)
        }
    }
}
