# IrisGate

**Your presence. Your device.** An original native macOS research app for local face enrollment, recognition, and a motion-challenged app unlock demonstration.

Inspired by a static examination of Glance 1.2, with original Swift source and interface. This repository does not contain Glance's executable, artwork, animations, or model weights, and is not affiliated with Glance.

## What works in this implementation

- SwiftUI dashboard and menu bar controls.
- Camera selection, permission handling, live preview, and explicit stop controls.
- Import of a compatible, separately licensed Core ML face embedding model.
- Nine enrollment samples across center and two head poses; vectors stored in the local macOS Keychain.
- Model fingerprint binding, normalized cosine scoring, and a randomized center → turn → center challenge.
- Recognition timeout, reset on mismatches/multiple faces/stale frames, and app relock on focus loss.
- Touch ID or macOS password fallback through LocalAuthentication for the app demonstration.
- No application network client, analytics, account registration, or camera recording.

**This version unlocks IrisGate only. It does not unlock the macOS login screen.** It does not collect or type your login password. Motion checks are experimental and are not validated presentation-attack detection. Camera/model behavior requires manual hardware verification; successful compilation and unit tests do not establish biometric accuracy.

## Build

macOS 15+, Apple Silicon or Intel, and Swift 6 / Xcode Command Line Tools. There are no third-party Swift dependencies.

```sh
bash scripts/test.sh
bash scripts/build-app.sh
open dist/IrisGate.app
```

Run the packaged `.app` for camera usage descriptions and a stable bundle identity. The build uses ad-hoc signing for local development; distributing a release requires your Developer ID signing and notarization.

## Bring your own model

Choose **Import face model…** and select a local `.mlmodel`, `.mlpackage`, or compiled `.mlmodelc` you are licensed to use. The selected path is remembered; leave the model at that location. Input must be named `input_image` (112×112 image); output must be named `embedding` (512 floats). Use a compatible face-embedding model with preprocessing inside the model. IrisGate normalizes the output itself.

No model is downloaded automatically. The reference app's model is deliberately not redistributed. Model weights and biometric samples are excluded from Git. Check model and training-data terms separately from this repository's MIT license.

Start with **Preview camera**, then **Enroll your face**, follow the three poses, and choose **Test face unlock**. Only one face may be visible. Recognition opens the app gate after matching throughout the motion challenge. Deleting enrollment removes only IrisGate's Keychain item, not other applications' data.

The current crop uses face bounds and eye-based roll correction. Exact five-landmark alignment, model-specific calibration, independent spoof testing, and accuracy evaluation remain future work.

## Project layout

`Sources/IrisGateCore` holds testable embedding math and the challenge state machine. `Sources/IrisGate` contains the UI, camera/Vision pipeline, Core ML adapter, and Keychain persistence. `Tests` covers invalid vectors, model binding, ordered challenges, mismatches, multiple faces, and timeouts. `docs/reverse-engineering.md` records observations and limits. GitHub Actions builds and tests without a camera or model.

## Roadmap

- Calibrated five-landmark model preprocessing and licensed model distribution.
- Camera/model and Keychain integration tests on real hardware.
- Accessibility, multi-window lifecycle, and long-running camera QA.
- Independent liveness/biometric security evaluation.
- Separate design and review of any macOS lock-screen integration; none is implemented or claimed here.

See [the investigation](docs/reverse-engineering.md) and [manual verification checklist](docs/verification.md).
