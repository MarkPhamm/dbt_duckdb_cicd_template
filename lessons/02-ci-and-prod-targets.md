# Lesson 02 — Adding `ci` and `prod`, and layered schemas

**Goal:** have all three environments working locally, and be able to explain
why production's tables are named differently from yours.

In Lesson 01 you had one target. Now you get three — and you'll run all three
on your laptop, before any of this is automated.

---

## 1. Answering the checkpoint from Lesson 01

> *You run `dbt build --target prod`, but `profiles.yml` has no `prod` entry.*

```
Runtime Error
  The profile 'dbt_cicd_course' does not have a target named 'prod'.
  The valid target names for this profile are:
   - dev
```

dbt tells you the valid targets. There's nothing to configure "about
environments" beyond adding an entry — which is the whole point of Lesson 00's
claim that an environment is just a target.

---

## 2. The three targets

Open `profiles.yml`. All three now exist, and **all three point at the same
database file**:

```yaml
outputs:
  dev:
    path: database/database.duckdb
    schema: dev

  ci:
    path: database/database.duckdb
    schema: "{{ env_var('DBT_CI_SCHEMA', 'ci_local') }}"

  prod:
    path: database/database.duckdb
    schema: prod
```

Only `schema:` differs. Two of those lines deserve attention.

### `env_var('DBT_CI_SCHEMA', 'ci_local')`

CI needs a *different* schema per pull request — PR #42 must not overwrite what
PR #43 is building. GitHub Actions will set `DBT_CI_SCHEMA=ci_pr_42` at
runtime.

The second argument is a **default**. With nothing set — i.e. on your laptop —
you get `ci_local`. That's deliberate: it means you can rehearse the entire CI
run by hand, which is exactly what Lesson 04 has you do.

> `env_var()` with a default is the standard way to make a target work both in
> CI and locally. Without the default, `dbt parse` would fail on your machine
> with `Env var required but not provided`.
>
> Prove it to yourself — this creates a *second*, separate CI schema:
>
> ```bash
> DBT_CI_SCHEMA=ci_pr_42 uv run dbt build --target ci
> ```
>
> You'll now have both `ci_local` and `ci_pr_42` holding 9 objects each. One
> environment variable, two isolated environments, zero file changes. That is
> precisely how two open pull requests stay out of each other's way.
>
> Clean up the extra one when you're done:
>
> ```bash
> uv run python -c "import duckdb; duckdb.connect('database/database.duckdb').execute('drop schema if exists ci_pr_42 cascade')"
> ```

### `schema: prod` — the one that lies

This is nearly a decoy. Production models do **not** land in a schema called
`prod`. Section 3 explains why.

---

## 3. Layered schemas — production only

Run all three and look at what appears:

```bash
rm -f database/database.duckdb
uv run dbt build --target dev
uv run dbt build --target ci
uv run dbt build --target prod
```

```bash
uv run python -c "
import duckdb
con = duckdb.connect('database/database.duckdb', read_only=True)
for r in con.execute('''select table_schema, count(*) from information_schema.tables
  where table_schema not in ('information_schema','pg_catalog','main')
  group by 1 order by 1''').fetchall(): print(f'  {r[0]:<16} {r[1]} objects')
"
```

```
  ci_local         9 objects     ← everything, flat
  dev              9 objects     ← everything, flat
  intermediate     1 objects     ┐
  marts            2 objects     │ production, split by layer
  raw              3 objects     │
  staging          3 objects     ┘
```

Same SQL. Same database file. Three very different layouts.

### Why the asymmetry

**Production is split** because it has many consumers. Analysts, BI tools and
downstream jobs need `marts.customers` to be a stable address they can write
into a dashboard. If `customers` sat next to `stg_customers` in one schema,
someone would eventually query a staging view by accident and not know it.

**Dev and CI are flat** because each has exactly one consumer — you, or one
pull request. Splitting six models across three schemas there buys nothing and
costs you a `union` every time you want to see what you just built.

