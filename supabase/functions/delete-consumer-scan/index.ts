import {
  enforceRateLimit,
  PublicError,
  requireCaller,
} from "../_shared/auth.ts";
import { json, preflight, readJson, safeError } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";

type RequestBody = { scanId: string };

Deno.serve(async (request) => {
  const option = preflight(request);
  if (option) return option;
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }
  try {
    const caller = await requireCaller(request);
    await enforceRateLimit(request, caller.userId, "delete", 100, 300, 2_000);
    const body = await readJson<RequestBody>(request, 20_000);
    if (!body.scanId) throw new PublicError("That scan could not be deleted.");
    const client = serviceClient();
    const scan = await client.from("consumer_scans").select(
      "owner_id, photo_path",
    )
      .eq("id", body.scanId).maybeSingle();
    if (scan.error) throw scan.error;
    if (!scan.data) return json({});
    if (scan.data.owner_id !== caller.userId) {
      throw new PublicError("That scan could not be deleted.", 404);
    }
    const removed = await client.storage.from("consumer-scan-photos").remove([
      scan.data.photo_path,
    ]);
    if (removed.error) throw removed.error;
    const deleted = await client.from("consumer_scans").delete().eq(
      "id",
      body.scanId,
    )
      .eq("owner_id", caller.userId);
    if (deleted.error) throw deleted.error;
    return json({});
  } catch (error) {
    return json(
      { error: safeError(error) },
      error instanceof PublicError ? error.status : 422,
    );
  }
});
