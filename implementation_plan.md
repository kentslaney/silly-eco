# Implementation Plan - AVP Spatial Target Studio, Error-Correcting QR Origin & "Silly Bells" Connected Ecosystem

Build an end-to-end spatial computing ecosystem featuring:
1. **Apple Vision Pro (AVP) App ("TargetStudio AVP")**: Spatial authoring tool to place and configure spherical targets in physical space, calibrate a reference origin, and generate/print a precision paper QR code.
2. **Precision Paper QR Code with Corner Line Segments**: Printable fiducial sheet (PDF/AirPrint) with a central course QR code and 4 calibrated straight line segments extending outward from its corners to eliminate origin tilt and position drift.
3. **Free Scanner & Preview App ("TargetScanner Free" - iOS & visionOS, with PWA roadmap)**: AR scanner that traces the corner line segments AR-style to compute an error-corrected spatial origin, renders placed spherical targets in AR, previews others' courses, and bridges directly to the connected $1 iOS app **"Silly Bells"**.
4. **Connected $1 App ("Silly Bells" - iOS)**: The existing paid app opened via deep link (`sillybells://course?data=...`), loading the course data and calibrated origin for active gameplay.
5. **TargetCore Framework**: Shared Swift package containing course data models, corner-line tracing and error-correction geometry math, PDF printable sheet generator, and URL scheme serialization codecs.

---

## User Review Required

> [!IMPORTANT]
> **Connected App Name & Deep Link**:
> The connected $1 app is **"Silly Bells"** on iOS. The scanner app provides an action card ("Open in Silly Bells ($1)") that fires the deep link `sillybells://course?v=1&data=<payload>` with a fallback to the App Store product view if not installed.

> [!NOTE]
> **Long-Term PWA Evolution**:
> The free scanner is planned to eventually run as a cross-platform Progressive Web App (PWA) using WebXR / WebCam and WebAssembly. To ensure smooth future migration, all geometry, corner line tracing algorithms, and payload codecs in `TargetCore` are structured with platform-agnostic pure math/data representations that can directly map to TypeScript / WebAssembly.

---

## Git Commit Review Anchoring Specification

To establish an immutable audit trail linking code changes directly to this reviewed implementation plan, we propose using **Git Trailers** (RFC 822-style key-value metadata in commit message footers).

### Standard Commit Format with Review Anchors:

```text
<type>(<scope>): <short summary>

<detailed description of what was changed and why>

Review-Doc: implementation_plan.md
Review-Anchor: #component-1-targetcore-shared-multi-platform-swift-package
Reviewed-By: Kent Slaney <kent@slaney.org>
Review-Status: Approved
Approved-At: 2026-09-02T16:10:22-07:00
```

### Why this works well:
1. **Machine-Readable**: Git natively parses these via `git log --format="%(trailers)"` or `git interpret-trailers`.
2. **Line/Section Traceability**: `Review-Anchor` points to the exact Markdown section heading or line range in the plan that authorized the change.
3. **GitHub / IDE Integration**: Markdown anchors and file links render as clickable navigation targets in web interfaces and local IDEs.

---

## Proposed Architecture & Component Overview

```
+-----------------------------------------------------------------------------------+
|                                   TargetCore                                      |
|  - Course & SphericalTarget Models (3D coordinates, radius, colors, scores)       |
|  - PrintableSheetRenderer (PDFKit vector sheet with QR + 4 corner error lines)    |
|  - CornerLineTracer & ErrorCorrectionEngine (Vision line solver, PnP refinement)  |
|  - CoursePayloadCodec (Compact Base64 / URL Scheme serialization)                 |
|  - CommunityCourseStore (Preloaded community courses + local library)             |
+-----------------------------------------+-----------------------------------------+
                                          |
        +---------------------------------+---------------------------------+
        |                                 |                                 |
        v                                 v                                 v
+-----------------------+     +-----------------------+     +-----------------------+
|   TargetStudio AVP    |     |  TargetScanner Free   |     |      Silly Bells      |
|     (visionOS)        |     |   (iOS & visionOS)    |     |  (Connected $1 App)   |
| - ImmersiveSpace 3D   |     | - ARKit Camera Feed   |     | - Existing iOS App    |
|   target placement    |     | - AR Line Tracing HUD |     | - Deep Link Handler   |
| - Spatial transform   |     | - 3D Target Preview   |     |   (sillybells://)     |
|   manipulation        |     | - Community Browser   |     | - Loads course data & |
| - Physical Origin set |     | - "Open in Silly      |     |   calibrated origin   |
| - AirPrint/PDF export |     |    Bells ($1)" bridge |     | - Active gameplay     |
+-----------------------+     +-----------------------+     +-----------------------+
                                          |
                                          v (Long-term Roadmap)
                              +-----------------------+
                              |      Scanner PWA      |
                              |   (WebXR / WebGL)     |
                              +-----------------------+
```

