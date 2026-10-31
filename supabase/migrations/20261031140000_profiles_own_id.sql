-- A profile's id comes from the caller's session, never the request. PostgREST's
-- upsert updates every column it was sent, so a client that sent `id` needed
-- `update(id)`, which players must not have. With the default, the app sends only
-- `display_name`, and the insert policy still holds the row to auth.uid().
alter table public.profiles alter column id set default auth.uid();
revoke insert on public.profiles from authenticated;
grant insert (display_name) on public.profiles to authenticated;
