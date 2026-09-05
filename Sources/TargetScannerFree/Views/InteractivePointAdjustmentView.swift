import SwiftUI
import TargetCore
import simd

/// Interactive touch overlay allowing the user to manually reposition detected
/// corner line endpoints on top of the camera feed with a magnified loupe.
/// Snaps to 0-length at the QR corner for standard identity calibration.
public struct InteractivePointAdjustmentView: View {

    @Binding public var segments: [CornerLineSegment]
    public let qrSizeMm: Float
    public var onLockOrigin: (CornerLineCalibrationResult) -> Void

    @State private var activeCorner: QRCorner?
    @State private var calibrationResult: CornerLineCalibrationResult = .identity
    private let engine = CornerLineCalibrationEngine()

    public init(
        segments: Binding<[CornerLineSegment]>,
        qrSizeMm: Float = 100.0,
        onLockOrigin: @escaping (CornerLineCalibrationResult) -> Void
    ) {
        self._segments = segments
        self.qrSizeMm = qrSizeMm
        self.onLockOrigin = onLockOrigin
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed camera overlay
                Color.black.opacity(0.15)
                    .allowsHitTesting(false)

                // Central QR Boundary Box Indicator
                let qrBoxSize = min(geometry.size.width, geometry.size.height) * 0.45
                let center = CGPoint(x: geometry.size.width / 2.0, y: geometry.size.height / 2.0)
                let qrRect = CGRect(
                    x: center.x - (qrBoxSize / 2.0),
                    y: center.y - (qrBoxSize / 2.0),
                    width: qrBoxSize,
                    height: qrBoxSize
                )

                Rectangle()
                    .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .frame(width: qrBoxSize, height: qrBoxSize)
                    .position(center)

                // Draw the 4 Corner Points and draggable handles
                ForEach(QRCorner.allCases, id: \.self) { corner in
                    let cornerBase = cornerPosition(for: corner, in: qrRect)
                    let currentEndpoint = endpointPosition(for: corner, base: cornerBase, qrBoxSize: qrBoxSize)

                    // Line segment connecting QR corner to endpoint
                    Path { path in
                        path.move(to: cornerBase)
                        path.addLine(to: currentEndpoint)
                    }
                    .stroke(Color.cyan, lineWidth: 3)

                    // Base Corner Crosshair
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .position(cornerBase)

                    // Draggable Endpoint Handle with circular ring
                    ZStack {
                        Circle()
                            .stroke(Color.cyan, lineWidth: 2)
                            .background(Circle().fill(Color.cyan.opacity(0.3)))
                            .frame(width: 36, height: 36)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                    }
                    .position(currentEndpoint)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                activeCorner = corner
                                updateCornerOffset(
                                    corner: corner,
                                    touchPoint: value.location,
                                    basePoint: cornerBase,
                                    qrBoxSize: qrBoxSize
                                )
                            }
                            .onEnded { _ in
                                activeCorner = nil
                            }
                    )
                }

                // Magnified Loupe when dragging a point
                if let corner = activeCorner {
                    let base = cornerPosition(for: corner, in: qrRect)
                    let pt = endpointPosition(for: corner, base: base, qrBoxSize: qrBoxSize)
                    LoupeView(point: pt, cornerName: corner.rawValue.capitalized)
                        .position(x: min(max(pt.x, 80), geometry.size.width - 80), y: max(60, pt.y - 70))
                }

                // Top Metrics & Calibration HUD Card
                VStack {
                    calibrationHUDCard
                        .padding(.top, 44)
                        .padding(.horizontal)

                    Spacer()

                    // Bottom Action Controls
                    HStack(spacing: 20) {
                        Button {
                            // Reset all to 0-length Identity
                            segments = QRCorner.allCases.map { CornerLineSegment.identity(for: $0) }
                            recalculate()
                        } label: {
                            Label("Reset Identity (0 mm)", systemImage: "arrow.counterclockwise")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)

                        Button {
                            onLockOrigin(calibrationResult)
                        } label: {
                            Label("Lock Origin", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .frame(minWidth: 140, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    .padding(.bottom, 36)
                }
            }
        }
        .onAppear {
            recalculate()
        }
    }

    // MARK: - HUD Card

    private var calibrationHUDCard: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: calibrationResult.isIdentity ? "sparkles" : "slider.horizontal.3")
                    .foregroundColor(calibrationResult.isIdentity ? .yellow : .cyan)
                Text(calibrationResult.isIdentity ? "Identity Calibration (0 Length)" : "Corrected Calibration")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("Scale: \(String(format: "%.2fx", calibrationResult.scaleFactor))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.cyan.opacity(0.3)))
                    .foregroundColor(.cyan)
            }

            HStack {
                Text("Shift Residual: \(String(format: "%.1f mm", calibrationResult.residualMm))")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("Drag handles to align with pen marks")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.75)))
    }

    // MARK: - Helpers

    private func cornerPosition(for corner: QRCorner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        }
    }

    private func endpointPosition(for corner: QRCorner, base: CGPoint, qrBoxSize: CGFloat) -> CGPoint {
        let seg = segments.first(where: { $0.corner == corner })
        let offsetMm = seg?.offsetMm ?? .zero
        let pixelsPerMm = qrBoxSize / CGFloat(qrSizeMm)

        // Screen space: +X right, +Y down (paper space has +Y up)
        return CGPoint(
            x: base.x + CGFloat(offsetMm.x) * pixelsPerMm,
            y: base.y - CGFloat(offsetMm.y) * pixelsPerMm
        )
    }

    private func updateCornerOffset(
        corner: QRCorner,
        touchPoint: CGPoint,
        basePoint: CGPoint,
        qrBoxSize: CGFloat
    ) {
        let pixelsPerMm = qrBoxSize / CGFloat(qrSizeMm)
        let dx = Float((touchPoint.x - basePoint.x) / pixelsPerMm)
        let dy = Float(-(touchPoint.y - basePoint.y) / pixelsPerMm)

        var newOffset = SIMD2<Float>(dx, dy)
        // Snap to corner if within 2mm (Identity)
        if simd_length(newOffset) < 2.0 {
            newOffset = .zero
        }

        if let idx = segments.firstIndex(where: { $0.corner == corner }) {
            segments[idx].offsetMm = newOffset
        } else {
            segments.append(CornerLineSegment(corner: corner, offsetMm: newOffset))
        }

        recalculate()
    }

    private func recalculate() {
        calibrationResult = engine.solve(segments: segments, qrSizeMm: qrSizeMm)
    }
}

// MARK: - Loupe View

struct LoupeView: View {
    let point: CGPoint
    let cornerName: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 60, height: 60)
                    .overlay(Circle().stroke(Color.cyan, lineWidth: 2))

                // Crosshair reticle
                Path { p in
                    p.move(to: CGPoint(x: 10, y: 30))
                    p.addLine(to: CGPoint(x: 50, y: 30))
                    p.move(to: CGPoint(x: 30, y: 10))
                    p.addLine(to: CGPoint(x: 30, y: 50))
                }
                .stroke(Color.red, lineWidth: 1.5)
            }
            Text(cornerName)
                .font(.caption2)
                .foregroundColor(.white)
        }
    }
}
