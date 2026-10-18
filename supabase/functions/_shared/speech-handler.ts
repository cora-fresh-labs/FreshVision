import { PublicError } from "./auth.ts";
import { json, preflight, readJson, safeError } from "./http.ts";
import { type SavedVerdict, SPEECH_UNAVAILABLE } from "./speech.ts";

type SpeechDependencies = {
  caller: (request: Request) => Promise<{ userId: string }>;
  load: (id: string, owner: string) => Promise<SavedVerdict | null>;
  limit: (request: Request, owner: string) => Promise<void>;
  speak: (scan: SavedVerdict) => Promise<unknown>;
};

export async function handleSpeech(
  request: Request,
  deps: SpeechDependencies,
): Promise<Response> {
  const option = preflight(request);
  if (option) return option;
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }
  try {
    const caller = await deps.caller(request);
    const body = await readJson<{ scanId?: string }>(request, 1_024);
    if (
      typeof body.scanId !== "string" ||
      !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(body.scanId)
    ) {
      return json({ error: SPEECH_UNAVAILABLE }, 400);
    }
    const scan = await deps.load(body.scanId, caller.userId);
    if (!scan || scan.analysis_status !== "complete" || !scan.verdict) {
      return json({ error: SPEECH_UNAVAILABLE }, 404);
    }
    await deps.limit(request, caller.userId);
    return json(await deps.speak(scan));
  } catch (error) {
    return json(
      { error: safeError(error) },
      error instanceof PublicError ? error.status : 503,
    );
  }
}
