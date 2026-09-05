import Foundation
import simd

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Paper Orientation & Format

public enum PaperOrientation: String, Codable, Sendable, CaseIterable {
    case portrait
    case landscape
}

public enum PaperFormat: Codable, Sendable, Equatable {
    case letter
    case a4
    case custom(widthMm: Float, heightMm: Float)

    public var dimensionsMm: (width: Float, height: Float) {
        switch self {
        case .letter:
            return (215.9, 279.4)
        case .a4:
            return (210.0, 297.0)
        case .custom(let width, let height):
            return (width, height)
        }
    }

    public func dimensionsMm(for orientation: PaperOrientation) -> (width: Float, height: Float) {
        let (w, h) = dimensionsMm
        switch orientation {
        case .portrait:
            return (min(w, h), max(w, h))
        case .landscape:
            return (max(w, h), min(w, h))
        }
    }
}

// MARK: - QR Corners & Corner Line Segments

public enum QRCorner: String, Codable, Sendable, CaseIterable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft

    /// Nominal relative unit direction extending outward at 45 degrees from the corner
    public var outwardDirection: SIMD2<Float> {
        switch self {
        case .topLeft:
            return SIMD2<Float>(-1, 1) / sqrt(2)
        case .topRight:
            return SIMD2<Float>(1, 1) / sqrt(2)
        case .bottomRight:
            return SIMD2<Float>(1, -1) / sqrt(2)
        case .bottomLeft:
            return SIMD2<Float>(-1, -1) / sqrt(2)
        }
    }
}

public struct CornerLineSegment: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var corner: QRCorner
    /// Offset vector in millimeters from the corresponding QR corner: (dx, dy).
    /// A value of (0, 0) (length == 0) represents the identity transformation.
    public var offsetMm: SIMD2<Float>
    /// Nominal physical length in millimeters corresponding to a scale factor of 1.0.
    /// Default is 50.0 mm if calibrated via extended line, or 0.0 if identity.
    public var nominalScaleLengthMm: Float

    public var lengthMm: Float {
        simd_length(offsetMm)
    }

    public var isIdentity: Bool {
        lengthMm < 0.5 // Tolerance within 0.5 mm
    }

    public init(
        id: UUID = UUID(),
        corner: QRCorner,
        offsetMm: SIMD2<Float> = .zero,
        nominalScaleLengthMm: Float = 50.0
    ) {
        self.id = id
        self.corner = corner
        self.offsetMm = offsetMm
        self.nominalScaleLengthMm = nominalScaleLengthMm
    }

    public static func identity(for corner: QRCorner) -> CornerLineSegment {
        CornerLineSegment(corner: corner, offsetMm: .zero, nominalScaleLengthMm: 0.0)
    }
}

// MARK: - Spherical Target

public struct SphericalTarget: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Position in meters relative to calibrated paper origin (QR center).
    /// +X: Right, +Y: Upward Normal from paper, +Z: Down/Front along paper surface.
    public var position: SIMD3<Float>
    /// Radius in meters (e.g. 0.05m to 0.50m)
    public var radius: Float
    /// Hex color string (e.g. "#00FFCC")
    public var colorHex: String
    /// Gameplay point value
    public var pointValue: Int
    /// Optional label
    public var label: String

    public init(
        id: UUID = UUID(),
        position: SIMD3<Float>,
        radius: Float = 0.12,
        colorHex: String = "#00FFCC",
        pointValue: Int = 50,
        label: String = "Target"
    ) {
        self.id = id
        self.position = position
        self.radius = radius
        self.colorHex = colorHex
        self.pointValue = pointValue
        self.label = label
    }
}

// MARK: - Device Physical Profile (For Tangent Rounded Rectangle in Handheld AR)

public struct DevicePhysicalProfile: Codable, Sendable, Equatable {
    public var name: String
    /// Physical width in meters
    public var width: Float
    /// Physical height in meters
    public var height: Float
    /// Physical thickness in meters
    public var thickness: Float
    /// Corner radius in meters
    public var cornerRadius: Float

    public init(
        name: String,
        width: Float,
        height: Float,
        thickness: Float,
        cornerRadius: Float
    ) {
        self.name = name
        self.width = width
        self.height = height
        self.thickness = thickness
        self.cornerRadius = cornerRadius
    }

    /// Standard iPhone dimensions (e.g. iPhone 15/16 Pro: ~71.5mm x 147.6mm x 8.2mm, radius 14mm)
    public static let iPhoneStandard = DevicePhysicalProfile(
        name: "iPhone",
        width: 0.0715,
        height: 0.1476,
        thickness: 0.0082,
        cornerRadius: 0.014
    )

    /// iPhone Pro Max dimensions (~77.6mm x 163.0mm x 8.25mm)
    public static let iPhoneProMax = DevicePhysicalProfile(
        name: "iPhone Pro Max",
        width: 0.0776,
        height: 0.1630,
        thickness: 0.00825,
        cornerRadius: 0.016
    )

    /// iPad dimensions (~178.5mm x 247.6mm x 6.1mm)
    public static let iPad = DevicePhysicalProfile(
        name: "iPad",
        width: 0.1785,
        height: 0.2476,
        thickness: 0.0061,
        cornerRadius: 0.018
    )

    /// Returns the 3D position and orientation of the device silhouette
    /// rendered tangent to the bottom of the spherical target and oriented upwards.
    /// The top edge of the device rectangle touches the bottom of the sphere at (target.position.y - target.radius).
    public func tangentTransform(for target: SphericalTarget) -> simd_float4x4 {
        // Position: centered under the sphere in X and Z, with top edge touching sphere bottom in Y
        let topEdgeY = target.position.y - target.radius
        let centerY = topEdgeY - (height / 2.0)
        let translation = SIMD3<Float>(target.position.x, centerY, target.position.z)

        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1.0)
        return matrix
    }
}

// MARK: - Course Model

public struct Course: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var authorName: String
    public var courseDescription: String
    public var paperOrientation: PaperOrientation
    public var paperFormat: PaperFormat
    /// Nominal physical dimension of the square QR code on paper in millimeters (e.g. 100mm)
    public var qrSizeMm: Float
    /// The 4 corner line segments starting at the QR corners.
    /// If all lengths are 0, this represents the identity transformation.
    public var cornerSegments: [CornerLineSegment]
    /// Targets authored in spatial space
    public var targets: [SphericalTarget]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        authorName: String = "Creator",
        courseDescription: String = "",
        paperOrientation: PaperOrientation = .portrait,
        paperFormat: PaperFormat = .letter,
        qrSizeMm: Float = 100.0,
        cornerSegments: [CornerLineSegment] = QRCorner.allCases.map { CornerLineSegment.identity(for: $0) },
        targets: [SphericalTarget] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.authorName = authorName
        self.courseDescription = courseDescription
        self.paperOrientation = paperOrientation
        self.paperFormat = paperFormat
        self.qrSizeMm = qrSizeMm
        self.cornerSegments = cornerSegments
        self.targets = targets
        self.createdAt = createdAt
    }

    /// Whether all corner line segments represent the identity transformation (0 length).
    public var isIdentityTransform: Bool {
        cornerSegments.allSatisfy { $0.isIdentity }
    }
}
