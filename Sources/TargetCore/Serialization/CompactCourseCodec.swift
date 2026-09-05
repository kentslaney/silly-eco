import Foundation
import simd

public enum CodecError: Error, Sendable {
    case invalidHeader
    case unsupportedVersion(UInt8)
    case corruptedPayload
    case bufferUnderflow
}

public final class CompactCourseCodec: Sendable {

    public static let currentVersion: UInt8 = 2

    public init() {}

    // MARK: - Binary Packing & Base64 URL Scheme

    /// Encodes a `Course` into a compact URL-safe Base64 string suitable for QR codes and deep links.
    public func encodeToBase64(course: Course) -> String {
        let binaryData = encodeToBinary(course: course)
        return binaryData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes a `Course` from a compact URL-safe Base64 string.
    public func decodeFromBase64(_ string: String) throws -> Course {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Re-pad with '=' if necessary
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64) else {
            throw CodecError.corruptedPayload
        }
        return try decodeFromBinary(data: data)
    }

    /// Creates a deep link URL for the connected Silly Bells app.
    public func makeDeepLink(for course: Course) -> URL {
        let base64 = encodeToBase64(course: course)
        var components = URLComponents()
        components.scheme = "sillybells"
        components.host = "course"
        components.queryItems = [
            URLQueryItem(name: "v", value: "\(Self.currentVersion)"),
            URLQueryItem(name: "data", value: base64)
        ]
        return components.url ?? URL(string: "sillybells://course?v=2&data=\(base64)")!
    }

