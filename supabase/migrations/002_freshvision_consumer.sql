create extension if not exists pgcrypto;

create table if not exists public.consumer_scans (
  id uuid primary key,
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
  installation_id uuid not null,
  vote text not null check (vote in ('good', 'not_good')),
  voted_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists consumer_scans_captured_at_idx on public.consumer_scans(captured_at desc);
create index if not exists consumer_scans_fruit_verdict_idx on public.consumer_scans(fruit, verdict);

alter table public.consumer_scans enable row level security;
alter table public.consumer_feedback enable row level security;

revoke all on public.consumer_scans from anon, authenticated;
revoke all on public.consumer_feedback from anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('consumer-scan-photos', 'consumer-scan-photos', false, 8388608, array['image/jpeg'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

comment on table public.consumer_scans is 'Private FreshVision consumer scans. Written only by service-role Edge Functions.';
comment on table public.consumer_feedback is 'Private post-purchase feedback. One current vote per scan.';
