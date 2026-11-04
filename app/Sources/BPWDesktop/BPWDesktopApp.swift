import SwiftUI

@main
struct BPWDesktopApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("创作者工作流", id: "main") {
            RootView(model: model)
                .frame(minWidth: 1100, minHeight: 720)
                .task { await model.start() }
        }
        .defaultSize(width: 1280, height: 860)

        MenuBarExtra("创作者工作流", systemImage: model.menuSymbol) {
            MenuBarContent(model: model)
        }
    }
}
