-- Persistent chat sessions, scoped per user via RLS.
create table if not exists public.chats (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null default 'New chat',
  messages jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.chats enable row level security;

drop policy if exists "chats_owner_all" on public.chats;
create policy "chats_owner_all" on public.chats
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create index if not exists chats_user_updated_idx
  on public.chats (user_id, updated_at desc);

-- Auto-update updated_at on every write
create or replace function public.chats_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists chats_touch on public.chats;
create trigger chats_touch before update on public.chats
  for each row execute function public.chats_touch_updated_at();
