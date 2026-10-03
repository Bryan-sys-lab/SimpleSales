// Called once, when an owner enables M-Pesa (or eTIMS) for the first time
// and the app needs to register this shop with the backend. Must run with
// the service role because the normal profiles_insert_owner RLS policy
// requires is_owner() to already be true for the caller — which is
// impossible for the very first profile in a brand-new tenant. This
// function is the one deliberate, narrow exception to "RLS decides
// everything," and it only ever creates exactly one thing: a tenant plus
// exactly one owner profile pointing at the caller's own already-verified
// auth.users id. It cannot be used to create a profile for anyone else,
// or to join an existing tenant — see the checks below.
import { userClient, serviceClient, corsHeaders } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders() });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supa = userClient(authHeader);
    const { data: { user }, error: authErr } = await supa.auth.getUser();
    if (authErr || !user) return json({ error: "Not signed in" }, 401);

    const svc = serviceClient();

    // Refuse if this auth user already has a profile anywhere — provisioning
    // is strictly a one-time, first-run operation per Supabase account.
    const { data: existing } = await svc.from("profiles").select("id").eq("id", user.id).maybeSingle();
    if (existing) return json({ error: "This account is already linked to a shop" }, 409);

    const body = await req.json();
    const shopName: string = body.shop_name;
    const ownerName: string = body.owner_name;
    if (!shopName?.trim() || !ownerName?.trim()) {
      return json({ error: "shop_name and owner_name are required" }, 400);
    }

    const { data: tenant, error: tenantErr } = await svc.from("tenants")
      .insert({ shop_name: shopName.trim() }).select().single();
    if (tenantErr) return json({ error: tenantErr.message }, 500);

    const { error: profileErr } = await svc.from("profiles").insert({
      id: user.id, // the caller's own verified id — never anyone else's
      tenant_id: tenant.id,
      name: ownerName.trim(),
      // 'admin', not 'owner': this is the role vocabulary the enum, the RLS
      // policies and the Express API all use. Writing 'owner' here would
      // violate the enum and leave the new shop with no profile at all.
      role: "admin",
    });
    if (profileErr) {
      // Roll back the orphaned tenant rather than leaving a tenant with no owner.
      await svc.from("tenants").delete().eq("id", tenant.id);
      return json({ error: profileErr.message }, 500);
    }

    return json({ tenant_id: tenant.id });
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
