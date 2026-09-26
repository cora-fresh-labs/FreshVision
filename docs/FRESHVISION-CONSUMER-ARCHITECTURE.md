# FreshVision Consumer v1 architecture

FreshVision Consumer answers one question for a shopper: is this fruit worth buying?

The app is separate from the parked packhouse QC prototype. It has no grading codes, defect taxonomies, operator workflows, reports, or packhouse screens.

## Shared pipeline

1. Capture one image from iPhone or Meta glasses.
2. Save it locally before any network call.
3. Analyze it through the FreshVision backend.
4. Accept only one of five fruits and five fixed verdicts.
5. Show one large verdict and one plain-English reason.
6. Upload the scan and optional vote to Supabase, retrying until confirmed.

`CaptureSource` separates hardware from the product pipeline. Every scan records `iphone` or `meta_glasses` so performance can be measured separately.

SwiftData is the tester-facing source of truth. Images live in Application Support. Client-generated UUIDs make backend retries idempotent.

Each installation establishes an anonymous Supabase Auth session stored in the iOS Keychain. Edge Functions bind every scan to that authenticated owner, enforce daily per-user and project-wide limits, and never trust the bundled publishable key as identity. App Attest is the next hardening step before distribution expands beyond the two-person pilot.

The prototype uses a server-side vision model. The fine-tuned model can replace that adapter later without changing the app, history or database contract.

## Meta AI glasses

The native app uses Meta Wearables DAT for glasses registration, preview and capture. Voice invocation will be enabled once approved in Wearables Developer Center.

The backend analysis operation is client-independent and is prepared for registration as a Meta AI Connector. Muse can assist development, but the runtime surfaces are DAT and Meta AI. See `docs/META-MUSE-CONNECTOR.md`.
