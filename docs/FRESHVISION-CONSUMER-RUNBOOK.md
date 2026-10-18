# FreshVision Consumer v1 runbook

## What is implemented

- Native SwiftUI app for iOS 17.2 and later
- Camera-first launch with one-tap capture
- Private photo picker, including when camera access is denied
- Meta Wearables DAT 1.0 camera preview and photo capture
- Short press on the connected glasses capture button to scan hands-free
- Emma result audio through a server-side ElevenLabs adapter, plus replay and stop controls
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
deno task check
deno task test
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

## Emma voice

`speak-verdict` accepts a scan UUID and a user JWT. It loads only that user's
saved, completed assessment. It never accepts an arbitrary speech prompt or a
voice ID from the client. The server pins Emma to `56bWURjYFHyYyVf490Dp`, model
`eleven_flash_v2_5`, and MP3 output. Set `ELEVENLABS_API_KEY` only in the approved
backend's Edge Function secrets through its secure dashboard. Never put provider
keys in Xcode, a tester device, a repository, logs or chat.

The app shows the result before speech starts. It caches up to ten clips in memory
to avoid repeat generation. Backgrounding, changing scans and pressing Stop cancel
playback. A speech error leaves the written assessment available. No system voice
is substituted for Emma.

The pilot caps each analysis and speech endpoint at 20 requests per user, 40 per
network and 50 across the project in each 24-hour rate-limit window. Speech is at
most 200 characters per request. These are cost circuit breakers, not a spending
authorization. Increasing the tester audience requires an agreed budget and abuse
protection review.

Release builds fail when the HTTPS backend URL or public client key is missing,
or a server key is supplied. Debug builds can show the unconfigured state for
testing. The check does not prove a backend is deployed or healthy; run the live
acceptance flow before distribution.
