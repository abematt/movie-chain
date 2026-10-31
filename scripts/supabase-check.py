#!/usr/bin/env python3
"""Security checks for the Supabase service, held to supabase/access.toml.

Supabase's advisors check that the safety rules exist (RLS on, no exposed definer
functions). These check what the rules actually let the public keys do, the part
the advisors can't judge, plus the secrets and auth settings around them:

  migrations  every table gets RLS and a revoke; grants, policies and functions
              stay inside access.toml (offline, so it runs before `db push`)
  secrets     no service-role key, secret key, TMDB token or our own keys in any
              tracked file, the git history, or a built Release app
  advisors    `supabase db advisors --linked`, security and performance
  catalog     the live grants, column grants, policies, RPC functions, views and
              buckets, against access.toml
  probe       read, insert, update and delete on every exposed table with the
              app's publishable key, as a stranger would (writes match no rows)
  auth        the live auth settings: signups, email confirmation, anonymous
              sign-ins, redirect URLs, password length

The judgment pass (Edge Function logic, what a policy means) is /supabase-audit.

Usage:
  scripts/supabase-check.py             everything (needs `supabase login`; ~20s)
  scripts/supabase-check.py --offline   migrations + secrets in staged files (pre-commit)
  scripts/supabase-check.py --app PATH  scan this .app instead of the newest Release build

Exits 1 on any failure. Warnings print but pass. Secret values are never printed.
"""

import base64
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tomllib
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ACCESS = ROOT / "supabase" / "access.toml"
MIGRATIONS = ROOT / "supabase" / "migrations"
CONFIG = ROOT / "supabase" / "config.toml"
APP_SECRETS = ROOT / "movie-quiz" / "AppSecrets.plist"
TMDB_SECRETS = ROOT / "movie-quiz" / "TMDBSecrets.plist"
CONFIG_SWIFT = ROOT / "movie-quiz" / "Config.swift"
DERIVED_DATA = Path.home() / "Library" / "Developer" / "Xcode" / "DerivedData"

PUBLIC_ROLES = ("anon", "authenticated")
PRIVILEGES = ("select", "insert", "update", "delete", "truncate")
COLUMN_SCOPED = ("select", "insert", "update")


class Report:
    def __init__(self):
        self.failures = 0
        self.warnings = 0

    def section(self, name):
        print(f"\n{name}")

    def ok(self, message):
        print(f"  ok    {message}")

    def fail(self, rule, message):
        self.failures += 1
        print(f"  FAIL  [{rule}] {message}")

    def warn(self, rule, message):
        self.warnings += 1
        print(f"  warn  [{rule}] {message}")

    def skip(self, message):
        print(f"  skip  {message}")


# ---------------------------------------------------------------- access.toml

def qualified(name):
    return name if "." in name else f"public.{name}"


def load_access():
    access = tomllib.loads(ACCESS.read_text(encoding="utf-8"))
    tables = {qualified(name): {role: set(spec.get(role, [])) for role in PUBLIC_ROLES}
              for name, spec in access.get("tables", {}).items()}
    for name, roles in tables.items():
        for role, privileges in roles.items():
            roles[role] = {normalize_privilege(p) for p in privileges}
    callable_ = {qualified(f) for f in access.get("rpc", {}).get("callable", [])}
    return tables, callable_, access.get("buckets", {}), access.get("auth", {})


def normalize_privilege(privilege):
    """'update( b, a )' → 'update(a,b)' so declared and live compare as strings."""
    match = re.fullmatch(r"\s*(\w+)\s*(?:\(([^)]*)\))?\s*", privilege.lower())
    if not match:
        return privilege
    name, columns = match.groups()
    if columns is None:
        return name
    return f"{name}({','.join(sorted(c.strip() for c in columns.split(',') if c.strip()))})"


def describe(privileges):
    return ", ".join(sorted(privileges)) or "nothing"


# ---------------------------------------------------------------- migrations

def migration_statements():
    for path in sorted(MIGRATIONS.glob("*.sql")):
        text = path.read_text(encoding="utf-8")
        text = re.sub(r"\$(\w*)\$.*?\$\1\$", "$$", text, flags=re.S)   # function bodies
        text = re.sub(r"--[^\n]*", "", text)
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        for statement in text.split(";"):
            statement = " ".join(statement.split())
            if statement:
                yield path.name, statement


