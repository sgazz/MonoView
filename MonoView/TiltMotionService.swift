import Foundation
import CoreMotion

@MainActor
protocol TiltControlling: AnyObject {
    var sensitivity: Double { get set }
    func start(orientation: TiltOrientation, onMove: @escaping (CGSize) -> Void,
               onFailure: @escaping (String) -> Void) -> Bool
    func stop()
    func recenter()
}

@MainActor
final class TiltMotionService: TiltControlling {
    var sensitivity = 1.0
    private let manager = CMMotionManager()
    private var reference: TiltQuaternion?
    private var lastTimestamp: TimeInterval?
    private var integrator = TiltIntegrator()
    private var generation = UUID()
    private var startupTimeout: Task<Void, Never>?

    func start(orientation: TiltOrientation, onMove: @escaping (CGSize) -> Void,
               onFailure: @escaping (String) -> Void) -> Bool {
        stop()
        guard manager.isDeviceMotionAvailable else { return false }
        let run = generation
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            let attitude = motion?.attitude.quaternion
            let quaternion = attitude.map { TiltQuaternion(x: $0.x, y: $0.y, z: $0.z, w: $0.w) }
            let timestamp = motion?.timestamp
            let failure = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.generation == run else { return }
                if let failure {
                    self.stop()
                    onFailure("Device motion could not be read. \(failure)")
                    return
                }
                guard let quaternion, let timestamp else { return }
                self.startupTimeout?.cancel()
                self.startupTimeout = nil
                guard let reference = self.reference, let last = self.lastTimestamp else {
                    self.reference = quaternion
                    self.lastTimestamp = timestamp
                    return
                }
                self.lastTimestamp = timestamp
                let relative = quaternion.relative(to: reference)
                let delta = self.integrator.movement(roll: relative.roll, pitch: relative.pitch,
                                                    orientation: orientation, sensitivity: self.sensitivity,
                                                    deltaTime: timestamp - last)
                onMove(delta)
            }
        }
        startupTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.generation == run, self.reference == nil else { return }
            self.stop()
            onFailure("No motion data arrived. You can still use the arrows or drag the photo.")
        }
        return true
    }

    func recenter() {
        reference = nil
        lastTimestamp = nil
        integrator.reset()
    }

    func stop() {
        generation = UUID()
        startupTimeout?.cancel()
        startupTimeout = nil
        manager.stopDeviceMotionUpdates()
        recenter()
    }

    deinit {
        startupTimeout?.cancel()
        manager.stopDeviceMotionUpdates()
    }
}
