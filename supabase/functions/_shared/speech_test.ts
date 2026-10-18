import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import {
  EMMA_VOICE_ID,
  type SavedVerdict,
  SPEECH_MODEL_ID,
  SPEECH_UNAVAILABLE,
  synthesizeVerdict,
  verdictText,
} from "./speech.ts";
import { handleSpeech } from "./speech-handler.ts";
import { PublicError } from "./auth.ts";

const scan: SavedVerdict = {
  analysis_status: "complete",
  fruit: "banana",
  verdict: "Buy \u2014 ready now",
  reason: "The peel is evenly yellow.",
  issue: null,
  confidence: 0.9,
};
const id = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
const request = (body: unknown = { scanId: id }) =>
  new Request("https://fixture.invalid", {
    method: "POST",
    body: JSON.stringify(body),
    headers: { authorization: "Bearer fixture" },
  });

Deno.test("Emma adapter pins the established voice, model, format and server-only key", async () => {
  let calls = 0;
  const fakeFetch: typeof fetch = async (url, init) => {
    calls++;
    assertEquals(
      String(url).includes(
        `/text-to-speech/${EMMA_VOICE_ID}?output_format=mp3_44100_128`,
      ),
      true,
    );
    assertEquals(new Headers(init?.headers).get("xi-api-key"), "fixture-key");
    const body = JSON.parse(init?.body as string);
    assertEquals(body.model_id, SPEECH_MODEL_ID);
    assertEquals(body.text, "Buy, ready now. The peel is evenly yellow.");
    assertEquals(body.text.length <= 200, true);
    return new Response(new Uint8Array([73, 68, 51]), {
      headers: { "content-type": "audio/mpeg" },
    });
  };
  const result = await synthesizeVerdict(scan, "fixture-key", fakeFetch);
  assertEquals(result.voiceId, EMMA_VOICE_ID);
  assertEquals(atob(result.audioBase64), "ID3");
  assertEquals(calls, 1);
});

Deno.test("missing key and invalid verdict cannot trigger provider requests", async () => {
  const noFetch: typeof fetch = () => {
    throw new Error("must not call provider");
  };
  await assertRejects(
    () => synthesizeVerdict(scan, "", noFetch),
    Error,
    SPEECH_UNAVAILABLE,
  );
  assertThrows(() => verdictText({ ...scan, analysis_status: "needs_retry" }));
  assertThrows(() => verdictText({ ...scan, verdict: "Free text" }));
  assertThrows(() => verdictText({ ...scan, reason: "x".repeat(141) }));
});

Deno.test("provider errors and timeout details never reach client or logs", async () => {
  for (const status of [401, 429, 500]) {
    const fakeFetch: typeof fetch = async () =>
      new Response("private-provider-detail", { status });
    await assertRejects(
      () => synthesizeVerdict(scan, "fixture-key", fakeFetch),
      Error,
      SPEECH_UNAVAILABLE,
    );
  }
  const timeout: typeof fetch = () =>
    Promise.reject(new DOMException("secret-detail", "TimeoutError"));
  await assertRejects(
    () => synthesizeVerdict(scan, "fixture-key", timeout),
    Error,
    SPEECH_UNAVAILABLE,
  );
});

Deno.test("speech requires identity and loads only that owner's saved scan", async () => {
  let paid = 0;
  const deps = {
    caller: async () => ({ userId: "owner-1" }),
    load: async (scanId: string, owner: string) => {
      assertEquals(scanId, id);
      assertEquals(owner, "owner-1");
      return scan;
    },
    limit: async () => {},
    speak: async () => {
      paid++;
      return { voiceId: EMMA_VOICE_ID };
    },
  };
  assertEquals((await handleSpeech(request(), deps)).status, 200);
  assertEquals(paid, 1);
  assertEquals(
    (await handleSpeech(request(), {
      ...deps,
      caller: () =>
        Promise.reject(
          new PublicError("Open FreshVision again and retry.", 401),
        ),
    })).status,
    401,
  );
  assertEquals(
    (await handleSpeech(request(), { ...deps, load: async () => null })).status,
    404,
  );
  assertEquals(
    (await handleSpeech(request({ scanId: "bad" }), deps)).status,
    400,
  );
  assertEquals(paid, 1);
});

Deno.test("circuit breaker blocks speech before a paid provider call", async () => {
  let paid = 0;
  const result = await handleSpeech(request(), {
    caller: async () => ({ userId: "owner" }),
    load: async () => scan,
    limit: () =>
      Promise.reject(
        new PublicError(
          "FreshVision has reached today’s scan limit. Try again tomorrow.",
          429,
        ),
      ),
    speak: async () => {
      paid++;
      return {};
    },
  });
  assertEquals(result.status, 429);
  assertEquals(paid, 0);
});
