import SwiftUI

struct ReachCalibrationView: View {
    let initialHand: String
    let onManual: () -> Void
    let onApply: (ReachProfile) -> Void
    @State private var stage = 0
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var hand = "right"
    @State private var suggestion: String?
    @State private var recommendation: ReachProfile?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if stage > 0 { drawing(size: geometry.size) }
                if stage == 2, let recommendation {
                    ReachZonePreview(profile: recommendation, canvasSize: geometry.size,
                                     onTry: { onApply(recommendation) },
                                     onChangeHand: { hand = hand == "left" ? "right" : "left" })
                }
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(stage == 0 ? "Find your comfortable reach" : stage == 1 ? "Sweep gently with your thumb" : "Confirm your hand")
                                .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                            Text(instructions).font(.body)
                            if stage == 1 {
                                Text("\(strokes.count) sweeps recorded")
                                    .font(.headline).foregroundStyle(.yellow)
                            }
                            if stage == 2 {
                                Text(suggestion.map { "Suggested hand: \($0). Please confirm below." } ?? "Your hand could not be identified reliably. Choose it below.")
                                Picker("Hand used to hold your phone", selection: $hand) {
                                    Text("Left").tag("left")
                                    Text("Right").tag("right")
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: hand) { _, _ in updateRecommendation(size: geometry.size) }
                                Text(recommendation == nil ? "The traced band is too narrow for two large touch targets. Sweep across a wider comfortable area, or use manual setup." : "The button surfaces follow your traced band. Tap Try inside the zone. The hand button switches Left and Right. In the app, More cycles through commands.")
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.9))
                    }
                    .frame(maxHeight: stage == 1 ? (typeSize.isAccessibilitySize ? 250 : 180) : headerHeight(in: geometry.size))
                    Spacer(minLength: 8)
                    actions(size: geometry.size)
                }
            }
            .onChange(of: geometry.size) { _, _ in
                // Coordinates from different orientations must never be mixed.
                if stage > 0 {
                    strokes = []
                    current = []
                    recommendation = nil
                    stage = 1
                }
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onAppear { hand = initialHand }
    }

    private func headerHeight(in size: CGSize) -> CGFloat {
        guard stage == 2, let recommendation else { return size.height * 0.55 }
        return min(size.height * 0.55, max(110, recommendation.rect(in: size).minY - 12))
    }

    private var instructions: String {
        switch stage {
        case 0:
            return "Hold your phone comfortably. Keep the same grip. Start each sweep where your thumb naturally rests, then move over the area you can reach without stretching. Lift your thumb and repeat. You can use manual setup instead. Only the fitted button boundaries are saved on this device; the original sweep trails are discarded."
        case 1:
            return "Start at your thumb's resting position. Sweep over a comfortable area, lift, and repeat at least twice. Do not chase the edges or change your grip."
        default:
            return "The trace shows only where you moved. It does not prove that every area between the lines is reachable. Confirm your hand and try the proposed controls."
        }
    }

    private func drawing(size: CGSize) -> some View {
        let paths = strokes + [current]
        return Canvas { context, _ in
            for stroke in paths {
                guard let first = stroke.first else { continue }
                var path = Path()
                path.move(to: first)
                for point in stroke.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(.yellow.opacity(0.4)), style: StrokeStyle(lineWidth: 36, lineCap: .round, lineJoin: .round))
                context.fill(Path(ellipseIn: CGRect(x: first.x - 7, y: first.y - 7, width: 14, height: 14)), with: .color(.white))
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard stage == 1, current.count < 1500 else { return }
                if current.last.map({ hypot($0.x - value.location.x, $0.y - value.location.y) > 5 }) ?? true {
                    current.append(value.location)
                }
            }
            .onEnded { _ in
                guard stage == 1 else { return }
                if current.count > 1, strokes.count < 20 { strokes.append(current) }
                current = []
            })
        .accessibilityLabel("Thumb sweep area")
        .accessibilityHint("Move your thumb across a comfortable area. Manual setup is also available.")
    }

    private func actions(size: CGSize) -> some View {
        VStack(spacing: 10) {
            if stage == 0 {
                action("Start sweeps", primary: true) { stage = 1 }
            } else if stage == 1 {
                HStack(spacing: 10) {
                    action("Clear") { strokes = []; current = [] }
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
        .padding(12)
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, alignment: hand == "left" ? .leading : .trailing)
        .background(Color.black.opacity(0.9))
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
