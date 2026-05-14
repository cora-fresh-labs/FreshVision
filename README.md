# FreshVision QC

![FreshVision](assets/teaserimage.png)

FreshVision is an open iOS prototype for real-time fresh-produce quality control using Meta Ray-Ban smart glasses or the iPhone camera.

Point the camera at produce, cartons, PLU labels, thermometers, refractometers, or defect closeups. The app sends selected frames to Claude Vision and returns a structured QC assessment: commodity, visible label data, defect estimates, compliance flags, GREEN/AMBER/RED score, recommended action, and SOP coverage.

This repo is meant to be a builder path, not a black-box SaaS pitch. If you have the will, a pair of camera glasses or an iPhone, and a Claude or Codex subscription to help you adapt the code, you can build and tailor a working QC layer yourself.

![Cover](assets/cover.png)

## What it does

- **Inspect produce in the field or warehouse** from smart glasses or the iPhone camera.
- **Capture representative photos** hands-free, including via volume-button capture while streaming.
- **Analyze with Claude Vision** using a produce-QC system prompt and JSON output schema.
- **Read labels and QC instruments** when visible: origin, supplier, PLU, temperature, brix, weight.
- **Score common defects** with estimated percentages and confidence.
- **Track SOP coverage** across load overview, label, top-down fruit, defect closeup, cut fruit, temperature, brix, and weight photos.
- **Finalize/share a report** with inspector notes, checklist items, selected photos, and the AI assessment.

## Why this exists

Large retailers already run quality programs with human inspectors, cameras, spreadsheets, and SOPs. FreshVision shows how close a small builder can get to a practical assistive layer using commodity AI tools and wearable cameras.

It is not a certified replacement for a trained inspector. It is a prototype for faster triage, better photo discipline, and more consistent first-pass documentation.

## How it works

![How It Works](assets/how.png)

```text
Meta Ray-Ban glasses or iPhone camera
        |
        | video frames / captured photos
        v
iOS app
        |
        | JPEG image + QC prompt
        v
Claude Vision API
        |
        | structured JSON assessment
        v
FreshVision UI + shareable report
```

Key pieces:

- **Meta Wearables DAT SDK** for Ray-Ban Meta camera streaming.
- **iPhone camera mode** so you can test without glasses.
- **Claude Vision** for produce-QC image analysis.
- **Local runtime API key entry** via the app UI; no API keys are committed to the repo.

## Quick start

### 1. Clone and open

```bash
git clone https://github.com/cora-fresh-labs/FreshVision.git
cd FreshVision/samples/CameraAccess
open CameraAccess.xcodeproj
```

### 2. Get an Anthropic API key

Create an API key at <https://console.anthropic.com/>.

The app stores the key locally in iOS `UserDefaults` after you enter it in the key-icon settings UI. Do **not** commit real API keys to source files.

### 3. Build and run

- Xcode 15+
- iOS 17+
- Physical iPhone recommended
- Meta Ray-Ban glasses optional

Select your iPhone target and run with `Cmd+R`.

### 4. Try it without glasses

1. Tap **Start on iPhone**.
2. Enter your Claude API key with the key icon if prompted.
3. Point the camera at produce or a label.
4. Tap **Inspect**.
5. Review the JSON-backed QC card and share/finalize a report.

### 5. Try it with Meta Ray-Ban glasses

First enable Developer Mode in the Meta AI app:

1. Open the **Meta AI** app on your iPhone.
2. Go to **Settings**.
3. Tap **App Info**.
4. Tap the **App version** number five times.
5. Return to Settings and enable **Developer Mode**.

![How to enable Developer Mode](assets/dev_mode.png)

Then in FreshVision:

1. Pair the glasses through Meta AI.
2. Tap **Start streaming**.
3. Capture photos or inspect frames from the glasses stream.

## Repository map

```text
samples/CameraAccess/
  CameraAccess.xcodeproj                 Xcode project
  CameraAccess/
    Claude/                              FreshVision QC analysis, report, UI models
      ClaudeConfig.swift                 Runtime key storage + QC system prompt
      ClaudeVisionService.swift          Anthropic Messages API image calls
      FreshVisionViewModel.swift         inspection/session/report workflow
      QCResult.swift                     Codable QC schema
      QCResultCardView.swift             result card UI
      ReportShareSheet.swift             iOS share sheet wrapper
    iPhone/IPhoneCameraManager.swift     iPhone camera test mode
    ViewModels/StreamSessionViewModel.swift
    Views/StreamView.swift               FreshVision inspection UI
```

Legacy Gemini/OpenClaw files remain in the sample tree because this project started from a real-time assistant prototype, but the public FreshVision QC flow is Claude Vision based.

## Optional bridge upload

Finalized reports can optionally be uploaded to a private bridge endpoint if you set both values in `UserDefaults`:

- `freshvision.bridge.endpoint`
- `freshvision.bridge.token`

No public endpoint or token is configured by default. If either value is missing, upload is skipped.

## Security notes

- No real API keys, bearer tokens, bridge tokens, or local hostnames should be committed.
- Enter Anthropic keys at runtime only.
- Treat photos of labels, cartons, suppliers, or warehouse operations as potentially sensitive.
- This prototype sends selected images to Anthropic for analysis; review Anthropic’s data and retention terms before using real customer/supplier data.

## Requirements

- Xcode 15+
- iOS 17+
- Anthropic API key with vision-capable Claude model access
- Physical iPhone
- Meta Ray-Ban glasses for wearable mode, optional

## Troubleshooting

**Claude API key not configured**  
Tap the key icon in the app and enter an Anthropic key. It should start with `sk-`.

**Camera does not start**  
Check iOS camera permissions and run on a physical device.

**Speech notes do not work**  
Enable Speech Recognition and Microphone permissions in iOS Settings.

**Glasses do not connect**  
Confirm Meta AI Developer Mode is enabled, the glasses are paired, and the DAT SDK setup is complete.

**The assessment is wrong**  
Treat the model output as a draft. Use the inspector checklist and notes before finalizing. For production use, calibrate prompts, tolerances, and validation against your own SOPs.

## Status

Prototype / public reference implementation. Contributions and forks are welcome, especially around commodity-specific SOPs, validation sets, and safer report export flows.
