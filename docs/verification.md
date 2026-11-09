# Verification

Automated checks: `bash scripts/test.sh` and `bash scripts/build-app.sh`.

## Recorded local verification — 2026-11-09

- Release compilation and app bundle creation passed with Swift 6.2.3.
- Ad-hoc code signing completed; Info.plist passed `plutil -lint`.
- All five Swift Testing tests passed, covering embedding validation, model binding, ordered poses, reset conditions, expiration, and threshold bounds.
- Opened the generated app bundle. Its native accessibility tree showed the dashboard, four navigation controls, camera-off state, model-import button, disabled enrollment/recognition before model import, and the app-only unlock notice.
- Further native UI automation lost its connection before settings-page verification. No camera activation, model import, face enrollment, Touch ID prompt, Keychain persistence, or biometric accuracy test was performed.

Manual checks still required on a development Mac:

- Start the built bundle and inspect all four navigation pages at minimum window size.
- Deny camera permission, verify the explanation, then grant permission through System Settings.
- Test built-in/external cameras, device removal, repeated start/stop, and sleep/wake.
- Import a licensed compatible model; reject incompatible inputs/outputs and corrupt files.
- Enroll all three poses, restart the app, and verify enrollment persists in Keychain.
- Switch models and verify old enrollment cannot authenticate.
- Recognize an enrolled person under different lighting and head poses; measure false accept/reject rates with consented participants.
- Confirm a second face, no face, missed challenge, mismatch, or timeout does not unlock.
- Confirm the demo relocks on focus loss and Touch ID/password cancellation leaves it locked.
- Delete enrollment and verify recognition cannot proceed.
- Inspect network behavior; the app source contains no network client, but OS services may have their own activity.

Do not describe this prototype as secure biometric authentication or a macOS login replacement based on unit tests alone.
