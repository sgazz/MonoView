import SwiftUI
import UIKit

nonisolated struct PanelPosition: Codable, Equatable {
    var x: Double
    var y: Double
    static func initial(hand: String) -> Self { Self(x: hand == "left" ? 0 : 1, y: 1) }
}

/// A positioning envelope, not a claim about any individual's measured reach.
nonisolated enum PanelGeometry {
    static func range(container: CGSize, panel: CGSize, hand: String) -> CGRect {
        let inset: CGFloat = 12
        let maxX = max(inset, container.width - panel.width - inset)
        let travel = min(64, maxX - inset)
        let minX = hand == "left" ? inset : max(inset, maxX - travel)
        let right = hand == "left" ? min(maxX, inset + travel) : maxX
        let maxY = max(inset, container.height - panel.height - inset)
        let top = container.width > container.height ? inset : min(maxY, container.height * 0.42)
        return CGRect(x: minX, y: top, width: max(0, right - minX), height: max(0, maxY - top))
    }

    static func origin(position: PanelPosition, range: CGRect) -> CGPoint {
        CGPoint(x: range.minX + min(1, max(0, position.x)) * range.width,
                y: range.minY + min(1, max(0, position.y)) * range.height)
    }

    static func position(origin: CGPoint, range: CGRect) -> PanelPosition {
        PanelPosition(x: range.width > 0 ? min(1, max(0, (origin.x - range.minX) / range.width)) : 0,
                      y: range.height > 0 ? min(1, max(0, (origin.y - range.minY) / range.height)) : 1)
    }
}

struct MovablePanel<Content: View>: View {
    let container: CGSize
    let panel: CGSize
    let hand: String
    @Binding var position: PanelPosition
    var showRange = false
    @ViewBuilder let content: () -> Content
    @GestureState private var moving = false
    @State private var dragStart: CGPoint?
    @AppStorage("lockControls") private var locked = false
    @AppStorage("moveHoldDuration") private var holdDuration = 0.45
    @AppStorage("moveTolerance") private var tolerance = 20.0

    var body: some View {
        let range = PanelGeometry.range(container: container, panel: panel, hand: hand)
        let origin = PanelGeometry.origin(position: position, range: range)
        ZStack(alignment: .topLeading) {
            if showRange || moving {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .frame(width: range.width + panel.width, height: range.height + panel.height)
                    .offset(x: range.minX, y: range.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal").font(.headline)
                    Text(locked && !showRange ? "Position locked" : moving ? "Move within the outline" : "Hold to move").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .gesture(LongPressGesture(minimumDuration: holdDuration, maximumDistance: tolerance)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("panelContainer")))
                    .updating($moving) { value, state, _ in
                        if (!locked || showRange), case .second(true, _) = value { state = true }
                    }
                    .onChanged { value in
                        guard (!locked || showRange), case .second(true, let drag?) = value else { return }
                        if dragStart == nil { dragStart = origin }
                        guard let start = dragStart else { return }
                        position = PanelGeometry.position(origin: CGPoint(x: start.x + drag.translation.width,
                                                                         y: start.y + drag.translation.height), range: range)
                    }
                    .onEnded { _ in dragStart = nil })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Move control panel")
                .accessibilityValue("\(locked && !showRange ? "Position locked. " : "")Horizontal \(Int(position.x * 100)) percent. Height \(Int((1 - position.y) * 100)) percent up.")
                .accessibilityHint(locked && !showRange ? "Position locked. Unlock in Settings to move." : "Touch and hold, then drag. You can also use the movement actions.")
                .accessibilityIdentifier("panelHandle")
                .accessibilityAdjustableAction { direction in
                    guard !locked || showRange else { return }
                    position.y = min(1, max(0, position.y + (direction == .increment ? -0.2 : 0.2)))
                }
                .accessibilityActions {
                    Button("Move left") { if !locked || showRange { position.x = max(0, position.x - 0.2) } }
                    Button("Move right") { if !locked || showRange { position.x = min(1, position.x + 0.2) } }
                    Button("Reset position") { if !locked || showRange { position = .initial(hand: hand) } }
                }
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: panel.width, height: panel.height)
            .background(ManualMenuSurface())
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(moving ? 1 : 0), lineWidth: 2))
            .offset(x: origin.x, y: origin.y)
        }
        .frame(width: container.width, height: container.height, alignment: .topLeading)
        .coordinateSpace(name: "panelContainer")
        .onChange(of: moving) { _, active in
            if active { ComfortFeedback.play() }
            else { dragStart = nil }
        }
        .onChange(of: container) { _, _ in dragStart = nil }
        .onChange(of: hand) { _, _ in dragStart = nil }
    }
}

