-- New tables get no grants in this project ("automatically expose new tables" is
-- off), not even for the service role, so the proxy's cache reads and writes were
-- refused. The service role bypasses RLS but still needs table privileges.

grant select, insert, update on public.tmdb_cache to service_role;
