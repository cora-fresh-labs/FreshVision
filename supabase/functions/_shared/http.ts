export const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json; charset=utf-8",
    },
  });
}

export function preflight(request: Request): Response | null {
  return request.method === "OPTIONS"
    ? new Response("ok", { headers: corsHeaders })
    : null;
}

export async function readJson<T>(
  request: Request,
  maxBytes = 12_000_000,
): Promise<T> {
  const length = Number(request.headers.get("content-length") ?? 0);
  if (length > maxBytes) {
    throw new Error("That photo is too large. Please take another.");
  }
  const text = await request.text();
  if (text.length > maxBytes) {
    throw new Error("That photo is too large. Please take another.");
  }
  return JSON.parse(text) as T;
}

export function safeError(error: unknown): string {
  if (error instanceof Error && error.message.length <= 180) {
    return error.message;
  }
  return "FreshVision couldn’t finish that scan. Please try again.";
}