/// Holding and dragging repositions the dot; a short tap remains the immediate stop action.
struct MovableTiltDot: View {
    let container: CGSize
    let hand: String
    let zoom: CGFloat
    let defaultCenter: CGPoint
    @Binding var position: PanelPosition?
    let onStop: () -> Void
    @AppStorage("largeControls") private var large = false
    @State private var moving = false
    @State private var dragStart: CGPoint?
    @AppStorage("lockControls") private var locked = false
    @AppStorage("moveHoldDuration") private var holdDuration = 0.45
    @AppStorage("moveTolerance") private var tolerance = 20.0

    var body: some View {
        let diameter: CGFloat = large ? 76 : 60
        let range = PanelGeometry.range(container: container, panel: CGSize(width: diameter, height: diameter), hand: hand)
        let initial = PanelGeometry.position(origin: CGPoint(x: defaultCenter.x - diameter / 2, y: defaultCenter.y - diameter / 2), range: range)
        let current = position ?? initial
        let origin = PanelGeometry.origin(position: current, range: range)
        ZStack(alignment: .topLeading) {
            TiltDotFace()
                .overlay(Circle().stroke(.white.opacity(moving ? 1 : 0), lineWidth: 3))
                .contentShape(Circle())
                .overlay(DotTouchSurface(holdDuration: holdDuration, tolerance: tolerance, locked: locked, onTap: onStop, onBegin: {
                    dragStart = origin
                    moving = true
                }, onMove: { translation in
                    guard let start = dragStart else { return }
                    let target = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
                    position = PanelGeometry.position(origin: target, range: range)
                }, onEnd: { moving = false; dragStart = nil }).accessibilityHidden(true))
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Stop tilt and show controls")
                .accessibilityValue("Tilt panning is on. Zoom \(Int(zoom * 100)) percent")
                .accessibilityHint(locked ? "Tap to stop. Position locked. Unlock in Settings to move." : "Tap to stop. Touch and hold, then drag to move the button. VoiceOver movement actions are also available.")
                .accessibilityIdentifier("stopTiltDot")
                .accessibilityAction { onStop() }
                .accessibilityActions {
                    Button("Move up") { move(from: current, dx: 0, dy: -0.2) }
                    Button("Move down") { move(from: current, dx: 0, dy: 0.2) }
                    Button("Move left") { move(from: current, dx: -0.2, dy: 0) }
                    Button("Move right") { move(from: current, dx: 0.2, dy: 0) }
                    Button("Reset button position") { if !locked { position = nil } }
                }
                .offset(x: origin.x, y: origin.y)
        }
        .frame(width: container.width, height: container.height, alignment: .topLeading)
        .coordinateSpace(name: "tiltDotContainer")
        .onChange(of: moving) { _, active in
            if active { ComfortFeedback.play() }
            else { dragStart = nil }
        }
        .onChange(of: container) { _, _ in dragStart = nil }
    }
    private func move(from current: PanelPosition, dx: Double, dy: Double) {
        guard !locked else { return }
        position = PanelPosition(x: min(1.0, max(0.0, current.x + dx)), y: min(1.0, max(0.0, current.y + dy)))
    }

 }

/// UIKit recognizer arbitration preserves an immediate short tap while a hold enables dragging.
private struct DotTouchSurface: UIViewRepresentable {
    let holdDuration: Double
    let tolerance: Double
    let locked: Bool
    let onTap: () -> Void
    let onBegin: () -> Void
    let onMove: (CGSize) -> Void
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = holdDuration
        hold.isEnabled = !locked
        hold.allowableMovement = tolerance
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.require(toFail: hold)
        view.addGestureRecognizer(hold)
        view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.actions = self
        if let hold = uiView.gestureRecognizers?.compactMap({ $0 as? UILongPressGestureRecognizer }).first {
            hold.minimumPressDuration = holdDuration
            hold.allowableMovement = tolerance
            hold.isEnabled = !locked
        }
    }

    final class Coordinator: NSObject {
        var actions: DotTouchSurface
        private var start: CGPoint?
        init(_ actions: DotTouchSurface) { self.actions = actions }
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended { actions.onTap() }
        }
        @objc func held(_ gesture: UILongPressGestureRecognizer) {
            let point = gesture.location(in: gesture.view?.window)
            switch gesture.state {
            case .began:
                start = point
                actions.onBegin()
            case .changed:
                if let start { actions.onMove(CGSize(width: point.x - start.x, height: point.y - start.y)) }
            case .ended, .cancelled, .failed:
                start = nil
                actions.onEnd()
            default: break
            }
        }
    }
}