    /// Parses a `Course` from a `sillybells://course?v=2&data=...` deep link.
    public func decodeFromDeepLink(url: URL) throws -> Course {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw CodecError.invalidHeader
        }
        guard let dataParam = queryItems.first(where: { $0.name == "data" })?.value else {
            throw CodecError.corruptedPayload
        }
        return try decodeFromBase64(dataParam)
    }

    // MARK: - Binary Serialization Format

    public func encodeToBinary(course: Course) -> Data {
        var data = Data()

        // 1. Version
        data.append(Self.currentVersion)

        // 2. Flags: bit 0: orientation, bit 1..2: format, bit 3: isIdentity
        var flags: UInt8 = 0
        if course.paperOrientation == .landscape {
            flags |= 0x01
        }
        switch course.paperFormat {
        case .letter:
            flags |= (0 << 1)
        case .a4:
            flags |= (1 << 1)
        case .custom:
            flags |= (2 << 1)
        }
        let isIdentity = course.isIdentityTransform
        if isIdentity {
            flags |= (1 << 3)
        }
        data.append(flags)

        // 3. QR Size in mm (clamped 20..255)
        data.append(UInt8(clamping: Int(course.qrSizeMm)))

        // 4. Target count
        data.append(UInt8(min(course.targets.count, 255)))

        // 5. Corner Line Segments (only if not identity)
        if !isIdentity {
            let cornerOrder: [QRCorner] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
            for corner in cornerOrder {
                let seg = course.cornerSegments.first(where: { $0.corner == corner })
                let dx = Int16(clamping: Int((seg?.offsetMm.x ?? 0.0) * 10.0))
                let dy = Int16(clamping: Int((seg?.offsetMm.y ?? 0.0) * 10.0))
                data.append(contentsOf: withUnsafeBytes(of: dx.littleEndian) { Array($0) })
                data.append(contentsOf: withUnsafeBytes(of: dy.littleEndian) { Array($0) })
            }
        }

        // 6. Targets: 9 bytes per target
        for target in course.targets {
            // Position in mm (-32768 to 32767 mm)
            let xMm = Int16(clamping: Int(target.position.x * 1000.0))
            let yMm = Int16(clamping: Int(target.position.y * 1000.0))
            let zMm = Int16(clamping: Int(target.position.z * 1000.0))
            data.append(contentsOf: withUnsafeBytes(of: xMm.littleEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: yMm.littleEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: zMm.littleEndian) { Array($0) })

            // Radius in cm (0.05m -> 5cm, clamped to 1..255)
            let radiusCm = UInt8(clamping: Int(target.radius * 100.0))
            data.append(radiusCm)

            // Color: simple index or fallback
            data.append(Self.colorToByte(target.colorHex))

            // Point value (clamped 0..255)
            data.append(UInt8(clamping: target.pointValue))
        }

        // 7. Title string
        let titleBytes = Array(course.title.utf8.prefix(64))
        data.append(UInt8(titleBytes.count))
        data.append(contentsOf: titleBytes)

        return data
    }

    public func decodeFromBinary(data: Data) throws -> Course {
        guard data.count >= 4 else {
            throw CodecError.bufferUnderflow
        }

        var offset = 0

        // 1. Version
        let version = data[offset]
        offset += 1
        guard version == Self.currentVersion else {
            throw CodecError.unsupportedVersion(version)
        }

        // 2. Flags
        let flags = data[offset]
        offset += 1
        let orientation: PaperOrientation = (flags & 0x01) != 0 ? .landscape : .portrait
        let formatVal = (flags >> 1) & 0x03
        let format: PaperFormat
        switch formatVal {
        case 0: format = .letter
        case 1: format = .a4
        default: format = .letter
        }
        let isIdentity = (flags & (1 << 3)) != 0

        // 3. QR Size
        let qrSizeMm = Float(data[offset])
        offset += 1

        // 4. Target count
        let targetCount = Int(data[offset])
        offset += 1

        // 5. Corner segments
        var segments: [CornerLineSegment] = []
        let cornerOrder: [QRCorner] = [.topLeft, .topRight, .bottomRight, .bottomLeft]

        if isIdentity {
            segments = cornerOrder.map { CornerLineSegment.identity(for: $0) }
        } else {
            guard data.count >= offset + (cornerOrder.count * 4) else {
                throw CodecError.bufferUnderflow
            }
            for corner in cornerOrder {
                let dxRaw = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
                offset += 2
                let dyRaw = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
                offset += 2

                let dx = Float(dxRaw) / 10.0
                let dy = Float(dyRaw) / 10.0
                segments.append(CornerLineSegment(corner: corner, offsetMm: SIMD2<Float>(dx, dy)))
            }
        }

        // 6. Targets
        var targets: [SphericalTarget] = []
        for i in 0..<targetCount {
            guard data.count >= offset + 9 else {
                throw CodecError.bufferUnderflow
            }
            let xMm = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
            offset += 2
            let yMm = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
            offset += 2
            let zMm = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
            offset += 2

            let radiusCm = data[offset]
            offset += 1
            let colorByte = data[offset]
            offset += 1
            let pointVal = data[offset]
            offset += 1

            let target = SphericalTarget(
                position: SIMD3<Float>(Float(xMm) / 1000.0, Float(yMm) / 1000.0, Float(zMm) / 1000.0),
                radius: Float(radiusCm) / 100.0,
                colorHex: Self.byteToColor(colorByte),
                pointValue: Int(pointVal),
                label: "Target \(i + 1)"
            )
            targets.append(target)
        }

        // 7. Title string
        var title = "Spatial Course"
        if data.count > offset {
            let titleLen = Int(data[offset])
            offset += 1
            if data.count >= offset + titleLen {
                let titleData = data.subdata(in: offset..<(offset + titleLen))
                if let decodedTitle = String(data: titleData, encoding: .utf8) {
                    title = decodedTitle
                }
            }
        }

        return Course(
            title: title,
            paperOrientation: orientation,
            paperFormat: format,
            qrSizeMm: qrSizeMm,
            cornerSegments: segments,
            targets: targets
        )
    }

    // MARK: - Color Palette Helpers

    private static let presetColors: [String] = [
        "#00FFCC", // Cyber Cyan
        "#FF0055", // Neon Magenta
        "#39FF14", // Lime Green
        "#FFFF00", // Electric Yellow
        "#FF6600", // Blaze Orange
        "#0077FF", // Deep Azure
        "#AA00FF", // Purple Neon
        "#FFFFFF"  // Pure White
    ]

    public static func colorToByte(_ hex: String) -> UInt8 {
        if let idx = presetColors.firstIndex(of: hex.uppercased()) {
            return UInt8(idx)
        }
        return 0 // default
    }

    public static func byteToColor(_ byte: UInt8) -> String {
        let idx = Int(byte)
        if idx < presetColors.count {
            return presetColors[idx]
        }
        return presetColors[0]
    }
}
