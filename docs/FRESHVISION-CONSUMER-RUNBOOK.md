# FreshVision Consumer v1 runbook

## What is implemented

- Native SwiftUI app for iOS 17.2 and later
- Camera-first launch with one-tap capture
- Meta Wearables DAT 1.0 camera preview and photo capture
- Short press on the connected glasses capture button to scan hands-free
- Spoken result for scans captured through Meta glasses
- Five fixed fruits and five fixed verdicts
- Plain-language failure states
- Local SwiftData history and private local JPEG storage
- Local-first scan and feedback outbox with foreground retry
- Private Supabase tables and storage bucket
- Server-side vision analysis through a Supabase Edge Function
- Provisional `assess_fruit` Meta AI Connector tool contract

## Local build

1. Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig`.
2. Add the Supabase URL and anonymous client key.
3. Enable anonymous sign-ins in Supabase Auth. Each installation receives a
   private session stored in Keychain.
4. Add the Meta Developer Center app ID and client token when available.
5. Run `xcodegen generate` from `consumer/FreshVisionConsumer`.
6. Open `FreshVisionConsumer.xcodeproj`.

No Anthropic key belongs in the iOS app. It is stored only as a Supabase Edge
Function secret.

## Verification commands

```sh
xcodebuild -quiet -project FreshVisionConsumer.xcodeproj -scheme FreshVisionConsumer -destination 'platform=iOS Simulator,name=iPhone 16e' CODE_SIGNING_ALLOWED=NO test
deno check supabase/functions/analyze-fruit/index.ts supabase/functions/save-consumer-scan/index.ts supabase/functions/save-consumer-feedback/index.ts supabase/functions/delete-consumer-scan/index.ts supabase/functions/meta-ai-freshvision/index.ts
deno test supabase/functions/_shared/analysis_test.ts
```

## Work that requires explicit approval

- Apply the Supabase migration
- Add production Edge Function secrets
- Deploy Edge Functions
- Create or configure the Meta Developer Center app
- Invite TestFlight testers
- Submit to Meta AI Connectors or any public discovery surface

The Edge Functions require a valid anonymous-user JWT, enforce record ownership
and apply daily user, network and project-wide circuit breakers. The
project-wide limit caps model cost even if disposable anonymous identities or
forwarded network headers are abused. The provisional Meta connector fails
closed unless its protected shared secret is configured. Add Apple App Attest
before expanding beyond the two-person TestFlight pilot.
