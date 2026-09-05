# Implementation Plan - AVP Spatial Target Studio, Error-Correcting Pen-Drawn Fiducials & "Silly Bells" Serverless Ecosystem

Build an end-to-end spatial computing ecosystem featuring:
1. **Apple Vision Pro (AVP) App ("TargetStudio AVP")**: Spatial authoring tool to place and configure spherical targets in physical space, calibrate a reference origin, measure user hand dimensions to render targets held up by realistically scaled 3D hands, and generate/print a precision fiducial sheet (portrait or landscape).
2. **Precision Paper Fiducial with Pen-Drawn Line Segments**: Printable reference sheet (PDF/AirPrint) in portrait or landscape format featuring a central course QR code, printed coordinate guides/ruler ticks along the margins, and designated zones for user pen-drawn line segments. The pen marks allow the paper to be slightly displaced or re-positioned without losing course alignment, and encode physical scale correction.
3. **Free Scanner & Calibration App ("TargetScanner Free" - iOS & visionOS)**: AR scanner that detects the paper QR code, printed coordinate guides, and pen-drawn line segments. Includes an **Interactive Point Adjustment UI** allowing the user to manually reposition detected points on screen, computes scale correction, renders targets held up by 3D hands sized to the user, and bridges directly to the connected $1 iOS app **"Silly Bells"**.
4. **100% Serverless & Decentralized Sharing**: Zero server hosting. All course geometry, target configs, paper orientation, and scale corrections are fully self-contained in the printed QR code and deep links (`sillybells://course?v=2&data=...`), with local file storage and peer-to-peer AirDrop/iMessage export.
5. **Connected $1 App ("Silly Bells" - iOS)**: The existing paid app opened via deep link, loading course data and the error-corrected, scale-calibrated origin for active gameplay.
6. **TargetCore Framework**: Shared Swift package containing course data models, portrait/landscape coordinate geometry, pen-line alignment and scale-correction solvers, PDF printable sheet generator, and compact payload codecs.

---

## User Review Required

> [!IMPORTANT]
> **Pen-Drawn Line Segments & Paper Displacement**:
> Line segments are drawn onto the surface or paper with a pen during setup. If the printed paper is subsequently bumped, shifted, or replaced slightly off its original position, the scanner compares the printed coordinate guides with the pen-drawn marks to compute the relative paper displacement $\Delta \mathbf{T} = [\Delta \mathbf{R} \mid \Delta \mathbf{t}]$ and restore the exact authoring origin.

> [!IMPORTANT]
> **Interactive Manual Point Adjustment**:
> Because ink visibility, lighting, or paper warping can affect computer vision line detection, the scanner HUD provides draggable touch/pinch reticles on each detected endpoint. The user can fine-tune point positions manually on top of the camera feed, with instant reprojection feedback.

> [!IMPORTANT]
> **Targets Held by User-Scaled 3D Hands**:
> Floating billboard distance tags are eliminated. Instead, each target sphere is rendered resting in a 3D hand entity. On visionOS (AVP), ARKit hand tracking measures the user's actual hand dimensions (wrist to fingertips, palm span) to dynamically scale the 3D hand model. On iOS, the scanner uses standard anthropometric hand scaling with a quick-calibration slider.

> [!IMPORTANT]
> **No Community Server (100% Serverless)**:
> All server hosting and community course browser backends are removed. Course sharing is 100% serverless, private, and offline via self-contained high-density QR codes, `.sillycourse` file export (AirDrop, iMessage, Files), and direct deep links (`sillybells://`).

---

## Proposed Architecture & Component Overview

