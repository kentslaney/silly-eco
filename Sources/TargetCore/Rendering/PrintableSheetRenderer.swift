import Foundation
import CoreGraphics
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(CoreImage)
import CoreImage
#endif

public final class PrintableSheetRenderer: Sendable {

    public init() {}

    /// Renders a complete course calibration sheet into PDF data.
    /// Supports both Portrait and Landscape paper orientations.
    /// - Parameters:
    ///   - course: The course containing paper orientation, format, and targets.
    ///   - qrPayload: The serialized string payload to render into the central QR code.
    /// - Returns: PDF `Data` ready for AirPrint, saving to disk, or sharing.
    public func renderPDF(for course: Course, qrPayload: String) -> Data {
        let (widthMm, heightMm) = course.paperFormat.dimensionsMm(for: course.paperOrientation)

        // 72 points per inch; 1 inch = 25.4 mm
        let mmToPoints: CGFloat = 72.0 / 25.4
        let pageWidth = CGFloat(widthMm) * mmToPoints
        let pageHeight = CGFloat(heightMm) * mmToPoints

        let pdfData = NSMutableData()
        let consumer = CGDataConsumer(data: pdfData as CFMutableData)!

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        context.beginPage(mediaBox: &mediaBox)

        // Draw background
        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(mediaBox)

        let centerX = pageWidth / 2.0
        let centerY = pageHeight / 2.0

        // 1. Draw Title and Course Header
        drawHeader(
            context: context,
            course: course,
            pageWidth: pageWidth,
            pageHeight: pageHeight
        )

        // 2. Draw Central QR Code
        let qrSizePoints = CGFloat(course.qrSizeMm) * mmToPoints
        let qrRect = CGRect(
            x: centerX - (qrSizePoints / 2.0),
            y: centerY - (qrSizePoints / 2.0),
            width: qrSizePoints,
            height: qrSizePoints
        )
        drawQRCode(context: context, payload: qrPayload, in: qrRect)

        // 3. Draw 4 Corner Calibration Line Tracks
        drawCornerGuides(
            context: context,
            qrRect: qrRect,
            mmToPoints: mmToPoints
        )

        // 4. Draw Outer Margin Metric Coordinate Guides
        drawMarginCoordinateRulers(
            context: context,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            mmToPoints: mmToPoints,
            orientation: course.paperOrientation
        )

        // 5. Draw 50mm Physical Verification Bar & Instructions
        drawCalibrationBarAndNotes(
            context: context,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            mmToPoints: mmToPoints
        )

        context.endPage()
        context.closePDF()

        return pdfData as Data
    }

    // MARK: - Header

    private func drawHeader(
        context: CGContext,
        course: Course,
        pageWidth: CGFloat,
        pageHeight: CGFloat
    ) {
        context.saveGState()

        // Border rectangle
        context.setStrokeColor(CGColor(gray: 0.8, alpha: 1.0))
        context.setLineWidth(1.0)
        context.stroke(CGRect(x: 20, y: 20, width: pageWidth - 40, height: pageHeight - 40))

        context.restoreGState()
    }

    // MARK: - Central QR Code

    private func drawQRCode(context: CGContext, payload: String, in rect: CGRect) {
        context.saveGState()

        #if canImport(CoreImage)
        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            let data = payload.data(using: .utf8)
            filter.setValue(data, forKey: "inputMessage")
            filter.setValue("Q", forKey: "inputCorrectionLevel")

            if let outputImage = filter.outputImage {
                let ciContext = CIContext()
                let extent = outputImage.extent
                let scaleX = rect.width / extent.width
                let scaleY = rect.height / extent.height
                let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

                if let cgImage = ciContext.createCGImage(scaledImage, from: scaledImage.extent) {
                    context.draw(cgImage, in: rect)
                    // QR Boundary
                    context.setStrokeColor(CGColor(gray: 0.1, alpha: 1.0))
                    context.setLineWidth(1.5)
                    context.stroke(rect)
                    context.restoreGState()
                    return
                }
            }
        }
        #endif

        // Fallback placeholder square with border
        context.setFillColor(CGColor(gray: 0.05, alpha: 1.0))
        context.fill(rect)
        context.setStrokeColor(CGColor(gray: 0.8, alpha: 1.0))
        context.stroke(rect)

