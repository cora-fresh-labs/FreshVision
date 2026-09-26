create extension if not exists pgcrypto;

create table if not exists public.consumer_scans (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  installation_id uuid not null,
  captured_at timestamptz not null,
  photo_path text not null unique,
  capture_source text not null check (capture_source in ('iphone', 'meta_glasses', 'meta_ai_connector')),
  device_model text not null,
  analysis_status text not null check (analysis_status in ('captured', 'analyzing', 'complete', 'needs_retry')),
  fruit text check (fruit is null or fruit in ('banana', 'grapes', 'strawberries', 'avocado', 'apple')),
  verdict text check (verdict is null or verdict in (
    'Buy — ready now',
    'Buy — ripe in 2–3 days',
    'Skip — overripe',
    'Skip — underripe',
    'Skip — damaged'
  )),
  reason text,
  issue text check (issue is null or issue in ('no_fruit', 'multiple_fruits', 'poor_lighting', 'unsupported_fruit')),
  confidence double precision check (confidence is null or (confidence >= 0 and confidence <= 1)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.consumer_feedback (
  scan_id uuid primary key references public.consumer_scans(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  installation_id uuid not null,
  vote text not null check (vote in ('good', 'not_good')),
  voted_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists consumer_scans_captured_at_idx on public.consumer_scans(captured_at desc);
create index if not exists consumer_scans_fruit_verdict_idx on public.consumer_scans(fruit, verdict);
create index if not exists consumer_scans_owner_idx on public.consumer_scans(owner_id, captured_at desc);

create table if not exists public.consumer_rate_limits (
  key_hash text primary key,
  request_count integer not null,
  resets_at timestamptz not null,
  updated_at timestamptz not null default now()
);

alter table public.consumer_scans enable row level security;
alter table public.consumer_feedback enable row level security;
alter table public.consumer_rate_limits enable row level security;

revoke all on public.consumer_scans from anon, authenticated;
revoke all on public.consumer_feedback from anon, authenticated;
revoke all on public.consumer_rate_limits from anon, authenticated;

create or replace function public.consume_consumer_rate_limit(
  p_key_hash text,
  p_limit integer,
  p_window_seconds integer
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  allowed boolean;
begin
  insert into public.consumer_rate_limits as limits (
    key_hash, request_count, resets_at, updated_at
  ) values (
    p_key_hash, 1, now() + make_interval(secs => p_window_seconds), now()
  )
  on conflict (key_hash) do update set
    request_count = case
      when limits.resets_at <= now() then 1
      else limits.request_count + 1
    end,
    resets_at = case
      when limits.resets_at <= now() then now() + make_interval(secs => p_window_seconds)
      else limits.resets_at
    end,
    updated_at = now()
  returning request_count <= p_limit into allowed;
  return allowed;
end;
$$;

revoke all on function public.consume_consumer_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.consume_consumer_rate_limit(text, integer, integer) to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('consumer-scan-photos', 'consumer-scan-photos', false, 8388608, array['image/jpeg'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

comment on table public.consumer_scans is 'Private FreshVision consumer scans. Written only by service-role Edge Functions.';
comment on table public.consumer_feedback is 'Private post-purchase feedback. One current vote per scan.';
comment on table public.consumer_rate_limits is 'Service-only fixed-window limits for FreshVision Edge Functions.';