```
+---------------------------------------------------------------------------------------+
|                                      TargetCore                                       |
|  - Course & SphericalTarget Models (3D relative coordinates, hand-anchor pose, radius) |
|  - PrintableSheetRenderer (Vector PDF: Portrait & Landscape, QR + Coordinate Guides)  |
|  - PenLineCalibrationEngine (Paper displacement solver, scale correction calculator)  |
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
| - RealityKit 3D Hand-Held Targets     |              | - Scale & Paper Shift Error Refinement|
| - Portrait/Landscape PDF Sheet Export |              | - RealityKit Hand-Held Target Preview |
| - Local Course Manager & QR Generator |              | - "Open in Silly Bells ($1)" Bridge   |
+---------------------------------------+              +-------------------+-------------------+
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
- `PenLineSegment`:
  - `id: UUID`
  - `startAnchor: SIMD2<Float>` (paper coordinates in mm)
  - `endAnchor: SIMD2<Float>` (paper coordinates in mm)
  - `nominalLengthMm: Float` (physical reference length for scale correction)
  - `drawnOnSurface: Bool` (whether drawn on underlying table/floor across the paper boundary)
- `SphericalTarget`:
  - `id: UUID`
  - `position: SIMD3<Float>` (meters relative to calibrated origin)
  - `radius: Float` (0.05m – 0.50m)
  - `colorHex: String`
  - `pointValue: Int`
  - `handPose`: Grip angle, wrist elevation, and tilt for the supporting 3D hand.
- `Course`:
  - `id: UUID`, `title: String`, `authorName: String`
  - `paperOrientation: PaperOrientation`, `paperFormat: PaperFormat`
  - `referenceSegments: [PenLineSegment]` (segments encoding scale & offset)
  - `targets: [SphericalTarget]`
  - `createdAt: Date`

#### [NEW] `Sources/TargetCore/Geometry/PenLineCalibrationEngine.swift`
- Mathematical representation of paper displacement and metric scale correction:
  - **Paper Shift Solver**: Computes translation $\Delta \mathbf{t}$ and rotation $\Delta \mathbf{R}$ when the physical paper moves relative to pen lines drawn onto the supporting surface.
  - **Scale Correction Calculator**: Compares the observed pixel/3D length of pen-drawn line segments between known guide points against `nominalLengthMm`, deriving scale factor $s = \frac{L_{measured}}{L_{nominal}}$. Applies uniform metric scaling $\mathbf{x}_{world} = s \cdot \mathbf{x}_{author}$.
  - **Manual Point Refinement**: Takes updated 2D screen coordinates from the Interactive Point Adjustment HUD and recalculates the refined 6-DoF pose and scale factor via Levenberg-Marquardt / PnP optimization.

#### [NEW] `Sources/TargetCore/Rendering/PrintableSheetRenderer.swift`
- Generates vector PDF and high-res printable images for AirPrint / export:
  - Supports both **Portrait** ($215.9 \times 279.4$ mm Letter / $210 \times 297$ mm A4) and **Landscape** formats.
  - Central high-contrast course QR code.
  - Precision coordinate guides printed outside the QR code:
    - Metric millimeter ruler ticks along outer margins.
    - Alignment crosshairs and corner boxes.
    - Pen Drawing Zones: High-contrast guidelines indicating where to draw pen calibration segments bridging the paper and desk/floor.
    - Scale calibration reference ruler ("50 mm Reference Bar").

#### [NEW] `Sources/TargetCore/Serialization/CompactCourseCodec.swift`
- Ultra-compact binary/Base64 serialization designed to fit inside a single high-density QR code (Version 15–25) and offline URL schemes:
  - Header: 1-byte version + 1-byte flags (orientation: portrait/landscape, format).
  - Encoded line segment anchors (16-bit fixed-point millimeters).
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
  - Compact serialization & deserialization round-trip into `< 400` byte payloads.
  - Paper orientation (portrait vs landscape) transform math.
  - Scale correction derived from pen line lengths.
  - Paper displacement solver with simulated offset and rotation.
  - PDF sheet generation across portrait and landscape orientations.

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
  - Visual Origin: Renders 3D sheet preview with coordinate guides and drawn line anchors.
  - **Hand-Held Target Entities**: Targets are not floating billboard tags. Each target sphere rests in a 3D hand model scaled precisely to the user's hand size.
  - Gestures: Drag to reposition target in 3D space; virtual hand moves with target, dynamically orienting its palm to support the sphere.
  - Visual indicator of current metric scale and distance.

#### [NEW] `Sources/TargetStudioAVP/Views/TargetInspectorPalette.swift`
- Floating spatial palette:
  - Radius slider (5cm to 50cm).
  - Target color selector & point value.
  - Hand orientation controls (wrist tilt, palm angle).
  - Paper format toggle: Portrait vs Landscape.

#### [NEW] `Sources/TargetStudioAVP/Views/PrintSheetModalView.swift`
- Preview printable sheet in Portrait or Landscape with coordinate guides.
- AirPrint (`UIPrintInteractionController`) and system PDF export (`ShareLink`).

---

### Component 3: `TargetScannerFree` (Universal iOS & visionOS Companion App)

#### [NEW] `Sources/TargetScannerFree/App/TargetScannerApp.swift`
- Companion scanner app entry point.

#### [NEW] `Sources/TargetScannerFree/Views/ARScannerView.swift`
- Camera viewport with `AVFoundation` + `Vision`:
  - Detects QR code barcode (`VNDetectBarcodesRequest`).
  - Detects pen line segments and printed coordinate guides (`VNDetectLineSegmentsRequest` + contour analysis).
  - Displays HUD status: "Align with Paper Fiducial" $\to$ "Pen Segments Detected" $\to$ "Origin & Scale Calibrated".

#### [NEW] `Sources/TargetScannerFree/Views/InteractivePointAdjustmentView.swift`
- Draggable touch/pinch overlay on top of camera feed:
  - Displays detected endpoints of pen line segments as interactive handles with magnified loupes.
  - Allows user to manually drag any point if ink has changed, faded, or if paper moved slightly.
  - Real-time readout of computed scale correction factor ($s$) and displacement residuals.
  - "Lock Origin" confirmation button once points are aligned.

#### [NEW] `Sources/TargetScannerFree/Views/ARRealityPreviewView.swift`
- RealityKit scene rendering author-placed targets:
  - Targets held up by user-scaled 3D hands anchored to the corrected origin.
  - iOS hand scale adjustment: ergonomic preset (Small / Medium / Large) or quick on-screen palm measurement.
  - Interactive hit/ping preview to verify 3D positioning in the physical space.

#### [NEW] `Sources/TargetScannerFree/Views/LocalCourseLibraryView.swift`
- Replaces former community browser:
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
feat(calibration): support pen-drawn line segments and interactive point adjustment

Implement pen line displacement solver, scale correction factor,
and interactive touch handles for manually moving line endpoints in AR.

Review-Doc: implementation_plan.md
Review-Anchor: #component-1-targetcore-shared-multi-platform-swift-package
Reviewed-By: Kent Slaney <kent@slaney.org>
Review-Status: Approved
Approved-At: 2026-09-05T12:30:00-07:00
```

