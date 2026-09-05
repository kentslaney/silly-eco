import Foundation
import simd

/// Solves coordinate alignment, paper displacement tolerance, and metric scale correction
/// based on 4 pen-drawn line segments starting at the corners of the QR code.
/// When line segment lengths are 0, returns the identity transformation.
public struct CornerLineCalibrationResult: Sendable, Equatable {
    /// Metric scale correction factor (1.0 = nominal physical scale)
    public var scaleFactor: Float
    /// Translation offset in meters of the paper relative to the original authoring origin
    public var translationOffset: SIMD3<Float>
    /// Rotation correction quaternion (simd_quatf)
    public var rotationCorrection: simd_quatf
    /// Combined 4x4 transformation matrix
    public var transformMatrix: simd_float4x4
    /// Alignment residual in millimeters (0 for exact match)
    public var residualMm: Float
    /// Whether this represents the nominal identity transformation
    public var isIdentity: Bool

    public static let identity = CornerLineCalibrationResult(
        scaleFactor: 1.0,
        translationOffset: .zero,
        rotationCorrection: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
        transformMatrix: matrix_identity_float4x4,
        residualMm: 0.0,
        isIdentity: true
    )
}

public final class CornerLineCalibrationEngine: Sendable {

    public init() {}

    /// Computes the nominal 2D positions of the 4 QR corners on the paper plane (in millimeters)
    /// where (0, 0) is the center of the QR code.
    public static func qrCorners(qrSizeMm: Float) -> [QRCorner: SIMD2<Float>] {
        let half = qrSizeMm / 2.0
        return [
            .topLeft: SIMD2<Float>(-half, half),
            .topRight: SIMD2<Float>(half, half),
            .bottomRight: SIMD2<Float>(half, -half),
            .bottomLeft: SIMD2<Float>(-half, -half)
        ]
    }

    /// Solves origin calibration from detected/adjusted corner line segments.
    /// - Parameters:
    ///   - segments: The 4 corner line segments starting at the QR corners.
    ///   - qrSizeMm: Nominal width of the QR code in mm (default 100mm).
    /// - Returns: `CornerLineCalibrationResult` containing scale factor and transformation.
    public func solve(
        segments: [CornerLineSegment],
        qrSizeMm: Float = 100.0
    ) -> CornerLineCalibrationResult {
        // 1. Check if all line segments have 0 length (Identity Transformation)
        let totalLength = segments.reduce(0.0) { $0 + $1.lengthMm }
        if totalLength < 0.5 { // Less than 0.5mm total across all corners -> Identity
            return .identity
        }

        let corners = Self.qrCorners(qrSizeMm: qrSizeMm)

        // 2. Compute Scale Correction Factor
        // Compare measured length against nominal scale reference length
        var validNominalSum: Float = 0.0
        var validObservedSum: Float = 0.0

        for segment in segments {
            if segment.nominalScaleLengthMm > 0.1 {
                validNominalSum += segment.nominalScaleLengthMm
                validObservedSum += segment.lengthMm
            }
        }

        let scaleFactor: Float
        if validNominalSum > 0.1 {
            scaleFactor = max(0.5, min(2.0, validObservedSum / validNominalSum))
        } else {
            scaleFactor = 1.0
        }

        // 3. Compute Paper Displacement relative to pen marks
        // The pen marks were drawn starting at the 4 corners: c_i.
        // The offsets v_i = offsetMm define the displacement vectors.
        // If the paper shifted by translation (tx, ty) and rotation (theta):
        // Average translation offset in mm:
        var avgOffsetMm = SIMD2<Float>.zero
        for segment in segments {
            avgOffsetMm += segment.offsetMm
        }
        avgOffsetMm /= Float(max(1, segments.count))

        // Rotational offset estimation around Z-axis (normal to paper):
        // Cross product of nominal corner radial vector with offset vector
        var angularSum: Float = 0.0
        var weightSum: Float = 0.0

        for segment in segments {
            guard let cornerPos = corners[segment.corner] else { continue }
            let r = simd_length(cornerPos)
            if r > 0.001 && segment.lengthMm > 0.5 {
                // Tangential component of offset: (corner x offset) / |corner|^2
                let cross = (cornerPos.x * segment.offsetMm.y) - (cornerPos.y * segment.offsetMm.x)
                let dTheta = cross / (r * r)
                angularSum += dTheta
                weightSum += 1.0
            }
        }

        let thetaZ = weightSum > 0 ? (angularSum / weightSum) : 0.0

        // Convert offsets to meters in 3D:
        // Paper plane: X = Right, Y = Paper Normal (+Y up), Z = Down/Front (-Y in 2D paper)
        // Or in standard CAD convention: X = Right, Y = Up, Z = Out of plane
        // Here we use paper frame: X (meters) = offsetMm.x / 1000, Z (meters) = -offsetMm.y / 1000
        let translationMeters = SIMD3<Float>(
            avgOffsetMm.x / 1000.0,
            0.0,
            -avgOffsetMm.y / 1000.0
        )

        // Rotation around normal (Y axis)
        let rotationQuat = simd_quatf(angle: thetaZ, axis: SIMD3<Float>(0, 1, 0))

        // Build 4x4 matrix
        var matrix = simd_matrix4x4(rotationQuat)
        // Apply uniform scale
        matrix.columns.0 *= scaleFactor
        matrix.columns.1 *= scaleFactor
        matrix.columns.2 *= scaleFactor
        // Apply translation
        matrix.columns.3 = SIMD4<Float>(translationMeters.x, translationMeters.y, translationMeters.z, 1.0)

        // Compute residual
        let residual = simd_length(avgOffsetMm)

        return CornerLineCalibrationResult(
            scaleFactor: scaleFactor,
            translationOffset: translationMeters,
            rotationCorrection: rotationQuat,
            transformMatrix: matrix,
            residualMm: residual,
            isIdentity: false
        )
    }

    /// Projects 2D screen touches back onto paper plane coordinates (in mm)
    /// to support manual interactive adjustment in the scanner HUD.
    /// - Parameters:
    ///   - screenPoint: Normalized screen coordinates (0.0 ... 1.0).
    ///   - corner: Which corner segment is being adjusted.
    ///   - qrCenterScreen: Normalized screen position of QR center.
    ///   - qrScreenRadius: Approximate pixel radius of the QR code on screen.
    ///   - qrSizeMm: Physical size of QR code in mm.
    /// - Returns: Refined offset in millimeters.
    public func adjustCornerPoint(
        screenPoint: SIMD2<Float>,
        corner: QRCorner,
        qrCenterScreen: SIMD2<Float>,
        qrScreenRadius: Float,
        qrSizeMm: Float = 100.0
    ) -> SIMD2<Float> {
        let screenDelta = screenPoint - qrCenterScreen
        let mmPerScreenUnit = (qrSizeMm / 2.0) / max(0.001, qrScreenRadius)

        // Screen space to paper coordinates (Y inverted)
        let paperPosMm = SIMD2<Float>(screenDelta.x * mmPerScreenUnit, -screenDelta.y * mmPerScreenUnit)
        let corners = Self.qrCorners(qrSizeMm: qrSizeMm)
        let cornerBase = corners[corner] ?? .zero

        // Offset from corner base
        let offset = paperPosMm - cornerBase
        // If within snap tolerance (2mm), snap to 0 (Identity)
        if simd_length(offset) < 2.0 {
            return .zero
        }
        return offset
    }
}