def relation_name(raw):
    return qualified(raw.replace('"', "").lower())


def check_migrations(report, tables):
    report.section("migrations")
    created, rls_on, revoked, net = {}, set(), {}, {}
    for file, sql in migration_statements():
        low = sql.lower()

        if m := re.match(r"create (?:unlogged )?table (?:if not exists )?([\w.\"]+)", low):
            created[relation_name(m[1])] = file
        if m := re.match(r"alter table (?:only )?([\w.\"]+) enable row level security", low):
            rls_on.add(relation_name(m[1]))
        if m := re.match(r"alter table (?:only )?([\w.\"]+) disable row level security", low):
            report.fail("rls-disabled", f"{file}: turns RLS off on {relation_name(m[1])}")
        if m := re.match(r"revoke all(?: privileges)? on (?:table )?([\w.\", ]+?) from (.+)", low):
            roles = {r.strip() for r in m[2].split(",")}
            for name in m[1].split(","):
                revoked.setdefault(relation_name(name.strip()), set()).update(roles)

        # Grants are tracked net of later revokes, in migration order: what
        # access.toml must match is what the last migration leaves.
        if m := re.match(r"(grant|revoke) (.+?) on (?:table )?([\w.\", ]+?) (?:to|from) (.+)", low):
            verb, privileges, names, role_list = m.groups()
            if privileges.startswith(("usage", "execute")) or " on function " in f" {low} ":
                continue
            roles = {r.strip() for r in role_list.split(",")} & {*PUBLIC_ROLES, "public"}
            listed = {normalize_privilege(p) for p in re.split(r",(?![^(]*\))", privileges)}
            everything = bool(listed & {"all", "all privileges"})
            for name in names.split(","):
                table = relation_name(name.strip())
                for role in roles:
                    held = net.setdefault((table, role), {})
                    if verb == "revoke":
                        # Revoking a table privilege revokes it on every column too.
                        bases = {p.split("(")[0] for p in listed}
                        for privilege in list(held):
                            if everything or privilege.split("(")[0] in bases:
                                del held[privilege]
                    else:
                        for privilege in (set(PRIVILEGES) if everything else listed):
                            held[privilege] = file

        if low.startswith("create policy"):
            check_policy_sql(report, file, low)

        if m := re.match(r"create (?:or replace )?view ([\w.\"]+)(.*)", low):
            if "security_invoker" not in m[2].split(" as ", 1)[0]:
                report.fail("view-no-invoker",
                            f"{file}: view {relation_name(m[1])} runs as its owner and skips "
                            "RLS; create it `with (security_invoker = true)`")

        if low.startswith(("create function", "create or replace function")) \
                and "security definer" in low:
            name = relation_name(re.match(r"create (?:or replace )?function ([\w.\"]+)", low)[1])
            revokes = [s.lower() for _, s in migration_statements()
                       if re.match(rf"revoke execute on function {re.escape(name.split('.')[1])}\b",
                                   s.lower().replace("public.", ""))]
            if not any(all(r in s for r in ("public", "anon", "authenticated")) for s in revokes):
                report.fail("definer-callable",
                            f"{file}: SECURITY DEFINER {name}() keeps its default execute grant; "
                            "revoke it from public, anon, authenticated")

    for (table, role), held in net.items():
        allowed = tables.get(table, {}).get(role if role != "public" else "anon", set())
        extra = {p: f for p, f in held.items() if role == "public" or p not in allowed}
        if extra:
            report.fail("grant-not-declared",
                        f"{', '.join(sorted(set(extra.values())))}: grants {describe(set(extra))} "
                        f"on {table} to {role}; access.toml allows {describe(allowed)}")

    for table, file in created.items():
        if table not in rls_on:
            report.fail("rls-missing", f"{file}: {table} is created without enabling RLS")
        if not set(PUBLIC_ROLES) <= revoked.get(table, set()):
            report.fail("revoke-missing", f"{file}: {table} needs `revoke all on {table} "
                        "from anon, authenticated` (deny by default)")
        if table not in tables:
            report.fail("table-not-declared", f"{file}: {table} isn't in supabase/access.toml")
    for table in tables:
        if table not in created:
            report.warn("declared-not-created", f"access.toml lists {table}, no migration creates it")
    if not report.failures:     # the first section, so any failure is this one's
        report.ok(f"{len(created)} tables, all with RLS, a revoke and declared access")


