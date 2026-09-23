# Lesson 03 — State: what's actually inside `manifest.json`

**Goal:** stop treating `manifest.json` as a mystery file, and get dbt to
answer the question you've been sitting on since Lesson 01 — *which models does
this change actually affect?*

Still entirely local. No GitHub Actions yet.

---

## 1. Where the manifest comes from

Every dbt command that parses your project writes one:

```bash
uv run dbt compile --target prod
ls target/manifest.json
```

`dbt compile` is the cheapest way to produce one — it resolves every `ref()`
and renders every model's SQL, but **runs nothing against the warehouse**.
That matters later: CI can get a manifest without touching your data.

---

## 2. Simulating the production handoff

In the real pipeline, production uploads its manifest and CI downloads it. We
don't have GitHub Actions yet, so do the handoff by hand:

```bash
mkdir -p state
uv run dbt compile --target prod
cp target/manifest.json state/manifest.json
```

**`state/` now holds "what production looks like."** That's the entire concept.
From here on, `--state state/` means *"compare against production."*

> `state/` is gitignored on purpose. It's never committed — in the real
> pipeline it arrives fresh from the last production run. Committing it would
> mean comparing against whatever was true the day someone last remembered to
> update it.

---

## 3. What's inside

It's a big JSON file (a few MB even for our six models), but you only need four
things from it.

```bash
uv run python -c "
import json
m = json.load(open('state/manifest.json'))
n = m['nodes']['model.dbt_duckdb_cicd.stg_payments']
for k in ['unique_id','schema','checksum','depends_on']:
    print(f'{k:<12} {json.dumps(n[k])[:90]}')
"
```

```
unique_id    "model.dbt_duckdb_cicd.stg_payments"
schema       "staging"
checksum     {"name": "sha256", "checksum": "3c95919f4bc4744..."}
depends_on   {"macros": [], "nodes": ["seed.dbt_duckdb_cicd.raw_payments"]}
```

### `checksum` — how dbt knows what changed

A SHA-256 of the model's **file contents**. Change one character in
`stg_payments.sql` and this number changes completely. Compare the checksums in
two manifests and you know exactly which files differ — no git required, and it
works even if someone rewrote history.

### `schema` — how `--defer` knows where to look

Note it says `staging`, not `dev`. This manifest was compiled with
`--target prod`, so it recorded **production's** addresses:

```
customers            -> marts.customers
int_order_payments   -> intermediate.int_order_payments
orders               -> marts.orders
stg_customers        -> staging.stg_customers
stg_orders           -> staging.stg_orders
stg_payments         -> staging.stg_payments
```

Hold onto this. In Lesson 04, `--defer` reads exactly these strings to decide
where to point a `ref()` it didn't build.

### `child_map` — how `+` knows what's downstream

```bash
uv run python -c "
import json
m = json.load(open('state/manifest.json'))
for c in m['child_map']['model.dbt_duckdb_cicd.stg_payments']: print(' ', c)
"
```

```
  model.dbt_duckdb_cicd.int_order_payments
  test.dbt_duckdb_cicd.accepted_values_stg_payments_payment_method__...
  test.dbt_duckdb_cicd.not_null_stg_payments_payment_id...
  test.dbt_duckdb_cicd.unique_stg_payments_payment_id...
```

The DAG, precomputed and serialised. This is why dbt can answer "what's
downstream?" instantly without re-reading your SQL.

---

## 4. The payoff

Make a change — anything, even a comment:

```bash
echo "-- experiment" >> models/staging/stg_payments.sql
```

Now ask dbt the Lesson 01 question:

```bash
uv run dbt ls --quiet --select state:modified+ --state state/ \
  --resource-type model --output name
```

```
customers
int_order_payments
orders
stg_payments
```

**Four of six.** `stg_customers` and `stg_orders` are absent — they don't
depend on payments, so nothing you did can affect them.

Compare your written-down answer from Lesson 01. If they match, you already
understood slim CI; the rest is plumbing.

> `--quiet` suppresses dbt's log lines so you get just the list. Very handy
> when piping into other commands — and it's what CI uses.

### Drop the `+`

```bash
uv run dbt ls --quiet --select state:modified --state state/ \
  --resource-type model --output name
```

```
stg_payments
```

One model. **That's what makes the `+` essential rather than decorative.**
Without it, CI would build your changed model, never rebuild `orders` or
`customers`, and cheerfully report green — while the models that your change
actually breaks went untested.

`+` after a selector means "and everything downstream." `+` before means
"and everything upstream." `state:modified+` is *"what I changed, plus
everything it could possibly break."*

Now put it back:

```bash
git checkout models/staging/stg_payments.sql
```

---

## 5. One thing worth verifying yourself

There's a trap here that used to bite people, and it's worth seeing that it
*doesn't* bite us.

Our `state/manifest.json` was compiled with `--target prod`, where models live
in `staging` / `marts`. But CI runs with `--target ci`, where everything lands
in one flat schema. **Different schemas for every single model.** Shouldn't
that make dbt think everything changed?

Test it:

```bash
echo "-- experiment" >> models/staging/stg_payments.sql
for t in prod ci dev; do
  printf "%-5s -> " "$t"
  uv run dbt ls --quiet --select state:modified+ --state state/ \
    --resource-type model --output name --target "$t" | tr '\n' ' '
  echo
done
git checkout models/staging/stg_payments.sql
```

```
prod  -> customers int_order_payments orders stg_payments
ci    -> customers int_order_payments orders stg_payments
dev   -> customers int_order_payments orders stg_payments
```

Identical. Modern dbt compares the **unrendered** config values — the literal
`+schema: marts` from `dbt_project.yml`, not the `marts` that our macro
resolved it to. So target-driven naming differences don't register as changes.

On older dbt versions this was a genuine and confusing failure mode: CI would
report every model as modified, slim CI would silently degrade into a full
build, and nobody would notice except the billing department. If you ever
inherit a project where `state:modified` selects everything, this is the first
thing to check.

---

## 6. Other state selectors

`state:modified` has siblings you'll meet eventually:

| selector | means |
|---|---|
| `state:new` | didn't exist in the old manifest at all |
| `state:modified.body` | only the SQL changed (ignores config and test changes) |
| `state:old` | the opposite of `state:new` |
| `result:error+` | nodes that failed last run, plus downstream — great for retries |

**`state:modified` already includes new models.** It means "differs from the
old manifest," and a model that didn't exist certainly differs. So
`state:modified+` catches added models too — you don't need to write
`state:modified+ state:new+`, and plenty of CI configs do so needlessly.

`state:new` is for when you want *only* the additions, which is rarer.

`state:modified+` is the one you'll use 95% of the time.

---

## ✅ Checkpoint

1. `state/manifest.json` records `stg_orders -> staging.stg_orders`. You now
   run a build with `--target ci`. **Does CI write to `staging.stg_orders`?**
   If not, what is that recorded address for?

2. You change only `models/marts/customers.sql` — the very bottom of the DAG.
   How many models does `state:modified+` select, and why?

3. You add a brand-new model `models/marts/revenue.sql`. Does `state:modified`
   catch it, or do you need to add `state:new` to your CI selector? Try it —
   create the file, run the selector, then delete it.

4. Someone proposes dropping the `+` from CI "to make it faster." Give them the
   one-sentence reason that's a bad trade.

---

## Where this leaves us

You can now compute **exactly which models a change affects.** But try actually
building that list into an empty schema and it will fail — because
`int_order_payments` needs `stg_orders`, and you didn't build `stg_orders`.

That's Lesson 04, and `--defer` is the answer.

---

Next: **Lesson 04 — Defer.**
