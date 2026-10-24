import SwiftUI
import AVFoundation
import Combine

@MainActor
final class GuideSpeaker: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    init() { synthesizer.usesApplicationAudioSession = false }
    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.45
        synthesizer.speak(utterance)
    }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

enum GuidePicture { case welcome, hand, move, photo, tilt, doubleTap, sweep }

/// Native shapes and symbols stay sharp at larger sizes. Motion is optional and finite.
struct GuideIllustration: View {
    let picture: GuidePicture
    var hand = "right"
    var replay = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var advanced = false

    var body: some View {
        ZStack {
            if picture == .welcome {
                Image(systemName: "photo").font(.system(size: 92, weight: .light))
                Image(systemName: "plus.magnifyingglass").font(.system(size: 58, weight: .bold))
                    .padding(10).background(MonoTheme.deepBlue, in: Circle()).offset(x: advanced ? 30 : 55, y: advanced ? 10 : 34).scaleEffect(advanced ? 1.12 : 1)
            } else {
                RoundedRectangle(cornerRadius: 22).stroke(.white, lineWidth: 5)
                    .frame(width: 104, height: 174)
                    .overlay(Image(systemName: "photo").font(.system(size: 44)).offset(y: -15))
                    .rotationEffect(.degrees(picture == .tilt && advanced ? 14 : 0))
                if picture == .hand {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 96))
                        .scaleEffect(x: hand == "left" ? -1 : 1, y: 1)
                        .offset(x: hand == "left" ? -54 : 54, y: 54)
                } else if picture == .photo {
                    Image(systemName: "photo.fill").font(.system(size: 64))
                        .padding(14).background(MonoTheme.deepBlue, in: RoundedRectangle(cornerRadius: 14))
                        .compositingGroup()
                        .scaleEffect(advanced ? 1.15 : 0.8)
                        .offset(x: advanced ? 0 : -64, y: advanced ? 0 : 40)
                    Image(systemName: "arrow.right").font(.system(size: 28, weight: .bold)).offset(x: -68, y: -35)
                } else if picture == .move {
                    RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.2))
                        .frame(width: 64, height: 50).overlay(Image(systemName: "line.3.horizontal").font(.title2))
                        .offset(x: advanced ? -12 : 20, y: advanced ? 5 : 50)
                    Image(systemName: "hand.point.up.left.fill").font(.system(size: 48))
                        .offset(x: advanced ? 25 : 57, y: advanced ? 40 : 85)
                    Image(systemName: "arrow.up.left").font(.title2.bold()).offset(x: -47, y: 28)
                } else if picture == .tilt {
                    HStack(spacing: 120) { Image(systemName: "arrow.left"); Image(systemName: "arrow.right") }
                        .font(.title2.bold())
                } else if picture == .doubleTap {
                    ZStack {
                        Circle().stroke(.white, lineWidth: advanced ? 4 : 2).frame(width: advanced ? 58 : 32)
                        Image(systemName: "hand.point.up.left.fill").font(.system(size: 52)).offset(x: 26, y: 35)
                    }.offset(y: 20)
                    Text("2×").font(.title.bold()).offset(x: 83, y: -35)
                } else if picture == .sweep {
                    ThumbArc().stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 100, height: 130).offset(x: 45, y: 12)
                    Image(systemName: "hand.point.up.left.fill").font(.system(size: 44))
                        .offset(x: advanced ? 65 : 15, y: advanced ? -35 : 70)
                    Image(systemName: "arrow.up.arrow.down").font(.title2.bold()).offset(x: 98, y: 15)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 210, maxHeight: 210)
        .accessibilityHidden(true)
        .task(id: "\(replay)-\(picture)-\(reduceMotion)") {
            advanced = false
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatCount(2, autoreverses: true)) { advanced = true }
        }
    }
}

private struct ThumbArc: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    }
}

