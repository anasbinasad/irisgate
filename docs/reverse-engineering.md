# Glance 1.2 static investigation

Date: 2026-11-09. User-provided target: `Glance.dmg`.

SHA-256: `c10ad703e9306f3e4174c269c6c1845d83694f34febef1b8f936ccb0b3f096db`.

## Evidence and method

REA opened the supplied disk image and traversed it read-only. Retained inspection Evidence: `ev_c894f12a5e9e812cc10abc20ff5bf827999514b7de02a53d96b2f8b371b18538`; summary Evidence: `ev_bfbe41b096aff18505b84cee87704e202b39b28bc29968fa776792d751b985fd`; graph manifest: `agm_2097cb18c3920ba460c2012c3153ca2ade94a441a4d76ee9ab2563b7aea2c3a0`. The graph contains 141 nodes and 153 occurrences with no reported integrity contradictions.

REA extraction rejected DMG as unsupported by its extraction reader. A separate `hdiutil attach -readonly -nobrowse` mounted the image for examination. `plutil`, `strings`, `nm -u`, and `otool -L` inspected the contained app. The app was not installed or executed. No camera access, password entry, face enrollment, credential retrieval, or lock-screen interaction was performed on Glance.

## Observed static facts

| Area | Evidence in the artifact |
| --- | --- |
| Identity | `com.jonathan.glance`, version 1.2, build 4, macOS 15 minimum in Info.plist |
| Architecture | Mach-O executable includes arm64 and x86_64 |
| Native UI | SwiftUI, AppKit, Charts, and Symbols framework dependencies |
| Camera | AVFoundation linkage; camera usage description says on-device face recognition and enrollment |
| Vision | Imports for face rectangles, landmarks, face capture quality, and image feature prints |
| Embeddings | `ArcFace.mlmodelc` metadata describes w600k_mbf, 112×112 RGB `input_image`, 512-float unnormalized `embedding` |
| Enrollment | Type names include FaceEnrollmentStore, FaceIdentity, FaceSample, EnrollmentPose; strings describe center and eight directional poses |
| Liveness | LivenessAnalyzer, LivenessEvaluator, blinkFrames, LivenessMode; UI string describes light/heavy modes |
| Settings | General, camera, password, recognition, your-face, and about type names; match threshold, unlock triggers, and animations |
| Credentials | Keychain API imports and strings describing encrypted, device-local password storage |
| Unlock mechanism | CGEvent keyboard creation, Unicode string, post, and flags imports; UI string explicitly describes typing the password through Accessibility |
| Triggers | Wake, space-key lock-screen listening, and screen locked/unlocked notification strings |
| Updates | Sparkle 2.9.6 dependency; feed `https://tryglance.app/appcast.xml` in Info.plist |
| Media | Bundled branding, icon, idle, successful and unsuccessful unlock animations |

## Inferences and unknowns

The linkage and strings support a camera → Vision face processing → embedding → similarity/liveness → password-event pipeline hypothesis. They do not establish exact control flow, thresholds, encryption key handling, anti-spoof effectiveness, or runtime reliability. Strings mentioning offline behavior are the original app's claims, not a verified network audit. The visible password-typing mechanism is inferred from multiple static signals; it was not exercised.

No native function decompilation or original Swift source recovery was completed. This report is not a claim of exhaustive reverse engineering. No signing, license, entitlement, or authentication checks were patched or bypassed.

## IrisGate reconstruction decisions

IrisGate implements an original native app around the observed concepts: camera/Vision processing, an explicit model adapter, multiple-pose enrollment, normalized embeddings, local Keychain storage, configurable recognition, and motion challenge. The dashboard and state machine are new implementations; they are not recovered Glance source.

The public project excludes the supplied DMG, executable, compiled model, signing materials, and media. It accepts a separately licensed model. It implements an app gate and native device-owner authentication fallback. macOS login password storage/typing, lock-screen wake/spacebar monitoring, Sparkle updates, and the reference animations are not implemented. These gaps are deliberate project boundaries and remain visible in the README.
