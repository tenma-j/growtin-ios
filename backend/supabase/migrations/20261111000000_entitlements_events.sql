-- Droits Premium alimentés par le webhook RevenueCat, en ignorant les événements arrivés dans le désordre.
alter table public.entitlements add column if not exists last_event_ms bigint not null default 0;

create or replace function public.apply_entitlement(p_user uuid, p_premium boolean, p_event_ms bigint)
returns void
language sql
security definer
set search_path = public
as $$
  insert into entitlements (user_id, premium, last_event_ms, updated_at)
  select p_user, p_premium, p_event_ms, now()
  where exists (select 1 from auth.users where id = p_user)
  on conflict (user_id) do update
    set premium = excluded.premium, last_event_ms = excluded.last_event_ms, updated_at = now()
    where entitlements.last_event_ms <= excluded.last_event_ms;
$$;

revoke all on function public.apply_entitlement(uuid, boolean, bigint) from public, anon, authenticated;