struct MonoGuideView: View {
    @Binding var hand: String
    @Binding var practicePosition: PanelPosition
    let onFinish: (Bool) -> Void
    @State private var step = 0
    @State private var showComfort = false
    @AppStorage("largeControls") private var large = false
    @AppStorage("showControlLabels") private var labels = false
    @State private var replay = 0
    @State private var practiceCount = 0
    @State private var handConfirmed = false
    @StateObject private var speaker = GuideSpeaker()
    @Environment(\.scenePhase) private var scenePhase

    private var title: String { ["Welcome to MonoView", "Which hand do you use?", "Make it comfortable", "Your first photo"][step] }
    private var message: String {
        ["See photo details more easily, with controls made for one hand.",
         "Choose the hand you use to hold your phone.",
         "Hold the grip on the panel, then move it. Try a button. Keep your hand relaxed.",
         "Open a photo. Use the large buttons to zoom and explore."][step]
    }
    private var narration: String {
        "\(title). \(message) " + (step == 0 ? "Made for people with low vision and anyone using one hand. We want seeing details and reaching controls to feel comfortable." : "")
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MonoBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        Text("Step \(step + 1) of 4").font(.headline).accessibilityIdentifier("guideProgress")
                        Text(title).font(.system(.title2, design: .rounded, weight: .bold)).accessibilityAddTraits(.isHeader)
                        if step == 1 || step == 2 {
                            Text(message).font(.body)
                            Spacer(minLength: 16)
                            if step == 2 {
                                DisclosureGroup("See controls comfortably?", isExpanded: $showComfort) {
                                    ComfortSettings(appearanceOnly: true).padding(.vertical, 12)
                                }
                                practice
                            } else { handChoices }
                            footer
                            listenButton
                        } else {
                            GuideIllustration(picture: step == 0 ? .welcome : .photo, hand: hand, replay: replay)
                            Text(message).font(.body)
                            if step == 0 {
                                Text("Built for low vision and one-handed use. Less reaching. More independence.").font(.body)
                            }
                            HStack(spacing: 12) {
                                listenButton
                                Button { replay += 1 } label: {
                                    Label("Replay", systemImage: "arrow.clockwise").frame(minHeight: 48).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                            footer
                        }
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .padding(20)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }.id("\(step)-\(showComfort)")
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onChange(of: step) { _, _ in speaker.stop(); replay += 1 }
        .onChange(of: scenePhase) { _, phase in if phase != .active { speaker.stop() } }
        .onDisappear { speaker.stop() }
        .interactiveDismissDisabled()
    }

    private var listenButton: some View {
        Button { speaker.speak(narration) } label: {
            Label("Listen", systemImage: "speaker.wave.2.fill").frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("guideListen")
    }

    private var handChoices: some View {
        HStack(spacing: 12) {
            ForEach(["left", "right"], id: \.self) { option in
                Button { hand = option; handConfirmed = true } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).stroke(lineWidth: 3).frame(width: 60, height: 100)
                            Image(systemName: "hand.point.up.left.fill").font(.system(size: 58))
                                .scaleEffect(x: option == "left" ? -1 : 1, y: 1)
                                .offset(x: option == "left" ? -27 : 27, y: 25)
                        }.frame(height: 132)
                        Label(option == "left" ? "Left" : "Right", systemImage: handConfirmed && hand == option ? "checkmark.circle.fill" : "circle")
                    }.frame(maxWidth: .infinity, minHeight: 178)
                }
                .buttonStyle(ControlStyle(primary: handConfirmed && hand == option))
                .accessibilityIdentifier("guideHand-\(option)")
                .accessibilityLabel(option == "left" ? "Left hand" : "Right hand")
                .accessibilityAddTraits(handConfirmed && hand == option ? [.isSelected] : [])
            }
        }
    }

    private var practice: some View {
        GeometryReader { area in
            MovablePanel(container: area.size, panel: CGSize(width: min(256, area.size.width - 24), height: large || labels ? 184 : 132), hand: hand,
                         position: $practicePosition, showRange: true) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]) {
                    ForEach(["minus.magnifyingglass", "plus.magnifyingglass", "photo"], id: \.self) { icon in
                        Button { practiceCount += 1; ComfortFeedback.play() } label: {
                            VStack {
                                Image(systemName: icon).font(.system(size: large ? 34 : 28))
                                if labels { Text(icon == "photo" ? "Photo" : icon == "plus.magnifyingglass" ? "In" : "Out").font(.caption) }
                            }.frame(maxWidth: .infinity, minHeight: large || labels ? 88 : 56).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .accessibilityLabel(icon == "photo" ? "Try photo button" : icon == "plus.magnifyingglass" ? "Try zoom in" : "Try zoom out")
                    }
                }
                Text(practiceCount > 0 ? "Button reached ✓" : "Try a button").font(.caption).padding(.bottom, 8)
            }
        }
        .frame(height: 240)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                if step == 3 { onFinish(true) } else { step += 1 }
            } label: {
                Label(step == 3 ? "Open photo" : step == 2 ? "Comfortable" : "Continue", systemImage: step == 3 ? "photo" : "arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle())
            }
            .buttonStyle(ControlStyle(primary: true))
            .accessibilityIdentifier("guideNext")
            .disabled(step == 1 && !handConfirmed)
            if step > 0 {
                Button { step -= 1 } label: { Label("Back", systemImage: "arrow.left").frame(maxWidth: .infinity, minHeight: 48) }
                    .buttonStyle(ControlStyle())
                    .accessibilityIdentifier("guideBack")
            }
            if step == 3 {
                Button("Start without a photo") { onFinish(false) }
                    .frame(minHeight: 48).contentShape(Rectangle()).buttonStyle(.plain)
                    .accessibilityIdentifier("guideFinish")
            }
        }.frame(maxWidth: 260)
    }
}

