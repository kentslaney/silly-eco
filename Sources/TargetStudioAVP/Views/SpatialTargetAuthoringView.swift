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

/// RealityKit ImmersiveSpace spatial target authoring environment.
/// Targets are held up by 3D hands scaled to the user's hand dimensions.
public struct SpatialTargetAuthoringView: View {

    @Binding public var course: Course
    @State private var selectedTargetID: UUID?
    @State private var userHandScale: Float = 1.0

    public init(course: Binding<Course>) {
        self._course = course
    }

    public var body: some View {
        #if canImport(RealityKit)
        RealityView { content in
            // Build root origin entity
            let rootEntity = Entity()
            rootEntity.name = "OriginRoot"

            // 1. Add paper fiducial preview with corner line guides
            let paperMesh = MeshResource.generatePlane(
                width: course.paperFormat.dimensionsMm(for: course.paperOrientation).width / 1000.0,
                depth: course.paperFormat.dimensionsMm(for: course.paperOrientation).height / 1000.0
            )
            var paperMaterial = SimpleMaterial()
            paperMaterial.color = .init(tint: TargetColor.white.withAlphaComponent(0.85))
            let paperEntity = ModelEntity(mesh: paperMesh, materials: [paperMaterial])
            rootEntity.addChild(paperEntity)

            // 2. Add authored targets held by user-scaled 3D hands
            for target in course.targets {
                let targetGroup = makeHandHeldTargetEntity(target: target, handScale: userHandScale)
                rootEntity.addChild(targetGroup)
            }

            content.add(rootEntity)
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "OriginRoot" }) else { return }

            // Update user hand scale from active HandTracking measurements
            let activeScale = UserHandSizer.shared.currentHandScale
            if abs(activeScale - userHandScale) > 0.02 {
                userHandScale = activeScale
            }

            // Synchronize targets
            for target in course.targets {
                let entityName = "Target_\(target.id.uuidString)"
                if let existing = root.children.first(where: { $0.name == entityName }) {
                    existing.position = target.position
                } else {
                    let newEntity = makeHandHeldTargetEntity(target: target, handScale: userHandScale)
                    root.addChild(newEntity)
                }
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard let id = selectedTargetID,
                          let idx = course.targets.firstIndex(where: { $0.id == id }) else { return }
                    // Update target position in 3D space
                    let deltaX = Float(value.translation.width) * 0.001
                    let deltaY = -Float(value.translation.height) * 0.001
                    course.targets[idx].position.x += deltaX
                    course.targets[idx].position.y += deltaY
                }
        )
        #else
        VStack {
            Text("Spatial Target Authoring Space")
                .font(.title)
            Text("Target count: \(course.targets.count)")
        }
        #endif
    }

    #if canImport(RealityKit)
    /// Creates a composite Entity containing the target sphere and the supporting 3D hand
    /// scaled to match the user's actual hand dimensions.
    private func makeHandHeldTargetEntity(target: SphericalTarget, handScale: Float) -> Entity {
        let group = Entity()
        group.name = "Target_\(target.id.uuidString)"
        group.position = target.position

        // 1. Spherical Target Entity
        let sphereMesh = MeshResource.generateSphere(radius: target.radius)
        var sphereMaterial = SimpleMaterial()
        sphereMaterial.color = .init(tint: TargetColor.fromHex(target.colorHex))
        let sphereEntity = ModelEntity(mesh: sphereMesh, materials: [sphereMaterial])
        sphereEntity.name = "SphereMesh"
        group.addChild(sphereEntity)

        // 2. 3D Hand Model Supporting the Sphere
        // A stylized cupped palm model supporting the sphere from below
        let handEntity = makeSupportingHandMeshEntity(sphereRadius: target.radius, scale: handScale)
        handEntity.name = "SupportingHand"
        group.addChild(handEntity)

        return group
    }

    /// Generates a RealityKit entity representing a human hand scaled to the user's hand size,
    /// cupping the bottom of the target sphere.
    private func makeSupportingHandMeshEntity(sphereRadius: Float, scale: Float) -> Entity {
        let handGroup = Entity()

        // Scaled palm base
        let palmWidth: Float = 0.085 * scale
        let palmLength: Float = 0.095 * scale
        let palmThickness: Float = 0.020 * scale

        let palmMesh = MeshResource.generateBox(width: palmWidth, height: palmThickness, depth: palmLength, cornerRadius: 0.008 * scale)
        var handMaterial = SimpleMaterial()
        handMaterial.color = .init(tint: TargetColor(white: 0.85, alpha: 0.9))
        let palmEntity = ModelEntity(mesh: palmMesh, materials: [handMaterial])

        // Position palm just tangent to the bottom of the sphere
        palmEntity.position = SIMD3<Float>(0.0, -sphereRadius - (palmThickness / 2.0), 0.0)
        handGroup.addChild(palmEntity)

        // Forearm / wrist extension downward
        let armRadius: Float = 0.030 * scale
        let armLength: Float = 0.200 * scale
        let armMesh = MeshResource.generateCylinder(height: armLength, radius: armRadius)
        let armEntity = ModelEntity(mesh: armMesh, materials: [handMaterial])
        armEntity.position = SIMD3<Float>(0.0, palmEntity.position.y - (armLength / 2.0), -0.02 * scale)
        handGroup.addChild(armEntity)

        return handGroup
    }
    #endif
}
