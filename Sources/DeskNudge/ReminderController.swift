import AppKit
import Combine
import DeskCore
import Foundation

/// Keeps track of how long the user has been sitting or standing and raises the reminder panel.
@MainActor
final class ReminderController: ObservableObject {
    @Published private(set) var posture: Posture = .sitting
    @Published private(set) var cycleStart = Date()
    @Published private(set) var isPromptVisible = false

    private static let checkInterval: TimeInterval = 20

    private let store: SettingsStore
    private let desk: DeskController
    private let panel = ReminderPanel()
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(store: SettingsStore, desk: DeskController) {
        self.store = store
        self.desk = desk
        observeDesk()
        observeSleep()
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    var dueDate: Date {
        ReminderLogic.dueDate(posture: posture, since: cycleStart, settings: store.settings)
    }

    func restartCycle() {
        cycleStart = Date()
    }

    /// Shows the prompt right away (menu entry "Jetzt erinnern").
    func promptNow() {
        showPrompt()
    }

    private func check() {
        guard store.settings.remindersEnabled, !isPromptVisible, Date() >= dueDate else { return }
        showPrompt()
    }

    private func showPrompt() {
        let favourites = store.settings.favourites
        let target = favourites.map { ReminderLogic.target(after: posture, favourites: $0) }
        let title = posture == .sitting ? "Zeit zum Aufstehen" : "Zeit zum Hinsetzen"
        let detail: String
        if let target {
            let name = posture == .sitting ? "Stehen" : "Sitzen"
            detail = "Tisch fährt auf \(name) (\(store.centimetres(target)))."
        } else {
            detail = "Favoriten fehlen noch, bitte in den Einstellungen festlegen."
        }
        isPromptVisible = true
        NSSound(named: "Glass")?.play()
        panel.show(
            title: title,
            detail: detail,
            canMove: target != nil,
            onConfirm: { [weak self] in self?.confirm(target: target) },
            onDecline: { [weak self] in self?.decline() }
        )
    }

    private func confirm(target: UInt16?) {
        guard let target else {
            decline()
            return
        }
        panel.showProgress("Tisch fährt …", onStop: { [weak self] in self?.desk.stop() })
        desk.move(to: target) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.closePrompt()
            case .failure(.cancelled):
                self.closePrompt()
            case .failure(let error):
                self.panel.showError(error.localizedDescription) { [weak self] in self?.closePrompt() }
            }
        }
    }

    private func decline() {
        closePrompt()
    }

    private func closePrompt() {
        panel.close()
        isPromptVisible = false
        restartCycle()
    }

    private func observeDesk() {
        desk.$sample
            .compactMap { $0?.position }
            .removeDuplicates()
            .sink { [weak self] position in
                MainActor.assumeIsolated { self?.updatePosture(position: position) }
            }
            .store(in: &cancellables)
    }

    private func updatePosture(position: UInt16) {
        guard let favourites = store.settings.favourites else { return }
        let newPosture = ReminderLogic.posture(position: position, favourites: favourites)
        guard newPosture != posture else { return }
        posture = newPosture
        restartCycle()
    }

    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.publisher(for: name)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated { self?.restartCycle() }
                }
                .store(in: &cancellables)
        }
    }
}
