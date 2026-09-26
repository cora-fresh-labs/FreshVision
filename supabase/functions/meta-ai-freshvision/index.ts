import { analyzeFruit } from "../_shared/analysis.ts";
import {
  enforceRateLimit,
  PublicError,
  requireConnector,
} from "../_shared/auth.ts";
import { json, preflight, readJson, safeError } from "../_shared/http.ts";

type RequestBody = {
  tool?: string;
  name?: string;
  arguments?: { imageBase64?: string };
  imageBase64?: string;
};

Deno.serve(async (request) => {
  const option = preflight(request);
  if (option) return option;
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }
  try {
    requireConnector(request);
    await enforceRateLimit(
      request,
      "meta-connector",
      "connector-analyze",
      100,
      150,
      200,
    );
    const body = await readJson<RequestBody>(request);
    const toolName = body.tool ?? body.name ?? "assess_fruit";
    if (toolName !== "assess_fruit") {
      return json({ error: "Unknown FreshVision tool." }, 404);
    }
    const image = body.arguments?.imageBase64 ?? body.imageBase64;
    if (!image) return json({ error: "Show me one piece of fruit." }, 400);
    const result = await analyzeFruit(image);
    const spokenResponse = result.verdict
      ? `${result.verdict}. ${result.reason}`
      : result.reason;
    return json({ result, spoken_response: spokenResponse });
  } catch (error) {
    return json(
      { error: safeError(error) },
      error instanceof PublicError ? error.status : 422,
    );
  }
});
