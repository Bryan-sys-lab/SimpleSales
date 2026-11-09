-- finalize_mpesa_sale: called only from the payhero-callback Edge Function
-- (via the service role, which bypasses RLS) once PayHero has confirmed a
-- payment as SUCCESS. This is where an M-Pesa payment actually becomes a
-- sale — stock is untouched until money is genuinely confirmed received,
-- unlike a cash sale where confirmation is immediate at the till.
--
-- Idempotent on purpose: PayHero (like most payment providers) may deliver
-- the same callback more than once. If this function is called twice for the
-- same payment, the second call is a safe no-op rather than double
-- selling the same cart.
--
-- The cart contract matches `src/routes/payment.ts`: each snapshot line
-- carries `portion`, `portion_ml` and the portion-weighted `stock_units`, and
-- prices were already resolved server-side when the payment was initiated.
-- Stock is accumulated per product, because one bottle may legitimately be
-- sold as a full bottle and a half bottle in the same basket.
create or replace function finalize_mpesa_sale(p_payment_id uuid)
returns uuid -- returns the sale id
language plpgsql security definer set search_path = public
as $$
declare
  v_payment payments%rowtype;
  v_item jsonb;
  v_sale_id uuid;
  v_total numeric(12,2) := 0;
  v_profit numeric(12,2) := 0;
  v_cost numeric(12,2);
  v_product_id uuid;
  v_qty numeric;
  v_needed numeric;
  v_available numeric;
begin
  select * into v_payment from payments where id = p_payment_id for update;

  -- `found` is the reliable test here: a composite variable is only "null" when
  -- every field is null, which is not the same statement as "no row matched".
  if not found then
    raise exception 'Payment % not found', p_payment_id;
  end if;

  if v_payment.sale_id is not null then
    return v_payment.sale_id; -- already finalized — idempotent replay
  end if;

  -- Verify stock and compute totals before writing anything, so a
  -- short-stock item fails the whole thing rather than partially applying.
  -- The tenant_id predicate is what keeps one shop from decrementing another
  -- shop's catalogue: `cart_snapshot` is a service-role write, so nothing
  -- upstream constrains the product ids it names to this payment's tenant.
  for v_item in select * from jsonb_array_elements(v_payment.cart_snapshot)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := coalesce((v_item->>'qty')::numeric, 0);

    select cost_price into v_cost
      from products
      where id = v_product_id
        and tenant_id = v_payment.tenant_id
      for update;

    if v_cost is null then
      raise exception 'Product unavailable: %', v_item->>'product_name';
    end if;

    v_total := v_total + v_qty * (v_item->>'unit_price')::numeric;
    v_profit := v_profit + v_qty * ((v_item->>'unit_price')::numeric - v_cost);
  end loop;

  -- Accumulate the units each product must give up, so a basket holding a
  -- full and a half of the same bottle is checked and decremented once.
  for v_product_id, v_needed in
    select (line->>'product_id')::uuid,
           sum(coalesce((line->>'stock_units')::numeric, (line->>'qty')::numeric))
    from jsonb_array_elements(v_payment.cart_snapshot) as item(line)
    group by (line->>'product_id')::uuid
  loop
    select stock_qty into v_available
      from products
      where id = v_product_id and tenant_id = v_payment.tenant_id
      for update;

    if v_available is null or v_available < v_needed then
      raise exception 'Insufficient stock for product %', v_product_id;
    end if;
  end loop;

  insert into sales (tenant_id, staff_id, staff_name, payment_method, payment_reference, total, profit)
    values (v_payment.tenant_id, v_payment.initiated_by, v_payment.staff_name, 'mpesa', v_payment.reference, v_total, v_profit)
    returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(v_payment.cart_snapshot)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    insert into sale_items (tenant_id, sale_id, product_id, product_name, qty, unit_price, unit_cost, portion, portion_ml)
      values (
        v_payment.tenant_id, v_sale_id, v_product_id, v_item->>'product_name',
        coalesce((v_item->>'qty')::numeric, 0), (v_item->>'unit_price')::numeric, (v_item->>'unit_cost')::numeric,
        coalesce(v_item->>'portion', 'full'), coalesce((v_item->>'portion_ml')::integer, 0)
      );
    update products
      set stock_qty = stock_qty - coalesce((v_item->>'stock_units')::numeric, (v_item->>'qty')::numeric),
          updated_at = now()
      where id = v_product_id and tenant_id = v_payment.tenant_id;
  end loop;

  update payments set status = 'SUCCESS', sale_id = v_sale_id, updated_at = now()
    where id = p_payment_id;

  return v_sale_id;
end;
$$;

-- Called by the same callback function when PayHero reports FAILED, purely
-- to keep payments.status accurate for the app's polling/UI — no sale or
-- stock change happens on this path.
create or replace function mark_payment_failed(p_payment_id uuid)
returns void
language sql security definer set search_path = public
as $$
  update payments set status = 'FAILED', updated_at = now()
    where id = p_payment_id and sale_id is null;
$$;

-- ---------------------------------------------------------------------------
-- Execute permissions.
--
-- Both functions above are SECURITY DEFINER in the `public` schema, and
-- PostgreSQL grants EXECUTE on a new function to PUBLIC by default. PostgREST
-- therefore exposed them to `anon` and `authenticated` — meaning any client
-- could POST /rest/v1/rpc/finalize_mpesa_sale with a payment id it could read
-- through the `payments_select` policy, mark the payment SUCCESS and book a
-- sale with no money having moved. RLS does not help: SECURITY DEFINER runs
-- as the function owner, so the policies never apply.
--
-- Locking them to the service role is the point of the comment at the top of
-- this file: only the callback, which holds a verified provider response,
-- should ever be able to turn a payment into a sale.
-- ---------------------------------------------------------------------------
revoke execute on function finalize_mpesa_sale(uuid) from public;
revoke execute on function mark_payment_failed(uuid) from public;
revoke execute on function finalize_mpesa_sale(uuid) from anon, authenticated;
revoke execute on function mark_payment_failed(uuid) from anon, authenticated;
grant execute on function finalize_mpesa_sale(uuid) to service_role;
grant execute on function mark_payment_failed(uuid) to service_role;
