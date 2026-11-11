import AppKit
import DeskCore
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var desk: DeskController
    @EnvironmentObject private var reminder: ReminderController
    @Environment(\.openWindow) private var openWindow

    /// Within 1 cm of a favourite counts as "there".
    private static let activeTolerance = 100

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 14) {
                header
                favourites
                if let error = desk.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ReminderCard()
                footer
            }
            .padding(16)
        }
        .frame(width: 300)
        .onDisappear { desk.endJog() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                heightReadout
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if desk.status == .moving {
                Button(role: .destructive) { desk.stop() } label: {
                    Image(systemName: "stop.fill").frame(width: 22, height: 22)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(.red)
                .help("Stopp")
            }
            JogControl(isEnabled: desk.isReady, onPress: desk.startJog, onRelease: desk.endJog)
        }
    }

    private var heightReadout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(heightValue)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: desk.sample?.position)
            Text("cm").font(.system(.title3, design: .rounded)).foregroundStyle(.secondary)
        }
    }

    private var heightValue: String {
        guard let position = desk.sample?.position else { return "––" }
        return LinakCodec.centimetres(position: position, baseHeightCm: store.settings.baseHeightCm)
            .formatted(.number.precision(.fractionLength(1)))
    }

    // MARK: Favourites

    private var favourites: some View {
        HStack(spacing: 8) {
            FavouriteTile(title: "Sitzen", symbol: "chair.lounge.fill", position: store.settings.sitPosition, isActive: isActive(store.settings.sitPosition), isEnabled: canMove) { desk.move(to: $0) }
            FavouriteTile(title: "Stehen", symbol: "figure.stand", position: store.settings.standPosition, isActive: isActive(store.settings.standPosition), isEnabled: canMove) { desk.move(to: $0) }
            FavouriteTile(title: store.settings.customDisplayName, symbol: "star.fill", position: store.settings.customPosition, isActive: isActive(store.settings.customPosition), isEnabled: canMove) { desk.move(to: $0) }
        }
    }

    private var canMove: Bool { desk.status != .moving }

    private func isActive(_ position: UInt16?) -> Bool {
        guard let position, let current = desk.sample?.position else { return false }
        return abs(Int(position) - Int(current)) <= Self.activeTolerance
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape.fill").frame(width: 18, height: 18)
            }
            .help("Einstellungen")
            Spacer()
            Text("DeskNudge").font(.caption.weight(.medium)).foregroundStyle(.tertiary)
            Spacer()
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power").frame(width: 18, height: 18)
            }
            .help("Beenden")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    // MARK: Status

    private var statusColor: Color {
        switch desk.status {
        case .connected: return .green
        case .moving: return .blue
        case .connecting: return .yellow
        case .bluetoothOff, .unauthorized, .notConfigured: return .red
        }
    }

    private var statusText: String {
        switch desk.status {
        case .bluetoothOff: return "Bluetooth ist aus"
        case .unauthorized: return "Bluetooth-Zugriff nicht erlaubt"
        case .notConfigured: return "Kein Tisch gewählt"
        case .connecting: return "Verbinde mit \(store.settings.deskName ?? "Tisch") …"
        case .connected: return store.settings.deskName ?? "Verbunden"
        case .moving: return "Fährt …"
        }
    }
}

private struct FavouriteTile: View {
    @EnvironmentObject private var store: SettingsStore
    let title: String
    let symbol: String
    let position: UInt16?
    let isActive: Bool
    let isEnabled: Bool
    let onSelect: (UInt16) -> Void

    var body: some View {
        let button = Button {
            if let position { onSelect(position) }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                Text(position.map(store.centimetres) ?? "–")
                    .font(.caption2)
                    .monospacedDigit()
                    .opacity(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .disabled(position == nil || !isEnabled)

        if isActive {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }
}

private struct ReminderCard: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var reminder: ReminderController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            HStack(spacing: 12) {
                ring(now: context.date)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline(now: context.date)).font(.callout.weight(.semibold))
                    Text(subline(now: context.date)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $store.settings.remindersEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            .padding(12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contextMenu {
                Button("Jetzt erinnern") { reminder.promptNow() }
                Button("Timer neu starten") { reminder.restartCycle() }
            }
        }
    }

    private func ring(now: Date) -> some View {
        let total = reminder.dueDate.timeIntervalSince(reminder.cycleStart)
        let progress = total > 0 ? min(1, max(0, now.timeIntervalSince(reminder.cycleStart) / total)) : 0
        return ZStack {
            Circle().stroke(.quaternary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: store.settings.remindersEnabled ? progress : 0)
                .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
            Image(systemName: reminder.posture == .sitting ? "figure.stand" : "chair.lounge.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 34, height: 34)
        .onTapGesture { reminder.promptNow() }
        .help("Klicken: jetzt erinnern · Rechtsklick: mehr")
    }

    private func headline(now: Date) -> String {
        guard store.settings.remindersEnabled else { return "Erinnerungen aus" }
        let minutes = max(0, Int(reminder.dueDate.timeIntervalSince(now) / 60))
        let action = reminder.posture == .sitting ? "Aufstehen" : "Hinsetzen"
        return minutes == 0 ? "\(action) jetzt" : "\(action) in \(minutes) min"
    }

    private func subline(now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(reminder.cycleStart) / 60))
        let state = reminder.posture == .sitting ? "Sitzen" : "Stehen"
        return "\(state) seit \(minutes) min"
    }
}
