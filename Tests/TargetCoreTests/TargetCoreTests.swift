import Testing
import Foundation
import simd
@testable import TargetCore

struct TargetCoreTests {

    // MARK: - 1. 0-Length Identity Transformation

    @Test func testZeroLengthIdentityTransform() {
        let engine = CornerLineCalibrationEngine()
        let segments = QRCorner.allCases.map { CornerLineSegment.identity(for: $0) }

        let result = engine.solve(segments: segments, qrSizeMm: 100.0)

        #expect(result.isIdentity)
        #expect(abs(result.scaleFactor - 1.0) < 0.001)
        #expect(simd_length(result.translationOffset) < 0.001)
        #expect(result.residualMm < 0.001)
    }

    // MARK: - 2. Scale Correction Calculation

    @Test func testScaleCorrectionCalculation() {
        let engine = CornerLineCalibrationEngine()

        // Nominal length 50mm, drawn line measured at 45mm (scale 0.90)
        let segments90 = QRCorner.allCases.map { corner in
            CornerLineSegment(
                corner: corner,
                offsetMm: corner.outwardDirection * 45.0,
                nominalScaleLengthMm: 50.0
            )
        }
        let result90 = engine.solve(segments: segments90, qrSizeMm: 100.0)
        #expect(abs(result90.scaleFactor - 0.90) < 0.01)

        // Nominal length 50mm, drawn line measured at 55mm (scale 1.10)
        let segments110 = QRCorner.allCases.map { corner in
            CornerLineSegment(
                corner: corner,
                offsetMm: corner.outwardDirection * 55.0,
                nominalScaleLengthMm: 50.0
            )
        }
        let result110 = engine.solve(segments: segments110, qrSizeMm: 100.0)
        #expect(abs(result110.scaleFactor - 1.10) < 0.01)
    }

    // MARK: - 3. Paper Displacement Calculation

    @Test func testPaperDisplacementCalculation() {
        let engine = CornerLineCalibrationEngine()

        // Paper shifted +10mm in X and +5mm in Y
        let shiftMm = SIMD2<Float>(10.0, 5.0)
        let segments = QRCorner.allCases.map { corner in
            CornerLineSegment(corner: corner, offsetMm: shiftMm, nominalScaleLengthMm: 0.0)
        }

        let result = engine.solve(segments: segments, qrSizeMm: 100.0)

        #expect(!result.isIdentity)
        // 10mm -> 0.010m X; 5mm -> -0.005m Z in paper coordinates
        #expect(abs(result.translationOffset.x - 0.010) < 0.001)
        #expect(abs(result.translationOffset.z - (-0.005)) < 0.001)
    }

    // MARK: - 4. Compact Course Codec Round-Trip & Deep Link

    @Test func testCompactCourseCodecRoundTrip() throws {
        let codec = CompactCourseCodec()

        let originalCourse = Course(
            title: "Test Tactical Course",
            authorName: "Tester",
            paperOrientation: .landscape,
            paperFormat: .letter,
            qrSizeMm: 100.0,
            cornerSegments: QRCorner.allCases.map { CornerLineSegment.identity(for: $0) },
            targets: [
                SphericalTarget(position: SIMD3<Float>(0.25, 0.50, -1.25), radius: 0.15, colorHex: "#00FFCC", pointValue: 25, label: "Alpha"),
                SphericalTarget(position: SIMD3<Float>(-0.50, 0.80, -2.00), radius: 0.10, colorHex: "#FF0055", pointValue: 50, label: "Beta")
            ]
        )

        // 1. Binary / Base64 encoding
        let base64 = codec.encodeToBase64(course: originalCourse)
        #expect(!base64.isEmpty)
        #expect(base64.count < 300) // Ultra compact!

        // 2. Decode back
        let decodedCourse = try codec.decodeFromBase64(base64)
        #expect(decodedCourse.title == originalCourse.title)
        #expect(decodedCourse.paperOrientation == .landscape)
        #expect(decodedCourse.isIdentityTransform)
        #expect(decodedCourse.targets.count == 2)
        #expect(abs(decodedCourse.targets[0].position.x - 0.25) < 0.005)
        #expect(abs(decodedCourse.targets[0].radius - 0.15) < 0.02)
        #expect(decodedCourse.targets[0].pointValue == 25)

        // 3. Deep link encoding and decoding
        let deepLink = codec.makeDeepLink(for: originalCourse)
        #expect(deepLink.scheme == "sillybells")
        #expect(deepLink.host == "course")

        let fromLink = try codec.decodeFromDeepLink(url: deepLink)
        #expect(fromLink.targets.count == originalCourse.targets.count)
    }

    // MARK: - 5. PDF Sheet Rendering (Portrait & Landscape)

