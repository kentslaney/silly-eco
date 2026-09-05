# Implementation Plan - AVP Spatial Target Studio, Error-Correcting Pen-Drawn Fiducials & "Silly Bells" Serverless Ecosystem

Build an end-to-end spatial computing ecosystem featuring:
1. **Apple Vision Pro (AVP) App ("TargetStudio AVP")**: Spatial authoring tool to place and configure spherical targets in physical space, calibrate a reference origin, measure user hand dimensions to render targets held up by realistically scaled 3D hands in visionOS, and generate/print a precision fiducial sheet (portrait or landscape).
2. **Precision Paper Fiducial with Pen-Drawn Corner Line Segments**: Printable reference sheet (PDF/AirPrint) in portrait or landscape format featuring a central course QR code, printed coordinate guides/ruler ticks along the margins, and calibration line segments drawn with pen starting directly from the **4 corners of the QR code**. A line segment length of **0 represents the identity transformation**. Deviations in length and orientation encode paper displacement ($\Delta \mathbf{R}, \Delta \mathbf{t}$) and metric scale correction factor ($s$).
3. **Free Scanner & Calibration App ("TargetScanner Free" - iOS & visionOS)**: AR scanner that detects the paper QR code, printed coordinate guides, and pen-drawn corner line segments. Includes an **Interactive Point Adjustment UI** allowing the user to manually reposition detected points on screen, computes scale correction, renders targets held up by:
   - **Handheld AR (iOS)**: A rounded rectangle the physical size of the device rendered tangent to the spherical target oriented upwards on the device.
   - **Spatial visionOS**: 3D hands dynamically sized to the user's measured hand dimensions.
   - Bridges directly to the connected $1 iOS app **"Silly Bells"**.
4. **100% Serverless & Decentralized Sharing**: Zero server hosting. All course geometry, target configs, paper orientation, and scale corrections are fully self-contained in the printed QR code and deep links (`sillybells://course?v=2&data=...`), with local file storage and peer-to-peer AirDrop/iMessage export.
5. **Connected $1 App ("Silly Bells" - iOS)**: The existing paid app opened via deep link, loading course data and the error-corrected, scale-calibrated origin for active gameplay.
6. **TargetCore Framework**: Shared Swift package containing course data models, portrait/landscape coordinate geometry, pen-line corner alignment and scale-correction solvers, PDF printable sheet generator, and compact payload codecs.

---

## User Review Required

> [!IMPORTANT]
> **Pen-Drawn Corner Line Segments & Identity at 0 Length**:
> The 4 line segments start precisely from the 4 corners of the central QR code. A length of **0** represents the nominal identity transformation (no paper shift, nominal 1.0 scale). Drawing outward from the corners encodes paper displacement tolerance and scale correction. If the printed paper is shifted relative to marks drawn onto the underlying desk/surface, the scanner solves for the offset.

> [!IMPORTANT]
> **Interactive Manual Point Adjustment**:
> The scanner HUD provides draggable touch/pinch reticles on each corner segment endpoint. The user can fine-tune point positions manually on top of the camera feed, with instant reprojection feedback.

> [!IMPORTANT]
> **Target Visualization: Handheld AR vs. visionOS Spatial**:
> - **Handheld AR (iOS)**: Targets are rendered with a rounded rectangle matching the physical dimensions of the iOS device (e.g. iPhone bezel/screen aspect ratio) rendered tangent to the bottom of the spherical target, oriented upwards on the device.
> - **Spatial (visionOS)**: Targets are held up by 3D hands dynamically sized to the user's hand dimensions measured via ARKit `HandTrackingProvider`.

> [!IMPORTANT]
> **No Community Server (100% Serverless)**:
> All server hosting and community course browser backends are removed. Course sharing is 100% serverless, private, and offline via self-contained high-density QR codes, `.sillycourse` file export (AirDrop, iMessage, Files), and direct deep links (`sillybells://`).

---

## Proposed Architecture & Component Overview