struct MonoTiltGuideView: View {
    let onFinish: () -> Void
    let onCancel: () -> Void
    @State private var step = 0
    @State private var replay = 0
    @StateObject private var speaker = GuideSpeaker()
    @Environment(\.scenePhase) private var scenePhase
    private var title: String { ["Tilt to explore", "Two taps to zoom", "Sweep to zoom"][step] }
    private var message: String {
        ["Tilt your phone gently to move through the photo. Tap the floating dot to stop.",
         "Tap the photo twice for your chosen zoom level. Tap twice again to see the whole photo.",
         "Move your thumb in a comfortable arc. Up zooms in; down zooms out."][step]
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MonoBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        Text("Step \(step + 1) of 3").font(.headline)
                        Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        GuideIllustration(picture: [.tilt, .doubleTap, .sweep][step], replay: replay)
                        Text(message)
                        HStack(spacing: 16) {
                            Button { speaker.speak("\(title). \(message)") } label: { Label("Listen", systemImage: "speaker.wave.2.fill").frame(minHeight: 48).contentShape(Rectangle()) }
                            Button { replay += 1 } label: { Label("Replay", systemImage: "arrow.clockwise").frame(minHeight: 48).contentShape(Rectangle()) }
                        }.buttonStyle(.plain)
                        Button { if step < 2 { step += 1 } else { onFinish() } } label: {
                            Label(step == 2 ? "Start Tilt" : "Continue", systemImage: step == 2 ? "move.3d" : "arrow.right")
                                .frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle())
                        }.buttonStyle(ControlStyle(primary: true)).frame(maxWidth: 260).accessibilityIdentifier("tiltGuideNext")
                        if step > 0 {
                            Button { step -= 1 } label: { Label("Back", systemImage: "arrow.left").frame(minHeight: 48).contentShape(Rectangle()) }.buttonStyle(.plain)
                        }
                        Button("Not now", action: onCancel).frame(minHeight: 48).contentShape(Rectangle()).buttonStyle(.plain)
                    }
                    .font(.body).multilineTextAlignment(.center).frame(maxWidth: 340).padding(24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }.id(step)
            }
        }.foregroundStyle(.white).preferredColorScheme(.dark)
        .onChange(of: step) { _, _ in speaker.stop(); replay += 1 }
        .onChange(of: scenePhase) { _, phase in if phase != .active { speaker.stop() } }
        .onDisappear { speaker.stop() }
    }
}
