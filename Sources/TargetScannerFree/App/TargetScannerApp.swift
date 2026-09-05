import SwiftUI
import TargetCore

@main
public struct TargetScannerApp: App {

    @State private var isShowingScanner = false
    @State private var selectedCourse: Course?
    @State private var previewCalibration: CornerLineCalibrationResult = .identity

    public init() {}

    public var body: some Scene {
        WindowGroup {
            NavigationStack {
                LocalCourseLibraryView(
                    onSelectCourse: { course in
                        self.selectedCourse = course
                        self.previewCalibration = .identity
                    },
                    onScanNewSheet: {
                        self.isShowingScanner = true
                    }
                )
                .sheet(isPresented: $isShowingScanner) {
                    ARScannerView()
                }
                .sheet(item: $selectedCourse) { course in
                    NavigationStack {
                        VStack {
                            ARRealityPreviewView(
                                course: course,
                                calibration: previewCalibration
                            ) {
                                let codec = CompactCourseCodec()
                                let deepLink = codec.makeDeepLink(for: course)
                                #if canImport(UIKit)
                                UIApplication.shared.open(deepLink)
                                #endif
                            }

                            OpenConnectedAppBanner(course: course)
                                .padding(.bottom, 16)
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    selectedCourse = nil
                                }
                            }
                        }
                    }
                }
                .onOpenURL { url in
                    // Handle imported courses or deep links
                    let codec = CompactCourseCodec()
                    if let course = try? codec.decodeFromDeepLink(url: url) {
                        try? LocalCourseStore.shared.saveCourse(course)
                        self.selectedCourse = course
                    }
                }
            }
        }
    }
}