```
+---------------------------------------------------------------------------------------+
|                                      TargetCore                                       |
|  - Course & SphericalTarget Models (3D coordinates, hand/device anchor pose, radius)  |
|  - PrintableSheetRenderer (Vector PDF: Portrait & Landscape, QR + Coordinate Guides)  |
|  - CornerLineCalibrationEngine (4 QR corners, 0-length = identity, scale correction)  |
|  - CompactCourseCodec (High-density compressed binary / Base64 URL serialization)     |
|  - LocalCourseStore (Sandboxed file store for local saving, import/export)            |
+-------------------------------------------+-------------------------------------------+
                                            |
         +----------------------------------+-----------------------------------+
         |                                                                      |
         v                                                                      v
+---------------------------------------+              +---------------------------------------+
|           TargetStudio AVP            |              |          TargetScanner Free           |
|              (visionOS)               |              |           (iOS & visionOS)            |
| - ImmersiveSpace 3D target authoring  |              | - ARKit Camera & Vision Line Detector |
| - HandTrackingProvider hand sizing    |              | - Interactive Point Adjustment HUD    |
| - RealityKit 3D Hand-Held Targets     |              | - 0-length identity Corner Solver     |
| - Portrait/Landscape PDF Sheet Export |              | - Handheld AR: Device-sized Rounded   |
| - Local Course Manager & QR Generator |              |   Rectangle Tangent to Target Sphere  |
+---------------------------------------+              | - "Open in Silly Bells ($1)" Bridge   |
                                                       +-------------------+-------------------+
                                                                           |
                                                                           | sillybells://course?data=...
                                                                           v
                                                       +---------------------------------------+
                                                       |              Silly Bells              |
                                                       |          (Connected $1 App)           |
                                                       | - Offline Deep Link Handler           |
                                                       | - Loads Course & Calibrated Origin    |
                                                       | - Active Gameplay Mode                |
                                                       +---------------------------------------+
```

---

## Proposed Changes

### Component 1: `TargetCore` (Shared Multi-Platform Swift Package)

A standalone Swift package compiling cleanly across iOS, visionOS, and macOS with zero external server dependencies.

#### [NEW] `Package.swift`
- Configures `TargetCore` library target and unit test target `TargetCoreTests`.
- Platforms: `.iOS(.v18)`, `.visionOS(.v2)`, `.macOS(.v14)`.

#### [NEW] `Sources/TargetCore/Models/Course.swift`
- `PaperOrientation`: `enum` (`portrait`, `landscape`).
- `PaperFormat`: `enum` (`letter`, `a4`, `custom(widthMm: Float, heightMm: Float)`).
- `QRCorner`: `enum` (`topLeft`, `topRight`, `bottomRight`, `bottomLeft`).
- `CornerLineSegment`:
  - `corner: QRCorner` (base anchor at QR corner)
  - `endpoint: SIMD2<Float>` (paper coordinates in mm)
  - `lengthMm: Float` (0 = identity transformation)
  - `nominalScaleLengthMm: Float` (reference length corresponding to 1.0 metric scale)
- `SphericalTarget`:
  - `id: UUID`
  - `position: SIMD3<Float>` (meters relative to calibrated origin)
  - `radius: Float` (0.05m – 0.50m)
  - `colorHex: String`
  - `pointValue: Int`
- `DevicePhysicalProfile`:
  - Helper providing physical device dimensions (width, height, thickness, corner radius in meters) for the tangent rounded-rectangle rendering on iOS devices.
- `Course`:
  - `id: UUID`, `title: String`, `authorName: String`
  - `paperOrientation: PaperOrientation`, `paperFormat: PaperFormat`
  - `qrSizeMm: Float` (nominal physical width of QR code, e.g. 100mm)
  - `cornerSegments: [CornerLineSegment]` (4 segments starting at QR corners)
  - `targets: [SphericalTarget]`
  - `createdAt: Date`

#### [NEW] `Sources/TargetCore/Geometry/CornerLineCalibrationEngine.swift`
- Mathematical representation of corner line segments:
  - Base points: $\mathbf{c}_i \in \{TL, TR, BR, BL\}$ computed from QR code geometry.
  - If $\forall i, \|\mathbf{p}_i - \mathbf{c}_i\| = 0$: Returns **Identity Transformation** ($\mathbf{T} = \mathbf{I}$, scale $s = 1.0$).
  - Displacement & Orientation: When pen lines extend from the 4 corners, solves for paper displacement relative to marks drawn onto the surface:
    $$\min_{\Delta \mathbf{R}, \Delta \mathbf{t}, s} \sum_{i=1}^4 \|\pi(\mathbf{K} \cdot (\Delta \mathbf{R} \mathbf{P}_i + \Delta \mathbf{t})) - \mathbf{u}_i\|^2$$
  - Scale Correction: Evaluates the line segment lengths relative to nominal guide lengths, yielding uniform scale $s = \frac{L_{observed}}{L_{nominal}}$.
  - Manual Point Refinement: Ingests user-adjusted screen coordinates from the touch/drag HUD and updates the solved pose and scale in real-time.

