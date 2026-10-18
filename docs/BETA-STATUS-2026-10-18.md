# FreshVision beta checkpoint, 18 October 2026

FreshVision is locally implemented and tested. A usable shared beta is blocked on
backend and Apple account decisions. No upload or invitation has occurred.

## Verified state

The correct starting point is the existing native consumer branch at `c52323b`,
not the parked packhouse QC sample in PR #1. The original checkout is untouched.
This branch extends that work with photo import, reliable camera setup, reopenable
history, server-side Emma audio, playback controls and failure handling.

The actual SwiftUI app builds with Xcode 26.2. Fourteen iOS tests pass on an
isolated iOS 26.2 simulator, including local photo persistence, explicit retry,
successful fixture assessments, session ownership, exact voice response checking,
and actual MP3 playback using a synthetic tone. Ten Deno tests pass. All six Edge
Functions type-check. Release configuration rejection passed for empty, insecure
and server-key inputs; a public-key fixture passed. A source pattern scan found
no provider keys or private keys.

An unsigned Debug build for `generic/platform=iOS` also passed. It confirms device
compilation only; it is not a signed archive, installed iPhone test or TestFlight
upload. The reviewable implementation is in draft
[PR #2](https://github.com/cora-fresh-labs/FreshVision/pull/2).

The actual app was opened, camera permission was denied, and the photo picker
imported the repository's demo image. The app correctly displayed
`FreshVision is not connected yet.` The local scan was retained. These checks
prove local behavior, not live fruit-assessment accuracy or live Emma generation.

## Current external blockers

The connected Supabase account lists CORA (`rbjyvwfsncoohufrcxmi`), ams-lookup,
ekotwin-spine and rugby-register. No dedicated FreshVision project is visible.
CORA is healthy but has no consumer tables or FreshVision functions. The native
client config is empty. No shared CORA schema, access settings or data changed.

The accessible Apple API account lists only BlockM8. FreshVision's intended bundle
`com.coraglobalprojects.freshvision.consumer` is unregistered there. Xcode's paid
Clint Borle team is `49ZS4FL5A8`; the existing FreshVision project specifies
`WY253UX7FC`. A Clint development signing identity is available. No team change,
app registration, new credential, provisioning request or agreement acceptance
has been performed.

Emma `56bWURjYFHyYyVf490Dp` was verified in the connected ElevenLabs voice library.
Flash v2.5 is currently supported. Published Flash/Turbo pricing is $0.04 per
1,000 characters, before any account-specific terms. The implemented 50-request,
200-character circuit breaker allows at most 10,000 characters per rolling
rate-limit window, about $0.40 at that published base rate. No paid provider
test or subscription commitment has been made. A dedicated project's exact
Supabase quote and a model budget still need confirmation.

## Decisions needed

1. Identify the existing dedicated FreshVision backend, or select the organization
   for a new dedicated project so its exact cost can be quoted. The only visible
   organization is Eko Twin Org (`cpyfqqrrgbnihtmkzyvi`). Approval must cover its
   anonymous tester sessions, private schema/bucket/functions and bounded provider
   usage. Keep the consumer beta separate from CORA production data.
2. Confirm use of Clint's paid Apple team `49ZS4FL5A8` and registration of the
   existing consumer bundle, or restore access to source team `WY253UX7FC`.
3. Confirm the named tester audience before invitations or a public link. After
   backend selection, Clint must securely set existing authorized Anthropic and
   ElevenLabs credentials in that backend's supported secret settings. Never send
   secret values in chat.

## Distribution stages

| Stage | State |
| --- | --- |
| Local native implementation and simulator tests | Passed, fixtures only |
| Live camera/photo assessment, remote history, Emma voice | Blocked on backend setup; not verified |
| Physical iPhone and glasses | Not verified |
| Signed archive | Blocked on team, app registration and backend config |
| TestFlight upload | Not attempted |
| Apple processing and external beta review | Not started |
| Actual tester availability | Unavailable |

External mates will require TestFlight external beta review for the first build.
An upload does not itself make a build available to them. The current request
does not authorize an App Store public release.

References: [ElevenLabs TTS API](https://elevenlabs.io/docs/api-reference/text-to-speech/convert),
[API pricing](https://elevenlabs.io/pricing/api),
[Apple external tester review](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).
