-- =====================================================================
-- CoopIQ Supabase schema
-- Run once in the Supabase SQL editor on a fresh project.
-- Auth itself (signup, login, sessions) is handled by Supabase Auth in
-- the auth schema. This file builds everything the app needs on top of it.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0. Extensions
-- ---------------------------------------------------------------------
create extension if not exists pgcrypto;
create extension if not exists vector with schema extensions;


-- ---------------------------------------------------------------------
-- 1. Enums
-- ---------------------------------------------------------------------
create type public.user_role         as enum ('farmer', 'agrovet', 'admin');
create type public.farmer_segment    as enum ('smallholder_poultry', 'commercial_poultry', 'livestock', 'other');
create type public.farm_type         as enum ('poultry', 'livestock', 'both');
create type public.flock_type        as enum ('broiler', 'layer', 'village', 'other');
create type public.flock_status      as enum ('active', 'closed');
create type public.diagnosis_subject as enum ('poultry_droppings', 'poultry_bird', 'cattle', 'goat_sheep', 'pig');
create type public.confidence_level  as enum ('high', 'medium', 'low');
create type public.request_status    as enum ('pending', 'contacted', 'scheduled', 'completed', 'cancelled');
create type public.urgency_level     as enum ('standard', 'urgent');
create type public.visit_reason      as enum ('immunization', 'treatment', 'follow_up', 'other');
create type public.chat_role         as enum ('user', 'assistant');


-- ---------------------------------------------------------------------
-- 2. Generic updated_at trigger
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;


-- ---------------------------------------------------------------------
-- 3. Profiles (one row per auth user)
-- ---------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null default '',
  email       text,
  phone       text,
  role        public.user_role not null default 'farmer',
  segment     public.farmer_segment,
  language    text not null default 'English'
              check (language in ('English', 'Nyanja', 'Bemba', 'Lozi', 'Tonga')),
  country     text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Role helpers. SECURITY DEFINER so policies can read profiles without
-- recursing into the profiles policies.
create or replace function public.my_role()
returns public.user_role
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.profiles where id = (select auth.uid());
$$;

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.my_role() in ('agrovet', 'admin'), false);
$$;

-- Create a profile automatically whenever someone signs up (email, phone or OAuth).
-- Pass full_name, phone and language as user metadata from the Flutter signUp call.
-- The role is never read from metadata, so nobody can sign up as an agrovet or admin.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, email, phone, language)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.email,
    coalesce(nullif(new.phone, ''), new.raw_user_meta_data ->> 'phone'),
    case
      when new.raw_user_meta_data ->> 'language' in ('English', 'Nyanja', 'Bemba', 'Lozi', 'Tonga')
        then new.raw_user_meta_data ->> 'language'
      else 'English'
    end
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Only admins can change roles. Changes made from the SQL editor or with the
-- service role key (no auth.uid()) are allowed, which is how you promote the first
-- agrovet or admin.
create or replace function public.guard_profile_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role is distinct from old.role
     and (select auth.uid()) is not null
     and coalesce(public.my_role(), 'farmer') <> 'admin' then
    raise exception 'Only admins can change roles';
  end if;
  return new;
end;
$$;

create trigger profiles_guard_role
  before update on public.profiles
  for each row execute function public.guard_profile_role();


