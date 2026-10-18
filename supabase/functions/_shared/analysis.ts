export const fruits = [
  "banana",
  "grapes",
  "strawberries",
  "avocado",
  "apple",
] as const;
export const verdicts = [
  "Buy — ready now",
  "Buy — ripe in 2–3 days",
  "Skip — overripe",
  "Skip — underripe",
  "Skip — damaged",
] as const;
export const issues = [
  "no_fruit",
  "multiple_fruits",
  "poor_lighting",
  "unsupported_fruit",
] as const;

export type Fruit = typeof fruits[number];
export type Verdict = typeof verdicts[number];
export type Issue = typeof issues[number];
export type FruitAnalysis = {
  supported: boolean;
  fruit: Fruit | null;
  verdict: Verdict | null;
  reason: string;
  issue: Issue | null;
  confidence: number;
};

const tool = {
  name: "report_fruit_assessment",
  description: "Return the FreshVision consumer assessment for the image.",
  input_schema: {
    type: "object",
    additionalProperties: false,
    required: [
      "supported",
      "fruit",
      "verdict",
      "reason",
      "issue",
      "confidence",
    ],
    properties: {
      supported: { type: "boolean" },
      fruit: { anyOf: [{ type: "string", enum: fruits }, { type: "null" }] },
      verdict: {
        anyOf: [{ type: "string", enum: verdicts }, { type: "null" }],
      },
      reason: { type: "string", maxLength: 140 },
      issue: { anyOf: [{ type: "string", enum: issues }, { type: "null" }] },
      confidence: { type: "number", minimum: 0, maximum: 1 },
    },
  },
};

export async function analyzeFruit(
  imageBase64: string,
): Promise<FruitAnalysis> {
  if (!imageBase64 || imageBase64.length > 11_500_000) {
    throw new Error("That photo is too large. Please take another.");
  }
  const key = Deno.env.get("ANTHROPIC_API_KEY");
  const model = Deno.env.get("ANTHROPIC_MODEL");
  if (!key || !model) {
    throw new Error("FreshVision analysis is not configured.");
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);
  try {
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      signal: controller.signal,
      headers: {
        "content-type": "application/json",
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model,
        max_tokens: 260,
        temperature: 0,
        system: [
          "You are FreshVision, a cautious grocery shopping assistant.",
          "Judge only one visible item of fruit from this image.",
          "Supported fruits are banana, grapes, strawberries, avocado and apple.",
          "Use only visible evidence such as color, bruising, shriveling, broken skin and mold.",
          "Never claim softness, smell, taste, internal condition or certainty you cannot see.",
          "The reason must be one short sentence in everyday language with no grading codes or produce jargon.",
          "When the image is ambiguous, return the matching issue instead of guessing.",
        ].join(" "),
        tools: [tool],
        tool_choice: { type: "tool", name: tool.name },
        messages: [{
          role: "user",
          content: [
            {
              type: "image",
              source: {
                type: "base64",
                media_type: "image/jpeg",
                data: imageBase64,
              },
            },
            {
              type: "text",
              text: "Assess whether this fruit is worth buying.",
            },
          ],
        }],
      }),
    });
    if (!response.ok) {
      throw new Error(
        "FreshVision couldn’t finish that scan. Please try again.",
      );
    }
    const body = await response.json();
    const block = body.content?.find((
      value: { type?: string; name?: string },
    ) => value.type === "tool_use" && value.name === tool.name);
    return validateAnalysis(block?.input);
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error("That took too long. Please try again.");
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

export function validateAnalysis(input: unknown): FruitAnalysis {
  if (!input || typeof input !== "object") {
    throw new Error("I couldn’t read that result. Please try again.");
  }
  const value = input as Record<string, unknown>;
  const supported = value.supported === true;
  const fruit =
    typeof value.fruit === "string" && fruits.includes(value.fruit as Fruit)
      ? value.fruit as Fruit
      : null;
  const verdict = typeof value.verdict === "string" &&
      verdicts.includes(value.verdict as Verdict)
    ? value.verdict as Verdict
    : null;
  const issue =
    typeof value.issue === "string" && issues.includes(value.issue as Issue)
      ? value.issue as Issue
      : null;
  const confidence = typeof value.confidence === "number"
    ? Math.min(1, Math.max(0, value.confidence))
    : 0;
  const reason = oneSentence(
    typeof value.reason === "string"
      ? value.reason
      : "I couldn’t judge that fruit.",
  );
  if (supported && (!fruit || !verdict || issue)) {
    throw new Error("I couldn’t read that result. Please try again.");
  }
  if (!supported && (!issue || fruit || verdict)) {
    throw new Error("I couldn’t read that result. Please try again.");
  }
  return { supported, fruit, verdict, reason, issue, confidence };
}

function oneSentence(value: string): string {
  const clean = value.replace(/\s+/g, " ").trim().slice(0, 140);
  const match = clean.match(/^.*?[.!?](?:\s|$)/);
  return (match?.[0] ?? clean).trim() || "I couldn’t judge that fruit.";
}
