import SwiftUI

@main
struct MacTidyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 620)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("重新扫描") { model.scan() }
                    .keyboardShortcut("r")
                    .disabled(model.scanning)
            }
        }
    }
}