def check_policy_sql(report, file, low):
    head = re.match(r'create policy (".*?"|\S+)', low)
    name, low = head[1], low[head.end():]                     # the name can say anything
    if not re.search(r"\bto\b", low) or re.search(r"\bto public\b", low):
        report.fail("policy-public", f"{file}: policy {name} applies to every role; "
                    "name the roles (`to anon, authenticated`)")
    command = re.search(r"\bfor (select|insert|update|delete|all)\b", low)
    command = command[1] if command else "all"
    if command != "select" and re.search(r"(using|with check) \(\s*true\s*\)", low):
        report.fail("policy-true-write", f"{file}: policy {name} lets anyone {command} any row")
    if "user_metadata" in low or "raw_user_meta_data" in low:
        report.fail("policy-user-metadata", f"{file}: policy {name} trusts user_metadata, "
                    "which the user can edit")
    if command != "select" and re.search(r"\bto\b[^()]*\bauthenticated\b", low) and "auth.uid()" not in low:
        report.fail("policy-not-own-row", f"{file}: policy {name} lets signed-in players "
                    f"{command} rows not keyed on auth.uid(); anyone can be signed in "
                    "(anonymous sign-ins), so a write must be their own row")


# ---------------------------------------------------------------- secrets

JWT = re.compile(rb"eyJ[A-Za-z0-9_-]{8,}\.(eyJ[A-Za-z0-9_-]{8,})\.[A-Za-z0-9_-]{8,}")
SECRET_KEY = re.compile(rb"sb_secret_[A-Za-z0-9_-]{8,}")
SERVICE_ROLE_ASSIGNED = re.compile(rb"SERVICE_ROLE_KEY\s*[:=]\s*[\"']?[A-Za-z0-9_.-]{20,}")


def jwt_kind(payload_b64):
    try:
        padded = payload_b64 + b"=" * (-len(payload_b64) % 4)
        claims = json.loads(base64.urlsafe_b64decode(padded))
    except (ValueError, json.JSONDecodeError):
        return None
    if claims.get("role") == "service_role":
        return "a Supabase service-role key"
    if "api_read" in (claims.get("scopes") or []):
        return "a TMDB access token"
    return None


def known_secrets():
    """Our own values from the gitignored plists: (label, bytes)."""
    found = []
    for path, key, label in ((TMDB_SECRETS, "TMDBToken", "the TMDB token"),
                             (APP_SECRETS, "ServiceKey", "the publishable key")):
        try:
            value = plistlib.loads(path.read_bytes()).get(key, "")
        except (OSError, plistlib.InvalidFileException):
            continue
        if len(value) >= 16 and "PASTE" not in value:
            found.append((label, value.encode()))
    return found


def secret_hits(data, known, *, skip_known=()):
    hits = set()
    for m in JWT.finditer(data):
        if kind := jwt_kind(m[1]):
            hits.add(kind)
    if SECRET_KEY.search(data):
        hits.add("a Supabase secret key")
    if SERVICE_ROLE_ASSIGNED.search(data):
        hits.add("a service-role key assigned in code")
    for label, value in known:
        if label not in skip_known and value in data:
            hits.add(label)
    return hits


