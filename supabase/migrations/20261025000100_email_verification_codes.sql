create table if not exists public.email_verification_codes (
  email text primary key,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts integer not null default 0,
  last_sent_at timestamptz not null default now(),
  verified_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.email_verification_codes
  enable row level security;

revoke all on public.email_verification_codes
  from anon, authenticated;

comment on table public.email_verification_codes is
  'Private storage for hashed, short-lived email verification codes.';
