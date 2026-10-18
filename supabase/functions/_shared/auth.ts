import { serviceClient } from "./supabase.ts";

export type Caller = { userId: string };

export async function requireCaller(request: Request): Promise<Caller> {
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) throw new PublicError("Open FreshVision again and retry.", 401);
  const { data, error } = await serviceClient().auth.getUser(token);
  if (error || !data.user?.id) {
    throw new PublicError("Open FreshVision again and retry.", 401);
  }
  return { userId: data.user.id };
}

export function requireConnector(request: Request): void {
  const expected = Deno.env.get("META_CONNECTOR_SHARED_SECRET") ?? "";
  const supplied = request.headers.get("authorization") ?? "";
  if (!expected || supplied !== `Bearer ${expected}`) {
    throw new PublicError("FreshVision connector is not authorized.", 401);
  }
}

export async function enforceRateLimit(
  request: Request,
  userId: string,
  action: string,
  userLimit: number,
  ipLimit: number,
  globalLimit: number,
): Promise<void> {
  const forwarded =
    request.headers.get("x-forwarded-for")?.split(",").at(-1)?.trim() ??
      "unknown";
  const userKey = await hash(`${action}:user:${userId}`);
  const ipKey = await hash(`${action}:ip:${forwarded}`);
  const globalKey = await hash(`${action}:project`);
  const client = serviceClient();
  await consumeLimit(client, userKey, userLimit);
  await consumeLimit(client, ipKey, ipLimit);
  await consumeLimit(client, globalKey, globalLimit);
}

async function consumeLimit(
  client: ReturnType<typeof serviceClient>,
  key: string,
  limit: number,
): Promise<void> {
  const result = await client.rpc("consume_consumer_rate_limit", {
    p_key_hash: key,
    p_limit: limit,
    p_window_seconds: 86_400,
  });
  if (result.error) throw new Error("Rate limit storage failed");
  if (result.data !== true) {
    throw new PublicError(
      "FreshVision has reached today’s scan limit. Try again tomorrow.",
      429,
    );
  }
}

async function hash(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export class PublicError extends Error {
  constructor(message: string, readonly status = 400) {
    super(message);
  }
}
