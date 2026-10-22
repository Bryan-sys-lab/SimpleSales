// The public URL PayHero POSTs to when a payment's status changes. This
// endpoint has to be reachable with no Supabase user session attached —
// PayHero isn't one of your users — which is exactly why its contents
// can't be trusted at face value: anyone who discovers this URL could POST
// a fake "SUCCESS" body to it. Because I could not verify PayHero's exact
// webhook signing/authentication scheme from their public docs, this
// handler treats the webhook purely as a trigger to go check the real
// status directly with PayHero's own transaction-status endpoint (using
// our server-held credentials) — the webhook body's own claims are never
// what finalizes a sale. Confirm PayHero's current signing method in your
// dashboard/docs before launch and tighten this further if one exists
// (e.g. verifying a signature header), rather than relying on this
// verify-by-requery approach alone long-term.
import { serviceClient, corsHeaders } from "../_shared/supabase.ts";
import { queryTransactionStatus } from "../_shared/payhero.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders() });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  try {
    const body = await req.json().catch(() => ({}));
    const reference: string | undefined = body?.reference ?? body?.external_reference;
    if (!reference) {
      // Nothing usable to act on — acknowledge so PayHero doesn't keep
      // retrying a malformed callback forever, but do nothing state-changing.
      return new Response("ok", { status: 200, headers: corsHeaders() });
    }

    const svc = serviceClient();
    const { data: payment } = await svc.from("payments").select("*").eq("reference", reference).single();
    if (!payment) return new Response("ok", { status: 200, headers: corsHeaders() }); // unknown reference, ignore
    // "Already done" is `sale_id is set`, not "status is not QUEUED". Both
    // payment paths move a payment to PENDING the moment the STK push lands,
    // so the old `status !== 'QUEUED'` guard short-circuited every real
    // payment created by the Express API: the webhook returned early and
    // polling never re-queried, so a paid basket produced no sale and no
    // stock decrement.
    if (payment.sale_id || payment.status === "SUCCESS" || payment.status === "FAILED") {
      return new Response("ok", { status: 200, headers: corsHeaders() }); // already resolved, idempotent no-op
    }

    // The re-query against PayHero directly (not the webhook body) is what
    // actually decides the outcome.
    const remote = await queryTransactionStatus(reference);

    if (remote.status === "SUCCESS") {
      await svc.rpc("finalize_mpesa_sale", { p_payment_id: payment.id });
    } else if (remote.status === "FAILED") {
      await svc.rpc("mark_payment_failed", { p_payment_id: payment.id });
    }
    // If still QUEUED even after re-querying, leave it — the polling
    // endpoint or a later callback delivery will resolve it.

    return new Response("ok", { status: 200, headers: corsHeaders() });
  } catch (e) {
    console.error("payhero-callback error:", e);
    // Return 200 anyway: a 5xx here causes PayHero to retry-storm an
    // endpoint that's failing for a reason retrying won't fix (e.g. a bug),
    // which just adds noise. Errors are logged for the developer instead.
    return new Response("ok", { status: 200, headers: corsHeaders() });
  }
});