    @Test func testPDFSheetRendering() {
        let renderer = PrintableSheetRenderer()

        // Portrait
        let portraitCourse = Course(
            title: "Portrait Sheet",
            paperOrientation: .portrait,
            paperFormat: .letter
        )
        let portraitPDF = renderer.renderPDF(for: portraitCourse, qrPayload: "sillybells://course?v=2&data=sample")
        #expect(!portraitPDF.isEmpty)
        let portraitHeader = String(data: portraitPDF.prefix(5), encoding: .ascii)
        #expect(portraitHeader == "%PDF-")

        // Landscape
        let landscapeCourse = Course(
            title: "Landscape Sheet",
            paperOrientation: .landscape,
            paperFormat: .a4
        )
        let landscapePDF = renderer.renderPDF(for: landscapeCourse, qrPayload: "sillybells://course?v=2&data=sample")
        #expect(!landscapePDF.isEmpty)
        let landscapeHeader = String(data: landscapePDF.prefix(5), encoding: .ascii)
        #expect(landscapeHeader == "%PDF-")
    }

    // MARK: - 6. Device Physical Profile & Tangent Transform

    @Test func testDevicePhysicalProfileTangentTransform() {
        let profile = DevicePhysicalProfile.iPhoneStandard
        let target = SphericalTarget(
            position: SIMD3<Float>(0.0, 1.5, -2.0),
            radius: 0.10
        )

        let transform = profile.tangentTransform(for: target)

        // Target center Y is 1.5m, radius is 0.10m
        // Sphere bottom is at Y = 1.5 - 0.10 = 1.40m
        // Device top edge is at Y = 1.40m
        // Device center is at Y = 1.40 - (profile.height / 2.0)
        let expectedCenterY = 1.40 - (profile.height / 2.0)
        let actualCenterY = transform.columns.3.y

        #expect(abs(actualCenterY - expectedCenterY) < 0.001)
        #expect(abs(transform.columns.3.x - target.position.x) < 0.001)
        #expect(abs(transform.columns.3.z - target.position.z) < 0.001)
    }

    // MARK: - 7. Local Course Store (100% Serverless)

    @Test func testLocalCourseStore() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("TestStore_\(UUID().uuidString)")
        let store = LocalCourseStore(customDirectory: tempDir)

        let course = Course(
            title: "Local Offline Course",
            authorName: "Serverless Player",
            targets: [
                SphericalTarget(position: SIMD3<Float>(0.0, 1.0, -1.0), radius: 0.12, colorHex: "#39FF14", pointValue: 100)
            ]
        )

        // Save
        try store.saveCourse(course)

        // Load
        let loaded = store.loadAllCourses()
        #expect(loaded.contains(where: { $0.id == course.id }))

        // Delete
        try store.deleteCourse(id: course.id)
        let afterDelete = store.loadAllCourses()
        #expect(!afterDelete.contains(where: { $0.id == course.id }))

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - 8. Interactive Point Snap & Geometry

    @Test func testInteractivePointSnapToIdentity() {
        let engine = CornerLineCalibrationEngine()

        // 1. Verify corner positions for 100mm QR
        let corners = CornerLineCalibrationEngine.qrCorners(qrSizeMm: 100.0)
        #expect(corners[.topLeft] == SIMD2<Float>(-50.0, 50.0))
        #expect(corners[.topRight] == SIMD2<Float>(50.0, 50.0))
        #expect(corners[.bottomRight] == SIMD2<Float>(50.0, -50.0))
        #expect(corners[.bottomLeft] == SIMD2<Float>(-50.0, -50.0))

        // 2. Adjust point very close to corner (< 2mm snap tolerance) -> snaps to .zero (identity)
        // Center is (200, 200) px, radius is 100 px. qrSizeMm = 100mm (0.5 mm/px).
        // TL corner is at screen (100, 100).
        // Touch near (99, 101) px gives 0.7mm offset -> snaps to .zero!
        let nearCornerTouch = SIMD2<Float>(99.0, 101.0)
        let offset = engine.adjustCornerPoint(
            screenPoint: nearCornerTouch,
            corner: .topLeft,
            qrCenterScreen: SIMD2<Float>(200.0, 200.0),
            qrScreenRadius: 100.0,
            qrSizeMm: 100.0
        )
        #expect(offset == .zero) // Snapped to exact 0mm identity!
    }

    // MARK: - 9. Course Orientation Serialization & IsIdentity Helper

    @Test func testCourseOrientationAndIdentityHelper() throws {
        let codec = CompactCourseCodec()

        var course = Course(
            title: "Portrait Identity Course",
            paperOrientation: .portrait,
            paperFormat: .a4,
            targets: [SphericalTarget(position: SIMD3<Float>(0, 0, -1), radius: 0.1)]
        )

        #expect(course.isIdentityTransform)

        let encoded = codec.encodeToBase64(course: course)
        let decoded = try codec.decodeFromBase64(encoded)

        #expect(decoded.paperOrientation == .portrait)
        #expect(decoded.paperFormat == .a4)
        #expect(decoded.isIdentityTransform)

        // Modify a corner line to non-identity
        course.cornerSegments[0].offsetMm = SIMD2<Float>(15.0, -10.0)
        #expect(!course.isIdentityTransform)

        let encodedNonIdentity = codec.encodeToBase64(course: course)
        let decodedNonIdentity = try codec.decodeFromBase64(encodedNonIdentity)
        #expect(!decodedNonIdentity.isIdentityTransform)
        #expect(decodedNonIdentity.cornerSegments[0].lengthMm > 10.0)
    }
}
