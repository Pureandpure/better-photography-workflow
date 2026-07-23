import SwiftUI

@main
struct BPWDesktopApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("摄影工作流", id: "main") {
            RootView(model: model)
                .frame(minWidth: 820, minHeight: 580)
                .task { await model.start() }
        }
        .defaultSize(width: 940, height: 680)

        MenuBarExtra("摄影工作流", systemImage: model.menuSymbol) {
            MenuBarContent(model: model)
        }
    }
}
