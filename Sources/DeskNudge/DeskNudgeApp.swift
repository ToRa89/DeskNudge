import AppKit
import SwiftUI

@main
struct DeskNudgeApp: App {
    @StateObject private var store: SettingsStore
    @StateObject private var desk: DeskController
    @StateObject private var reminder: ReminderController

    init() {
        let store = SettingsStore()
        let desk = DeskController(deskID: store.settings.deskID)
        _store = StateObject(wrappedValue: store)
        _desk = StateObject(wrappedValue: desk)
        _reminder = StateObject(wrappedValue: ReminderController(store: store, desk: desk))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(store)
                .environmentObject(desk)
                .environmentObject(reminder)
        } label: {
            Image(systemName: reminder.posture == .standing ? "figure.stand" : "chair.lounge")
        }
        .menuBarExtraStyle(.window)

        Window("DeskNudge Einstellungen", id: "settings") {
            SettingsView()
                .environmentObject(store)
                .environmentObject(desk)
                .environmentObject(reminder)
        }
        .windowResizability(.contentSize)
    }
}
