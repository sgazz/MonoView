import SwiftUI

struct ReachCalibrationView: View {
    let initialHand: String
    let onManual: () -> Void
    let onApply: (ReachProfile) -> Void
    @State private var stage = 0
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var leftSweepArea = false
    @State private var hand = "right"
    @State private var suggestion: String?
    @State private var recommendation: ReachProfile?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MonoBackground()
                if stage == 0 {
                    introduction(size: geometry.size)
                } else if stage == 1 {
                    VStack(spacing: 0) {
                        header(size: geometry.size)
                            .frame(height: min(typeSize.isAccessibilitySize ? 250 : 180, geometry.size.height * 0.3))
                        GeometryReader { field in
                            sweepArea(frame: field.frame(in: .named("calibration")))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        actions(size: geometry.size)
                    }
                } else {
                    trails(origin: .zero)
                        .allowsHitTesting(false)
                    if let recommendation {
                        ReachZonePreview(profile: recommendation, canvasSize: geometry.size,
                                         onTry: { onApply(recommendation) },
                                         onChangeHand: { hand = hand == "left" ? "right" : "left" })
                    }
                    VStack(spacing: 0) {
                        header(size: geometry.size)
                            .frame(maxHeight: headerHeight(in: geometry.size))
                        Spacer(minLength: 8)
                        actions(size: geometry.size)
                    }
                }
            }
            .coordinateSpace(name: "calibration")
            .onChange(of: geometry.size) { _, _ in
                // Coordinates from different orientations must never be mixed.
                if stage > 0 {
                    strokes = []
                    current = []
                    leftSweepArea = false
                    recommendation = nil
                    stage = 1
                }
            }
        }
        .foregroundStyle(MonoTheme.text)
        .tint(MonoTheme.accent)
        .preferredColorScheme(.dark)
        .onAppear { hand = initialHand }
    }

    private func introduction(size: CGSize) -> some View {
        // One centered column for either hand, before a hand preference is confirmed.
        // Short screens and large text can scroll without hiding the actions.
        ScrollView {
            VStack(spacing: 18) {
                Text("MonoView")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Find your comfortable reach")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Hold your phone naturally. Trace where your thumb reaches without stretching, or choose manual setup.")
                    .font(.body)
                actions(size: size)
                Text("Only your fitted layout is saved on this device. Sweep trails are discarded.")
                    .font(.footnote)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 340)
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: size.height, alignment: .center)
        }
    }

    private func header(size: CGSize) -> some View {
        ScrollView {
            VStack(alignment: .center, spacing: 12) {
                Text(stage == 1 ? "Sweep inside the outline" : "Confirm your hand")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(stage == 1
                     ? "Start where your thumb rests. Sweep, lift, and repeat at least twice. Stay comfortable; you don’t need to fill the area."
                     : "This layout is an estimate. Confirm your hand, then try the buttons with a relaxed grip.")
                if stage == 1 {
                    Text(leftSweepArea ? "Edge reached. Lift your thumb and start another sweep." : "\(strokes.count) sweeps recorded")
                        .font(.headline).foregroundStyle(MonoTheme.accent)
                } else {
                    Text(suggestion.map { "Suggested: \($0) hand. Confirm below." } ?? "Choose the hand you used.")
                    Picker("Hand used to hold your phone", selection: $hand) {
                        Text("Left").tag("left")
                        Text("Right").tag("right")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .onChange(of: hand) { _, _ in updateRecommendation(size: size) }
                    Text(recommendation == nil
                         ? "Not enough room for large buttons. Add comfortable sweeps or use manual setup."
                         : "Tap Try in the outlined area, or Try layout below.")
                }
            }
            .font(.body)
            .multilineTextAlignment(.center)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(MonoTheme.surface)
    }

    private func headerHeight(in size: CGSize) -> CGFloat {
        guard let recommendation else { return size.height * 0.55 }
        return min(size.height * 0.55, max(110, recommendation.rect(in: size).minY - 12))
    }

    private func trails(origin: CGPoint) -> some View {
        let paths = strokes + [current]
        return Canvas { context, _ in
            for stroke in paths {
                guard let first = stroke.first else { continue }
                var path = Path()
                path.move(to: CGPoint(x: first.x - origin.x, y: first.y - origin.y))
                for point in stroke.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
                }
                context.stroke(path, with: .color(MonoTheme.white.opacity(0.65)), style: StrokeStyle(lineWidth: 36, lineCap: .round, lineJoin: .round))
                context.fill(Path(ellipseIn: CGRect(x: first.x - origin.x - 7, y: first.y - origin.y - 7, width: 14, height: 14)), with: .color(MonoTheme.text))
            }
        }
    }

    private func sweepArea(frame: CGRect) -> some View {
        let local = CGRect(origin: .zero, size: frame.size)
        // Leave room for the 18-point brush radius and the estimator's reach buffer.
        let recordingBounds = local.insetBy(dx: 18, dy: 18)
        let recordingShape = RoundedRectangle(cornerRadius: 28).path(in: recordingBounds)
        return ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(MonoTheme.surface)
            RoundedRectangle(cornerRadius: 28)
                .stroke(MonoTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            trails(origin: frame.origin)
                .clipShape(RoundedRectangle(cornerRadius: 28))
        }
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard stage == 1, strokes.count < 20, current.count < 1500, !leftSweepArea else { return }
                guard recordingShape.contains(value.startLocation), recordingShape.contains(value.location) else {
                    // Stop this stroke at the edge. Never clamp to it or join a later re-entry.
                    leftSweepArea = true
                    return
                }
                let point = CGPoint(x: frame.minX + value.location.x, y: frame.minY + value.location.y)
                if current.last.map({ hypot($0.x - point.x, $0.y - point.y) > 5 }) ?? true {
                    current.append(point)
                }
            }
            .onEnded { _ in
                guard stage == 1 else { return }
                if current.count > 1, strokes.count < 20 { strokes.append(current) }
                current = []
                leftSweepArea = false
            })
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("thumbSweepArea")
        .accessibilityLabel("Thumb sweep area")
        .accessibilityHint("Trace comfortably inside the outline. Movement outside is not recorded. Manual setup is also available.")
    }

    private func actions(size: CGSize) -> some View {
        VStack(spacing: 10) {
            if stage == 0 {
                action("Start sweeps", primary: true) { stage = 1 }
            } else if stage == 1 {
                HStack(spacing: 10) {
                    action("Clear") { strokes = []; current = []; leftSweepArea = false }
                    action("Review", primary: true) {
                        suggestion = ReachEstimator.suggestedHand(strokes: strokes, size: size)
                        hand = suggestion ?? initialHand
                        updateRecommendation(size: size)
                        stage = 2
                    }
                    .disabled(!ReachEstimator.hasEnoughMovement(strokes))
                }
                if strokes.count >= 20 { Text("Sweep limit reached. Review or clear to start again.").font(.footnote) }
            } else {
                HStack(spacing: 10) {
                    action("More sweeps") { stage = 1 }
                    action("Try layout", primary: true) {
                        if let recommendation { onApply(recommendation) }
                    }
                    .disabled(recommendation == nil)
                }
            }
            action("Use manual setup") { onManual() }
        }
        .frame(maxWidth: 260)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(stage == 0 ? Color.clear : MonoTheme.surface)
    }

    private func action(_ title: String, primary: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(ControlStyle(primary: primary))
    }

    private func updateRecommendation(size: CGSize) {
        recommendation = ReachEstimator.recommend(strokes: strokes, size: size, hand: hand)
    }
}
