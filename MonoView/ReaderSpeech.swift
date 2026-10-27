import AVFoundation
import Combine
import NaturalLanguage

@MainActor protocol ReaderSpeechEngine: AnyObject {
    var onFinish: ((UUID) -> Void)? { get set }
    func speak(text: String, language: String, rate: Float, id: UUID) -> Bool
    func pause() -> Bool
    func resume() -> Bool
    func stop()
}

@MainActor final class SystemReaderSpeech: NSObject, ReaderSpeechEngine, AVSpeechSynthesizerDelegate {
    var onFinish: ((UUID) -> Void)?
    private let synthesizer = AVSpeechSynthesizer()
    private var utterances: [ObjectIdentifier: UUID] = [:]
    override init() {
        super.init()
        synthesizer.usesApplicationAudioSession = false
        synthesizer.delegate = self
    }
    func speak(text: String, language: String, rate: Float, id: UUID) -> Bool {
        guard let voice = AVSpeechSynthesisVoice(language: language) else { return false }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        utterances[ObjectIdentifier(utterance)] = id
        synthesizer.speak(utterance)
        return true
    }
    func pause() -> Bool { synthesizer.pauseSpeaking(at: .word) }
    func resume() -> Bool { synthesizer.continueSpeaking() }
    func stop() { utterances.removeAll(); synthesizer.stopSpeaking(at: .immediate) }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }
    nonisolated private func finished(_ identity: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, let id = self.utterances.removeValue(forKey: identity) else { return }
            self.onFinish?(id)
        }
    }
}

@MainActor enum ReaderVoices {
    static let languages = Array(Set(AVSpeechSynthesisVoice.speechVoices().map(\.language))).sorted {
        name($0) < name($1)
    }
    static func name(_ language: String) -> String {
        Locale(identifier: "en").localizedString(forIdentifier: language) ?? language
    }
    static func resolve(text: String, preference: String) -> String? {
        let detected = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? "en"
        let requested = preference == "automatic" ? detected : preference
        return AVSpeechSynthesisVoice(language: requested)?.language
            ?? AVSpeechSynthesisVoice(language: "en-US")?.language
    }
}

@MainActor final class ReaderSpeech: ObservableObject {
    enum State: Equatable { case idle, speaking, paused }
    @Published private(set) var state = State.idle
    @Published private(set) var voiceName = ""
    @Published private(set) var notice: String?
    private let engine: any ReaderSpeechEngine
    private var activeID: UUID?
    private let resolveLanguage: @MainActor (String, String) -> String?
    init(engine: (any ReaderSpeechEngine)? = nil, resolveLanguage: @escaping @MainActor (String, String) -> String? = ReaderVoices.resolve) {
        self.resolveLanguage = resolveLanguage
        self.engine = engine ?? SystemReaderSpeech()
        self.engine.onFinish = { [weak self] id in
            guard let self, self.activeID == id else { return }
            self.activeID = nil
            self.state = .idle
        }
    }
    func toggle(text: String, language: String, rate: Double) {
        notice = nil
        switch state {
        case .speaking:
            if engine.pause() { state = .paused }
        case .paused:
            if engine.resume() { state = .speaking }
            else { stop(); notice = "Reading could not resume. Tap Read aloud to start again." }
        case .idle:
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard let resolved = resolveLanguage(text, language) else {
                notice = "No reading voice is available. Check the spoken-content voices in iPhone Settings."
                return
            }
            let id = UUID()
            activeID = id
            voiceName = ReaderVoices.name(resolved)
            let safeRate = rate.isFinite ? min(0.6, max(0.3, rate)) : 0.45
            if engine.speak(text: text, language: resolved, rate: Float(safeRate), id: id) { state = .speaking }
            else { activeID = nil; notice = "The selected voice could not start. Try another voice in Reading options." }
        }
    }
    func pauseForComparison() {
        if state == .speaking {
            if engine.pause() { state = .paused } else { stop() }
        }
    }
    func stop() { activeID = nil; engine.stop(); state = .idle }
}
