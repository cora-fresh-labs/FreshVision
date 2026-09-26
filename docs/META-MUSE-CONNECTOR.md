# FreshVision on Meta AI glasses

Muse is Meta's model and coding-tool family, not the distribution layer for third-party glasses apps. FreshVision uses Muse-compatible development materials, but reaches shoppers through the Wearables Device Access Toolkit and, if accepted to the developer preview, Meta AI Connectors.

FreshVision will reach Meta glasses through two complementary paths:

1. A native iOS app using Meta Wearables Device Access Toolkit 1.0 for camera capture, future voice invocation and future display output.
2. A narrow `assess_fruit` backend tool prepared for Meta AI Connectors, so Meta AI can call FreshVision without opening a separate app.

## Connector contract

Input: one JPEG image from the current glasses view.

Output:

- supported: boolean
- fruit: banana, grapes, strawberries, avocado, apple, or null
- verdict: one fixed consumer verdict, or null
- reason: one short sentence
- issue: no_fruit, multiple_fruits, poor_lighting, unsupported_fruit, or null
- confidence: zero to one

## Submission path

Before applying to Meta:

1. Verify capture on supported glasses.
2. Measure latency and accuracy by capture source.
3. Prepare privacy and retention copy.
4. Record a short hands-free demonstration.
5. Apply for Meta AI Connectors developer preview.
6. Create a Wearables Developer Center organization and release channel.

The checked-in connector schema is a provisional contract until Meta grants developer-preview access and provides its current registration schema. No application or public submission occurs without Clint's approval.
