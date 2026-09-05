import SwiftUI
import TargetCore
import simd

#if canImport(RealityKit)
import RealityKit
#endif

#if canImport(UIKit)
import UIKit
public typealias TargetColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias TargetColor = NSColor
#endif

extension TargetColor {
    static func fromHex(_ hex: String) -> TargetColor {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        guard cleanHex.count == 6, let rgbValue = UInt64(cleanHex, radix: 16) else { return .cyan }
        return TargetColor(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }
}

/// Renders the course targets in RealityKit AR anchored to the calibrated origin.
/// - On iOS (Handheld AR): Renders a rounded rectangle the physical size of the device
///   positioned tangent to the spherical target and oriented upwards on the device.
/// - On visionOS: Renders 3D hands scaled to the user's hand size holding the targets.
public struct ARRealityPreviewView: View {

    public let course: Course
    public let calibration: CornerLineCalibrationResult
    public let onPlayInSillyBells: () -> Void

    @State private var selectedTargetID: UUID?

    public init(
        course: Course,
        calibration: CornerLineCalibrationResult,
        onPlayInSillyBells: @escaping () -> Void
    ) {
        self.course = course
        self.calibration = calibration
        self.onPlayInSillyBells = onPlayInSillyBells
    }

    public var body: some View {
        ZStack {
            #if canImport(RealityKit)
            RealityView { content in
                let originAnchor = Entity()
                originAnchor.name = "CalibratedOrigin"
                originAnchor.transform = Transform(matrix: calibration.transformMatrix)

                let profile = DevicePhysicalProfile.iPhoneStandard

                for target in course.targets {
                    let targetEntity = makeTargetEntity(target: target, profile: profile)
                    originAnchor.addChild(targetEntity)
                }

                content.add(originAnchor)
            }
            #else
            Color.black
            #endif

            // Top Status Bar
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(course.title)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("\(course.targets.count) Targets • Scale: \(String(format: "%.2fx", calibration.scaleFactor))")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Spacer()
                    Button(action: onPlayInSillyBells) {
                        Label("Play in Silly Bells ($1)", systemImage: "play.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.bold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.75)))
                .padding(.horizontal)
                .padding(.top, 44)

                Spacer()

                // Target Carousel / Selector at bottom
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(course.targets) { target in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: target.colorHex) ?? .cyan)
                                        .frame(width: 12, height: 12)
                                    Text(target.label)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                }
                                Text("Score: \(target.pointValue) pts • \(Int(target.radius * 100))cm")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedTargetID == target.id ? Color.cyan.opacity(0.4) : Color.black.opacity(0.65))
                            )
                            .onTapGesture {
                                selectedTargetID = target.id
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
        }
    }

    #if canImport(RealityKit)
    /// Builds the target composite entity.
    /// In handheld AR, attaches a rounded rectangle matching device size tangent to the sphere oriented upwards.
    private func makeTargetEntity(target: SphericalTarget, profile: DevicePhysicalProfile) -> Entity {
        let group = Entity()
        group.name = "Target_\(target.id.uuidString)"
        group.position = target.position

        // 1. Spherical Target Mesh
        let sphereMesh = MeshResource.generateSphere(radius: target.radius)
        var sphereMat = SimpleMaterial()
        sphereMat.color = .init(tint: TargetColor.fromHex(target.colorHex))
        let sphereModel = ModelEntity(mesh: sphereMesh, materials: [sphereMat])
        group.addChild(sphereModel)

        // 2. Handheld AR Device-Sized Rounded Rectangle
        // Rendered tangent to the spherical target oriented upwards on the device
        #if os(iOS)
        let deviceEntity = makeDeviceTangentEntity(target: target, profile: profile)
        group.addChild(deviceEntity)
        #elseif os(visionOS)
        // On visionOS, held up by hands sized to user
        let handEntity = makeSupportingHandEntity(sphereRadius: target.radius)
        group.addChild(handEntity)
        #endif

        return group
    }

    #if os(iOS)
    /// Creates a 3D rounded box matching the exact physical dimensions of the device,
    /// positioned tangent to the bottom of the spherical target, oriented upwards.
    private func makeDeviceTangentEntity(target: SphericalTarget, profile: DevicePhysicalProfile) -> Entity {
        let boxMesh = MeshResource.generateBox(
            width: profile.width,
            height: profile.height,
            depth: profile.thickness,
            cornerRadius: profile.cornerRadius
        )
        var deviceMat = SimpleMaterial()
        deviceMat.color = .init(tint: TargetColor(white: 0.15, alpha: 0.8))
        let deviceEntity = ModelEntity(mesh: boxMesh, materials: [deviceMat])

        // The top edge of the device rectangle touches the bottom of the sphere at Y = -target.radius.
        // Therefore, the center of the device box is at Y = -target.radius - (height / 2.0).
        let centerY = -target.radius - (profile.height / 2.0)
        deviceEntity.position = SIMD3<Float>(0.0, centerY, 0.0)

        // Subtle accent line along the top edge tangent to the sphere
        let tangentLineMesh = MeshResource.generateBox(width: profile.width * 0.8, height: 0.002, depth: 0.002)
        var lineMat = SimpleMaterial()
        lineMat.color = .init(tint: TargetColor.cyan)
        let lineEntity = ModelEntity(mesh: tangentLineMesh, materials: [lineMat])
        lineEntity.position = SIMD3<Float>(0.0, profile.height / 2.0, profile.thickness / 2.0 + 0.001)
        deviceEntity.addChild(lineEntity)

        return deviceEntity
    }
    #endif

    #if os(visionOS)
    private func makeSupportingHandEntity(sphereRadius: Float) -> Entity {
        let handGroup = Entity()
        let palmMesh = MeshResource.generateBox(width: 0.085, height: 0.020, depth: 0.095, cornerRadius: 0.008)
        var handMat = SimpleMaterial()
        handMat.color = .init(tint: TargetColor(white: 0.85, alpha: 0.9))
        let palm = ModelEntity(mesh: palmMesh, materials: [handMat])
        palm.position = SIMD3<Float>(0.0, -sphereRadius - 0.010, 0.0)
        handGroup.addChild(palm)
        return handGroup
    }
    #endif
    #endif
}

// MARK: - Color Hex Extension

extension Color {
    init?(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else { return nil }
        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
}
