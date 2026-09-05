import SwiftUI
import TargetCore
#if canImport(StoreKit)
import StoreKit
#endif

/// Action banner bridging the free scanner to the connected $1 app "Silly Bells".
public struct OpenConnectedAppBanner: View {

    public let course: Course
    @State private var isShowingStoreFallback = false

    public init(course: Course) {
        self.course = course
    }

    public var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready for Active Play?")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Open course in Silly Bells with live audio scoring")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button {
                    openInSillyBells()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.badge.fill")
                        Text("Open ($1)")
                    }
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.12))
                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
        )
        .padding(.horizontal)
        .sheet(isPresented: $isShowingStoreFallback) {
            SillyBellsStoreView()
        }
    }

    private func openInSillyBells() {
        let codec = CompactCourseCodec()
        let deepLink = codec.makeDeepLink(for: course)

        #if canImport(UIKit)
        UIApplication.shared.open(deepLink, options: [:]) { success in
            if !success {
                // Not installed: present App Store product view
                isShowingStoreFallback = true
            }
        }
        #endif
    }
}

// MARK: - App Store Fallback Sheet

struct SillyBellsStoreView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "bell.and.waves.left.and.right.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.yellow)
                    .padding(.top, 40)

                VStack(spacing: 8) {
                    Text("Silly Bells")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("$0.99 on the App Store")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                Text("Silly Bells is the interactive spatial target game with reactive spatial audio, combo multipliers, and calibrated physical origin play.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 32)

                Spacer()

                Button {
                    // Open App Store product URL
                    if let appStoreURL = URL(string: "https://apps.apple.com/app/silly-bells/id123456789") {
                        #if canImport(UIKit)
                        UIApplication.shared.open(appStoreURL)
                        #endif
                    }
                } label: {
                    Text("View on App Store")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)

                Button("Dismiss") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
            .navigationTitle("Connected Game")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
