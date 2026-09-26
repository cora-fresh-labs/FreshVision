import { json, preflight, readJson, safeError } from "../_shared/http.ts";
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
    const { scan, imageBase64 } = await readJson<RequestBody>(request);
    if (!scan?.id || !scan.installationId || !imageBase64) {
      return json({ error: "That scan is incomplete." }, 400);
    }
    const client = serviceClient();
    const photoPath = `${scan.installationId}/${scan.id}.jpg`;
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
    return json({ error: safeError(error) }, 422);
  }
});
