import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/// Client using the caller's own JWT (from the Authorization header the
/// Flutter app sends). Respects RLS exactly as if the query came from the
/// app directly — used to confirm the caller belongs to the tenant they
/// claim before we do anything on their behalf.
export function userClient(authHeader: string) {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
}

/// Client using the service role key, which bypasses RLS entirely. Only
/// ever used for the specific writes that must cross tenant/role boundaries
/// in a controlled way — e.g. the callback finalizing a sale from a payment
/// that was initiated by a different request. Never expose this key to the
/// Flutter app; it lives only as a Supabase secret on these functions.
export function serviceClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

export function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}
