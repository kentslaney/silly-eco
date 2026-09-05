import SwiftUI
import TargetCore

public struct TargetInspectorPalette: View {

    @Binding public var course: Course
    @Binding public var selectedTargetID: UUID?
    public var onOpenPrintSheet: () -> Void

    public init(
        course: Binding<Course>,
        selectedTargetID: Binding<UUID?>,
        onOpenPrintSheet: @escaping () -> Void
    ) {
        self._course = course
        self._selectedTargetID = selectedTargetID
        self.onOpenPrintSheet = onOpenPrintSheet
    }

    private var selectedTargetIndex: Int? {
        guard let id = selectedTargetID else { return nil }
        return course.targets.firstIndex(where: { $0.id == id })
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(course.title)
                        .font(.headline)
                    Text("\(course.targets.count) Spheres • Hand-Held Anchors")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: onOpenPrintSheet) {
                    Label("Print Sheet", systemImage: "printer.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            // Paper Format & Orientation Controls
            HStack(spacing: 20) {
                Picker("Orientation", selection: $course.paperOrientation) {
                    Text("Portrait").tag(PaperOrientation.portrait)
                    Text("Landscape").tag(PaperOrientation.landscape)
                }
                .pickerStyle(.segmented)

                Picker("Format", selection: Binding(
                    get: { course.paperFormat == .letter ? 0 : 1 },
                    set: { course.paperFormat = $0 == 0 ? .letter : .a4 }
                )) {
                    Text("US Letter").tag(0)
                    Text("A4").tag(1)
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Selected Target Inspector
            if let idx = selectedTargetIndex {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Selected Sphere: \(course.targets[idx].label)")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    // Radius slider
                    HStack {
                        Text("Radius:")
                        Slider(
                            value: $course.targets[idx].radius,
                            in: 0.05...0.40,
                            step: 0.01
                        )
                        Text("\(Int(course.targets[idx].radius * 100)) cm")
                            .monospacedDigit()
                    }

                    // Point value
                    HStack {
                        Text("Score:")
                        Stepper("\(course.targets[idx].pointValue) pts", value: $course.targets[idx].pointValue, in: 10...100, step: 10)
                    }

                    // Delete button
                    Button(role: .destructive) {
                        course.targets.remove(at: idx)
                        selectedTargetID = course.targets.first?.id
                    } label: {
                        Label("Delete Sphere", systemImage: "trash")
                    }
                }
            } else {
                Text("Select a sphere in space to edit properties.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Quick Add Action
            Button {
                let newTarget = SphericalTarget(
                    position: SIMD3<Float>(0.0, 0.5, -1.2),
                    radius: 0.12,
                    colorHex: "#00FFCC",
                    pointValue: 25,
                    label: "Sphere \(course.targets.count + 1)"
                )
                course.targets.append(newTarget)
                selectedTargetID = newTarget.id
            } label: {
                Label("Add Sphere in Front", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 360)
    }
}
