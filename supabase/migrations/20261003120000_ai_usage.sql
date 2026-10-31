-- Per-user usage log so the gemini-proxy Edge Function can rate limit.
-- Row level security is on with no policies: only the service role
-- (the Edge Function) can read or write this table.
create table public.ai_usage (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  kind        text not null check (kind in ('chat', 'diagnose')),
  created_at  timestamptz not null default now()
);

create index ai_usage_user_kind_idx on public.ai_usage (user_id, kind, created_at desc);

alter table public.ai_usage enable row level security;
