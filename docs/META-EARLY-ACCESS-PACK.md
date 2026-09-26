# FreshVision Meta early-access pack

## One-line description

FreshVision lets a shopper look at one piece of fruit through Meta glasses, press the glasses capture button, and hear a plain answer about whether it is worth buying.

## Why glasses improve the product

A shopper can keep both hands free while holding a basket, moving fruit, or comparing items. The camera sees the shopper's view. FreshVision returns one short verdict and reason rather than asking the shopper to interpret produce grades.

## Current interaction

1. Open FreshVision on the paired iPhone and connect Meta glasses.
2. Look at one banana, bunch of grapes, punnet of strawberries, avocado, or apple.
3. Short-press the glasses capture button.
4. FreshVision saves the image locally, assesses it, shows the result on iPhone, and speaks the result over the active audio route.
5. The shopper can later record whether the fruit was actually good.

## Safety and limits

- The app supports only five named fruits.
- It uses only visible evidence and does not claim to know smell, softness, taste, or internal condition.
- It returns one of five fixed verdicts.
- It asks for another image when lighting, framing, or the fruit is unsupported.
- It is shopping guidance, not food-safety advice.
- Photos and feedback are private and are not publicly accessible.
- Every image is disclosed as being sent to FreshVision's private Supabase backend and Anthropic for analysis, and the shopper can delete the FreshVision copies from History.

## Why this is useful to Meta

- Clear everyday use case that is better hands-free
- One action and one short answer
- Works on displayless glasses and can later add a display card
- Uses DAT camera and glasses input rather than treating glasses as a remote phone camera
- Produces an opt-in feedback dataset that can improve accuracy by fruit and capture source

## Demonstration script

Record one continuous demonstration with no cuts:

1. Show the FreshVision camera screen and connected-glasses state.
2. Look at a supported ripe fruit and short-press the glasses capture button.
3. Record the spoken verdict and the iPhone result.
4. Scan an unsupported fruit and show the plain five-fruit limit.
5. Open History and add a feedback vote.

## Submission sequence

1. Create the FreshVision app in Wearables Developer Center.
2. Add its app ID, client token, team ID and callback scheme to the private build configuration.
3. Test with Meta's Mock Device Kit.
4. Test with physical Ray-Ban Meta glasses.
5. Measure latency and accuracy separately for iPhone and glasses images.
6. Record the demonstration.
7. Apply for the Meta AI Connectors developer preview using the provisional `assess_fruit` tool as the starting contract.
8. Request consideration for the coming curated AI-glasses discovery surfaces.

No application, release-channel invitation or public submission should occur without Clint's approval.

## Official references

- Meta AI glasses developer paths: <https://developers.meta.com/wearables/>
- Meta wearables FAQ: <https://developers.meta.com/wearables/faq/>
- Wearables DAT iOS SDK: <https://github.com/facebook/meta-wearables-dat-ios>
