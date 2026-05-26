import AppKit
import SwiftUI

@main
struct WiZLightBarApp: App {
    @StateObject private var model = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(model)
                .frame(width: 400)
        } label: {
            Label {
                Text("WiZ Light Bar")
            } icon: {
                Image(systemName: model.lightState.isOn ? "lightbulb.fill" : "lightbulb")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