def check_secrets(report, *, history, app):
    report.section("secrets")
    known = known_secrets()
    tracked = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True,
                             check=True).stdout.decode().split("\0")
    clean = True
    for name in filter(None, tracked):
        if name.endswith(("AppSecrets.plist", "TMDBSecrets.plist")):
            report.fail("secrets-tracked", f"{name} is tracked; it must stay gitignored")
            clean = False
            continue
        path = ROOT / name
        if not path.is_file() or path.stat().st_size > 5_000_000:
            continue
        for hit in secret_hits(path.read_bytes(), known):
            report.fail("secret-in-repo", f"{name}: contains {hit}")
            clean = False
    if clean:
        report.ok(f"{len(tracked) - 1} tracked files hold no keys")

    if history:
        log = subprocess.run(["git", "log", "--all", "-p", "--no-color", "--format=commit %h"],
                             cwd=ROOT, capture_output=True, check=True).stdout
        commits = {}
        for chunk in re.split(rb"^commit (?=\w+$)", log, flags=re.M):
            sha = chunk[:12].split(b"\n", 1)[0].decode(errors="replace")
            for hit in secret_hits(chunk, known):
                commits.setdefault(hit, sha)
        for hit, sha in commits.items():
            report.fail("secret-in-history", f"commit {sha} added {hit}; rotate it, the repo is public")
        if not commits:
            report.ok("git history holds no keys")

    if app is None:
        builds = sorted(DERIVED_DATA.glob("movie-quiz-*/Build/Products/Release-*/movie-quiz.app"),
                        key=lambda p: p.stat().st_mtime)
        app = builds[-1] if builds else None
    if app is None:
        report.skip("no Release build to scan; build one with `xcodebuild -scheme movie-quiz "
                    "-configuration Release -destination 'generic/platform=iOS Simulator' build`")
        return
    app_clean = True
    if any(app.rglob("TMDBSecrets.plist")):
        report.fail("tmdb-token-shipped", f"{app.name} carries TMDBSecrets.plist; Release must exclude it")
        app_clean = False
    for path in (p for p in app.rglob("*") if p.is_file()):
        # The publishable key is meant to ship; everything else must not.
        for hit in secret_hits(path.read_bytes(), known, skip_known={"the publishable key"}):
            report.fail("secret-in-app", f"{path.relative_to(app.parent)}: contains {hit}")
            app_clean = False
    if app_clean:
        report.ok(f"{app.parent.name}/{app.name} ships no secrets")


# ---------------------------------------------------------------- the linked project

def supabase(*args):
    command = ["supabase"] if shutil.which("supabase") else ["npx", "--yes", "supabase@2"]
    result = subprocess.run([*command, *args], cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip().splitlines()[-1] if result.stderr.strip()
                           else f"supabase {args[0]} failed")
    return result.stdout


def json_from(output):
    """The JSON document in a CLI's stdout, after any status lines."""
    start = 0 if output.startswith("{") else output.find("\n{") + 1
    return json.loads(output[start:])


def check_advisors(report, tables, auth):
    report.section("advisors")
    issues = json_from(supabase("db", "advisors", "--linked", "--type", "all",
                                "--level", "info", "--output-format", "json")).get("results", [])
    # Deny-by-default tables have RLS and no policies on purpose: only the service role reads them.
    service_only = {name for name, roles in tables.items() if not any(roles.values())}
    shown = 0
    for issue in issues:
        level = str(issue.get("level", "")).upper()
        security = "SECURITY" in [c.upper() for c in issue.get("categories", [])]
        title = issue.get("title") or issue.get("name") or "issue"
        detail = re.sub(r"\s+", " ", str(issue.get("detail", "")).replace("\\`", "`"))[:200]
        rule = issue.get("name", "advisor")
        if rule == "rls_enabled_no_policy" and any(f"`{t}`" in detail for t in service_only):
            continue
        # Every player is an anonymous user, so a declared table's policies admit
        # anonymous users on purpose; the own-row rule (policy-not-own-row) holds them.
        meta = issue.get("metadata") or {}
        flagged = f"{meta.get('schema', 'public')}.{meta.get('name', '')}"
        if rule == "auth_allow_anonymous_sign_ins" and auth.get("anonymous_sign_ins") \
                and tables.get(flagged, {}).get("authenticated"):
            continue
        if level == "INFO" and not security:
            continue
        shown += 1
        if level == "ERROR" or (security and level == "WARN"):
            report.fail(rule, f"{title}: {detail}")
        else:
            report.warn(rule, f"{title} ({level.lower()}): {detail}")
    if not shown:
        report.ok(f"no issues ({len(issues)} expected or informational notices skipped)"
                  if issues else "no issues")


def resolved_config():
    """The live project's settings: config.toml overlaid with `config diff`'s remote values."""
    config = tomllib.loads(CONFIG.read_text(encoding="utf-8"))
    diff = json_from(supabase("config", "diff", "--output-format", "json"))
    for change in diff.get("changes", []):
        *parents, leaf = change["path"]
        node = config
        for key in parents:
            node = node.setdefault(key, {})
        if change["class"] == "local_only":
            node.pop(leaf, None)
        else:
            node[leaf] = change["remote"]
    return config


