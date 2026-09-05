import Foundation

public final class LocalCourseStore: @unchecked Sendable {

    public static let shared = LocalCourseStore()

    private let fileManager = FileManager.default
    private let storageDirectory: URL

    public init(customDirectory: URL? = nil) {
        if let custom = customDirectory {
            self.storageDirectory = custom
        } else {
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            let documentsDirectory = paths.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.storageDirectory = documentsDirectory.appendingPathComponent("Courses", isDirectory: true)
        }

        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Save, Load, Delete

    public func saveCourse(_ course: Course) throws {
        let fileURL = storageDirectory.appendingPathComponent("\(course.id.uuidString).sillycourse")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(course)
        try data.write(to: fileURL, options: .atomic)
    }

    public func loadAllCourses() -> [Course] {
        guard let fileURLs = try? fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) else {
            return Self.starterCourses
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var loaded: [Course] = []
        for url in fileURLs where url.pathExtension == "sillycourse" {
            if let data = try? Data(contentsOf: url),
               let course = try? decoder.decode(Course.self, from: data) {
                loaded.append(course)
            }
        }

        if loaded.isEmpty {
            return Self.starterCourses
        }
        return loaded.sorted(by: { $0.createdAt > $1.createdAt })
    }

    public func deleteCourse(id: UUID) throws {
        let fileURL = storageDirectory.appendingPathComponent("\(id.uuidString).sillycourse")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    // MARK: - Import & Export

    public func exportCourseFile(for course: Course, to destinationURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(course)
        try data.write(to: destinationURL, options: .atomic)
    }

    public func importCourse(from sourceURL: URL) throws -> Course {
        let data = try Data(contentsOf: sourceURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let course = try decoder.decode(Course.self, from: data)
        try saveCourse(course)
        return course
    }

    // MARK: - Offline Starter Courses (Serverless)

    public static let starterCourses: [Course] = [
        Course(
            title: "Living Room Marksman",
            authorName: "Silly Bells Studio",
            courseDescription: "5 tactical spheres arranged at desk and eye level around your room.",
            paperOrientation: .portrait,
            paperFormat: .letter,
            qrSizeMm: 100.0,
            cornerSegments: QRCorner.allCases.map { CornerLineSegment.identity(for: $0) },
            targets: [
                SphericalTarget(position: SIMD3<Float>(0.0, 0.45, -1.2), radius: 0.12, colorHex: "#00FFCC", pointValue: 20, label: "Front Alpha"),
                SphericalTarget(position: SIMD3<Float>(-0.8, 0.60, -1.5), radius: 0.10, colorHex: "#FF0055", pointValue: 30, label: "Left Flank"),
                SphericalTarget(position: SIMD3<Float>(0.8, 0.60, -1.5), radius: 0.10, colorHex: "#39FF14", pointValue: 30, label: "Right Flank"),
                SphericalTarget(position: SIMD3<Float>(-0.4, 1.10, -2.0), radius: 0.14, colorHex: "#FFFF00", pointValue: 50, label: "High Left"),
                SphericalTarget(position: SIMD3<Float>(0.4, 1.10, -2.0), radius: 0.14, colorHex: "#FF6600", pointValue: 50, label: "High Right")
            ]
        ),
        Course(
            title: "360° Reflex Orbit",
            authorName: "Silly Bells Studio",
            courseDescription: "Full surround layout encircling the fiducial origin at eye level.",
            paperOrientation: .landscape,
            paperFormat: .letter,
            qrSizeMm: 100.0,
            cornerSegments: QRCorner.allCases.map { CornerLineSegment.identity(for: $0) },
            targets: [
                SphericalTarget(position: SIMD3<Float>(0.0, 0.5, -1.5), radius: 0.12, colorHex: "#00FFCC", pointValue: 25, label: "North"),
                SphericalTarget(position: SIMD3<Float>(1.5, 0.5, 0.0), radius: 0.12, colorHex: "#FF0055", pointValue: 25, label: "East"),
                SphericalTarget(position: SIMD3<Float>(0.0, 0.5, 1.5), radius: 0.12, colorHex: "#39FF14", pointValue: 25, label: "South"),
                SphericalTarget(position: SIMD3<Float>(-1.5, 0.5, 0.0), radius: 0.12, colorHex: "#FFFF00", pointValue: 25, label: "West")
            ]
        )
    ]
}
