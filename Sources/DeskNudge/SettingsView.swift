import DeskCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var desk: DeskController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var inputError: String?

    var body: some View {
        Form {
            deskSection
            favouritesSection
            reminderSection
            Section("Allgemein") {
                Toggle("Beim Anmelden starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear { desk.stopScan() }
    }

    private var deskSection: some View {
        Section {
            LabeledContent("Gewählt", value: store.settings.deskName ?? "keiner")
            HStack {
                Button(desk.isScanning ? "Suche stoppen" : "Tisch suchen") {
                    desk.isScanning ? desk.stopScan() : desk.startScan()
                }
                if desk.isScanning { ProgressView().controlSize(.small) }
            }
            ForEach(desk.discovered) { found in
                HStack {
                    Text(found.name).fontWeight(found.advertisesLinak ? .semibold : .regular)
                    Spacer()
                    if found.id == store.settings.deskID {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    } else {
                        Button("Verwenden") {
                            store.settings.deskID = found.id
                            store.settings.deskName = found.name
                            desk.use(desk: found)
                        }
                    }
                }
            }
        } header: {
            Text("Tisch")
        } footer: {
            Text("Die LINAK-App vorher beenden, sie belegt sonst die Bluetooth-Verbindung.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var favouritesSection: some View {
        Section {
            favouriteRow(title: "Sitzen", symbol: "chair.lounge.fill", keyPath: \.sitPosition)
            favouriteRow(title: "Stehen", symbol: "figure.stand", keyPath: \.standPosition)
            favouriteRow(title: nil, symbol: "star.fill", keyPath: \.customPosition)
            if let inputError {
                Label(inputError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            LabeledContent("Tiefste Höhe") {
                TextField("", value: $store.settings.baseHeightCm, format: .number.precision(.fractionLength(1)))
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
                Text("cm").foregroundStyle(.secondary)
            }
        } header: {
            Text("Favoriten")
        } footer: {
            Text("Höhe in cm eintippen (Enter übernimmt) oder Tisch mit dem Handschalter hinfahren und den Zielpfeil klicken. „Tiefste Höhe“ ist die Höhe ganz unten; danach rechnet die App die cm-Werte um.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func favouriteRow(title: String?, symbol: String, keyPath: WritableKeyPath<DeskSettings, UInt16?>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 18)
            if let title {
                Text(title)
            } else {
                TextField("Name", text: customNameBinding, prompt: Text("Favorit 3"))
                    .frame(maxWidth: 120)
            }
            Spacer()
            TextField("", value: cmBinding(keyPath), format: .number.precision(.fractionLength(1)), prompt: Text("–"))
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
            Text("cm").foregroundStyle(.secondary)
            Button {
                if let current = desk.sample?.position {
                    store.settings[keyPath: keyPath] = current
                    inputError = nil
                }
            } label: {
                Image(systemName: "scope")
            }
            .buttonStyle(.borderless)
            .disabled(desk.sample == nil)
            .help("Aktuelle Tischhöhe übernehmen")
            Button {
                store.settings[keyPath: keyPath] = nil
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .disabled(store.settings[keyPath: keyPath] == nil)
            .help("Favorit löschen")
        }
    }

    private var customNameBinding: Binding<String> {
        Binding(
            get: { store.settings.customName ?? "" },
            set: { store.settings.customName = $0 }
        )
    }

    private func cmBinding(_ keyPath: WritableKeyPath<DeskSettings, UInt16?>) -> Binding<Double?> {
        Binding(
            get: {
                store.settings[keyPath: keyPath].map {
                    LinakCodec.centimetres(position: $0, baseHeightCm: store.settings.baseHeightCm)
                }
            },
            set: { newValue in
                guard let newValue else {
                    store.settings[keyPath: keyPath] = nil
                    return
                }
                let base = store.settings.baseHeightCm
                guard let position = LinakCodec.position(centimetres: newValue, baseHeightCm: base) else {
                    let maxCm = LinakCodec.centimetres(position: LinakCodec.maxStroke, baseHeightCm: base)
                    inputError = "Höhe muss zwischen \(base.formatted()) und \(maxCm.formatted()) cm liegen."
                    return
                }
                store.settings[keyPath: keyPath] = position
                inputError = nil
            }
        )
    }

    private var reminderSection: some View {
        Section("Erinnerung") {
            Stepper("Sitzen: \(store.settings.sitMinutes) min", value: $store.settings.sitMinutes, in: 5...180, step: 5)
            Stepper("Stehen: \(store.settings.standMinutes) min", value: $store.settings.standMinutes, in: 5...120, step: 5)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Autostart nicht möglich: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
