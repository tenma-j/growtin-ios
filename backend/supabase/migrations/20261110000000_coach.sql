-- Coach IA : quotas, suivi des coûts et droits d'abonnement.
-- Aucune conversation ni donnée de santé n'est stockée côté serveur : seulement des compteurs.

create table if not exists public.coach_usage_daily (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null default (now() at time zone 'Europe/Paris')::date,
  requests integer not null default 0,
  input_tokens bigint not null default 0,
  output_tokens bigint not null default 0,
  cache_read_tokens bigint not null default 0,
  cache_write_tokens bigint not null default 0,
  cost_micros bigint not null default 0,
  primary key (user_id, day)
);

-- Droits Premium, alimentés plus tard par les webhooks RevenueCat.
create table if not exists public.entitlements (
  user_id uuid primary key references auth.users (id) on delete cascade,
  premium boolean not null default false,
  updated_at timestamptz not null default now()
);

-- Sécurité au niveau des lignes : l'app n'accède jamais directement à ces tables,
-- seule la fonction serveur (clé de service) les lit et les écrit.
alter table public.coach_usage_daily enable row level security;
alter table public.entitlements enable row level security;

-- Réserve une question si le quota du jour le permet (opération atomique).
create or replace function public.coach_consume(p_user uuid, p_limit integer)
returns table (allowed boolean, used integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := (now() at time zone 'Europe/Paris')::date;
  v_used integer;
begin
  insert into coach_usage_daily (user_id, day) values (p_user, v_day)
  on conflict (user_id, day) do nothing;

  update coach_usage_daily
     set requests = requests + 1
   where user_id = p_user and day = v_day and requests < p_limit
  returning requests into v_used;

  if v_used is null then
    select requests into v_used from coach_usage_daily where user_id = p_user and day = v_day;
    return query select false, v_used;
  else
    return query select true, v_used;
  end if;
end;
$$;

-- Enregistre la consommation de jetons et le coût estimé d'une réponse.
create or replace function public.coach_record_usage(
  p_user uuid, p_input bigint, p_output bigint, p_cache_read bigint, p_cache_write bigint, p_cost_micros bigint
) returns void
language sql
security definer
set search_path = public
as $$
  update coach_usage_daily
     set input_tokens = input_tokens + p_input,
         output_tokens = output_tokens + p_output,
         cache_read_tokens = cache_read_tokens + p_cache_read,
         cache_write_tokens = cache_write_tokens + p_cache_write,
         cost_micros = cost_micros + p_cost_micros
   where user_id = p_user and day = (now() at time zone 'Europe/Paris')::date;
$$;

revoke all on function public.coach_consume(uuid, integer) from public, anon, authenticated;
revoke all on function public.coach_record_usage(uuid, bigint, bigint, bigint, bigint, bigint) from public, anon, authenticated;

-- Vue de suivi des coûts (tableau de bord Supabase).
create or replace view public.coach_cost_by_day as
  select day, count(distinct user_id) as users, sum(requests) as requests,
         round(sum(cost_micros) / 1e6, 2) as cost_usd
    from coach_usage_daily group by day order by day desc;
revoke all on public.coach_cost_by_day from anon, authenticated;
