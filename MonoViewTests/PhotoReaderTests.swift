import Testing
import SwiftUI
@testable import MonoView

struct PhotoReaderTests {
    @Test func readingOrderJoinsLinesButPreservesParagraphGaps() {
        let lines = [
            RecognizedPhotoLine(text: "Last paragraph.", box: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.05)),
            RecognizedPhotoLine(text: "First line", box: CGRect(x: 0.1, y: 0.8, width: 0.7, height: 0.05)),
            RecognizedPhotoLine(text: "continues here.", box: CGRect(x: 0.1, y: 0.74, width: 0.7, height: 0.05)),
            RecognizedPhotoLine(text: "  ", box: .zero)
        ]
        #expect(PhotoTextRecognition.readingText(from: lines) == "First line continues here.\n\nLast paragraph.")
    }

    @Test @MainActor func actualVisionReadsPrintedTextAndHandlesBlankImages() async throws {
        let sample = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 400)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 400))
            ("READ THIS TEXT" as NSString).draw(at: CGPoint(x: 60, y: 100), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 72), .foregroundColor: UIColor.black])
        }
        let text = try await PhotoTextRecognition.recognize(#require(sample.cgImage))
        #expect(text.uppercased().contains("READ THIS TEXT"))
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 500)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 500, height: 500))
        }
        #expect(try await PhotoTextRecognition.recognize(#require(blank.cgImage)).isEmpty)
    }

    @Test @MainActor func documentHandlesEmptyFailureAndRetry() async {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
        let empty = PhotoTextDocument(recognize: { _ in " \n" })
        await empty.load(image: image)
        #expect(empty.phase == .empty && empty.text.isEmpty)
        let failed = PhotoTextDocument(recognize: { _ in throw NSError(domain: "test", code: 1) })
        await failed.load(image: image)
        #expect(failed.phase == .failed)
        let ready = PhotoTextDocument(recognize: { _ in "Recognized text" })
        await ready.load(image: UIImage())
        #expect(ready.phase == .failed)
        await ready.load(image: image, retry: true)
        #expect(ready.phase == .ready && ready.text == "Recognized text")
    }

    @Test @MainActor func lateRecognitionCannotReplaceNewerTextOrReopenCancelledReader() async {
        let gate = RecognitionGate()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
        let document = PhotoTextDocument(recognize: { _ in try await gate.read() })
        let first = Task { await document.load(image: image) }
        while await gate.count < 1 { await Task.yield() }
        let second = Task { await document.load(image: image, retry: true) }
        while await gate.count < 2 { await Task.yield() }
        await gate.finish(1, text: "New text")
        await second.value
        await gate.finish(0, text: "Stale text")
        await first.value
        #expect(document.text == "New text" && document.phase == .ready)
        let third = Task { await document.load(image: image, retry: true) }
        while await gate.count < 3 { await Task.yield() }
        document.cancel(); third.cancel()
        await gate.finish(2, text: "Late text")
        await third.value
        #expect(document.phase == .idle && document.text.isEmpty)
    }

    @Test @MainActor func speechPausesResumesStopsAndIgnoresStaleCompletion() {
        let engine = FakeReaderSpeech()
        let reader = ReaderSpeech(engine: engine, resolveLanguage: { _, _ in "en-US" })
        reader.toggle(text: "Read me", language: "automatic", rate: 0.45)
        #expect(reader.state == .speaking)
        let firstID = engine.ids[0]
        reader.toggle(text: "Read me", language: "automatic", rate: 0.45)
        #expect(reader.state == .paused && engine.pauses == 1)
        reader.toggle(text: "Read me", language: "automatic", rate: 0.45)
        #expect(reader.state == .speaking && engine.resumes == 1)
        reader.pauseForComparison()
        #expect(reader.state == .paused)
        reader.stop()
        #expect(reader.state == .idle && engine.stops == 1)
        reader.toggle(text: "New text", language: "automatic", rate: .nan)
        #expect(engine.rates.last == 0.45)
        engine.onFinish?(firstID)
        #expect(reader.state == .speaking)
        engine.onFinish?(engine.ids.last!)
        #expect(reader.state == .idle)
    }

    @Test @MainActor func failedSpeechAndResumeDoNotLeavePlaybackStuck() {
        let engine = FakeReaderSpeech()
        let reader = ReaderSpeech(engine: engine, resolveLanguage: { _, _ in "en-US" })
        engine.canStart = false
        reader.toggle(text: "Text", language: "automatic", rate: 0.45)
        #expect(reader.state == .idle && reader.notice != nil)
        engine.canStart = true
        reader.toggle(text: "Text", language: "automatic", rate: 0.45)
        reader.toggle(text: "Text", language: "automatic", rate: 0.45)
        engine.canResume = false
        reader.toggle(text: "Text", language: "automatic", rate: 0.45)
        #expect(reader.state == .idle && reader.notice != nil)
        engine.canResume = true
        reader.toggle(text: "Text", language: "automatic", rate: 0.45)
        engine.canPause = false
        reader.pauseForComparison()
        #expect(reader.state == .idle)
    }
}

private actor RecognitionGate {
    private var continuations: [CheckedContinuation<String, Error>] = []
    var count: Int { continuations.count }
    func read() async throws -> String {
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func finish(_ index: Int, text: String) { continuations[index].resume(returning: text) }
}

@MainActor private final class FakeReaderSpeech: ReaderSpeechEngine {
    var onFinish: ((UUID) -> Void)?
    var ids: [UUID] = []
    var rates: [Float] = []
    var pauses = 0
    var resumes = 0
    var stops = 0
    var canStart = true
    var canResume = true
    var canPause = true
    func speak(text: String, language: String, rate: Float, id: UUID) -> Bool { ids.append(id); rates.append(rate); return canStart }
    func pause() -> Bool { pauses += 1; return canPause }
    func resume() -> Bool { resumes += 1; return canResume }
    func stop() { stops += 1 }
}
