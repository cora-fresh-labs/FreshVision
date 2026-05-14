# FreshVision CameraAccess sample

This is the iOS sample app for FreshVision QC.

It uses the Meta Wearables DAT SDK for smart-glasses streaming, an iPhone camera fallback for testing, and Claude Vision for structured fresh-produce quality-control assessments.

## Run it

```bash
git clone https://github.com/cora-fresh-labs/FreshVision.git
cd FreshVision/samples/CameraAccess
open CameraAccess.xcodeproj
```

In Xcode:

1. Select a physical iPhone target.
2. Set your signing team if needed.
3. Run with `Cmd+R`.
4. In the app, tap the key icon and enter your Anthropic API key.
5. Tap **Start on iPhone** or connect Meta Ray-Ban glasses and tap **Start streaming**.
6. Point at produce, labels, or QC equipment and tap **Inspect**.

## Main files

| File | Purpose |
|---|---|
| `CameraAccess/Claude/ClaudeConfig.swift` | Runtime key storage and produce-QC prompt |
| `CameraAccess/Claude/ClaudeVisionService.swift` | Anthropic Messages API client |
| `CameraAccess/Claude/FreshVisionViewModel.swift` | Inspection, voice notes, session photos, report workflow |
| `CameraAccess/Claude/QCResult.swift` | Structured QC result schema |
| `CameraAccess/Views/StreamView.swift` | Main inspection UI |
| `CameraAccess/ViewModels/StreamSessionViewModel.swift` | Streaming, frame capture, photo queue |
| `CameraAccess/iPhone/IPhoneCameraManager.swift` | iPhone camera test mode |

Legacy Gemini/OpenClaw files are still present from the upstream assistant prototype, but the FreshVision QC flow uses Claude Vision.

## API keys

Do not hard-code real API keys in source files. The public app expects the Anthropic key to be entered at runtime and stored locally on-device.

## Optional report bridge

If you want finalized reports to upload to your own backend, set these `UserDefaults` values:

- `freshvision.bridge.endpoint`
- `freshvision.bridge.token`

If either is missing, the app simply skips upload.
