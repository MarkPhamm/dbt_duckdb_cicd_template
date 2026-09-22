# Lesson 01 — The project, and your `dev` environment

**Goal:** get the project running on your machine, and be able to say exactly
where your tables went and *why they went there*.

---

## 1. Set up

```bash
uv sync          # installs Python 3.12 + dbt-core 1.12.5 + dbt-duckdb 1.11.0
uv run dbt build
```

That's it. No database to install, no credentials, no cloud account — DuckDB is
just a file that appears when dbt writes to it.

> **Why `uv run` and not plain `dbt`?** `uv run` uses the exact versions pinned
> in `pyproject.toml` and `uv.lock`. Your CI runner will install from those same
> two files, so local and CI are guaranteed identical. The day dbt 1.13 ships,
> nothing on your machine silently changes underneath you.
>
> This matters more than it sounds. "Works locally, fails in CI" is almost
> always a version drift problem.

---

## 2. The three files that define the project

### `pyproject.toml` — what to install

Pinned to exact versions (`==`, not `>=`). CI reads the same file.

### `dbt_project.yml` — what the project *is*

```yaml
profile: dbt_cicd_course      # <- which profile in profiles.yml to use

models:
  dbt_cicd_course:
    staging:
      +materialized: view     # staging = cheap, disposable
    marts:
      +materialized: table    # marts = queried often, worth persisting
```

The line that matters for this course is `profile:`. It's a **pointer**. This
file says *what to build*; `profiles.yml` says *where to put it*. That
separation is the reason one unchanged project can build into dev, ci, or prod.

### `profiles.yml` — where to write

```yaml
dbt_cicd_course:
  target: dev                 # <- the default when you don't pass --target
  outputs:
    dev:
      type: duckdb
      path: database.duckdb   # the file
      schema: dev             # the schema inside it
      threads: 4
```

**`outputs:` is a list of environments.** Right now there's exactly one. In
Lesson 02 we add `ci` and `prod` — and they'll point at the *same*
`database.duckdb`, differing only in `schema`.

> **Two things worth noticing.**
>
> 1. This file is **committed to the repo**, which is normally a cardinal sin.
>    We get away with it because DuckDB has no credentials at all. On Snowflake
>    the structure is identical, but every secret becomes
>    `password: "{{ env_var('DBT_PASSWORD') }}"` and lives in GitHub Secrets.
>    *The shape never changes — only where the values come from.*
>
> 2. dbt normally looks for `profiles.yml` in `~/.dbt/`. It also checks the
>    current directory, which is why ours works. Keeping it in the repo is what
>    lets CI use it without any extra setup.

---

## 3. The DAG

Five models, deliberately small enough to hold in your head:

```
raw_customers ──> stg_customers ───────────────┐
                                                ├──> customers
raw_orders ─────> stg_orders ──┐                │
                               ├──> orders ─────┘
raw_payments ───> stg_payments ┘
```

The `raw_*` are seeds (CSVs in `seeds/`) standing in for source tables.

**Study the shape — it's the whole reason the later lessons work.** Ask
yourself: if you edit `stg_payments`, which models are downstream of it? Which
are not? You'll need that answer in Lesson 03.

---

## 4. Where did everything go?

```bash
uv run python -c "
import duckdb
con = duckdb.connect('database.duckdb', read_only=True)
for r in con.execute('''
  select table_schema, table_name, table_type
  from information_schema.tables order by 1, 3 desc, 2
''').fetchall(): print(f'{r[0]:<8} {r[1]:<16} {r[2]}')
"
```

```
dev      stg_customers    VIEW
dev      stg_orders       VIEW
dev      stg_payments     VIEW
dev      customers        BASE TABLE
dev      orders           BASE TABLE
dev      raw_customers    BASE TABLE
dev      raw_orders       BASE TABLE
dev      raw_payments     BASE TABLE
```

Everything is in schema **`dev`**. Trace why, because this chain is the thing
the whole course rests on:

```
you ran `dbt build` with no --target
   └─> profiles.yml says `target: dev`
        └─> the `dev` output says `schema: dev`
             └─> so every model was created in schema `dev`
```

Change one word in `profiles.yml` and all eight objects land somewhere else.
**That is the entire mechanism behind environments.** There is nothing more to it.

---

## 5. The tests are not decoration

`dbt build` ran 22 nodes: 3 seeds, 5 models, and **14 tests**. Those tests are
the reason CI can have an opinion about your pull request.

Look at `models/staging/schema.yml`:

```yaml
- name: status
  data_tests:
    - accepted_values:
        arguments:
          values: ['completed', 'returned', 'placed']
```

If someone's PR introduces an order with status `'cancelled'`, this test goes
red — **in the pull request, before it merges**. A human reviewer reading a diff
would never catch that. A test does it for free, every time.

> The `arguments:` nesting is dbt 1.12+ syntax. Older tutorials put `values:`
> directly under `accepted_values:`; that still runs but emits a deprecation
> warning.

---

## 6. Try it yourself

**Experiment 1 — the target really is the only thing deciding where data lands.**
Temporarily change `schema: dev` to `schema: dev_scratch` in `profiles.yml`, then:

```bash
uv run dbt build
```

Re-run the inspection query from section 4. You now have *two* full copies of
your models side by side, in `dev` and `dev_scratch`, from identical SQL. One
word in one file. **Change it back to `dev` before moving on**, then drop the
scratch schema:

```bash
uv run python -c "import duckdb; duckdb.connect('database.duckdb').execute('drop schema if exists dev_scratch cascade')"
```

> **Try `dbt run` instead of `dbt build` there and it fails with 3 errors.**
> Worth understanding now: `run` builds models but *not* seeds, so the `raw_*`
> tables don't exist in the new schema and every staging model has nothing to
> read from.
>
> Sit with that for a second, because it's the whole problem of Lesson 04 in
> miniature: **a model can only build if the things it references already exist
> in the place it's looking.** CI hits this constantly — it builds two models
> into an empty schema and the refs point at nothing. The fix is `--defer`.

That's a preview of the real thing: `ci` and `prod` are that same one-word
difference, just automated.

**Experiment 2 — selecting a subset.**

```bash
uv run dbt run --select stg_payments
```

Only one model rebuilt. You already know how to select models by hand. **Hold
onto that**, because Slim CI is nothing more than dbt working out that
`--select` argument *for you*, automatically, from what the PR changed.

---

## ✅ Checkpoint

1. You run `uv run dbt build --target prod`, but `profiles.yml` has no `prod`
   entry yet. What happens, and which of the three config files would you fix?

2. `stg_orders` is a **view** and `orders` is a **table**. Where is that decided
   — and why would a team make staging models views and marts tables?

3. Here's the one that matters. Look at the DAG in section 3.
   **You edit `stg_payments.sql`.** Which of the five models genuinely need
   rebuilding, and which are unaffected?

   Write down your list. We'll have dbt generate the same list mechanically in
   Lesson 03, and you'll want to compare.

---

Next: **Lesson 02 — adding `ci` and `prod`.**
