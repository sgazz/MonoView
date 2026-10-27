import SwiftUI
import Combine
import Vision

nonisolated struct RecognizedPhotoLine: Sendable {
    let text: String
    let box: CGRect
}

nonisolated enum PhotoTextRecognition {
    /// Preserve visible paragraph gaps while letting each paragraph wrap to the reader width.
    /// This simple top-to-bottom order is intended for ordinary text, not table reconstruction.
    static func readingText(from lines: [RecognizedPhotoLine]) -> String {
        let sorted = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                if $0.box.midY == $1.box.midY {
                    return $0.box.minX < $1.box.minX
                }
                return $0.box.midY > $1.box.midY
            }
        var text = ""
        var previous: RecognizedPhotoLine?
        for line in sorted {
            if let previous {
                let gap = previous.box.minY - line.box.maxY
                text += gap > max(previous.box.height, line.box.height) * 0.8 ? "\n\n" : " "
            }
            text += line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            previous = line
        }
        return text
    }

    static func recognize(_ image: CGImage) async throws -> String {
        let job = VisionTextJob()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try job.perform(image)
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            job.cancel()
            worker.cancel()
        }
    }
}

/// The request is configured once; only Vision's cancellation API is called across threads.
nonisolated private final class VisionTextJob: @unchecked Sendable {
    private let request: VNRecognizeTextRequest
    init() {
        request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        request.preferBackgroundProcessing = true
    }
    func perform(_ image: CGImage) throws -> String {
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { result -> RecognizedPhotoLine? in
            guard let candidate = result.topCandidates(1).first else { return nil }
            return RecognizedPhotoLine(text: candidate.string, box: result.boundingBox)
        }
        return PhotoTextRecognition.readingText(from: lines)
    }
    func cancel() { request.cancel() }
}

@MainActor final class PhotoTextDocument: ObservableObject {
    enum Phase: Equatable { case idle, recognizing, ready, empty, failed }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var text = ""
    private var requestID = UUID()
    private let recognize: @Sendable (CGImage) async throws -> String

    init(recognize: @escaping @Sendable (CGImage) async throws -> String = PhotoTextRecognition.recognize) {
        self.recognize = recognize
    }
    func load(image: UIImage, retry: Bool = false) async {
        guard retry || phase == .idle else { return }
        let id = UUID()
        requestID = id
        text = ""
        phase = .recognizing
        guard let bitmap = image.cgImage else { phase = .failed; return }
        do {
            let result = try await recognize(bitmap).trimmingCharacters(in: .whitespacesAndNewlines)
            guard requestID == id, !Task.isCancelled else { return }
            text = result
            phase = result.isEmpty ? .empty : .ready
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            phase = .failed
        }
    }
    func cancel() {
        requestID = UUID()
        if phase == .recognizing { phase = .idle }
    }
}
