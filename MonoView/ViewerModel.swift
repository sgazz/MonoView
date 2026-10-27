import SwiftUI
import Combine
import ImageIO

/// Coordinates are in the visible image area, not the physical device screen.
@MainActor
final class ViewerModel: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var offset: CGSize = .zero
    @Published private(set) var isOverview = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var isTiltEnabled = false
    @Published var tiltNotice: String?
    private let tiltController: any TiltControlling
    private var tiltSweepStartZoom: CGFloat?
    static let maximumZoom: CGFloat = 20

    init(tiltController: (any TiltControlling)? = nil) {
        self.tiltController = tiltController ?? TiltMotionService()
    }

    private var zoomSpeed = 1.0
    private var doubleTapZoom: CGFloat = 20
    func setZoomPreferences(speed: Double, doubleTap: Double) {
        zoomSpeed = speed.isFinite ? min(1.5, max(0.6, speed)) : 1
        doubleTapZoom = doubleTap.isFinite ? min(Self.maximumZoom, max(2, CGFloat(doubleTap))) : 20
    }

    func setTiltSensitivity(_ value: Double) {
        tiltController.sensitivity = min(2, max(0.4, value))
    }

    func toggleTilt() {
        if isTiltEnabled { stopTilt(); return }
        guard image != nil, zoom > 1, !isOverview, !isLoading else {
            tiltNotice = "Open a photo and zoom in before starting tilt panning."
            return
        }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.windows.contains(where: \.isKeyWindow) }
        let orientation: TiltOrientation
        switch scene?.interfaceOrientation {
        case .landscapeLeft: orientation = .landscapeLeft
        case .landscapeRight: orientation = .landscapeRight
        case .portraitUpsideDown: orientation = .upsideDown
        default: orientation = .portrait
        }
        let started = tiltController.start(orientation: orientation, onMove: { [weak self] delta in
            guard let self, self.isTiltEnabled, self.tiltSweepStartZoom == nil else { return }
            self.offset = self.bounded(CGSize(width: self.offset.width + delta.width,
                                              height: self.offset.height + delta.height))
        }, onFailure: { [weak self] message in
            self?.stopTilt()
            self?.tiltNotice = message
        })
        isTiltEnabled = started
        if !started { tiltNotice = "Tilt panning is not available on this device. Use the arrows or drag the photo instead." }
    }

    func stopTilt() {
        tiltSweepStartZoom = nil
        guard isTiltEnabled else { return }
        isTiltEnabled = false
        tiltController.stop()
    }

    func recenterTilt() {
        guard isTiltEnabled else { return }
        tiltController.recenter()
    }
    private var savedZoom: CGFloat = 1
    private var savedOffset: CGSize = .zero
    private var viewport: CGSize = .zero
    private var importID = UUID()

    var displayedZoom: CGFloat { isOverview ? 1 : zoom }
    var displayedOffset: CGSize { isOverview ? .zero : offset }

    func resizeViewport(_ size: CGSize) {
        if viewport != size { stopTilt() }
        viewport = size
        offset = bounded(offset)
    }

    func changeZoom(by factor: CGFloat, keepingTilt: Bool = false) {
        guard factor.isFinite, factor > 0 else { return }
        applyZoom(zoom * factor, keepingTilt: keepingTilt)
    }

    private func applyZoom(_ target: CGFloat, keepingTilt: Bool) {
        guard target.isFinite else { return }
        leaveOverview()
        let next = min(Self.maximumZoom, max(1, target))
        let ratio = next / zoom
        if next != zoom && (next == 1 || next == Self.maximumZoom) { ComfortFeedback.play(boundary: true) }
        zoom = next
        // Thumb zoom can return to 1× without losing the active Tilt gesture mode.
        if next <= 1 && !keepingTilt { stopTilt() }
        offset = bounded(CGSize(width: offset.width * ratio, height: offset.height * ratio))
    }

    func toggleTiltZoomLimit() {
        guard isTiltEnabled, image != nil, !isLoading else { return }
        tiltSweepStartZoom = nil
        applyZoom(zoom >= doubleTapZoom - 0.001 ? 1 : doubleTapZoom, keepingTilt: true)
        tiltController.recenter()
    }

    func updateTiltZoomSweep(translation: CGSize) {
        guard isTiltEnabled, image != nil, !isLoading, translation.height.isFinite else { return }
        if tiltSweepStartZoom == nil { tiltSweepStartZoom = zoom }
        guard let start = tiltSweepStartZoom else { return }
        // At normal speed, 100 screen points of vertical travel doubles/halves the scale.
        // Horizontal travel is unrestricted, so left and right thumb arcs behave alike.
        let exponent = min(10, max(-10, -translation.height * zoomSpeed / 100))
        applyZoom(start * pow(2, exponent), keepingTilt: true)
    }

    func endTiltZoomSweep() {
        guard tiltSweepStartZoom != nil else { return }
        tiltSweepStartZoom = nil
        // Finger movement can change the grip; restart motion from that resting pose.
        if isTiltEnabled { tiltController.recenter() }
    }

    func move(dx: CGFloat, dy: CGFloat) {
        leaveOverview()
        offset = bounded(CGSize(width: offset.width + dx, height: offset.height + dy))
    }

    func finishDrag(_ translation: CGSize) {
        guard !isOverview else { return }
        move(dx: translation.width, dy: translation.height)
    }

    func toggleOverview() {
        stopTilt()
        guard image != nil else { return }
        if isOverview {
            leaveOverview()
        } else {
            savedZoom = zoom
            savedOffset = offset
            isOverview = true
        }
    }

    func reset() {
        stopTilt()
        isOverview = false
        zoom = 1
        offset = .zero
    }

    private func leaveOverview() {
        if isOverview {
            zoom = savedZoom
            offset = bounded(savedOffset)
            isOverview = false
        }
    }

    func bounded(_ proposed: CGSize) -> CGSize {
        guard let image, viewport.width > 0, viewport.height > 0 else { return .zero }
        return Self.clamp(proposed, image: image.size, viewport: viewport, zoom: zoom)
    }

    nonisolated static func clamp(_ proposed: CGSize, image: CGSize, viewport: CGSize, zoom: CGFloat) -> CGSize {
        guard image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        let fit = min(viewport.width / image.width, viewport.height / image.height)
        let limitX = max(0, (image.width * fit * zoom - viewport.width) / 2)
        let limitY = max(0, (image.height * fit * zoom - viewport.height) / 2)
        return CGSize(width: min(limitX, max(-limitX, proposed.width)),
                      height: min(limitY, max(-limitY, proposed.height)))
    }

    func beginImport() -> UUID {
        stopTilt()
        let id = UUID()
        importID = id
        isLoading = true
        errorMessage = nil
        return id
    }

    func completeImport(_ data: Data?, id: UUID) async {
        guard id == importID else { return }
        guard let data else {
            isLoading = false
            errorMessage = "The photo could not be loaded. If it is stored in iCloud, check your connection and try again."
            return
        }
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.decode(data)
        }.value
        guard id == importID else { return }
        isLoading = false
        guard let decoded else {
            errorMessage = "This image format could not be opened. Please choose another photo."
            return
        }
        image = decoded
        reset()
    }

    /// Decode outside the UI actor, preserving orientation and avoiding a full-size bitmap allocation.
    /// 4096 px is a preview budget, not an increase in the source image's detail.
    nonisolated private static func decode(_ data: Data) -> UIImage? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 4096,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: bitmap)
        }
    }
}