**And teardown gets trivial.** When PR #42 closes, cleanup is one statement:

```sql
drop schema ci_pr_42 cascade;
```

Not three. Same when you want to reset your dev sandbox. That's an operational
argument, not an aesthetic one.

---

## 4. How the split actually happens

Two files cooperate. Neither works without the other.

### `dbt_project.yml` declares the layer

```yaml
seeds:
  dbt_cicd_course:
    +schema: raw

models:
  dbt_cicd_course:
    staging:      {+materialized: view,  +schema: staging}
    intermediate: {+materialized: view,  +schema: intermediate}
    marts:        {+materialized: table, +schema: marts}
```

### `macros/generate_schema_name.sql` decides whether to listen

```sql
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if target.name == 'prod' and custom_schema_name is not none -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}
    {%- endif -%}
{%- endmacro %}
```

**dbt calls this macro once per model. Whatever it returns *is* the schema.**
There is no other mechanism. Environments are, quite literally, whatever this
macro says they are.

Trace two models through it:

| model | target | `custom_schema_name` | returns |
|---|---|---|---|
| `customers` | `prod` | `marts` | `marts` |
| `customers` | `dev` | `marts` | `dev` |
| `stg_orders` | `prod` | `staging` | `staging` |
| `stg_orders` | `ci` | `staging` | `ci_pr_42` |

Notice row 2: in dev, `+schema: marts` is **read and then thrown away**.

### ⚠️ This is not dbt's default

dbt's built-in `generate_schema_name` **concatenates**. Out of the box you'd
get:

| | default dbt | ours |
|---|---|---|
| dev + `marts` | `dev_marts` | `dev` |
| prod + `marts` | `prod_marts` | `marts` |

If you've ever set `+schema: staging`, expected a `staging` schema, and gotten
`dev_staging` instead — *that's* the default behaviour, and it confuses
everyone exactly once.

We override it because we want neither of those: clean names in prod, flat
everywhere else. **Remember this macro exists**, or you will eventually spend
an afternoon wondering why `+schema:` appears to do nothing in dev.

---

## 5. The risk we just created

Look again at all three targets:

```yaml
dev:   {path: database/database.duckdb, schema: dev}
ci:    {path: database/database.duckdb, schema: "..."}
prod:  {path: database/database.duckdb, schema: prod}
```

**Nothing stops you from typing `--target prod` right now and overwriting
production.** One file, one set of permissions, no protection.

That is *not* how a real warehouse works. On Snowflake, the three targets would
carry three different sets of credentials, and the CI role simply would not
hold write grants on production schemas. The separation is enforced by the
database, not by you remembering which flag to type.

This is the first real training wheel in the course. We'll come back to it in
Lesson 07 and be specific about what replaces it.

---

## 6. What production is really for

You can now run:

```bash
uv run dbt build --target prod
```

…and it builds every model into `raw` / `staging` / `intermediate` / `marts`.

But remember Lesson 00: **a production run produces two outputs.** You've seen
the tables. The other one is sitting in `target/manifest.json`, and it's the
reason CI can be clever.

That's Lesson 03.

---

## ✅ Checkpoint

1. `dbt build --target ci` on your laptop wrote to `ci_local`. In GitHub
   Actions the same command writes to `ci_pr_42`. **Nothing in the repo
   changed between those two runs** — so what did?

2. You add `models/reporting/exec_summary.sql` with no `+schema:` config
   anywhere. Where does it land in dev? Where in prod? (Follow the macro.)

3. A teammate asks: *"Why don't we just use separate DuckDB files —
   `dev.duckdb`, `prod.duckdb` — instead of schemas?"* Give them one reason
   schemas are the better model, and one thing the single-file approach makes
   genuinely riskier.

4. Still open from Lesson 01, and it's the one that matters:
   **you edit `stg_payments.sql` — which of the six models need rebuilding?**

   Lesson 03 has dbt answer this mechanically. Write yours down first.

---

Next: **Lesson 03 — what's actually inside `manifest.json`.**
