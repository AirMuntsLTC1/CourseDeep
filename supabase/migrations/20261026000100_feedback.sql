-- Real "Help & Feedback" storage. Each signed-in user can only INSERT their own rows.
create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  email text,
  message text not null check (char_length(message) between 3 and 4000),
  app_version text,
  created_at timestamptz not null default now()
);

alter table public.feedback enable row level security;

drop policy if exists "feedback_insert_own" on public.feedback;
create policy "feedback_insert_own" on public.feedback
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "feedback_select_own" on public.feedback;
create policy "feedback_select_own" on public.feedback
  for select to authenticated
  using (user_id = auth.uid());