CATALOG_SQL = """
begin transaction read only;
with exposed(nspname) as (select unnest(%(schemas)s::text[]))
select json_build_object(
  'tables', (select coalesce(json_agg(t), '[]') from (
    select n.nspname || '.' || c.relname as name, c.relkind as kind,
           c.relrowsecurity as rls, coalesce(c.reloptions, '{}') as options,
           (select a.attname from pg_attribute a where a.attrelid = c.oid and a.attnum > 0
              and not a.attisdropped and a.attidentity = '' and a.attgenerated = ''
              order by a.attnum limit 1) as first_column,
           (select json_object_agg(r, json_build_object(
              'select', has_table_privilege(r, c.oid, 'SELECT'),
              'insert', has_table_privilege(r, c.oid, 'INSERT'),
              'update', has_table_privilege(r, c.oid, 'UPDATE'),
              'delete', has_table_privilege(r, c.oid, 'DELETE'),
              'truncate', has_table_privilege(r, c.oid, 'TRUNCATE'),
              'columns', (select json_object_agg(p, coalesce((select json_agg(a.attname order by a.attname)
                  from pg_attribute a where a.attrelid = c.oid and a.attnum > 0
                  and not a.attisdropped and has_column_privilege(r, c.oid, a.attnum, p)), '[]'))
                from unnest(array['SELECT', 'INSERT', 'UPDATE']) p)))
            from unnest(array['anon', 'authenticated']) r) as access
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in (select nspname from exposed) and c.relkind in ('r', 'p', 'v', 'm', 'f')) t),
  'policies', (select coalesce(json_agg(p), '[]') from (
    select schemaname || '.' || tablename as table, policyname as name, permissive,
           roles, cmd, qual, with_check
    from pg_policies
    where schemaname in (select nspname from exposed)
       or (schemaname = 'storage' and tablename = 'objects')) p),
  'functions', (select coalesce(json_agg(f), '[]') from (
    select n.nspname || '.' || p.proname as name, p.prosecdef as security_definer,
           has_function_privilege('anon', p.oid, 'EXECUTE') as anon,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in (select nspname from exposed)) f),
  'buckets', (select coalesce(json_agg(b), '[]') from (
    select id, public from storage.buckets) b)
) as report;
commit;
"""


def live_catalog(schemas):
    array = "array[" + ",".join("'" + s.replace("'", "''") + "'" for s in schemas) + "]"
    rows = json_from(supabase("db", "query", "--linked", "--output-format", "json",
                              CATALOG_SQL % {"schemas": array}))["rows"]
    report = rows[0]["report"]
    return json.loads(report) if isinstance(report, str) else report


def live_privileges(role_access):
    granted = set()
    for privilege in PRIVILEGES:
        if role_access[privilege]:
            granted.add(privilege)
        elif privilege in COLUMN_SCOPED and (cols := role_access["columns"][privilege.upper()]):
            granted.add(f"{privilege}({','.join(sorted(cols))})")
    return granted


