import AppKit
import SwiftUI

/// Small floating card in the top-right corner. Never steals focus from the current app.
@MainActor
final class ReminderPanel {
    private let model = PanelModel()
    private var panel: NSPanel?

    func show(title: String, detail: String, canMove: Bool, onConfirm: @escaping () -> Void, onDecline: @escaping () -> Void) {
        model.phase = .ask(title: title, detail: detail, canMove: canMove)
        model.onConfirm = onConfirm
        model.onDecline = onDecline
        present()
    }

    func showProgress(_ text: String, onStop: @escaping () -> Void) {
        model.phase = .progress(text)
        model.onStop = onStop
    }

    func showError(_ text: String, onClose: @escaping () -> Void) {
        model.phase = .error(text)
        model.onDecline = onClose
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func present() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 10, y: frame.maxY - size.height - 10))
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 352, height: 144),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: PanelView(model: model))
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }
}

@MainActor
private final class PanelModel: ObservableObject {
    enum Phase {
        case ask(title: String, detail: String, canMove: Bool)
        case progress(String)
        case error(String)
    }

    @Published var phase: Phase = .progress("")
    var onConfirm: () -> Void = {}
    var onDecline: () -> Void = {}
    var onStop: () -> Void = {}
}

private struct PanelView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "figure.stand")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.accentColor), in: Circle())
            content
        }
        .padding(16)
        .frame(width: 340, height: 132, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(6)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case let .ask(title, detail, canMove):
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button("Ablehnen", action: model.onDecline)
                        .buttonStyle(.glass)
                    Button("Fahren", action: model.onConfirm)
                        .buttonStyle(.glassProminent)
                        .disabled(!canMove)
                }
            }
        case let .progress(text):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(text).font(.headline)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button("Stopp", role: .destructive, action: model.onStop)
                        .buttonStyle(.glassProminent)
                        .tint(.red)
                }
            }
        case let .error(text):
            VStack(alignment: .leading, spacing: 6) {
                Text("Fahrt nicht abgeschlossen").font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button("OK", action: model.onDecline).buttonStyle(.glass)
                }
            }
        }
    }
}
