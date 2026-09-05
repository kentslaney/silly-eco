import SwiftUI
import TargetCore

@main
public struct TargetStudioApp: App {

    @State private var course: Course = LocalCourseStore.starterCourses[0]
    @State private var isShowingPrintSheet = false
    @State private var selectedTargetID: UUID?

    public init() {}

    public var body: some Scene {
        WindowGroup(id: "DashboardWindow") {
            NavigationStack {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("TargetStudio AVP")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Spatial Target Authoring with Hand-Held Anchors")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)

                    Divider()

                    // Course Info Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(course.title)
                                .font(.title2)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(course.targets.count) Targets")
                                .font(.headline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                        }

                        Text("Orientation: \(course.paperOrientation.rawValue.capitalized) • Format: \(course.paperFormat == .letter ? "US Letter" : "A4")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("Calibration: 4 QR Corner Line Segments (0 Length = Identity)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.1)))
                    .padding(.horizontal)

                    Spacer()

                    // Action Buttons
                    HStack(spacing: 20) {
                        Button {
                            isShowingPrintSheet = true
                        } label: {
                            Label("Print Reference Sheet", systemImage: "printer.fill")
                                .frame(minWidth: 180, minHeight: 44)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            // In visionOS, open ImmersiveSpace("SpatialStudioSpace")
                        } label: {
                            Label("Enter Spatial Studio", systemImage: "cube.transparent")
                                .frame(minWidth: 180, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.bottom, 30)
                }
                .sheet(isPresented: $isShowingPrintSheet) {
                    PrintSheetModalView(course: course)
                }
            }
        }

        #if os(visionOS)
        ImmersiveSpace(id: "SpatialStudioSpace") {
            SpatialTargetAuthoringView(course: $course)
        }
        #endif
    }
}
