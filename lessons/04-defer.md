# Lesson 04 — Defer: making a build fail, then fixing it with one flag

**Goal:** watch Slim CI fail for the real reason, then fix it with `--defer`.

Still local. No GitHub Actions. After this lesson you have run the whole
CI command by hand.

---

## 1. Two jobs, not one

Lesson 03 answered *what to build*. That is only half the command.

- `state:modified+` asks: *which models do I build?*
- `--defer` asks: *for everything I did not build, where do I read it?*

Those are not the same job. Same `prod_dbt_artifacts/manifest.json`. Two
different uses.

Take `orders`. You did not edit it. You did not edit `stg_orders` either.
But `orders.sql` still says:

```sql
select * from {{ ref('stg_orders') }}
select * from {{ ref('int_order_payments') }}
```

| `ref()` | Selected by `state:modified+`? | Who should serve it? |
|---|---|---|
| `int_order_payments` | yes — downstream of `stg_payments` | CI, the new version |
| `stg_orders` | no — payments never touch it | prod, the existing version |

`--defer` is the switch that makes the second row work.

---

## 2. Empty the leftover CI schema

Lesson 02 already ran `dbt build --target ci`. So `ci_local` is full.
If you Slim-CI into a full schema, the missing-table error never shows up.
You read yesterday's leftover tables and call it a pass.

Empty it. Refresh prod while you are here, so the shelf you defer to is real.

```bash
uv run dbt build --target prod
mkdir -p prod_dbt_artifacts
cp target/manifest.json prod_dbt_artifacts/manifest.json

uv run python -c "import duckdb; duckdb.connect('database/database.duckdb').execute('drop schema if exists ci_local cascade')"
```

`--defer` reads **tables**, not just the manifest. A compile-only artifact
tells dbt the address. The warehouse still has to hold the data.

---

## 3. The same change as Lesson 03

```bash
echo "-- experiment" >> models/staging/stg_payments.sql

uv run dbt ls --quiet --select state:modified+ --state prod_dbt_artifacts/ \
  --resource-type model --output name
```

```
customers
int_order_payments
orders
stg_payments
```

Four models. Now **build** that list, not just list it.

---

## 4. Build it. Watch it fail.

```bash
uv run dbt build --target ci --select state:modified+ --state prod_dbt_artifacts/
```

```
ERROR creating sql view model ci_local.stg_payments
Catalog Error: Table with name raw_payments does not exist!
Did you mean "dev.raw_payments or raw.raw_payments"?

  select * from "database"."ci_local"."raw_payments"
```

Read that twice.

`stg_payments` refs `raw_payments`. The seed did not change, so it is not
selected. CI looks in its own schema: `ci_local.raw_payments`. Empty schema.
Nothing there.

DuckDB even points at the answer: `raw.raw_payments`. That is production.
`--defer` is how you take the hint.

| Thing | Selected? | CI looks for | Exists? |
|---|---|---|---|
| `stg_payments.sql` | yes | (this is what we are building) | — |
| `raw_payments` | no | `ci_local.raw_payments` | no |
| prod's seed | — | `raw.raw_payments` | yes |

The wrong mental model: *"I selected four models, so those four should
build."*

The right one: *a model can only build if every `ref()` already exists in
the place dbt is looking.*

---

## 5. The tempting wrong fix

"So add `+` on the other side and build the upstreams too."

```bash
uv run dbt ls --quiet --select +state:modified+ --state prod_dbt_artifacts/ \
  --resource-type model --output name
```

```
customers
int_order_payments
orders
stg_payments
```

Same four models. The extra `+` added the seed `raw_payments` — check with
`--resource-type seed` if you want — but not `stg_orders`.

Why? `+state:modified+` means ancestors of **the modified node**, plus its
descendants. The modified node is `stg_payments`. Its only ancestor is
`raw_payments`. `stg_orders` is an ancestor of `orders`, not of
`stg_payments`. The selector cannot see it.

Build it anyway:

```bash
uv run python -c "import duckdb; duckdb.connect('database/database.duckdb').execute('drop schema if exists ci_local cascade')"

uv run dbt build --target ci --select +state:modified+ --state prod_dbt_artifacts/
```

```
ERROR creating sql table model ci_local.orders
Catalog Error: Table with name stg_orders does not exist!
Did you mean "dev.stg_orders or staging.stg_orders"?

  select * from "database"."ci_local"."stg_orders"
```

Same crash. One hop later. You rebuilt the seed. You still did not rebuild
`stg_orders`. And you should not — that is the whole point of Slim CI.

Growing the selector is the wrong job. Pointing the leftover `ref()`s at
prod is the right one.

