import { analyzeFruit } from "../_shared/analysis.ts";
import {
  enforceRateLimit,
  PublicError,
  requireCaller,
} from "../_shared/auth.ts";
import { json, preflight, readJson, safeError } from "../_shared/http.ts";

type RequestBody = {
  scanId: string;
  imageBase64: string;
  captureSource: string;
};

Deno.serve(async (request) => {
  const option = preflight(request);
  if (option) return option;
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }
  try {
    const caller = await requireCaller(request);
    await enforceRateLimit(request, caller.userId, "analyze", 20, 40, 50);
    const body = await readJson<RequestBody>(request);
    if (!body.scanId || !body.imageBase64) {
      return json({ error: "Take another photo and try again." }, 400);
    }
    return json(await analyzeFruit(body.imageBase64));
  } catch (error) {
    return json(
      { error: safeError(error) },
      error instanceof PublicError ? error.status : 422,
    );
  }
});