---

## Verification Plan

### Automated Tests
- Run `swift test` on `TargetCoreTests`:
  ```bash
  swift test
  ```
  - Verify compact binary codec round-trip produces valid payloads for QR codes.
  - Verify pen line displacement solver correctly calculates $\Delta \mathbf{R}$ and $\Delta \mathbf{t}$ under simulated paper shift.
  - Verify scale factor calculation: $s = \frac{L_{observed}}{L_{nominal}}$ under intentional scale variations (90%, 100%, 110%).
  - Verify PDF generation generates correct dimensions and guide positions for both Portrait (Letter/A4) and Landscape (Letter/A4).
  - Verify local course store save, load, and `.sillycourse` file export/import.

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
1. **Interactive Point Adjustment**: In iOS Simulator/device, simulate camera feed with misaligned endpoints; drag point handles with touch, verify loupe magnification, and verify calibrated pose updates immediately.
2. **Scale Correction**: Test with a printed sheet scaled to 90%; draw calibration segment, verify computed scale matches 0.90, and target positions scale accordingly.
3. **Paper Displacement**: Slightly nudge paper fiducial; verify pen marks on desk/surface allow solver to maintain stable target positions in world space.
4. **User-Scaled 3D Hands**: On visionOS, author targets and observe 3D hands holding spheres; verify hands match user hand tracking scale rather than floating billboard text.
5. **Portrait & Landscape Sheet Generation**: Inspect generated PDFs; verify crisp QR code, margin millimeter rulers, and pen drawing guides in both orientations.
6. **100% Serverless Sharing & Silly Bells Bridge**:
   - Save course locally, export as QR code, scan from second device.
   - Tap "Play in Silly Bells ($1)", verify deep link payload `sillybells://course?v=2&data=...` launches the app with course data without any network requests.
