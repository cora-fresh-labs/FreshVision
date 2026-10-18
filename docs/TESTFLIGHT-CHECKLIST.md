# FreshVision Consumer TestFlight checklist

## Build and backend

- [x] Consumer app is a separate target from the parked QC prototype.
- [x] Simulator build succeeds with Meta Wearables DAT 1.0.
- [x] Fixed fruit and verdict contract tests pass.
- [x] Edge Functions type-check and analysis validation tests pass.
- [x] Every image is written locally before analysis or upload.
- [x] Pending scans and feedback retry while active and when the app becomes
      active.
- [x] Test clients use anonymous Supabase Auth sessions stored in Keychain.
- [x] Edge Functions enforce ownership and daily user and network rate limits.
- [ ] Apply the private Supabase migration.
- [ ] Set the server-side Anthropic model and API secret.
- [ ] Deploy and smoke-test the four consumer data functions and `speak-verdict`.
- [ ] Set the server-only ElevenLabs key and verify live Emma audio.
- [ ] Keep the optional Meta connector undeployed until its separate setup is approved.
- [ ] Add the Supabase client configuration to the private Xcode configuration.

## Meta glasses

- [x] DAT camera preview and photo capture compile against 1.0.0.
- [x] Glasses capture-button input is wired to the scan pipeline.
- [x] The native audio path plays backend MP3 data, verified with a synthetic tone fixture.
- [ ] Verify Emma generation and playback through the deployed backend on an iPhone.
- [ ] Create the app in Wearables Developer Center.
- [ ] Add Meta app credentials to the private Xcode configuration.
- [ ] Run the Mock Device Kit camera and capture-button test.
- [ ] Run one full scan on physical supported glasses.

## Acceptance testing

- [ ] Photograph at least 10 examples of each supported fruit under store
      lighting.
- [ ] Confirm fruit identification is correct at least 9 times out of 10 for
      each fruit.
- [ ] Confirm median verdict time is under 5 seconds on a normal store
      connection.
- [ ] Confirm unsupported fruit, no fruit, multiple fruit, poor light and
      offline messages.
- [ ] Confirm every test scan and vote appears in Supabase.
- [ ] Give an instruction-free build to both non-technical testers.

## Distribution

- [ ] Confirm Apple Developer team and signing profile.
- [ ] Create the App Store Connect record for the private TestFlight app.
- [ ] Add camera, photo retention and model-processing privacy copy.
- [ ] Add Apple App Attest before increasing access beyond the two-person pilot.
- [ ] Archive and validate the release build.
- [ ] Upload only after Clint approves the build and tester list.
