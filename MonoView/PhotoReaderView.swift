import SwiftUI
import AVFoundation

struct PhotoReaderView: View {
    let image: UIImage
    var backLabel = "Back to tools"
    @StateObject private var document = PhotoTextDocument()
    @StateObject private var speech = ReaderSpeech()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showPhoto = false
    @State private var showOptions = false
    @State private var attempt = 0
    @AppStorage("readerSize") private var size = 1.0
    @AppStorage("readerTheme") private var theme = "dark"
    @AppStorage("readerLanguage") private var language = "automatic"
    @AppStorage("readerRate") private var rate = 0.45
    @AppStorage("keepScreenAwake") private var keepScreenAwake = false
    @ScaledMetric(relativeTo: .body) private var baseSize = 24.0

    private var paper: Color { theme == "light" ? .white : theme == "cream" ? Color(red: 1, green: 0.96, blue: 0.84) : .black }
    private var ink: Color { theme == "dark" ? .white : .black }
    private var speechTitle: String { speech.state == .speaking ? "Pause" : speech.state == .paused ? "Resume" : "Read aloud" }

    var body: some View {
        VStack(spacing: 0) {
            Text(showPhoto ? "Photo" : "Read text").font(.title2.bold()).padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if document.phase == .ready {
                            Text("Check against the photo. Words and reading order may be incorrect.").font(.callout)
                            Text(document.text)
                                .font(.system(size: baseSize * min(1.6, max(0.85, size))))
                                .lineSpacing(baseSize * 0.25)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("recognizedText")
                        } else {
                            status
                        }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }
                .opacity(showPhoto ? 0 : 1).allowsHitTesting(!showPhoto).accessibilityHidden(showPhoto)
                if showPhoto {
                    Image(uiImage: image).resizable().scaledToFit().padding(12)
                        .accessibilityLabel("Original photo for comparison").accessibilityIdentifier("readerOriginalPhoto")
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let notice = speech.notice { Text(notice).font(.caption).padding(.horizontal, 20) }
            if !speech.voiceName.isEmpty && speech.state != .idle {
                Text("Voice: \(speech.voiceName)").font(.caption).padding(.horizontal, 20)
            }
            footer
        }
        .foregroundStyle(ink).background(paper.ignoresSafeArea())
        .preferredColorScheme(theme == "dark" ? .dark : .light)
        .task(id: attempt) { await document.load(image: image, retry: attempt > 0) }
        .onChange(of: showPhoto) { _, shown in if shown { speech.pauseForComparison() } }
        .onChange(of: document.phase) { _, phase in
            guard UIAccessibility.isVoiceOverRunning else { return }
            let message: String?
            switch phase {
            case .ready: message = "Text ready. Choose Read aloud."
            case .empty: message = "No text found. You can try again or return to the photo."
            case .failed: message = "Text could not be read. You can try again."
            default: message = nil
            }
            if let message { UIAccessibility.post(notification: .announcement, argument: message) }
        }
        .onChange(of: language) { _, _ in speech.stop() }
        .onChange(of: rate) { _, _ in speech.stop() }
        .onAppear { updateIdleTimer() }
        .onChange(of: keepScreenAwake) { _, _ in updateIdleTimer() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { speech.stop() }; updateIdleTimer() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in speech.stop() }
        .onDisappear { document.cancel(); speech.stop(); UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showOptions) { options }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake && scenePhase == .active
    }

