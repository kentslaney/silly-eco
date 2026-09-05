import SwiftUI
import TargetCore
import simd
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Vision)
import Vision
#endif

public enum ScannerState: Equatable {
    case searchingForSheet
    case sheetDetected(Course)
    case interactivePointAdjustment(Course)
    case originLocked(Course, CornerLineCalibrationResult)
}

public struct ARScannerView: View {

    @State private var scannerState: ScannerState = .searchingForSheet
    @State private var currentSegments: [CornerLineSegment] = QRCorner.allCases.map { CornerLineSegment.identity(for: $0) }
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        ZStack {
            // Camera Background / Simulated Viewport
            Color.black.ignoresSafeArea()

            switch scannerState {
            case .searchingForSheet:
                searchingView

            case .sheetDetected(let course):
                sheetDetectedView(course: course)

            case .interactivePointAdjustment(let course):
                InteractivePointAdjustmentView(
                    segments: $currentSegments,
                    qrSizeMm: course.qrSizeMm
                ) { result in
                    scannerState = .originLocked(course, result)
                }

            case .originLocked(let course, let result):
                ARRealityPreviewView(
                    course: course,
                    calibration: result
                ) {
                    // Open in Silly Bells
                    let codec = CompactCourseCodec()
                    let deepLink = codec.makeDeepLink(for: course)
                    #if canImport(UIKit)
                    UIApplication.shared.open(deepLink)
                    #endif
                }
            }

            // Close button in top-trailing corner
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }

    // MARK: - Subviews

    private var searchingView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 3, dash: [16, 8]))
                    .frame(width: 260, height: 260)

                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 72))
                    .foregroundColor(.cyan.opacity(0.7))
            }

            VStack(spacing: 8) {
                Text("Align Camera with Paper Fiducial")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Keep the QR code and 4 corner pen lines in frame")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            // Simulator Demo / Quick Load Button
            Button {
                simulateDetectedCourse()
            } label: {
                Label("Simulate Fiducial Sheet Scan", systemImage: "sparkles")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .padding(.bottom, 40)
        }
    }

    private func sheetDetectedView(course: Course) -> some View {
        VStack(spacing: 16) {
            Spacer()

            VStack(spacing: 12) {
                Text("Course Sheet Detected!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text(course.title)
                    .font(.headline)
                    .foregroundColor(.cyan)

                Text("\(course.targets.count) Targets • \(course.paperOrientation.rawValue.capitalized)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))

                HStack(spacing: 16) {
                    Button {
                        // Accept standard identity calibration immediately (0 length)
                        currentSegments = QRCorner.allCases.map { CornerLineSegment.identity(for: $0) }
                        scannerState = .originLocked(course, .identity)
                    } label: {
                        Text("Use Identity (0mm)")
                            .font(.subheadline)
                            .frame(minWidth: 120, minHeight: 38)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button {
                        // Enter manual interactive point adjustment
                        scannerState = .interactivePointAdjustment(course)
                    } label: {
                        Text("Adjust Pen Points")
                            .font(.subheadline)
                            .frame(minWidth: 120, minHeight: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                }
                .padding(.top, 8)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.85)))
            .padding(.horizontal)
            .padding(.bottom, 50)
        }
    }

    private func simulateDetectedCourse() {
        let sample = LocalCourseStore.starterCourses[0]
        self.currentSegments = sample.cornerSegments
        self.scannerState = .sheetDetected(sample)
    }
}
