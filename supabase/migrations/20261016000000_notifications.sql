-- In-app notifications for vet requests and farm visits.
-- Rows are created by triggers, never by the app. When a request or visit is
-- created, or its status or visit time changes (for example you edit the row
-- in the Supabase dashboard), the person who made it gets a notification.

create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  kind        text not null,
  title       text not null,
  body        text,
  ref_table   text,
  ref_id      uuid,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index notifications_user_idx on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

create policy "notifications: read own" on public.notifications
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "notifications: mark own read" on public.notifications
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- The app may only change read_at. Everything else is written by the triggers.
revoke insert, update, delete on public.notifications from anon, authenticated;
grant update (read_at) on public.notifications to authenticated;

-- ---------------------------------------------------------------------
-- Vet requests (consultations)
-- ---------------------------------------------------------------------
create or replace function public.notify_on_consultation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.notifications (user_id, kind, title, body, ref_table, ref_id)
    values (new.requester_id, 'request_received', 'Request received',
            'A vet will get back to you soon.', 'consultations', new.id);
  elsif new.status is distinct from old.status then
    insert into public.notifications (user_id, kind, title, body, ref_table, ref_id)
    values (
      new.requester_id,
      'request_update',
      case
        when new.status::text = 'contacted' then 'A vet has picked up your request'
        when new.status::text = 'scheduled' then 'Your request was scheduled'
        when new.status::text = 'completed' then 'Your request is complete'
        when new.status::text = 'cancelled' then 'Your request was cancelled'
        else 'Your request was updated'
      end,
      null,
      'consultations',
      new.id
    );
  end if;
  return new;
end;
$$;

create trigger consultations_notify
  after insert or update on public.consultations
  for each row execute function public.notify_on_consultation();

-- ---------------------------------------------------------------------
-- Farm visits
-- ---------------------------------------------------------------------
create or replace function public.notify_on_visit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  when_txt text;
begin
  if tg_op = 'INSERT' then
    insert into public.notifications (user_id, kind, title, body, ref_table, ref_id)
    values (new.requester_id, 'visit_received', 'Visit requested',
            'We will notify you when a vet schedules your visit.', 'farm_visits', new.id);
  elsif new.status is distinct from old.status
        or new.scheduled_for is distinct from old.scheduled_for then
    when_txt := case
      when new.scheduled_for is null then null
      else to_char(new.scheduled_for at time zone 'Africa/Harare', 'FMDay DD FMMonth, HH24:MI')
    end;
    insert into public.notifications (user_id, kind, title, body, ref_table, ref_id)
    values (
      new.requester_id,
      'visit_update',
      case
        when new.status::text = 'scheduled' and old.status::text = 'scheduled' then 'Your visit time was updated'
        when new.status::text = 'scheduled' then 'Your visit is scheduled'
        when new.status::text = 'contacted' then 'A vet has contacted you about your visit'
        when new.status::text = 'completed' then 'Your visit is complete'
        when new.status::text = 'cancelled' then 'Your visit was cancelled'
        else 'Your visit was updated'
      end,
      case
        when new.status::text = 'scheduled' then coalesce(when_txt, 'A vet will confirm the date soon.')
        else null
      end,
      'farm_visits',
      new.id
    );
  end if;
  return new;
end;
$$;

create trigger farm_visits_notify
  after insert or update on public.farm_visits
  for each row execute function public.notify_on_visit();

-- Live updates while the app is open. If this line says the table is already
-- in the publication, that is fine.
alter publication supabase_realtime add table public.notifications;

-- ---------------------------------------------------------------------
-- How staff update a visit (Supabase dashboard > Table Editor > farm_visits,
-- or SQL). The farmer is notified automatically:
--
-- update public.farm_visits
--    set status = 'scheduled', scheduled_for = '2026-10-20 09:00+02'
--  where id = 'PASTE-THE-VISIT-ID';
-- ---------------------------------------------------------------------
