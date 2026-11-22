create extension if not exists pgcrypto;

create table if not exists public.users (
  id uuid primary key default gen_random_uuid(), auth_user_id uuid not null unique, auth_email text not null unique,
  name text not null check (char_length(name) between 2 and 80), role text not null check (role in ('admin','cashier')),
  active boolean not null default true, archived_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(), name text not null unique, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(), barcode text not null unique, name text not null, category_id uuid references public.categories(id),
  cost_minor bigint not null check (cost_minor >= 0), price_minor bigint not null check (price_minor >= 0), stock_qty integer not null check (stock_qty >= 0),
  current_version_id uuid, archived_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.product_versions (
  id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id), cost_minor bigint not null check (cost_minor >= 0),
  price_minor bigint not null check (price_minor >= 0), created_by uuid references public.users(id), created_at timestamptz not null default now()
);
alter table public.products drop constraint if exists products_current_version_id_fkey;
alter table public.products add constraint products_current_version_id_fkey foreign key (current_version_id) references public.product_versions(id);
create table if not exists public.shifts (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.users(id), device_id text not null,
  opened_at timestamptz not null default now(), closed_at timestamptz, offline_authorized_until timestamptz not null,
  opening_cash_minor bigint not null check (opening_cash_minor >= 0), expected_cash_minor bigint, actual_cash_minor bigint, difference_minor bigint,
  close_operation_id uuid unique, status text not null default 'open' check (status in ('open','closed'))
);
create unique index if not exists shifts_one_open_store_idx on public.shifts ((status)) where status='open';
create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(), operation_id uuid not null unique, request_hash text not null, reference text not null unique,
  shift_id uuid not null references public.shifts(id), user_id uuid not null references public.users(id), total_minor bigint not null check (total_minor >= 0),
  cost_minor bigint not null check (cost_minor >= 0), profit_minor bigint not null, payment_method text not null check (payment_method in ('cash','card')),
  tendered_minor bigint, change_minor bigint, occurred_at timestamptz not null, received_at timestamptz not null default now(),
  reversed_at timestamptz, reversed_by uuid references public.users(id), reversal_reason text, reversal_shift_id uuid references public.shifts(id)
);
create index if not exists sales_occurred_idx on public.sales(occurred_at desc);
create index if not exists sales_user_occurred_idx on public.sales(user_id,occurred_at desc);
create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(), sale_id uuid not null references public.sales(id), product_id uuid not null references public.products(id),
  product_version_id uuid not null references public.product_versions(id), product_name text not null, qty integer not null check (qty > 0),
  unit_price_minor bigint not null check (unit_price_minor >= 0), unit_cost_minor bigint not null check (unit_cost_minor >= 0)
);
create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id), sale_id uuid references public.sales(id),
  quantity_delta integer not null check (quantity_delta <> 0), reason text not null, actor_id uuid not null references public.users(id), created_at timestamptz not null default now()
);
create table if not exists public.login_attempts (
  staff_id uuid not null references public.users(id) on delete cascade, ip_hash text not null, failed_count integer not null default 0,
  locked_until timestamptz, last_failed_at timestamptz not null default now(), primary key(staff_id,ip_hash)
);

alter table public.users enable row level security; alter table public.categories enable row level security; alter table public.products enable row level security;
alter table public.product_versions enable row level security; alter table public.shifts enable row level security; alter table public.sales enable row level security;
alter table public.sale_items enable row level security; alter table public.stock_movements enable row level security; alter table public.login_attempts enable row level security;

revoke all on public.users,public.categories,public.products,public.product_versions,public.shifts,public.sales,public.sale_items,public.stock_movements,public.login_attempts from anon,authenticated;
grant select on public.users,public.categories,public.products,public.product_versions,public.shifts,public.sales,public.sale_items,public.stock_movements to authenticated;
drop policy if exists "staff read active profiles" on public.users; create policy "staff read active profiles" on public.users for select to authenticated using (active);
drop policy if exists "staff read categories" on public.categories; create policy "staff read categories" on public.categories for select to authenticated using (true);
drop policy if exists "staff read products" on public.products; create policy "staff read products" on public.products for select to authenticated using (true);
drop policy if exists "staff read versions" on public.product_versions; create policy "staff read versions" on public.product_versions for select to authenticated using (true);
drop policy if exists "staff read own shifts" on public.shifts; create policy "staff read own shifts" on public.shifts for select to authenticated using (user_id=auth.uid() or exists(select 1 from public.users u where u.id=auth.uid() and u.role='admin'));
drop policy if exists "staff read own sales" on public.sales; create policy "staff read own sales" on public.sales for select to authenticated using (user_id=auth.uid() or exists(select 1 from public.users u where u.id=auth.uid() and u.role='admin'));
drop policy if exists "staff read own sale items" on public.sale_items; create policy "staff read own sale items" on public.sale_items for select to authenticated using (exists(select 1 from public.sales s where s.id=sale_id and (s.user_id=auth.uid() or exists(select 1 from public.users u where u.id=auth.uid() and u.role='admin'))));
drop policy if exists "staff read stock movements" on public.stock_movements; create policy "staff read stock movements" on public.stock_movements for select to authenticated using (true);

