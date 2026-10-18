import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { validateAnalysis } from "./analysis.ts";
import { safeError } from "./http.ts";

Deno.test("accepts one supported fruit and fixed verdict", () => {
  assertEquals(
    validateAnalysis({
      supported: true,
      fruit: "banana",
      verdict: "Buy — ready now",
      reason: "The peel is evenly yellow with only a few brown spots.",
      issue: null,
      confidence: 0.91,
    }),
    {
      supported: true,
      fruit: "banana",
      verdict: "Buy — ready now",
      reason: "The peel is evenly yellow with only a few brown spots.",
      issue: null,
      confidence: 0.91,
    },
  );
});

Deno.test("rejects verdicts outside the consumer contract", () => {
  assertThrows(() =>
    validateAnalysis({
      supported: true,
      fruit: "apple",
      verdict: "Looks okay",
      reason: "The skin looks even.",
      issue: null,
      confidence: 0.8,
    })
  );
});

Deno.test("requires a failure issue when fruit is unsupported", () => {
  assertThrows(() =>
    validateAnalysis({
      supported: false,
      fruit: null,
      verdict: null,
      reason: "I only know 5 fruits so far.",
      issue: null,
      confidence: 0.9,
    })
  );
});

Deno.test("keeps the explanation to one short sentence", () => {
  const result = validateAnalysis({
    supported: false,
    fruit: null,
    verdict: null,
    reason: "The image is too dark. This second sentence should not appear.",
    issue: "poor_lighting",
    confidence: 0.7,
  });
  assertEquals(result.reason, "The image is too dark.");
});

Deno.test("does not expose internal backend errors", () => {
  assertEquals(
    safeError(
      new Error(
        "duplicate key value violates unique constraint consumer_scans_pkey",
      ),
    ),
    "FreshVision couldn’t finish that scan. Please try again.",
  );
});
