// The app calls this every couple of seconds after initiating a payment,
// as a backstop in case the webhook is delayed or never arrives (real
// networks drop things; don't make "customer paid but app never found out"
// a possible outcome). Reads local status first — cheap — and only calls
// PayHero directly if still QUEUED after a few seconds, to avoid hammering
// their API on every poll tick.
import { userClient, serviceClient, corsHeaders } from "../_shared/supabase.ts";
import { queryTransactionStatus } from "../_shared/payhero.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders() });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supa = userClient(authHeader);
    const { data: { user } } = await supa.auth.getUser();
    if (!user) return json({ error: "Not signed in" }, 401);

    const url = new URL(req.url);
    const reference = url.searchParams.get("reference");
    if (!reference) return json({ error: "reference query param required" }, 400);

    // RLS on `payments` (select-only, tenant-scoped) means this simply
    // returns nothing if the reference doesn't belong to the caller's
    // tenant — no separate ownership check needed here.
    const { data: payment, error } = await supa.from("payments").select("*").eq("reference", reference).single();
    if (error || !payment) return json({ error: "Payment not found" }, 404);

    // Only an already-resolved payment short-circuits. PENDING is the live
    // "push sent, awaiting confirmation" state used by both payment paths, so
    // gating on QUEUED alone meant a PENDING payment — every successful STK
    // push — was reported as QUEUED forever and never re-queried.
    if (payment.sale_id || payment.status === "SUCCESS" || payment.status === "FAILED") {
      return json({ status: payment.status, sale_id: payment.sale_id });
    }

    // Still unresolved — ask PayHero directly rather than waiting
    // indefinitely for a webhook that may have been dropped. The comment at
    // the top of this file promises a "only after a few seconds" gate; this is
    // it, and without it every poll tick became a live provider request.
    const settledForMs = Date.now() - new Date(payment.created_at).getTime();
    if (settledForMs < 5_000) {
      return json({ status: payment.status });
    }

    const remote = await queryTransactionStatus(reference);
    if (remote.status === "SUCCESS" || remote.status === "FAILED") {
      const svc = serviceClient();
      if (remote.status === "SUCCESS") {
        const { data: saleId } = await svc.rpc("finalize_mpesa_sale", { p_payment_id: payment.id });
        return json({ status: "SUCCESS", sale_id: saleId });
      } else {
        await svc.rpc("mark_payment_failed", { p_payment_id: payment.id });
        return json({ status: "FAILED" });
      }
    }

    return json({ status: payment.status });
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders() },
  });
}