def check_catalog(report, catalog, tables, callable_, buckets):
    report.section("catalog")
    before = report.failures
    live_names = set()
    for table in catalog["tables"]:
        name = table["name"]
        live_names.add(name)
        if table["kind"] in ("r", "p") and not table["rls"]:
            report.fail("rls-disabled", f"{name} has RLS off; the publishable key reaches it directly")
        if table["kind"] == "v" and "security_invoker=true" not in table["options"]:
            report.fail("view-no-invoker", f"view {name} runs as its owner and skips RLS")
        declared = tables.get(name, {role: set() for role in PUBLIC_ROLES})
        if name not in tables:
            report.fail("table-not-declared", f"{name} is exposed but not in supabase/access.toml")
        for role in PUBLIC_ROLES:
            actual = live_privileges(table["access"][role])
            if actual != declared[role]:
                kind = "materialized view (no RLS) " if table["kind"] == "m" else ""
                report.fail("access-mismatch",
                            f"{role} can {describe(actual)} on {kind}{name}; "
                            f"access.toml allows {describe(declared[role])}")
            if "update" in actual:
                report.warn("update-every-column",
                            f"{role} may update every column of {name}; scope it to the "
                            "columns a player should edit")
    for name in tables:
        if name not in live_names:
            report.warn("declared-not-live", f"{name} is in access.toml but not on the service "
                        "(migration not pushed?)")

    for policy in catalog["policies"]:
        where = f"policy \"{policy['name']}\" on {policy['table']}"
        roles = set(policy["roles"] if isinstance(policy["roles"], list)
                    else policy["roles"].strip("{}").split(","))
        conditions = [c for c in (policy["qual"], policy["with_check"]) if c]
        if "public" in roles:
            report.fail("policy-public", f"{where} applies to every role; name the roles")
        if policy["permissive"] == "PERMISSIVE" and policy["cmd"] != "SELECT" \
                and any(c.strip() == "true" for c in conditions):
            report.fail("policy-true-write", f"{where} lets anyone {policy['cmd'].lower()} any row")
        if policy["cmd"] in ("SELECT", "ALL") and policy["qual"] == "true":
            readers = {r for r in roles if "select" in tables.get(policy["table"], {}).get(r, set())}
            if policy["table"] == "storage.objects" or readers != roles & set(PUBLIC_ROLES):
                report.fail("policy-true-read", f"{where} shows every row to "
                            f"{', '.join(sorted(roles))}, beyond what access.toml declares")
        if any("user_metadata" in c or "raw_user_meta_data" in c for c in conditions):
            report.fail("policy-user-metadata", f"{where} trusts user_metadata, which users can edit")
        if policy["cmd"] != "SELECT" and "authenticated" in roles \
                and not any("auth.uid()" in c for c in conditions):
            report.fail("policy-not-own-row", f"{where} lets signed-in players "
                        f"{policy['cmd'].lower()} rows not keyed on auth.uid()")

    for function in catalog["functions"]:
        reachable = function["anon"] or function["authenticated"]
        if reachable and function["name"] not in callable_:
            definer = "SECURITY DEFINER " if function["security_definer"] else ""
            report.fail("rpc-callable", f"{definer}{function['name']}() is callable over "
                        "/rest/v1/rpc; revoke execute or declare it in access.toml")

    live_buckets = {b["id"]: "public" if b["public"] else "private" for b in catalog["buckets"]}
    for bucket, visibility in live_buckets.items():
        if buckets.get(bucket) != visibility:
            report.fail("bucket-mismatch", f"bucket {bucket} is {visibility}; access.toml says "
                        f"{buckets.get(bucket, 'it should not exist')}")

    if report.failures == before:
        report.ok(f"{len(live_names)} relations, {len(catalog['policies'])} policies, "
                  f"{len(catalog['functions'])} functions, {len(live_buckets)} buckets match access.toml")


def check_probe(report, catalog, tables):
    report.section("probe (publishable key)")
    url = re.search(r'serviceURL = URL\(string: "(https://[^"]+)"\)',
                    CONFIG_SWIFT.read_text(encoding="utf-8"))
    try:
        key = plistlib.loads(APP_SECRETS.read_bytes()).get("ServiceKey", "")
    except (OSError, plistlib.InvalidFileException):
        key = ""
    if not url or not key:
        report.fail("probe-unavailable", "needs serviceURL in Config.swift and ServiceKey in "
                    "AppSecrets.plist; without them nothing checks what the app's key can do")
        return

    def request(method, table, query, body=None):
        schema, name = table["name"].split(".", 1)
        headers = {"apikey": key, "Accept-Profile": schema, "Content-Profile": schema,
                   "Content-Type": "application/json", "Prefer": "return=minimal"}
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(f"{url[1]}/rest/v1/{name}?{query}", data=data,
                                     method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=15) as response:
                return response.status
        except urllib.error.HTTPError as error:
            return error.code

    before = report.failures
    for table in catalog["tables"]:
        column = table["first_column"]
        nothing = f"{column}=is.null&{column}=not.is.null"     # matches no row
        attempts = {
            "select": ("GET", "select=*&limit=1", None),
            "insert": ("POST", "", []),                         # zero rows, privileges still checked
            "update": ("PATCH", nothing, {column: None}),
            "delete": ("DELETE", nothing, None),
        }
        allowed = {p.split("(")[0] for p in tables.get(table["name"], {}).get("anon", set())}
        for privilege, (method, query, body) in attempts.items():
            status = request(method, table, query, body)
            if 200 <= status < 300:
                got = "allowed"
            elif status in (401, 403, 404):
                got = "denied"
            else:
                report.fail("probe-inconclusive", f"{privilege} on {table['name']} returned {status}")
                continue
            want = "allowed" if privilege in allowed else "denied"
            if got != want:
                report.fail("probe-mismatch", f"the publishable key's {privilege} on "
                            f"{table['name']} was {got} (HTTP {status}); access.toml says {want}")
    if report.failures == before:
        report.ok(f"{len(catalog['tables'])} relations answer the publishable key as access.toml says")


