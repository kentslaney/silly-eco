import SwiftUI
import TargetCore

/// 100% Serverless local course library.
/// Courses are stored locally on device and shared peer-to-peer via QR codes, AirDrop, or files.
public struct LocalCourseLibraryView: View {

    @State private var courses: [Course] = []
    @State private var selectedCourseForQR: Course?
    public var onSelectCourse: (Course) -> Void
    public var onScanNewSheet: () -> Void

    public init(
        onSelectCourse: @escaping (Course) -> Void,
        onScanNewSheet: @escaping () -> Void
    ) {
        self.onSelectCourse = onSelectCourse
        self.onScanNewSheet = onScanNewSheet
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onScanNewSheet) {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                                .foregroundColor(.cyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan Physical Reference Sheet")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Point camera at paper fiducial and pen lines")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section("Offline Saved Courses (Serverless)") {
                    if courses.isEmpty {
                        Text("No courses found. Scan a paper sheet or create one!")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(courses) { course in
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(course.title)
                                        .font(.headline)
                                    HStack(spacing: 8) {
                                        Text("\(course.targets.count) Targets")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.cyan.opacity(0.2)))
                                            .foregroundColor(.cyan)

                                        Text(course.paperOrientation.rawValue.capitalized)
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        if course.isIdentityTransform {
                                            Text("Identity")
                                                .font(.caption2)
                                                .foregroundColor(.yellow)
                                        }
                                    }
                                }

                                Spacer()

                                // Share QR code on-screen button
                                Button {
                                    selectedCourseForQR = course
                                } label: {
                                    Image(systemName: "qrcode")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectCourse(course)
                            }
                        }
                        .onDelete(perform: deleteCourses)
                    }
                }
            }
            .navigationTitle("TargetScanner Free")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onScanNewSheet) {
                        Image(systemName: "camera.viewfinder")
                    }
                }
            }
            .sheet(item: $selectedCourseForQR) { course in
                CourseQRCodeSheet(course: course)
            }
            .onAppear {
                loadCourses()
            }
        }
    }

    private func loadCourses() {
        courses = LocalCourseStore.shared.loadAllCourses()
    }

    private func deleteCourses(at offsets: IndexSet) {
        for idx in offsets {
            let course = courses[idx]
            try? LocalCourseStore.shared.deleteCourse(id: course.id)
        }
        courses.remove(atOffsets: offsets)
    }
}

// MARK: - On-Screen QR Code Sheet for Peer-to-Peer Sharing

struct CourseQRCodeSheet: View {
    let course: Course
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(course.title)
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Scan from another device with TargetScanner to load instantly without a server.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                let codec = CompactCourseCodec()
                let deepLink = codec.makeDeepLink(for: course).absoluteString

                #if canImport(CoreImage)
                #if canImport(UIKit)
                if let qrImage = generateQRCodeImage(from: deepLink) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                        .shadow(radius: 8)
                }
                #elseif canImport(AppKit)
                if let qrImage = generateQRCodeNSImage(from: deepLink) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                        .shadow(radius: 8)
                }
                #endif
                #endif

                ShareLink(item: deepLink) {
                    Label("Share Course Deep Link", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("Peer-to-Peer Share")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    #if canImport(CoreImage) && canImport(UIKit)
    private func generateQRCodeImage(from string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        if let cgImage = context.createCGImage(output.transformed(by: CGAffineTransform(scaleX: 10, y: 10)), from: output.extent.applying(CGAffineTransform(scaleX: 10, y: 10))) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
    #endif

    #if canImport(CoreImage) && canImport(AppKit)
    private func generateQRCodeNSImage(from string: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        if let cgImage = context.createCGImage(output.transformed(by: CGAffineTransform(scaleX: 10, y: 10)), from: output.extent.applying(CGAffineTransform(scaleX: 10, y: 10))) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        return nil
    }
    #endif
}