#### [NEW] `Sources/TargetCore/Rendering/PrintableSheetRenderer.swift`
- Generates vector PDF and high-res printable images for AirPrint / export:
  - Supports both **Portrait** ($215.9 \times 279.4$ mm Letter / $210 \times 297$ mm A4) and **Landscape** formats.
  - Central high-contrast course QR code.
  - Precision coordinate guides printed outside the QR code:
    - 4 corner crosshairs radiating from the QR corners with millimeter tick marks.
    - Outer margin metric rulers along X and Y axes.
    - Clear instructions: "Segments start at the 4 QR corners. 0 length = standard identity calibration."

#### [NEW] `Sources/TargetCore/Serialization/CompactCourseCodec.swift`
- Ultra-compact binary/Base64 serialization designed to fit inside a single high-density QR code (Version 15–25) and offline URL schemes:
  - Header: 1-byte version + 1-byte flags (orientation: portrait/landscape, format).
  - 4 corner line vectors: 16-bit packed offsets $(\Delta x_i, \Delta y_i)$ relative to corners (0,0 when identity).
  - Targets: 16-bit compressed relative coordinates $(x, y, z)$ + 8-bit radius + 8-bit color index + 8-bit score.
  - Deflate/gzip compression + URL-safe Base64 encoding.
  - Produces deep links: `sillybells://course?v=2&data=<compact_base64>`.

#### [NEW] `Sources/TargetCore/Storage/LocalCourseStore.swift`
- 100% serverless local persistence:
  - Saves courses to app sandboxed Documents directory as `.sillycourse` files.
  - Functions: `saveCourse`, `loadAllCourses`, `deleteCourse`, `exportCourseFile(url:)`, `importCourseFile(url:)`.
  - Built-in sample starter courses stored locally (no network requests).

#### [NEW] `Tests/TargetCoreTests/TargetCoreTests.swift`
- Unit tests verifying:
  - 0-length corner line segments produce exact identity transform and $s=1.0$.
  - Corner line displacement solver handles simulated rotation, translation, and scale changes.
  - Compact binary serialization round-trips into `< 350` bytes.
  - Portrait and landscape PDF generation dimensions and coordinate guide alignment.
  - DevicePhysicalProfile dimensions calculation.

---

### Component 2: `TargetStudioAVP` (Apple Vision Pro - visionOS App)

#### [NEW] `Sources/TargetStudioAVP/App/TargetStudioApp.swift`
- visionOS lifecycle supporting 2D Course Manager Window and `ImmersiveSpace` for spatial target authoring.

#### [NEW] `Sources/TargetStudioAVP/HandTracking/UserHandSizer.swift`
- Uses visionOS `HandTrackingProvider` from ARKit:
  - Reads active `HandSkeleton` during authoring.
  - Measures anthropometric hand length (wrist joint to middle finger tip) and hand breadth.
  - Computes user hand scale ratio $S_{hand} = \frac{\text{measured length}}{185\text{ mm}}$.
  - Feeds measured dimensions directly into RealityKit hand entities.

#### [NEW] `Sources/TargetStudioAVP/Views/SpatialTargetAuthoringView.swift`
- `RealityView` in `ImmersiveSpace`:
  - Visual Origin: Renders 3D sheet preview with coordinate guides and corner rays.
  - **Hand-Held Target Entities**: Targets are held up by 3D hands dynamically sized to the user's hand measurements.
  - Gestures: Drag to reposition target in 3D space; virtual hand moves with target.
  - Visual indicator of current metric scale and distance.

#### [NEW] `Sources/TargetStudioAVP/Views/TargetInspectorPalette.swift`
- Floating spatial palette:
  - Radius slider (5cm to 50cm).
  - Target color selector & point value.
  - Paper format toggle: Portrait vs Landscape.

#### [NEW] `Sources/TargetStudioAVP/Views/PrintSheetModalView.swift`
- Preview printable sheet in Portrait or Landscape with coordinate guides and corner markings.
- AirPrint (`UIPrintInteractionController`) and system PDF export (`ShareLink`).

---

### Component 3: `TargetScannerFree` (Universal iOS & visionOS Companion App)

#### [NEW] `Sources/TargetScannerFree/App/TargetScannerApp.swift`
- Companion scanner app entry point.

#### [NEW] `Sources/TargetScannerFree/Views/ARScannerView.swift`
- Camera viewport with `AVFoundation` + `Vision`:
  - Detects QR code barcode (`VNDetectBarcodesRequest`).
  - Detects pen line segments radiating from the 4 QR corners (`VNDetectLineSegmentsRequest` + corner-proximity clustering).
  - Evaluates corner lines: if no lines detected, defaults to 0-length identity calibration.

