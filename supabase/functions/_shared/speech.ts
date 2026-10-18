import { validateAnalysis } from "./analysis.ts";

export const EMMA_VOICE_ID = "56bWURjYFHyYyVf490Dp";
export const SPEECH_MODEL_ID = "eleven_flash_v2_5";
export const SPEECH_UNAVAILABLE =
  "Emma’s voice is unavailable. Your result is still here.";

export type SavedVerdict = {
  analysis_status: string;
  fruit: string | null;
  verdict: string | null;
  reason: string | null;
  issue: string | null;
  confidence: number | null;
};

export function verdictText(scan: SavedVerdict): string {
  if (
    scan.analysis_status !== "complete" || !scan.reason ||
    scan.reason.length > 140
  ) {
    throw new Error(SPEECH_UNAVAILABLE);
  }
  const value = validateAnalysis({
    supported: true,
    fruit: scan.fruit,
    verdict: scan.verdict,
    reason: scan.reason,
    issue: scan.issue,
    confidence: scan.confidence,
  });
  return `${value.verdict!.replaceAll(" \u2014 ", ", ")}. ${value.reason}`;
}

export async function synthesizeVerdict(
  scan: SavedVerdict,
  apiKey: string,
  fetcher: typeof fetch = fetch,
) {
  const text = verdictText(scan);
  if (!apiKey || text.length > 200) throw new Error(SPEECH_UNAVAILABLE);
  try {
    const response = await fetcher(
      `https://api.elevenlabs.io/v1/text-to-speech/${EMMA_VOICE_ID}?output_format=mp3_44100_128`,
      {
        method: "POST",
        signal: AbortSignal.timeout(8_000),
        headers: { "content-type": "application/json", "xi-api-key": apiKey },
        body: JSON.stringify({
          text,
          model_id: SPEECH_MODEL_ID,
          voice_settings: {
            stability: 0.5,
            similarity_boost: 0.75,
            use_speaker_boost: true,
          },
        }),
      },
    );
    if (
      !response.ok ||
      !response.headers.get("content-type")?.startsWith("audio/")
    ) {
      throw new Error(SPEECH_UNAVAILABLE);
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (!bytes.length || bytes.length > 1_000_000) {
      throw new Error(SPEECH_UNAVAILABLE);
    }
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return {
      voiceId: EMMA_VOICE_ID,
      modelId: SPEECH_MODEL_ID,
      contentType: "audio/mpeg",
      audioBase64: btoa(binary),
    };
  } catch {
    // Provider bodies can contain account details. Never forward or log them.
    throw new Error(SPEECH_UNAVAILABLE);
  }
}
