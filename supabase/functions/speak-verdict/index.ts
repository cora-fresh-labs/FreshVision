import { enforceRateLimit, requireCaller } from "../_shared/auth.ts";
import { handleSpeech } from "../_shared/speech-handler.ts";
import { synthesizeVerdict } from "../_shared/speech.ts";
import { serviceClient } from "../_shared/supabase.ts";

Deno.serve((request) =>
  handleSpeech(request, {
    caller: requireCaller,
    load: async (id, owner) => {
      const result = await serviceClient().from("consumer_scans")
        .select("analysis_status,fruit,verdict,reason,issue,confidence")
        .eq("id", id).eq("owner_id", owner).maybeSingle();
      if (result.error) throw new Error("Speech lookup failed");
      return result.data;
    },
    // At most 10,000 input characters a day across the beta, including retries.
    limit: (req, owner) => enforceRateLimit(req, owner, "speech", 20, 40, 50),
    speak: (scan) =>
      synthesizeVerdict(scan, Deno.env.get("ELEVENLABS_API_KEY") ?? ""),
  })
);
