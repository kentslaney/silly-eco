import SwiftUI
import TargetCore
#if canImport(PDFKit)
import PDFKit
#endif

public struct PrintSheetModalView: View {

    public let course: Course
    @Environment(\.dismiss) private var dismiss

    @State private var pdfData: Data?

    public init(course: Course) {
        self.course = course
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let data = pdfData {
                    #if canImport(PDFKit)
                    PDFKitRepresentedView(data: data)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 6)
                        .padding()
                    #else
                    Text("PDF Ready (\(data.count) bytes)")
                    #endif
                } else {
                    ProgressView("Generating Precision PDF Sheet...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack(spacing: 20) {
                    if let data = pdfData {
                        ShareLink(
                            item: data,
                            preview: SharePreview("CourseSheet_\(course.title).pdf")
                        ) {
                            Label("Export PDF", systemImage: "square.and.arrow.up")
                                .frame(minWidth: 140)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("Printable Fiducial Sheet")
            .onAppear {
                generatePDF()
            }
        }
    }

    private func generatePDF() {
        let codec = CompactCourseCodec()
        let payload = codec.makeDeepLink(for: course).absoluteString
        let renderer = PrintableSheetRenderer()
        self.pdfData = renderer.renderPDF(for: course, qrPayload: payload)
    }
}

#if canImport(PDFKit)
#if canImport(UIKit)
import UIKit

public struct PDFKitRepresentedView: UIViewRepresentable {
    public let data: Data

    public func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(data: data)
        pdfView.autoScales = true
        return pdfView
    }

    public func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(data: data)
    }
}
#elseif canImport(AppKit)
import AppKit

public struct PDFKitRepresentedView: NSViewRepresentable {
    public let data: Data

    public func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(data: data)
        pdfView.autoScales = true
        return pdfView
    }

    public func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(data: data)
    }
}
#endif
#endif