    @ViewBuilder private var status: some View {
        switch document.phase {
        case .idle, .recognizing:
            ProgressView().padding(.vertical, 12)
            Text("Finding text on this device…").font(.title3).accessibilityIdentifier("readerLoading")
        case .empty:
            Text("No text found").font(.title2.bold()).accessibilityIdentifier("readerEmpty")
            Text("Try a clearer photo with upright, well-lit text. Some languages and handwriting may not be recognized.")
        case .failed:
            Text("Text could not be read").font(.title2.bold()).accessibilityIdentifier("readerError")
            Text("Try again, or return to the photo and choose another image.")
        case .ready: EmptyView()
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if document.phase == .ready {
                    Button {
                        showPhoto = false
                        speech.toggle(text: document.text, language: language, rate: rate)
                    } label: {
                        HStack {
                            if !typeSize.isAccessibilitySize { Image(systemName: speech.state == .speaking ? "pause.fill" : "play.fill") }
                            Text(typeSize.isAccessibilitySize && speech.state == .idle ? "Read" : speechTitle)
                                .fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, minHeight: 52)
                    }.accessibilityLabel(speechTitle).accessibilityIdentifier("readerSpeak")
                    Button { speech.stop() } label: {
                        Image(systemName: "stop.fill").frame(minWidth: 48, minHeight: 52)
                    }.accessibilityLabel("Stop reading").accessibilityIdentifier("readerStop")
                        .disabled(speech.state == .idle)
                } else {
                    Button { showPhoto = false; attempt += 1 } label: {
                        Text("Try again").frame(maxWidth: .infinity, minHeight: 52)
                    }.disabled(document.phase == .recognizing || document.phase == .idle)
                        .accessibilityIdentifier("readerRetry")
                }
            }
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) { secondaryButtons }
            } else {
                HStack(spacing: 8) { secondaryButtons }
            }
            Button { speech.stop(); dismiss() } label: {
                Text("Back").fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 48)
            }.accessibilityLabel(backLabel).accessibilityIdentifier("readerBack")
        }
        .font(.headline).buttonStyle(ReaderButtonStyle(ink: ink))
        .frame(maxWidth: 300).padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private var secondaryButtons: some View {
                Button { showPhoto.toggle() } label: {
                    Text(showPhoto ? "Text" : "Photo").fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 48)
                }.accessibilityLabel(showPhoto ? "Show recognized text" : "Compare with original photo")
                    .accessibilityIdentifier("readerCompare")
                Button { showOptions = true } label: {
                    Text("Options").fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 48)
                }.accessibilityLabel("Reading options").accessibilityIdentifier("readerOptions")
    }

    private var options: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Reading options").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text("Text size").font(.headline)
                    Picker("Text size", selection: $size) {
                        Text("Large").tag(1.0); Text("Larger").tag(1.3); Text("Largest").tag(1.6)
                    }.pickerStyle(.segmented)
                    Text("Page colors").font(.headline)
                    Picker("Page colors", selection: $theme) {
                        Text("Dark").tag("dark"); Text("Light").tag("light"); Text("Cream").tag("cream")
                    }.pickerStyle(.segmented)
                    Text("Reading speed").font(.headline)
                    Picker("Reading speed", selection: $rate) {
                        Text("Slow").tag(0.35); Text("Normal").tag(0.45); Text("Fast").tag(0.55)
                    }.pickerStyle(.segmented)
                    Picker("Reading voice", selection: $language) {
                        Text("Automatic").tag("automatic")
                        ForEach(ReaderVoices.languages, id: \.self) { language in
                            Text(ReaderVoices.name(language)).tag(language)
                        }
                    }.pickerStyle(.menu)
                    Text("Automatic tries to match the text's language. If no matching voice is available, English is used. Changing voice or speed stops playback; Read aloud starts again.").font(.callout)
                    Text("Text recognition runs on this device. The extracted text is kept only while this reader is open.").font(.callout)
                    Button("Reset reading options") { size = 1; theme = "dark"; language = "automatic"; rate = 0.45 }
                        .frame(minHeight: 48).accessibilityIdentifier("resetReaderOptions")
                }.padding(24)
            }
            Button { showOptions = false } label: { Text("Done").frame(maxWidth: .infinity, minHeight: 56) }
                .buttonStyle(ControlStyle(primary: true)).padding(16).accessibilityIdentifier("readerOptionsDone")
        }.foregroundStyle(.white).background(MonoBackground()).tint(.white).preferredColorScheme(.dark)
    }
}

private struct ReaderButtonStyle: ButtonStyle {
    let ink: Color
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 8)
            .foregroundStyle(ink)
            .background(ink.opacity(configuration.isPressed ? 0.22 : 0.1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ink.opacity(0.7), lineWidth: 1.5))
            .opacity(enabled ? 1 : 0.45)
    }
}
