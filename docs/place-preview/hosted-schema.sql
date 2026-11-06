-- Mirrors hosted migration durable_google_place_references, already applied.
create schema if not exists trippy_catalog;
revoke all on schema trippy_catalog from public, anon, authenticated;
create table if not exists trippy_catalog.google_place_references (
    place_id text primary key check (length(place_id) between 1 and 180),
    sources text[] not null default '{}',
    created_at timestamptz not null default now()
);
alter table trippy_catalog.google_place_references enable row level security;
revoke all on trippy_catalog.google_place_references from public, anon, authenticated;