---

## Proposed Changes

### Component 1: `TargetCore` (Shared Multi-Platform Swift Package)

A standalone Swift package compiling cleanly across iOS, visionOS, and macOS.

#### [NEW] `Package.swift`
- Configures `TargetCore` library target and unit test target `TargetCoreTests`.
- Platforms: `.iOS(.v18)`, `.visionOS(.v2)`, `.macOS(.v14)`.

#### [NEW] `Sources/TargetCore/Models/Course.swift`
- `SphericalTarget`: `id: UUID`, `position: SIMD3<Float>` (meters relative to QR origin), `radius: Float` (0.05m – 0.50m), `colorHex: String`, `pointValue: Int`, `label: String`, `hitSound: String`.
- `Course`: `id: UUID`, `title: String`, `creatorName: String`, `courseDescription: String`, `targets: [SphericalTarget]`, `markerConfig: OriginMarkerConfig`, `createdAt: Date`.
- `OriginMarkerConfig`: Physical sheet dimensions (QR code width: 100mm, corner line length: 60mm, corner line angle: 45°, line thickness: 3mm, unit: millimeters).

#### [NEW] `Sources/TargetCore/Geometry/CornerLineTracer.swift`
- Mathematical representation of the 4 corner calibration rays:
  - Top-Left: extends towards $(-x, +y)$
  - Top-Right: extends towards $(+x, +y)$
  - Bottom-Right: extends towards $(+x, -y)$
  - Bottom-Left: extends towards $(-x, -y)$
- Error metrics calculation: compares detected line vectors in screen space against theoretical projected line segments from the initial QR pose.
- Pose refinement: computes the rotation correction matrix $\Delta R$ and translation offset $\Delta t$ minimizing re-projection residuals across the 4 corner line segments.
- Modularized math designed for easy porting to WebGL / WebXR shaders and WebAssembly in the PWA.

#### [NEW] `Sources/TargetCore/Rendering/PrintableSheetRenderer.swift`
- Generates high-definition vector PDF and UIImage/CGImage for the calibration sheet:
  - High-contrast central QR code (generated via `CIFilter.qrCodeGenerator()`).
  - Precision straight line segments extending from the 4 corners at 45° with millimeter graduation marks and crosshair end-caps.
  - Coordinate system indicators: $+X$ (Right, Red arrow), $+Z$ (Down/Front, Blue arrow), $+Y$ (Upward Normal).
  - Physical dimension calibration bar ("Ensure this bar measures exactly 50 mm when printed").
  - Course metadata header: Course Name, Target Count, Creator, and Scan Instructions.

#### [NEW] `Sources/TargetCore/Serialization/CoursePayloadCodec.swift`
- Compact JSON + Gzip/Base64 serialization for encoding full course data into QR codes and URL schemes:
  - Deep link format: `sillybells://course?v=1&data=<base64_payload>`.
  - Also generates standard web fallback links.

#### [NEW] `Sources/TargetCore/Storage/CommunityCourseStore.swift`
- Preloaded directory of community target courses:
  - *Living Room Marksman* (5 tactical spheres around couch and desk).
  - *360° Reflex Orbit* (8 spheres encircling the origin at eye level).
  - *Vertical Tower Drill* (stacked spheres at varied elevations).
  - *Precision Mini-Targets* (compact close-range accuracy course).
- Methods for saving, editing, and loading user-created courses.

#### [NEW] `Tests/TargetCoreTests/TargetCoreTests.swift`
- Comprehensive unit tests verifying:
  - Model serialization and deserialization round-trip.
  - Payload compression and `sillybells://` URL scheme parsing.
  - Geometry math and corner ray projection calculations.
  - PDF document generation and dimensions.

---

### Component 2: `TargetStudioAVP` (Apple Vision Pro - visionOS App)

#### [NEW] `Sources/TargetStudioAVP/App/TargetStudioApp.swift`
- SwiftUI `App` lifecycle supporting both a 2D management Window and an `ImmersiveSpace` for RealityKit spatial target authoring.

#### [NEW] `Sources/TargetStudioAVP/Views/StudioDashboardView.swift`
- 2D Window UI: Course selector, target summary table, "Enter Spatial Studio" button, and "Print Reference Sheet" button.

#### [NEW] `Sources/TargetStudioAVP/Views/SpatialTargetAuthoringView.swift`
- `RealityView` implementation in `ImmersiveSpace`:
  - Visual Origin Entity: Rendered at $(0, 0, 0)$ showing physical QR paper preview with corner line segments and 3D axis arrows.
  - Interactive Target Entities: Spheres with glowing neon materials and floating billboard distance tags.
  - Gesture handling: Spatial Drag Gesture to move spheres in 3D, Pinch to select, Double-tap to duplicate/delete.
  - Live measurement lines connecting origin to each target with distance labels (e.g. "2.45 m @ +32°").