-- ---------------------------------------------------------------------
-- 4. Farms
-- ---------------------------------------------------------------------
create table public.farms (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  name        text not null,
  location    text,
  latitude    double precision,
  longitude   double precision,
  farm_type   public.farm_type not null default 'poultry',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index farms_owner_idx on public.farms (owner_id);

create trigger farms_updated_at
  before update on public.farms
  for each row execute function public.set_updated_at();


-- ---------------------------------------------------------------------
-- 5. Flocks (the Flock tab) and vaccination plans
-- ---------------------------------------------------------------------
create table public.flocks (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  farm_id     uuid references public.farms (id) on delete set null,
  name        text not null default 'Batch',
  flock_type  public.flock_type not null default 'broiler',
  breed       text,
  bird_count  integer not null default 0 check (bird_count >= 0),
  start_date  date not null default current_date,
  status      public.flock_status not null default 'active',
  notes       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index flocks_owner_idx on public.flocks (owner_id, status);

create trigger flocks_updated_at
  before update on public.flocks
  for each row execute function public.set_updated_at();

-- Reference schedule, readable by every signed-in user.
-- Seeded from the broiler vaccination schedule in the poultry knowledge file.
create table public.vaccination_templates (
  id          serial primary key,
  flock_type  public.flock_type not null default 'broiler',
  day         integer not null check (day >= 1),
  vaccine     text not null,
  method      text not null,
  unique (flock_type, day, vaccine)
);

insert into public.vaccination_templates (flock_type, day, vaccine, method) values
  ('broiler',  1, 'Marek''s and Newcastle', 'Given at the hatchery'),
  ('broiler',  7, 'Gumboro, 1st dose',      'In clean drinking water with skimmed milk powder'),
  ('broiler', 14, 'Newcastle, 1st dose',    'Drinking water or eye drops'),
  ('broiler', 18, 'Gumboro, 2nd booster',   'In drinking water'),
  ('broiler', 24, 'Newcastle, 2nd booster', 'In drinking water')
on conflict do nothing;

-- Per-flock tracking of each vaccination.
create table public.flock_vaccinations (
  id          uuid primary key default gen_random_uuid(),
  flock_id    uuid not null references public.flocks (id) on delete cascade,
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  day         integer not null,
  vaccine     text not null,
  method      text,
  due_date    date not null,
  done_at     date,
  notes       text,
  unique (flock_id, day, vaccine)
);
create index flock_vax_owner_idx on public.flock_vaccinations (owner_id, due_date);

-- When a flock is created, copy the matching schedule into it.
create or replace function public.seed_flock_vaccinations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.flock_vaccinations (flock_id, owner_id, day, vaccine, method, due_date)
  select new.id, new.owner_id, t.day, t.vaccine, t.method, new.start_date + (t.day - 1)
  from public.vaccination_templates t
  where t.flock_type = new.flock_type;
  return new;
end;
$$;

create trigger flocks_seed_vaccinations
  after insert on public.flocks
  for each row execute function public.seed_flock_vaccinations();


-- ---------------------------------------------------------------------
-- 6. Diagnoses (the Diagnose tab)
-- ---------------------------------------------------------------------
create table public.diagnoses (
  id                   uuid primary key default gen_random_uuid(),
  owner_id             uuid not null references public.profiles (id) on delete cascade,
  farm_id              uuid references public.farms (id) on delete set null,
  flock_id             uuid references public.flocks (id) on delete set null,
  subject              public.diagnosis_subject not null,
  image_path           text not null,            -- path inside the diagnosis-images bucket
  farmer_notes         text,
  condition            text not null default 'Unclear',
  confidence           public.confidence_level not null default 'low',
  summary              text,
  recommendation       text,
  isolate              boolean not null default false,
  escalate             boolean not null default false,
  model                text,                      -- e.g. gemini-2.5-flash or your own classifier
  raw_output           jsonb,
  -- Agrovet review. These confirmed labels become your training data later.
  confirmed_condition  text,
  reviewed_by          uuid references public.profiles (id) on delete set null,
  reviewed_at          timestamptz,
  review_notes         text,
  created_at           timestamptz not null default now()
);
create index diagnoses_owner_idx    on public.diagnoses (owner_id, created_at desc);
create index diagnoses_escalate_idx on public.diagnoses (escalate, reviewed_at) where escalate;


-- ---------------------------------------------------------------------
-- 7. Chat history (the Ask tab)
-- ---------------------------------------------------------------------
create table public.chat_messages (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  session_id  uuid not null,
  role        public.chat_role not null,
  content     text not null,
  language    text,
  sources     jsonb not null default '[]'::jsonb,   -- ids of the knowledge passages used
  created_at  timestamptz not null default now()
);
create index chat_user_session_idx on public.chat_messages (user_id, session_id, created_at);


-- ---------------------------------------------------------------------
-- 8. Agrovet consultations and farm visits (the Agrovet tab)
-- ---------------------------------------------------------------------
create table public.consultations (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references public.profiles (id) on delete cascade,
  name          text not null,
  phone         text not null,
  email         text,
  urgency       public.urgency_level not null default 'standard',
  details       text not null,
  diagnosis_id  uuid references public.diagnoses (id) on delete set null,
  status        public.request_status not null default 'pending',
  assigned_to   uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index consultations_requester_idx on public.consultations (requester_id, created_at desc);
create index consultations_open_idx      on public.consultations (status, urgency, created_at);

create trigger consultations_updated_at
  before update on public.consultations
  for each row execute function public.set_updated_at();

create table public.farm_visits (
  id             uuid primary key default gen_random_uuid(),
  requester_id   uuid not null references public.profiles (id) on delete cascade,
  farm_id        uuid references public.farms (id) on delete set null,
  name           text not null,
  phone          text not null,
  email          text,
  farm_location  text not null,
  farm_type      public.farm_type not null default 'poultry',
  reason         public.visit_reason not null default 'immunization',
  preferred_date date,
  notes          text,
  diagnosis_id   uuid references public.diagnoses (id) on delete set null,
  status         public.request_status not null default 'pending',
  assigned_to    uuid references public.profiles (id) on delete set null,
  scheduled_for  timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index farm_visits_requester_idx on public.farm_visits (requester_id, created_at desc);
create index farm_visits_open_idx      on public.farm_visits (status, preferred_date);

create trigger farm_visits_updated_at
  before update on public.farm_visits
  for each row execute function public.set_updated_at();


-- ---------------------------------------------------------------------
-- 9. Early access signups (the website form). No login needed to insert.
-- ---------------------------------------------------------------------
create table public.early_access_signups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  email       text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  segment     public.farmer_segment not null default 'other',
  created_at  timestamptz not null default now()
);
create unique index early_access_email_idx on public.early_access_signups (lower(email));


-- ---------------------------------------------------------------------
-- 10. Knowledge base for server-side retrieval (optional)
-- The app currently searches the bundled JSONL on the phone. Load the same
-- 105 passages here, and add embeddings, when you move retrieval to your
-- backend or the CoopIQ WhatsApp bot.
-- Embedding size 768 matches Gemini embeddings truncated to 768 dimensions.
-- ---------------------------------------------------------------------
create table public.knowledge_chunks (
  id          text primary key,         -- the "id" field in the JSONL
  content     text not null,            -- the "text" field in the JSONL
  source      text,
  section     text,
  topic       text,
  embedding   extensions.vector(768)
);
create index knowledge_embedding_idx
  on public.knowledge_chunks using hnsw (embedding extensions.vector_cosine_ops);

create or replace function public.match_knowledge(
  query_embedding extensions.vector(768),
  match_count integer default 5
)
returns table (id text, content text, source text, section text, topic text, similarity double precision)
language sql
stable
set search_path = ''
as $$
  select k.id, k.content, k.source, k.section, k.topic,
         1 - (k.embedding operator(extensions.<=>) query_embedding) as similarity
  from public.knowledge_chunks k
  where k.embedding is not null
  order by k.embedding operator(extensions.<=>) query_embedding
  limit match_count;
$$;


-- ---------------------------------------------------------------------
-- 11. Row Level Security
-- ---------------------------------------------------------------------
alter table public.profiles              enable row level security;
alter table public.farms                 enable row level security;
alter table public.flocks                enable row level security;
alter table public.vaccination_templates enable row level security;
alter table public.flock_vaccinations    enable row level security;
alter table public.diagnoses             enable row level security;
alter table public.chat_messages         enable row level security;
alter table public.consultations         enable row level security;
alter table public.farm_visits           enable row level security;
alter table public.early_access_signups  enable row level security;
alter table public.knowledge_chunks      enable row level security;

-- profiles: read and edit your own; staff can read everyone.
-- There is no insert policy because the signup trigger creates the row.
create policy "profiles: read own or staff" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or public.is_staff());

create policy "profiles: update own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- farms
create policy "farms: owner full access" on public.farms
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "farms: staff read" on public.farms
  for select to authenticated
  using (public.is_staff());

-- flocks
create policy "flocks: owner full access" on public.flocks
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- vaccination templates: everyone signed in can read
create policy "vaccination_templates: read" on public.vaccination_templates
  for select to authenticated
  using (true);

-- flock vaccinations
create policy "flock_vaccinations: owner full access" on public.flock_vaccinations
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- diagnoses: owners can read, add and delete their own. Staff can read escalated
-- cases and write the review fields.
create policy "diagnoses: owner read" on public.diagnoses
  for select to authenticated
  using (owner_id = (select auth.uid()));

create policy "diagnoses: owner insert" on public.diagnoses
  for insert to authenticated
  with check (owner_id = (select auth.uid()));

create policy "diagnoses: owner delete" on public.diagnoses
  for delete to authenticated
  using (owner_id = (select auth.uid()));

create policy "diagnoses: staff read escalated" on public.diagnoses
  for select to authenticated
  using (public.is_staff() and escalate);

create policy "diagnoses: staff review" on public.diagnoses
  for update to authenticated
  using (public.is_staff() and escalate)
  with check (public.is_staff());

-- chat messages: private to the user
create policy "chat_messages: owner full access" on public.chat_messages
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- consultations
create policy "consultations: requester read" on public.consultations
  for select to authenticated
  using (requester_id = (select auth.uid()));

create policy "consultations: requester insert" on public.consultations
  for insert to authenticated
  with check (requester_id = (select auth.uid()));

create policy "consultations: staff read" on public.consultations
  for select to authenticated
  using (public.is_staff());

create policy "consultations: staff update" on public.consultations
  for update to authenticated
  using (public.is_staff())
  with check (public.is_staff());

-- farm visits
create policy "farm_visits: requester read" on public.farm_visits
  for select to authenticated
  using (requester_id = (select auth.uid()));

create policy "farm_visits: requester insert" on public.farm_visits
  for insert to authenticated
  with check (requester_id = (select auth.uid()));

create policy "farm_visits: requester cancel" on public.farm_visits
  for update to authenticated
  using (requester_id = (select auth.uid()) and status = 'pending')
  with check (requester_id = (select auth.uid()) and status in ('pending', 'cancelled'));

create policy "farm_visits: staff read" on public.farm_visits
  for select to authenticated
  using (public.is_staff());

create policy "farm_visits: staff update" on public.farm_visits
  for update to authenticated
  using (public.is_staff())
  with check (public.is_staff());

-- early access: anyone can sign up, nobody can read through the API.
-- Read the list from the dashboard or with the service role key.
create policy "early_access: anyone can insert" on public.early_access_signups
  for insert to anon, authenticated
  with check (true);

-- knowledge base: readable by signed-in users, written only with the service role
create policy "knowledge_chunks: read" on public.knowledge_chunks
  for select to authenticated
  using (true);


-- ---------------------------------------------------------------------
-- 12. Storage: private bucket for diagnosis photos
-- Upload to "<user_id>/<filename>" so the folder name is the owner's id.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'diagnosis-images',
  'diagnosis-images',
  false,
  8388608,  -- 8 MB
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

create policy "diagnosis images: owner upload" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'diagnosis-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "diagnosis images: owner read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'diagnosis-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "diagnosis images: owner delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'diagnosis-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "diagnosis images: staff read" on storage.objects
  for select to authenticated
  using (bucket_id = 'diagnosis-images' and public.is_staff());


-- ---------------------------------------------------------------------
-- 13. Promote your first agrovet or admin (run manually, replace the email)
-- ---------------------------------------------------------------------
-- update public.profiles set role = 'admin'   where email = 'you@example.com';
-- update public.profiles set role = 'agrovet' where email = 'agrovet@example.com';
