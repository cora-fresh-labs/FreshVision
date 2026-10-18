import { json, preflight, readJson, safeError } from "../_shared/http.ts";
import {
  enforceRateLimit,
  PublicError,
  requireCaller,
} from "../_shared/auth.ts";
import { serviceClient } from "../_shared/supabase.ts";

type Scan = {
  id: string;
  installationId: string;
  capturedAt: string;
  captureSource: string;
  deviceModel: string;
  analysisStatus: string;
  fruit?: string | null;
  verdict?: string | null;
  reason?: string | null;
  issue?: string | null;
  confidence?: number | null;
};
type RequestBody = { scan: Scan; imageBase64: string };

Deno.serve(async (request) => {
  const option = preflight(request);
  if (option) return option;
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }
  try {
    const caller = await requireCaller(request);
    await enforceRateLimit(
      request,
      caller.userId,
      "save-scan",
      100,
      300,
      2_000,
    );
    const { scan, imageBase64 } = await readJson<RequestBody>(request);
    if (!scan?.id || !scan.installationId || !imageBase64) {
      return json({ error: "That scan is incomplete." }, 400);
    }
    const client = serviceClient();
    const existing = await client.from("consumer_scans").select("owner_id").eq(
      "id",
      scan.id,
    )
      .maybeSingle();
    if (existing.error) throw existing.error;
    if (existing.data && existing.data.owner_id !== caller.userId) {
      throw new PublicError("That scan could not be saved.", 403);
    }
    const photoPath = `${caller.userId}/${scan.id}.jpg`;
    const bytes = Uint8Array.from(
      atob(imageBase64),
      (character) => character.charCodeAt(0),
    );
    const upload = await client.storage.from("consumer-scan-photos").upload(
      photoPath,
      bytes,
      {
        contentType: "image/jpeg",
        upsert: true,
      },
    );
    if (upload.error) throw upload.error;
    const result = await client.from("consumer_scans").upsert({
      id: scan.id,
      owner_id: caller.userId,
      installation_id: scan.installationId,
      captured_at: scan.capturedAt,
      photo_path: photoPath,
      capture_source: scan.captureSource,
      device_model: scan.deviceModel,
      analysis_status: scan.analysisStatus,
      fruit: scan.fruit ?? null,
      verdict: scan.verdict ?? null,
      reason: scan.reason ?? null,
      issue: scan.issue ?? null,
      confidence: scan.confidence ?? null,
      updated_at: new Date().toISOString(),
    }, { onConflict: "id" });
    if (result.error) throw result.error;
    return json({});
  } catch (error) {
    return json(
      { error: safeError(error) },
      error instanceof PublicError ? error.status : 422,
    );
  }
});
