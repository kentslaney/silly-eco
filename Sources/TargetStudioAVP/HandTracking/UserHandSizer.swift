import Foundation
import simd
import TargetCore

#if canImport(ARKit)
import ARKit
#endif

/// Measures anthropometric user hand dimensions using visionOS HandTrackingProvider.
/// Used to dynamically scale 3D hands that hold up target spheres in TargetStudio AVP.
public final class UserHandSizer: @unchecked Sendable {

    public static let shared = UserHandSizer()

    /// Baseline reference hand length in meters (wrist joint to middle finger tip) ~ 185 mm
    public static let referenceHandLength: Float = 0.185

    /// Baseline reference palm breadth in meters ~ 85 mm
    public static let referencePalmBreadth: Float = 0.085

    /// Currently active measured scale factor (1.0 = baseline 185 mm)
    public private(set) var currentHandScale: Float = 1.0

    /// Measured physical hand length in meters
    public private(set) var measuredHandLength: Float = 0.185

    /// Measured physical palm width in meters
    public private(set) var measuredPalmWidth: Float = 0.085

    public init() {}

    /// Updates hand dimensions from visionOS ARKit HandSkeleton joint positions.
    public func updateFromJoints(
        wristPosition: SIMD3<Float>,
        middleFingerTip: SIMD3<Float>,
        indexKnuckle: SIMD3<Float>,
        littleKnuckle: SIMD3<Float>
    ) {
        // Hand length: wrist to middle finger tip
        let length = simd_distance(wristPosition, middleFingerTip)
        // Hand breadth: index knuckle to little knuckle
        let width = simd_distance(indexKnuckle, littleKnuckle)

        // Sanity check bounds for human hand: 120mm to 240mm
        if length > 0.12 && length < 0.25 {
            self.measuredHandLength = length
            self.currentHandScale = length / Self.referenceHandLength
        }

        if width > 0.05 && width < 0.13 {
            self.measuredPalmWidth = width
        }
    }

    /// Manually sets hand scale factor (0.7 to 1.4)
    public func setManualScale(_ scale: Float) {
        self.currentHandScale = max(0.7, min(1.4, scale))
        self.measuredHandLength = Self.referenceHandLength * currentHandScale
    }
}