create or replace function public.record_sale_v1(p_operation_id uuid,p_shift_id uuid,p_staff_id uuid,p_occurred_at timestamptz,p_payment_method text,p_tendered_minor bigint,p_items jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_sale public.sales%rowtype; v_item jsonb; v_product public.products%rowtype; v_version public.product_versions%rowtype; v_total bigint:=0;v_cost bigint:=0;v_hash text;v_id uuid:=gen_random_uuid();v_reference text;
begin
  if p_payment_method not in ('cash','card') or jsonb_array_length(p_items)=0 then raise exception 'Invalid sale'; end if;
  v_hash:=encode(digest((jsonb_build_object('shift',p_shift_id,'staff',p_staff_id,'occurred',p_occurred_at,'payment',p_payment_method,'tendered',p_tendered_minor,'items',p_items))::text,'sha256'),'hex');
  select * into v_sale from public.sales where operation_id=p_operation_id;
  if found then if v_sale.request_hash<>v_hash then raise exception 'Operation ID was already used with different content'; end if; return jsonb_build_object('id',v_sale.id,'reference',v_sale.reference,'total_minor',v_sale.total_minor); end if;
  perform 1 from public.users where id=p_staff_id and active; if not found then raise exception 'Inactive staff'; end if;
  perform 1 from public.shifts where id=p_shift_id and user_id=p_staff_id and status='open' and offline_authorized_until>=p_occurred_at for update; if not found then raise exception 'Shift is not open or offline authorization expired'; end if;
  for v_item in select * from jsonb_array_elements(p_items) loop
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and archived_at is null for update; if not found then raise exception 'Product unavailable'; end if;
    select * into v_version from public.product_versions where id=(v_item->>'version_id')::uuid and product_id=v_product.id; if not found then raise exception 'Catalog version conflict'; end if;
    if (v_item->>'qty')::integer<=0 or v_product.stock_qty<(v_item->>'qty')::integer then raise exception 'Insufficient stock for %',v_product.name; end if;
    if v_version.price_minor<>(v_item->>'unit_price_minor')::bigint or v_version.cost_minor<>(v_item->>'unit_cost_minor')::bigint then raise exception 'Catalog price conflict'; end if;
    v_total:=v_total+v_version.price_minor*(v_item->>'qty')::integer;v_cost:=v_cost+v_version.cost_minor*(v_item->>'qty')::integer;
  end loop;
  if p_payment_method='cash' and coalesce(p_tendered_minor,0)<v_total then raise exception 'Tendered cash is less than total'; end if;
  v_reference:='HM-'||upper(substr(replace(p_operation_id::text,'-',''),1,8));
  insert into public.sales(id,operation_id,request_hash,reference,shift_id,user_id,total_minor,cost_minor,profit_minor,payment_method,tendered_minor,change_minor,occurred_at) values(v_id,p_operation_id,v_hash,v_reference,p_shift_id,p_staff_id,v_total,v_cost,v_total-v_cost,p_payment_method,p_tendered_minor,case when p_payment_method='cash' then p_tendered_minor-v_total end,p_occurred_at);
  for v_item in select * from jsonb_array_elements(p_items) loop
    select * into v_version from public.product_versions where id=(v_item->>'version_id')::uuid;
    insert into public.sale_items(sale_id,product_id,product_version_id,product_name,qty,unit_price_minor,unit_cost_minor) values(v_id,(v_item->>'product_id')::uuid,v_version.id,v_item->>'product_name',(v_item->>'qty')::integer,v_version.price_minor,v_version.cost_minor);
    update public.products set stock_qty=stock_qty-(v_item->>'qty')::integer,updated_at=now() where id=(v_item->>'product_id')::uuid;
    insert into public.stock_movements(product_id,sale_id,quantity_delta,reason,actor_id) values((v_item->>'product_id')::uuid,v_id,-(v_item->>'qty')::integer,'sale',p_staff_id);
  end loop;
  return jsonb_build_object('id',v_id,'reference',v_reference,'total_minor',v_total,'change_minor',case when p_payment_method='cash' then p_tendered_minor-v_total end);
end$$;

create or replace function public.close_shift_v1(p_shift_id uuid,p_staff_id uuid,p_actual_cash_minor bigint,p_operation_id uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$ declare v public.shifts%rowtype;v_expected bigint;begin
  select * into v from public.shifts where id=p_shift_id for update;if not found then raise exception 'Shift not found';end if;
  if v.status='closed' then if v.close_operation_id=p_operation_id then return to_jsonb(v);else raise exception 'Shift already closed';end if;end if;
  if v.user_id<>p_staff_id then raise exception 'Shift belongs to another user';end if;
  select v.opening_cash_minor+coalesce(sum(total_minor),0) into v_expected from public.sales where shift_id=v.id and payment_method='cash' and reversed_at is null;
  update public.shifts set status='closed',closed_at=now(),expected_cash_minor=v_expected,actual_cash_minor=p_actual_cash_minor,difference_minor=p_actual_cash_minor-v_expected,close_operation_id=p_operation_id where id=v.id returning * into v;return to_jsonb(v);
end$$;

create or replace function public.reverse_sale_v1(p_sale_id uuid,p_admin_id uuid,p_shift_id uuid,p_reason text)
returns jsonb language plpgsql security invoker set search_path='' as $$declare v public.sales%rowtype;i public.sale_items%rowtype;begin
  perform 1 from public.users where id=p_admin_id and role='admin' and active;if not found then raise exception 'Administrator required';end if;
  select * into v from public.sales where id=p_sale_id for update;if not found or v.reversed_at is not null then raise exception 'Sale unavailable';end if;
  perform 1 from public.shifts where id=p_shift_id and status='open' for update;if not found then raise exception 'An open shift is required';end if;
  for i in select * from public.sale_items where sale_id=v.id loop update public.products set stock_qty=stock_qty+i.qty where id=i.product_id;insert into public.stock_movements(product_id,sale_id,quantity_delta,reason,actor_id)values(i.product_id,v.id,i.qty,'sale reversal: '||p_reason,p_admin_id);end loop;
  update public.sales set reversed_at=now(),reversed_by=p_admin_id,reversal_reason=p_reason,reversal_shift_id=p_shift_id where id=v.id returning * into v;return to_jsonb(v);
end$$;

create or replace function public.dashboard_summary_v1(p_staff_id uuid,p_admin boolean)
returns jsonb language sql security invoker set search_path='' stable as $$
with bounds as(select date_trunc('day',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca' d,date_trunc('week',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca' w,date_trunc('month',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca' m),base as(select * from public.sales where reversed_at is null and (p_admin or user_id=p_staff_id)),agg as(select coalesce(sum(total_minor)filter(where occurred_at>=d),0) rt,coalesce(sum(total_minor)filter(where occurred_at>=w),0) rw,coalesce(sum(total_minor)filter(where occurred_at>=m),0) rm,coalesce(sum(profit_minor)filter(where occurred_at>=d),0) pt,coalesce(sum(profit_minor)filter(where occurred_at>=w),0) pw,coalesce(sum(profit_minor)filter(where occurred_at>=m),0) pm from base,bounds)
select jsonb_build_object('revenue',jsonb_build_object('today',rt,'week',rw,'month',rm),'profit',jsonb_build_object('today',pt,'week',pw,'month',pm),'earnings',jsonb_build_object('today',round(pt/3.0),'week',round(pw/3.0),'month',round(pm/3.0)),'low_stock',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('version_id',p.current_version_id))from public.products p where p.archived_at is null and p.stock_qty<=5),'[]'::jsonb),'recent_sales',coalesce((select jsonb_agg(x)from(select jsonb_build_object('id',s.id,'operation_id',s.operation_id,'reference',s.reference,'shift_id',s.shift_id,'user_id',s.user_id,'cashier_name',u.name,'items','[]'::jsonb,'total_minor',s.total_minor,'payment_method',s.payment_method,'occurred_at',s.occurred_at,'pending',false) x from base s join public.users u on u.id=s.user_id order by s.occurred_at desc limit 10)q),'[]'::jsonb),'shifts','[]'::jsonb)from agg;
$$;

revoke execute on function public.record_sale_v1(uuid,uuid,uuid,timestamptz,text,bigint,jsonb),public.close_shift_v1(uuid,uuid,bigint,uuid),public.reverse_sale_v1(uuid,uuid,uuid,text),public.dashboard_summary_v1(uuid,boolean) from public,anon,authenticated;
grant execute on function public.record_sale_v1(uuid,uuid,uuid,timestamptz,text,bigint,jsonb),public.close_shift_v1(uuid,uuid,bigint,uuid),public.reverse_sale_v1(uuid,uuid,uuid,text),public.dashboard_summary_v1(uuid,boolean) to service_role;

do $$begin alter publication supabase_realtime add table public.products,public.categories,public.shifts,public.sales;exception when duplicate_object then null;end$$;
