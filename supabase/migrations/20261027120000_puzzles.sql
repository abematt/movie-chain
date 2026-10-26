-- Published content the app plays, one row per puzzle: the daily start now, other
-- modes later. A mode's rules and screens ship in the app; the service only serves
-- its content, so every mode shares this table with its data in `data`.
--
--   mode        which game the puzzle is for ('daily_start')
--   number      the day it's for, counted from #1 on the player's local date
--   revision    1 when first published; a fix goes in as the next revision
--   data        the mode's puzzle; for 'daily_start':
--                 {"kind": "actor", "id": 31, "name": "Tom Hanks"}
--                 {"kind": "movie", "id": 155, "name": "The Dark Knight", "year": 2008}
--               (`id` is the TMDB id). The app reads the highest playable revision.
--
-- Published is immutable: once a day has gone out, people have results against
-- it, so a row is never edited or deleted. Publishing is an insert (the SQL editor,
-- as postgres); the public roles can only read.

create table public.puzzles (
  mode text not null check (mode ~ '^[a-z][a-z0-9_]*$'),
  number integer not null check (number >= 1),
  revision integer not null default 1 check (revision >= 1),
  data jsonb not null,
  published_at timestamptz not null default now(),
  primary key (mode, number, revision)
);

alter table public.puzzles enable row level security;
revoke all on public.puzzles from anon, authenticated;
grant select on public.puzzles to anon, authenticated;
create policy "Published puzzles are readable by everyone"
  on public.puzzles for select to anon, authenticated using (true);

create function public.puzzles_are_immutable() returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  raise exception 'Published puzzles are immutable: publish the fix as the next revision';
end;
$$;
revoke execute on function public.puzzles_are_immutable() from public, anon, authenticated;

create trigger puzzles_no_update_or_delete
  before update or delete on public.puzzles
  for each row execute function public.puzzles_are_immutable();
create trigger puzzles_no_truncate
  before truncate on public.puzzles
  for each statement execute function public.puzzles_are_immutable();

-- The first nine days, matching the app's fallback list (`DailyStart.entries`), so
-- serving them changes nothing for anyone who has already played.
insert into public.puzzles (mode, number, data) values
  ('daily_start', 1, '{"kind": "actor", "id": 31, "name": "Tom Hanks"}'),
  ('daily_start', 2, '{"kind": "movie", "id": 155, "name": "The Dark Knight", "year": 2008}'),
  ('daily_start', 3, '{"kind": "actor", "id": 6384, "name": "Keanu Reeves"}'),
  ('daily_start', 4, '{"kind": "actor", "id": 5064, "name": "Meryl Streep"}'),
  ('daily_start', 5, '{"kind": "movie", "id": 597, "name": "Titanic", "year": 1997}'),
  ('daily_start', 6, '{"kind": "actor", "id": 6193, "name": "Leonardo DiCaprio"}'),
  ('daily_start', 7, '{"kind": "actor", "id": 1245, "name": "Scarlett Johansson"}'),
  ('daily_start', 8, '{"kind": "movie", "id": 680, "name": "Pulp Fiction", "year": 1994}'),
  ('daily_start', 9, '{"kind": "actor", "id": 287, "name": "Brad Pitt"}');