def check_auth(report, config, declared):
    report.section("auth")
    before, warned = report.failures, report.warnings
    auth = config.get("auth", {})
    email = auth.get("email", {})
    signups = auth.get("enable_signup", False) and email.get("enable_signup", False)
    if signups and not email.get("enable_confirmations", False):
        report.fail("ghost-auth", "signups are on without email confirmation: anyone gets an "
                    "authenticated session for an address they don't own")
    anonymous = auth.get("enable_anonymous_sign_ins", False)
    if anonymous != declared.get("anonymous_sign_ins", False):
        report.fail("anonymous-sign-ins", f"anonymous sign-ins are {'on' if anonymous else 'off'}; "
                    "access.toml says otherwise")
    for redirect in [auth.get("site_url", ""), *auth.get("additional_redirect_urls", [])]:
        if "*" in redirect:
            report.fail("redirect-wildcard", f"redirect URL {redirect} has a wildcard; "
                        "a crafted link can send a session token elsewhere")
    if signups and not declared.get("accounts", False):
        report.warn("signups-before-accounts", "signups are on but the app has no accounts yet; "
                    "anyone can mint an `authenticated` session. Turn off \"Allow new users to "
                    "sign up\" until 0.9.0, or keep authenticated's access equal to anon's")
    if signups and auth.get("minimum_password_length", 0) < 8:
        report.warn("password-length", f"minimum password length is "
                    f"{auth.get('minimum_password_length')}; use at least 8")
    if report.failures == before and report.warnings == warned:
        report.ok("signups, confirmation, anonymous sign-ins and redirects are as declared")


# ---------------------------------------------------------------- main

def main(argv):
    offline = "--offline" in argv
    app = None
    if "--app" in argv:
        app = Path(argv[argv.index("--app") + 1]).expanduser().resolve()

    report = Report()
    tables, callable_, buckets, auth = load_access()
    check_migrations(report, tables)
    if offline:
        check_staged_secrets(report)
    else:
        check_secrets(report, history=True, app=app)
        try:
            check_advisors(report, tables, auth)
            config = resolved_config()
            schemas = config.get("api", {}).get("schemas", ["public", "graphql_public"])
            catalog = live_catalog(schemas)
            check_catalog(report, catalog, tables, callable_, buckets)
            check_probe(report, catalog, tables)
            check_auth(report, config, auth)
        except RuntimeError as error:
            report.fail("supabase-cli", f"{error} (logged in? `npx --yes supabase@2 login`)")

    print(f"\nsupabase-check: {report.failures} failure(s), {report.warnings} warning(s)")
    return 1 if report.failures else 0


def check_staged_secrets(report):
    report.section("secrets")
    known = known_secrets()
    staged = subprocess.run(["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"],
                            cwd=ROOT, capture_output=True, check=True).stdout.decode().split("\0")
    clean = True
    for name in filter(None, staged):
        if name.endswith(("AppSecrets.plist", "TMDBSecrets.plist")):
            report.fail("secrets-tracked", f"{name} is staged; it must stay gitignored")
            clean = False
            continue
        blob = subprocess.run(["git", "show", f":{name}"], cwd=ROOT, capture_output=True).stdout
        for hit in secret_hits(blob, known):
            report.fail("secret-staged", f"{name}: contains {hit}")
            clean = False
    if clean:
        report.ok("staged files hold no keys")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