#### [NEW] `Sources/TargetStudioAVP/Views/TargetInspectorPalette.swift`
- Floating spatial palette:
  - Adjust selected sphere radius (slider from 5cm to 50cm).
  - Color picker with neon presets (Neon Red, Cyber Cyan, Lime, Electric Yellow, Plasma Magenta).
  - Point value input (10 to 100 pts).
  - "Add Sphere at Gaze" quick-action button.

#### [NEW] `Sources/TargetStudioAVP/Views/PrintSheetModalView.swift`
- Printable sheet preview modal with AirPrint (`UIPrintInteractionController`) and PDF export (`ShareLink`).

---

### Component 3: `TargetScannerFree` (Universal iOS & visionOS Companion App)

#### [NEW] `Sources/TargetScannerFree/App/TargetScannerApp.swift`
- App entry point for the free scanner and community course viewer.

#### [NEW] `Sources/TargetScannerFree/Views/ARScannerView.swift`
- Live camera viewport with real-time Vision barcode detection (`VNDetectBarcodesRequest`) and line segment detection (`VNDetectLineSegmentsRequest`).
- AR-style corner line tracing HUD:
  - Visual laser rays tracing along the 4 corner line segments in real-time.
  - Calibration state indicator: "Locating Marker..." $\to$ "Tracing 4 Corner Lines..." $\to$ "Origin Locked (±0.1° error)".
  - Haptic feedback when lock is achieved.

#### [NEW] `Sources/TargetScannerFree/Views/ARRealityPreviewView.swift`
- RealityKit scene anchored to the calibrated paper origin:
  - Renders all 3D spherical targets in their exact physical positions in the user's room.
  - Pulse animations and distance badges above each sphere.
  - Target list panel showing sphere distances from the scanner's current position.

#### [NEW] `Sources/TargetScannerFree/Views/CommunityCourseBrowserView.swift`
- Community preview directory:
  - Browse others' setup courses with difficulty tags, sphere count, and creator info.
  - 3D interactive thumbnail preview (interactive orbital view of the sphere layout).
  - "Project to My Origin" button to load any course onto the user's physical printed marker.

#### [NEW] `Sources/TargetScannerFree/Views/OpenConnectedAppBanner.swift`
- Native call-to-action banner on iOS:
  - "Play Course in Silly Bells ($1)"
  - Deep-link button: opens `sillybells://course?v=1&data=...`.
  - Fallback StoreKit modal: presents `SKStoreProductViewController` / simulated App Store modal showing "$0.99 - Silly Bells".
  - Share link button to copy or send the course launch URL.

---

### Component 4: Xcode Project & Build Configuration

#### [NEW] `TargetEco.xcodeproj` / Project Setup
- Configures multi-target Xcode project linking `TargetCore` to:
  - `TargetStudioAVP` (Targeting visionOS)
  - `TargetScannerFree` (Targeting iOS & visionOS)
- Includes camera usage descriptions (`NSCameraUsageDescription`), URL scheme configurations, and build settings.

---

## Verification Plan

### Automated Tests
- Run `swift test` on `TargetCoreTests`:
  ```bash
  swift test
  ```
  - Tests Course JSON and compact payload serialization/deserialization.
  - Tests `sillybells://` deep link encoding and URL parameter extraction.
  - Tests Corner line error-correction ray math and residual calculations.
  - Tests PDF printable sheet generation.

### Build Verification
- Compile and build `TargetCore` across platforms:
  ```bash
  swift build
  ```
- Build apps using `xcodebuild`:
  ```bash
  xcodebuild -scheme TargetScannerFree -destination "generic/platform=iOS Simulator" build
  xcodebuild -scheme TargetStudioAVP -destination "generic/platform=visionOS Simulator" build
  ```

### Manual & Interactive Verification
1. **AVP Target Studio**: Launch in visionOS Simulator to test sphere placement, spatial controls, and printable sheet preview.
2. **Printable Sheet**: Inspect generated PDF to verify crisp QR code, 4 corner line segments with mm graduations, and axis markers.
3. **Corner Line Tracing HUD**: Verify camera HUD visual feedback when simulating QR code with corner lines.
4. **Community Preview**: Browse preloaded courses, inspect 3D layout, and verify target metrics.
5. **Deep Link & "Silly Bells" Bridge**: Trigger "Open in Silly Bells ($1)" button, verify URL scheme payload transmission (`sillybells://course?data=...`), and verify fallback modal behavior.
