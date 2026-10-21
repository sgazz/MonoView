import Foundation
import CoreGraphics

nonisolated enum TiltOrientation: Sendable {
    case portrait, upsideDown, landscapeLeft, landscapeRight
}

nonisolated struct TiltQuaternion: Sendable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double

    /// Same relative rotation as current attitude multiplied by inverse reference attitude.
    func relative(to reference: TiltQuaternion) -> TiltQuaternion {
        TiltQuaternion(x: -w * reference.x + x * reference.w - y * reference.z + z * reference.y,
                       y: -w * reference.y + x * reference.z + y * reference.w - z * reference.x,
                       z: -w * reference.z - x * reference.y + y * reference.x + z * reference.w,
                       w: w * reference.w + x * reference.x + y * reference.y + z * reference.z)
    }

    var roll: Double { atan2(2 * (w * y + x * z), 1 - 2 * (x * x + y * y)) }
    var pitch: Double { asin(min(1, max(-1, 2 * (w * x - y * z)))) }
}

nonisolated struct TiltIntegrator {
    private var filteredX = 0.0
    private var filteredY = 0.0

    mutating func reset() { filteredX = 0; filteredY = 0 }

    mutating func movement(roll: Double, pitch: Double, orientation: TiltOrientation,
                           sensitivity: Double, deltaTime: Double) -> CGSize {
        guard roll.isFinite, pitch.isFinite, sensitivity.isFinite,
              deltaTime.isFinite, deltaTime > 0 else { return .zero }
        // Never jump after a delayed sensor sample or a stalled UI frame.
        let dt = min(deltaTime, 0.05)
        let input: (Double, Double)
        switch orientation {
        case .portrait: input = (roll, pitch)
        case .upsideDown: input = (-roll, -pitch)
        case .landscapeLeft: input = (-pitch, roll)
        case .landscapeRight: input = (pitch, -roll)
        }
        let alpha = 1 - exp(-dt / 0.08)
        filteredX += (input.0 - filteredX) * alpha
        filteredY += (input.1 - filteredY) * alpha
        func speed(_ angle: Double) -> Double {
            let deadZone = 0.04
            guard abs(angle) > deadZone else { return 0 }
            let fraction = min(1, (abs(angle) - deadZone) / (0.30 - deadZone))
            return (angle < 0 ? -1 : 1) * fraction * 180 * min(2, max(0.4, sensitivity))
        }
        // Moving the view right means moving the image left, matching the arrow controls.
        return CGSize(width: -speed(filteredX) * dt, height: speed(filteredY) * dt)
    }
}
