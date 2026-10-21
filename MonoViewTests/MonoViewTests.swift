import Testing
import SwiftUI
@testable import MonoView

struct MonoViewTests {
    @Test func fittedImageCannotPan() {
        let result = ViewerModel.clamp(CGSize(width: 300, height: -300), image: CGSize(width: 1200, height: 800), viewport: CGSize(width: 400, height: 600), zoom: 1)
        #expect(result == .zero)
    }

    @Test func zoomedLandscapeImageHasIndependentBounds() {
        let result = ViewerModel.clamp(CGSize(width: 999, height: -999), image: CGSize(width: 1200, height: 600), viewport: CGSize(width: 400, height: 400), zoom: 3)
        #expect(result == CGSize(width: 400, height: -100))
    }

    @Test @MainActor func zoomStaysInsideLimits() {
        let model = ViewerModel()
        model.changeZoom(by: 100)
        #expect(model.zoom == 20)
        model.changeZoom(by: 0.001)
        #expect(model.zoom == 1)
    }

    @Test func missingLayoutDoesNotCreateInvalidOffsets() {
        #expect(ViewerModel.clamp(CGSize(width: 100, height: 100), image: .zero, viewport: .zero, zoom: 20) == .zero)
    }
    @Test @MainActor func overviewRestoresDetailAndNewImageResetsTransform() async throws {
        let model = ViewerModel()
        let data = try #require(UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        }.pngData())
        await model.completeImport(data, id: model.beginImport())
        model.resizeViewport(CGSize(width: 300, height: 300))
        model.changeZoom(by: 3)
        model.move(dx: 80, dy: 20)
        let originalOffset = model.offset
        model.toggleOverview()
        #expect(model.displayedZoom == 1)
        #expect(model.displayedOffset == .zero)
        model.toggleOverview()
        #expect(model.displayedZoom == 3)
        #expect(model.displayedOffset == originalOffset)
        await model.completeImport(data, id: model.beginImport())
        #expect(model.zoom == 1)
        #expect(model.offset == .zero)
        #expect(!model.isOverview)
    }

    @Test @MainActor func staleImportCannotCompleteNewerRequest() async {
        let model = ViewerModel()
        let old = model.beginImport()
        let current = model.beginImport()
        await model.completeImport(nil, id: old)
        #expect(model.isLoading)
        #expect(model.errorMessage == nil)
        await model.completeImport(nil, id: current)
        #expect(!model.isLoading)
        #expect(model.errorMessage != nil)
    }
    @Test func ambiguousStartsDoNotGuessAHand() {
        let strokes = [
            [CGPoint(x: 200, y: 600), CGPoint(x: 300, y: 400)],
            [CGPoint(x: 210, y: 600), CGPoint(x: 100, y: 400)]
        ]
        #expect(ReachEstimator.suggestedHand(strokes: strokes, size: CGSize(width: 414, height: 814)) == nil)
    }

    @Test func rightSideStartsSuggestRightHand() {
        let strokes = Array(repeating: [CGPoint(x: 380, y: 600), CGPoint(x: 200, y: 400)], count: 2)
        #expect(ReachEstimator.suggestedHand(strokes: strokes, size: CGSize(width: 414, height: 814)) == "right")
    }

    @Test func gapBetweenPathsIsNotAssumedReachable() {
        let strokes = [20.0, 390.0].map { x in
            stride(from: 200.0, through: 700.0, by: 10).map { CGPoint(x: x, y: $0) }
        }
        #expect(ReachEstimator.recommend(strokes: strokes, size: CGSize(width: 414, height: 814), hand: "right") == nil)
    }

    @Test @MainActor func broadTracesProduceAnInBoundsLayout() throws {
        let strokes = stride(from: 300.0, through: 700.0, by: 16).map { y in
            stride(from: 80.0, through: 400.0, by: 10).map { CGPoint(x: $0, y: y) }
        }
        let profile = try #require(ReachEstimator.recommend(strokes: strokes, size: CGSize(width: 414, height: 814), hand: "right"))
        let rect = profile.rect(in: CGSize(width: 414, height: 814))
        #expect(rect.minX >= 6 && rect.maxX <= 408)
        #expect(rect.minY >= 96 && rect.maxY <= 808)
        #expect(profile.coverage >= 0.6)
        let data = try JSONEncoder().encode(profile)
        let restored = try JSONDecoder().decode(ReachProfile.self, from: data)
        #expect(restored.rect(in: CGSize(width: 414, height: 814)) == rect)
    }

