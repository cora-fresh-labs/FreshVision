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
  const allowed = [
    "That photo is too large. Please take another.",
    "FreshVision analysis is not configured.",
    "FreshVision couldn’t finish that scan. Please try again.",
    "That took too long. Please try again.",
    "I couldn’t read that result. Please try again.",
    "Open FreshVision again and retry.",
    "FreshVision has reached today’s scan limit. Try again tomorrow.",
    "That scan could not be saved.",
    "That feedback could not be saved.",
    "That scan could not be deleted.",
    "FreshVision connector is not authorized.",
  ];
  if (error instanceof Error && allowed.includes(error.message)) {
    return error.message;
  }
  console.error(error);
  return "FreshVision couldn’t finish that scan. Please try again.";
}
