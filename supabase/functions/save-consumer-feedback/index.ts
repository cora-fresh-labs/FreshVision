import { json, preflight, readJson, safeError } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";

type RequestBody = {
  scanId: string;
  installationId: string;
  vote: "good" | "not_good";
  votedAt: string;
};

Deno.serve(async (request) => {
  const option = preflight(request);
  if (option) return option;
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }
  try {
    const body = await readJson<RequestBody>(request, 20_000);
    if (
      !body.scanId || !body.installationId ||
      !["good", "not_good"].includes(body.vote)
    ) {
      return json({ error: "That feedback could not be saved." }, 400);
    }
    const result = await serviceClient().from("consumer_feedback").upsert({
      scan_id: body.scanId,
      installation_id: body.installationId,
      vote: body.vote,
      voted_at: body.votedAt,
      updated_at: new Date().toISOString(),
    }, { onConflict: "scan_id" });
    if (result.error) throw result.error;
    return json({});
  } catch (error) {
    return json({ error: safeError(error) }, 422);
  }
});