    @Test func tapsDoNotCountAsSweeps() {
        #expect(!ReachEstimator.hasEnoughMovement(Array(repeating: [CGPoint(x: 100, y: 200), CGPoint(x: 101, y: 201)], count: 10)))
    }
    @Test @MainActor func curvedBandProducesTerritoriesInsideTheTrace() throws {
        let size = CGSize(width: 414, height: 814)
        let arcs = stride(from: -48.0, through: 48.0, by: 12).map { offset in
            stride(from: 0.0, through: 1.0, by: 0.025).map { t in
                CGPoint(x: 140 + 220 * t, y: 640 - 170 * sqrt(t) + offset)
            }
        }
        let profile = try #require(ReachEstimator.recommend(strokes: arcs, size: size, hand: "right"))
        let regions = try #require(profile.regions)
        #expect(regions.count >= 2)
        let paths: [CGPath] = regions.map { region in
            let path = CGMutablePath()
            for loop in region.contours {
                guard let first = loop.first else { continue }
                path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                for point in loop.dropFirst() { path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height)) }
                path.closeSubpath()
            }
            return path
        }
        for (index, region) in regions.enumerated() {
            for dx in stride(from: -22.0, through: 22.0, by: 11) {
                for dy in stride(from: -22.0, through: 22.0, by: 11) {
                    let point = CGPoint(x: region.anchor.x * size.width + dx, y: region.anchor.y * size.height + dy)
                    #expect(paths[index].contains(point, using: .evenOdd))
                    #expect(paths.enumerated().filter { $0.offset != index }.allSatisfy { !$0.element.contains(point, using: .evenOdd) })
                }
            }
        }
        #expect(paths.allSatisfy { !$0.contains(CGPoint(x: 150, y: 440), using: .evenOdd) })
        #expect(profile.matches(size))
        #expect(!profile.matches(CGSize(width: 390, height: 814)))
        #expect(!profile.matches(CGSize(width: 814, height: 414)))
        let restored = try JSONDecoder().decode(ReachProfile.self, from: JSONEncoder().encode(profile))
        #expect(restored.regions?.count == regions.count)
    }

    @Test func narrowLineCannotCreateSmallUnusableButtons() {
        let line = stride(from: 300.0, through: 700.0, by: 10).map { CGPoint(x: 280, y: $0) }
        #expect(ReachEstimator.recommend(strokes: [line, line], size: CGSize(width: 414, height: 814), hand: "right") == nil)
    }
    @Test func tiltIsStableAcrossSampleRatesAndHasADeadZone() {
        func total(hz: Double) -> CGSize {
            var integrator = TiltIntegrator()
            var result = CGSize.zero
            for _ in 0..<Int(hz * 2) {
                let step = integrator.movement(roll: 0.2, pitch: 0, orientation: .portrait, sensitivity: 1, deltaTime: 1 / hz)
                result.width += step.width
                result.height += step.height
            }
            return result
        }
        let slow = total(hz: 30), fast = total(hz: 120)
        #expect(slow.width < 0 && fast.width < 0)
        #expect(abs(slow.width - fast.width) < 3)
        var integrator = TiltIntegrator()
        #expect(integrator.movement(roll: 0.02, pitch: -0.02, orientation: .portrait, sensitivity: 1, deltaTime: 1 / 60) == .zero)
        let bounded = integrator.movement(roll: 1, pitch: 1, orientation: .portrait, sensitivity: 2, deltaTime: 10)
        #expect(abs(bounded.width) <= 18 && abs(bounded.height) <= 18)
    }

    @Test func relativeTiltStartsAtZeroAndMapsLandscapeAxes() {
        let reference = TiltQuaternion(x: 0.3, y: 0.2, z: 0.1, w: sqrt(0.86))
        let neutral = reference.relative(to: reference)
        #expect(abs(neutral.roll) < 0.00001 && abs(neutral.pitch) < 0.00001)
        var left = TiltIntegrator(), right = TiltIntegrator()
        let a = left.movement(roll: 0.2, pitch: 0, orientation: .landscapeLeft, sensitivity: 1, deltaTime: 0.05)
        let b = right.movement(roll: 0.2, pitch: 0, orientation: .landscapeRight, sensitivity: 1, deltaTime: 0.05)
        #expect(a.width == 0 && b.width == 0)
        #expect(a.height > 0 && b.height < 0)
        #expect(abs(a.height + b.height) < 0.00001)
    }

    @Test @MainActor func tiltStopsOnOverviewImportAndResetAndClampsMotion() async throws {
        let source = MockTiltController()
        let model = ViewerModel(tiltController: source)
        let data = try #require(UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
        }.pngData())
        await model.completeImport(data, id: model.beginImport())
        model.resizeViewport(CGSize(width: 300, height: 300))
        model.changeZoom(by: 3)
        model.toggleTilt()
        #expect(model.isTiltEnabled)
        source.onMove?(CGSize(width: 999, height: -999))
        #expect(model.offset == CGSize(width: 300, height: -300))
        model.recenterTilt()
        #expect(source.recenterCount == 1)
        model.toggleOverview()
        #expect(!model.isTiltEnabled)
        let frozen = model.offset
        source.onMove?(CGSize(width: -100, height: 100))
        #expect(model.offset == frozen)
        model.toggleOverview()
        model.toggleTilt()
        _ = model.beginImport()
        #expect(!model.isTiltEnabled)
        await model.completeImport(data, id: model.beginImport())
        model.changeZoom(by: 2)
        model.toggleTilt()
        model.reset()
        #expect(!model.isTiltEnabled)
        #expect(source.stopCount >= 3)
    }
}

@MainActor
private final class MockTiltController: TiltControlling {
    var sensitivity = 1.0
    var onMove: ((CGSize) -> Void)?
    var recenterCount = 0
    var stopCount = 0
    func start(orientation: TiltOrientation, onMove: @escaping (CGSize) -> Void, onFailure: @escaping (String) -> Void) -> Bool {
        self.onMove = onMove
        return true
    }
    func stop() { stopCount += 1 }
    func recenter() { recenterCount += 1 }
}