#### [NEW] `Sources/TargetScannerFree/Views/InteractivePointAdjustmentView.swift`
- Draggable touch/pinch overlay on top of camera feed:
  - Displays detected endpoints of the 4 corner line segments with interactive handles and magnified circular loupes.
  - Allows user to manually snap or drag endpoints (including snapping back to 0-length corner for identity).
  - Real-time readout of computed scale correction factor ($s$) and displacement residuals.
  - "Lock Origin" confirmation button.

#### [NEW] `Sources/TargetScannerFree/Views/ARRealityPreviewView.swift`
- RealityKit scene rendering author-placed targets:
  - **Handheld AR Mode (iOS)**: Renders a rounded rectangle matching the physical dimensions of the iOS device, positioned tangent to the bottom of the spherical target and oriented upwards on the device.
  - **Spatial Mode (visionOS)**: Renders user-scaled 3D hands holding the target spheres.
  - Interactive hit/ping preview to verify 3D positioning in physical space.

#### [NEW] `Sources/TargetScannerFree/Views/LocalCourseLibraryView.swift`
- Local course browser:
  - Lists locally saved and previously scanned courses.
  - "Scan New Sheet" button.
  - File import/export: AirDrop or share `.sillycourse` files.
  - On-screen QR generator to beam course to another player's device without a server.

#### [NEW] `Sources/TargetScannerFree/Views/OpenConnectedAppBanner.swift`
- Call-to-action banner:
  - "Play in Silly Bells ($1)"
  - Fires offline deep link: `sillybells://course?v=2&data=<compact_base64>`.
  - Fallback modal: `SKStoreProductViewController` / App Store link if Silly Bells is not yet installed.

---

### Component 4: Xcode Project & Build Configuration

#### [NEW] `TargetEco.xcodeproj` / Workspace Setup
- Multi-target project linking `TargetCore` to:
  - `TargetStudioAVP` (visionOS)
  - `TargetScannerFree` (iOS & visionOS)
- Configures camera usage descriptions (`NSCameraUsageDescription`), file type declarations (`.sillycourse`), and custom URL scheme registration (`sillybells`).

---

## Git Commit Review Anchoring Specification

Commit messages and audit trail adhere to the RFC 822 trailers and Git Notes standard:

```text
feat(calibration): corner line calibration with 0-length identity and handheld device tangent visualization

Implement 4 QR corner line calibration (0-length = identity), scale correction,
and handheld AR rounded rectangle device visualization tangent to target spheres.

Review-Doc: implementation_plan.md
Review-Anchor: #component-1-targetcore-shared-multi-platform-swift-package
Reviewed-By: Kent Slaney <kent@slaney.org>
Review-Status: Approved
Approved-At: 2026-09-05T12:48:00-07:00
```

---

## Verification Plan

### Automated Tests
- Run `swift test` on `TargetCoreTests`:
  ```bash
  swift test
  ```
  - Verify 0-length corner line segments produce exact identity transform and $s=1.0$.
  - Verify displacement calculation when corner line segments have non-zero lengths.
  - Verify scale factor calculation: $s = \frac{L_{observed}}{L_{nominal}}$.
  - Verify compact binary codec round-trip produces valid payloads for QR codes.
  - Verify PDF generation generates correct dimensions and corner guides for both Portrait and Landscape.
  - Verify `DevicePhysicalProfile` dimensions for common iPhone/iPad models.

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
1. **0-Length Identity**: Test scanner when no corner lines are drawn; verify identity transform ($s=1.0, \Delta \mathbf{R}=\mathbf{I}, \Delta \mathbf{t}=\mathbf{0}$) is applied immediately.
2. **Corner Line Adjustment**: Simulate or draw pen lines starting from the 4 QR corners; drag point handles with touch loupe; verify solved origin adjusts smoothly.
3. **Handheld AR Device Tangent Visualization**: In iOS AR preview, verify spherical targets are rendered with a device-sized rounded rectangle tangent to the bottom of the sphere, oriented upwards on the device.
4. **visionOS User Hand Sizing**: On AVP, verify authoring space renders 3D hands matching the user's measured hand skeleton.
5. **Portrait & Landscape PDFs**: Generate and visually check both Portrait and Landscape printable sheets.
6. **100% Serverless & Silly Bells Bridge**: Test local `.sillycourse` file export and `sillybells://course?v=2&data=...` deep link offline.