        context.restoreGState()
    }

    // MARK: - Corner Guides (Starting at 4 Corners of QR Code)

    private func drawCornerGuides(
        context: CGContext,
        qrRect: CGRect,
        mmToPoints: CGFloat
    ) {
        context.saveGState()

        let corners: [(CGPoint, CGPoint, String)] = [
            (CGPoint(x: qrRect.minX, y: qrRect.maxY), CGPoint(x: -1, y: 1), "TL"),
            (CGPoint(x: qrRect.maxX, y: qrRect.maxY), CGPoint(x: 1, y: 1), "TR"),
            (CGPoint(x: qrRect.maxX, y: qrRect.minY), CGPoint(x: 1, y: -1), "BR"),
            (CGPoint(x: qrRect.minX, y: qrRect.minY), CGPoint(x: -1, y: -1), "BL")
        ]

        let guideLengthPoints = 60.0 * mmToPoints // 60mm track
        let diagUnit = 1.0 / sqrt(2.0)

        for (base, dir, _) in corners {
            // Draw crosshair at the exact QR corner
            context.setStrokeColor(CGColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1.0)) // Red crosshair
            context.setLineWidth(1.5)

            let chSize: CGFloat = 6.0
            context.move(to: CGPoint(x: base.x - chSize, y: base.y))
            context.addLine(to: CGPoint(x: base.x + chSize, y: base.y))
            context.move(to: CGPoint(x: base.x, y: base.y - chSize))
            context.addLine(to: CGPoint(x: base.x, y: base.y + chSize))
            context.strokePath()

            // Draw dashed track line radiating outward at 45 degrees
            context.setStrokeColor(CGColor(gray: 0.5, alpha: 1.0))
            context.setLineWidth(0.75)
            context.setLineDash(phase: 0, lengths: [4.0, 3.0])

            let endPoint = CGPoint(
                x: base.x + (dir.x * diagUnit * guideLengthPoints),
                y: base.y + (dir.y * diagUnit * guideLengthPoints)
            )

            context.move(to: base)
            context.addLine(to: endPoint)
            context.strokePath()

            // Draw millimeter tick marks along the diagonal track
            context.setLineDash(phase: 0, lengths: [])
            context.setStrokeColor(CGColor(gray: 0.3, alpha: 1.0))

            for mm in stride(from: 10, through: 50, by: 10) {
                let dist = CGFloat(mm) * mmToPoints
                let tickCenter = CGPoint(
                    x: base.x + (dir.x * diagUnit * dist),
                    y: base.y + (dir.y * diagUnit * dist)
                )
                // Perpendicular vector
                let perp = CGPoint(x: -dir.y * diagUnit * 3.0, y: dir.x * diagUnit * 3.0)
                context.move(to: CGPoint(x: tickCenter.x - perp.x, y: tickCenter.y - perp.y))
                context.addLine(to: CGPoint(x: tickCenter.x + perp.x, y: tickCenter.y + perp.y))
                context.strokePath()
            }
        }

        context.restoreGState()
    }

    // MARK: - Margin Coordinate Rulers

    private func drawMarginCoordinateRulers(
        context: CGContext,
        pageWidth: CGFloat,
        pageHeight: CGFloat,
        mmToPoints: CGFloat,
        orientation: PaperOrientation
    ) {
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0.4, alpha: 1.0))
        context.setLineWidth(0.5)

        let margin: CGFloat = 28.0

        // Bottom ruler
        context.move(to: CGPoint(x: margin, y: margin))
        context.addLine(to: CGPoint(x: pageWidth - margin, y: margin))
        context.strokePath()

        let totalMmX = Int((pageWidth - (margin * 2)) / mmToPoints)
        for mm in stride(from: 0, through: totalMmX, by: 5) {
            let x = margin + (CGFloat(mm) * mmToPoints)
            let tickHeight: CGFloat = (mm % 10 == 0) ? 6.0 : 3.0
            context.move(to: CGPoint(x: x, y: margin))
            context.addLine(to: CGPoint(x: x, y: margin + tickHeight))
            context.strokePath()
        }

        // Left ruler
        context.move(to: CGPoint(x: margin, y: margin))
        context.addLine(to: CGPoint(x: margin, y: pageHeight - margin))
        context.strokePath()

        let totalMmY = Int((pageHeight - (margin * 2)) / mmToPoints)
        for mm in stride(from: 0, through: totalMmY, by: 5) {
            let y = margin + (CGFloat(mm) * mmToPoints)
            let tickWidth: CGFloat = (mm % 10 == 0) ? 6.0 : 3.0
            context.move(to: CGPoint(x: margin, y: y))
            context.addLine(to: CGPoint(x: margin + tickWidth, y: y))
            context.strokePath()
        }

        context.restoreGState()
    }

    // MARK: - 50mm Calibration Bar

    private func drawCalibrationBarAndNotes(
        context: CGContext,
        pageWidth: CGFloat,
        pageHeight: CGFloat,
        mmToPoints: CGFloat
    ) {
        context.saveGState()

        let barLength = 50.0 * mmToPoints // 50 mm
        let startX = (pageWidth - barLength) / 2.0
        let barY: CGFloat = 45.0

        // Draw solid calibration bar
        context.setFillColor(CGColor(gray: 0.15, alpha: 1.0))
        context.fill(CGRect(x: startX, y: barY, width: barLength, height: 4.0))

        // End caps
        context.setStrokeColor(CGColor(gray: 0.15, alpha: 1.0))
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: startX, y: barY - 4.0))
        context.addLine(to: CGPoint(x: startX, y: barY + 8.0))
        context.move(to: CGPoint(x: startX + barLength, y: barY - 4.0))
        context.addLine(to: CGPoint(x: startX + barLength, y: barY + 8.0))
        context.strokePath()

        context.restoreGState()
    }
}
