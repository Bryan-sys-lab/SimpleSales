// Called by the Flutter app when the cashier picks "M-Pesa" at checkout.
// This is the ONLY place the PayHero credentials are used to start a
// payment — the app never talks to PayHero directly, so the credentials
// never need to exist anywhere the app's compiled code could expose them.
import { userClient, serviceClient, corsHeaders } from "../_shared/supabase.ts";
import { initiateStkPush } from "../_shared/payhero.ts";

/// A cart line as the client sends it. `unit_price`/`unit_cost` are accepted so
/// an older till build does not break, but they are never trusted — see
/// `priceCart` below.
interface CartItem {
  product_id: string;
  product_name: string;
  qty: number;
  portion?: "full" | "half" | "quarter";
  unit_price?: number;
  unit_cost?: number;
}

/// One priced line, as stored in `payments.cart_snapshot`.
interface PricedCartItem {
  product_id: string;
  product_name: string;
  qty: number;
  portion: "full" | "half" | "quarter";
  portion_ml: number;
  stock_units: number;
  unit_price: number;
  unit_cost: number;
}

function portionFactor(portion: string) {
  return portion === "half" ? 0.5 : portion === "quarter" ? 0.25 : 1;
}

/// Re-prices the cart from the database and returns the lines plus the total.
///
/// The client's `unit_price` is untrusted input: summing it directly let a
/// caller push an STK for KES 1 and have the sale booked — and the profit
/// recorded — at that price, so a real basket of stock could be sold for
/// nothing. Prices, portion math and cost all come from `products`, exactly as
/// the Express `/api/payments/initiate` route does.
function priceCart(
  items: CartItem[],
  products: Array<Record<string, unknown>>,
): { lines: PricedCartItem[]; total: number } {
  const byId = new Map(
    products.map((product) => [String(product.id), product]),
  );
  const lines: PricedCartItem[] = [];
  for (const item of items) {
    const product = byId.get(item.product_id);
    if (!product) {
      throw new Error(`Product unavailable: ${item.product_name}`);
    }
    const portion = item.portion ?? "full";
    const factor = portionFactor(portion);
    const qty = Number(item.qty);
    if (!Number.isFinite(qty) || qty <= 0) {
      throw new Error("Quantity must be greater than zero");
    }
    const sellPrice = Number(product.sell_price);
    const halfPrice = product.half_price == null
      ? sellPrice / 2
      : Number(product.half_price);
    const quarterPrice = product.quarter_price == null
      ? sellPrice / 4
      : Number(product.quarter_price);
    const unitPrice = portion === "half"
      ? halfPrice
      : portion === "quarter"
      ? quarterPrice
      : sellPrice;
    lines.push({
      product_id: String(product.id),
      product_name: String(product.name),
      qty,
      portion: portion as PricedCartItem["portion"],
      portion_ml: Math.round(Number(product.bottle_ml ?? 750) * factor),
      stock_units: qty * factor,
      unit_price: unitPrice,
      unit_cost: Number(product.cost_price) * factor,
    });
  }
  return {
    lines,
    total: lines.reduce((sum, line) => sum + line.qty * line.unit_price, 0),
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders() });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supa = userClient(authHeader);

    // Confirms the caller is a real signed-in user with a profile — this is
    // what stops someone without valid credentials from reaching this
    // function at all, before any tenant-specific logic runs.
    const { data: { user }, error: authErr } = await supa.auth.getUser();
    if (authErr || !user) {
      return json({ error: "Not signed in" }, 401);
    }

    const { data: profile, error: profileErr } = await supa
      .from("profiles").select("tenant_id, active").eq("id", user.id).single();
    if (profileErr || !profile || !profile.active) {
      return json({ error: "No active profile for this account" }, 403);
    }

    const { data: tenant, error: tenantErr } = await supa
      .from("tenants").select("mpesa_enabled, payhero_channel_id, payhero_credential_id, shop_name")
      .eq("id", profile.tenant_id).single();
    if (tenantErr || !tenant) return json({ error: "Tenant not found" }, 404);
    if (!tenant.mpesa_enabled) {
      return json({ error: "M-Pesa is not enabled for this shop. Turn it on in Settings first." }, 400);
    }
    if (!tenant.payhero_channel_id) {
      return json({ error: "PayHero channel ID is not configured in Settings." }, 400);
    }

    const body = await req.json();
    const items: CartItem[] = Array.isArray(body.items) ? body.items : [];
    const phoneNumber: string = body.phone_number;
    if (!items.length || !phoneNumber) {
      return json({ error: "items and phone_number are required" }, 400);
    }

    // The cashier label is resolved server-side from the caller's own profile.
    // Taking it from the request body put an attacker-chosen string — or a raw
    // tenant UUID, which is what the old `?? profile.tenant_id` fallback
    // produced — onto the financial ledger that reports and cashier-deletion
    // attribution are keyed on.
    const { data: staffRow, error: staffErr } = await supa
      .from("profiles").select("name").eq("id", user.id).single();
    if (staffErr || !staffRow?.name) {
      return json({ error: "Could not resolve the cashier for this account" }, 403);
    }
    const staffName: string = staffRow.name;

    // Load the tenant's own products and price the cart server-side.
    const productIds = [...new Set(items.map((item) => item.product_id))];
    const { data: products, error: productErr } = await supa
      .from("products")
      .select("id, name, cost_price, sell_price, half_price, quarter_price, bottle_ml, stock_qty")
      .in("id", productIds)
      .eq("active", true);
    if (productErr) return json({ error: productErr.message }, 500);
    if (!products || products.length !== productIds.length) {
      return json({ error: "One or more products are unavailable" }, 400);
    }

    let cart;
    let total: number;
    try {
      // One product can appear under several portions, so availability is
      // accumulated across the whole basket, not per line.
      const requested = new Map<string, number>();
      for (const line of items) {
        const portion = line.portion ?? "full";
        const units = Number(line.qty) * portionFactor(portion);
        requested.set(line.product_id, (requested.get(line.product_id) ?? 0) + units);
      }
      for (const [id, units] of requested) {
        const product = products.find((row) => String(row.id) === id)!;
        if (Number(product.stock_qty) < units) {
          return json({ error: `Insufficient stock for ${product.name}` }, 409);
        }
      }
      const priced = priceCart(items, products as Array<Record<string, unknown>>);
      cart = priced.lines;
      total = priced.total;
    } catch (err) {
      return json({ error: (err as Error).message }, 400);
    }

    const reference = crypto.randomUUID();
    const functionsBase = Deno.env.get("SUPABASE_URL")!.replace(".supabase.co", ".functions.supabase.co");

    // Written with the service role because a `payments` row spans exactly
    // one write path (this function + the callback) that isn't a normal
    // user CRUD operation — RLS only grants SELECT on payments to end users
    // by design (see 0002_rls.sql), so INSERT has to go through here.
    const svc = serviceClient();
    const { data: payment, error: insertErr } = await svc.from("payments").insert({
      tenant_id: profile.tenant_id,
      initiated_by: user.id,
      staff_name: staffName,
      reference,
      phone_number: phoneNumber,
      amount: total,
      status: "QUEUED",
      cart_snapshot: cart,
    }).select().single();
    if (insertErr) return json({ error: insertErr.message }, 500);

    try {
      const stk = await initiateStkPush({
        amount: total,
        phoneNumber,
        channelId: tenant.payhero_channel_id,
        externalReference: reference,
        customerName: body.customer_name,
        callbackUrl: `${functionsBase}/payhero-callback`,
        credentialId: tenant.payhero_credential_id ?? undefined,
      });
      if (stk.checkoutRequestId) {
        // Matches the Express route: the push is in flight, so the row leaves
        // QUEUED. `0001_schema.sql` permits PENDING for exactly this state.
        await svc.from("payments").update({ status: "PENDING", checkout_request_id: stk.checkoutRequestId }).eq("id", payment.id);
      }
    } catch (stkErr) {
      await svc.from("payments").update({ status: "FAILED" }).eq("id", payment.id);
      return json({ error: `Could not reach PayHero: ${(stkErr as Error).message}`, reference }, 502);
    }

    return json({ reference, payment_id: payment.id, amount: total });
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