---

## 6. One flag

Empty CI again, then add `--defer`. Nothing else changes.

```bash
uv run python -c "import duckdb; duckdb.connect('database/database.duckdb').execute('drop schema if exists ci_local cascade')"

uv run dbt build --target ci --select state:modified+ --defer --state prod_dbt_artifacts/
```

```
OK created sql view model ci_local.stg_payments
OK created sql view model ci_local.int_order_payments
OK created sql table model ci_local.orders
OK created sql table model ci_local.customers
Done. PASS=16 ERROR=0
```

That is the whole Slim CI command. You will put it in GitHub Actions in
Lesson 06.

### What `--defer` rewrote

Look at the compiled SQL. dbt left this file after the run:

```bash
cat target/compiled/dbt_duckdb_cicd/models/marts/orders.sql
```

Without `--defer`:

```sql
select * from "database"."ci_local"."stg_orders"            -- missing
select * from "database"."ci_local"."int_order_payments"    -- being built
```

With `--defer`:

```sql
select * from "database"."staging"."stg_orders"             -- prod
select * from "database"."ci_local"."int_order_payments"    -- CI
```

One model. Two `ref()`s. Two different shelves.

`--defer` only rewrites a `ref()` when **both** are true:

1. That node is **not** selected.
2. It does **not** already exist in the current target.

`int_order_payments` is selected, so it stays `ci_local`.
`stg_orders` is not selected and `ci_local` is empty, so it becomes
`staging.stg_orders` — the address Lesson 03 printed from the manifest.

| `ref()` in `orders` | Selected? | Exists in `ci_local`? | Resolves to |
|---|---|---|---|
| `int_order_payments` | yes | about to | `ci_local.int_order_payments` |
| `stg_orders` | no | no | `staging.stg_orders` |

`customers` does the same split: new `ci_local.orders`, existing
`staging.stg_customers`.

### What landed

```bash
uv run python -c "
import duckdb
con = duckdb.connect('database/database.duckdb', read_only=True)
for r in con.execute('''select table_name from information_schema.tables
  where table_schema = 'ci_local' order by 1''').fetchall():
    print(r[0])
"
```

```
customers
int_order_payments
orders
stg_payments
```

Four objects. Not nine. `stg_orders` and `stg_customers` never left
`staging`. That is Slim CI: write only what the PR can break, read the rest
from prod.

---

## 7. Why we emptied `ci_local`

`--defer` checks "does this already exist in the current target?" before
it rewrites.

Skip the drop and `ci_local.raw_payments` is still sitting there from
Lesson 02. The first command — **no `--defer`** — goes green. That is not
success. You tested against leftover CI tables, not production.

Real CI deletes the PR schema at the end of the run, so this does not
come up. On a laptop it does. Drop the schema before you rehearse.

There is a flag for the leftover-table case: `--favor-state`. It means
"use prod for unselected refs even if a local copy exists." Useful in
dev. We do not need it here. We emptied the schema instead.

---

## 8. Put the file back

```bash
git restore models/staging/stg_payments.sql
```

`git restore` discards every uncommitted change to that file. Fine for
this experiment. Do not run it on a file you have been editing for real.

Confirm you are clean:

```bash
uv run dbt ls --quiet --select state:modified --state prod_dbt_artifacts/ --output name
```

That must print nothing.

Optional — tear down the rehearsal schema:

```bash
uv run python -c "import duckdb; duckdb.connect('database/database.duckdb').execute('drop schema if exists ci_local cascade')"
```

---

Tiny mental model: `state:modified+` is the shopping list. `--defer` is
the note that says "for anything not on the list, grab it from the prod
shelf." Same manifest. Two jobs.

---

## Checkpoint

1. You skip the `drop schema ci_local` step. The no-`--defer` build goes
   green. **Why is that not Slim CI working?**

2. `orders` refs `stg_orders`. Without `--defer`, where does CI look?
   With `--defer`, where?

3. Someone proposes `--select +state:modified+` "so we don't need
   `--defer`." What does that still miss, and why?

4. `--defer` rewrites `raw_payments` to `raw.raw_payments`. You never ran
   `dbt build --target prod` — you only compiled. What happens, and why?

---

## Where this leaves us

You now have the whole command, on your laptop, and you have watched it
fail without `--defer`:

```bash
uv run dbt build --target ci \
  --select state:modified+ \
  --defer --state prod_dbt_artifacts/
```

Lesson 05 puts the production half on GitHub Actions. Merge to `main`
builds everything and uploads that artifact. Lesson 06 is this same
command, on a pull request.

---

Next: **Lesson 05 — Your first workflow, production (CD).**
