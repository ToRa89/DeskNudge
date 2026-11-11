import SwiftUI

/// Vertical glass capsule with two press-and-hold arrows. Moves only while a finger/mouse is down.
struct JogControl: View {
    let isEnabled: Bool
    let onPress: (DeskController.JogDirection) -> Void
    let onRelease: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HoldArrow(symbol: "chevron.up", label: "Hoch", isEnabled: isEnabled) { onPress(.up) } onRelease: { onRelease() }
            Divider().frame(width: 22)
            HoldArrow(symbol: "chevron.down", label: "Runter", isEnabled: isEnabled) { onPress(.down) } onRelease: { onRelease() }
        }
        .glassEffect(.regular.interactive(), in: Capsule())
        .help("Gedrückt halten zum Fahren")
    }
}

private struct HoldArrow: View {
    let symbol: String
    let label: String
    let isEnabled: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    @State private var isPressed = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .bold))
            .frame(width: 44, height: 36)
            .contentShape(Rectangle())
            .foregroundStyle(isPressed ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .scaleEffect(isPressed ? 0.88 : 1)
            .animation(.spring(duration: 0.2), value: isPressed)
            .opacity(isEnabled ? 1 : 0.35)
            .accessibilityLabel(label)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isEnabled, !isPressed else { return }
                        isPressed = true
                        onPress()
                    }
                    .onEnded { _ in
                        guard isPressed else { return }
                        isPressed = false
                        onRelease()
                    }
            )
            .onDisappear {
                if isPressed {
                    isPressed = false
                    onRelease()
                }
            }
    }
}
