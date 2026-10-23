# Lesson 08 — Where the training wheels are

**Goal:** keep the two files, the three flags, and the three targets.
Drop the DuckDB habits that would hurt you on Snowflake.

This course used one file and no passwords so you could see Slim CI
with your hands. That was the point. It is also a list of things you
must not copy into a real warehouse.

---

## 1. Two lists, not a rewrite

The wrong picture: *"Throw this repo away and start over on
Snowflake."*

The command does not change.

```bash
uv run dbt build --target ci \
  --select state:modified+ \
  --defer --state prod_dbt_artifacts/
```

`cd.yml` still builds everything on merge. `ci.yml` still proves a
PR. `state:modified+` still diffs the recipe. `--defer` still reads
the prod shelf. An environment is still a target.

What changes is **how you connect**, and **what you upload**.

| You keep | You drop |
|---|---|
| three targets in `profiles.yml` | committing the secrets next to them |
| `generate_schema_name.sql` (flat CI, layered prod) | one DuckDB file for every target |
| `state:modified+ --defer --state` | uploading `database.duckdb` |
| `cd.yml` + `ci.yml` | `DBT_PROFILES_DIR` pointing at a password in git |
| required check `ci / slim-ci` | hoping nobody types `--target prod` |

Take `stg_payments` through both worlds. Same edit. Same PR.

---

## 2. The warehouse is not a file

This course:

```
database/database.duckdb
├── dev
├── ci_pr_42
├── staging
├── intermediate
└── marts
```

One path in every target. CI downloads that file, writes `ci_pr_42`
into it, and `--defer` finds `staging.stg_orders` sitting next door.

Snowflake (or BigQuery, or Redshift) is already there. It does not
get checked out. It does not get uploaded. CD writes `marts.customers`
into the warehouse. CI connects to the **same warehouse** with a
**different role**, writes `ci_pr_42.stg_payments`, and `--defer`
reads `staging.stg_orders` over the wire.

| | This course | Snowflake |
|---|---|---|
| Where prod tables live | a gitignored file on the runner | the warehouse, always |
| What CD uploads | `manifest.json` + `database.duckdb` | `manifest.json` |
| What CI downloads | both, then `cp` into `database/` | the manifest only |
| How `--defer` finds `stg_orders` | open the downloaded file | `select` from `staging.stg_orders` as the CI role |

The `.duckdb` in the artifact was the tax. Remove those two lines
from `cd.yml` and the `cp` from `ci.yml`. Keep the manifest. That is
the whole mechanical change.

If you keep uploading a database dump to GitHub on a real project,
you are shipping production data to the runner's artifact store.
Do not.

---

## 3. Credentials are the lock Lesson 07 could not install

`profiles.yml` is committed here because DuckDB has nothing to steal.
On Snowflake the **shape** stays. The values move.

```yaml
# this course
prod:
  type: duckdb
  path: database/database.duckdb

# work
prod:
  type: snowflake
  account:  "{{ env_var('SNOWFLAKE_ACCOUNT') }}"
  user:     "{{ env_var('SNOWFLAKE_USER') }}"
  role:     transformer_prod
  warehouse: transform_l
  database: analytics
  password: "{{ env_var('SNOWFLAKE_PASSWORD') }}"
```

The password lives in GitHub Secrets. It does not live in git. Lesson
01 said this. The shape never changes — only where the values come
from.

Three targets, three roles. That is the lock.

| Target | Role | Can write | Can read |
|---|---|---|---|
| `dev` | `transformer_dev` | `dev` | sources, maybe `marts` |
| `ci` | `transformer_ci` | `ci_pr_*` | `staging`, `marts` (for `--defer`) |
| `prod` | `transformer_prod` | `staging`, `intermediate`, `marts` | sources |

Now walk `stg_payments` again.

| Command | This course | Snowflake |
|---|---|---|
| `dbt build --target prod` on a laptop | overwrites `marts.customers` | fails. your user is not `transformer_prod` |
| someone edits `ci.yml` to `--target prod` | overwrites prod from a PR | fails. the CI secret is `transformer_ci` |
| Slim CI `--defer` to `stg_orders` | reads the downloaded file | reads `analytics.staging.stg_orders` as `transformer_ci` |

The replacement for "please do not type `--target prod`" is not a
flag. It is a role that cannot `create table` on `marts`. GitHub
Secrets hold the CI role. The prod role stays on the CD job, and
with the people who are allowed to run it.

You still want `target: dev` as a seatbelt. You still want the Lesson
07 ruleset. The role is the lock those two cannot be.

---

## 4. What the YAML looks like after you drop the wheels

CD, shorter:

```yaml
- run: uv run dbt build --target prod
- run: mkdir -p prod_dbt_artifacts && cp target/manifest.json prod_dbt_artifacts/
- uses: actions/upload-artifact@v4
  with:
    name: prod-dbt-artifacts
    path: prod_dbt_artifacts/manifest.json
```

CI, shorter. No `cp` of a warehouse.

```yaml
- run: gh run download "$RUN_ID" --name prod-dbt-artifacts --dir prod_dbt_artifacts
- run: >
    uv run dbt build --target ci
    --select state:modified+
    --defer --state prod_dbt_artifacts/
```

Same flags. The CI job still needs `actions: read` and
`DBT_CI_SCHEMA=ci_pr_42`. It still fails if CD has never run. The
handshake did not move.

`generate_schema_name.sql` stays. That is not a training wheel. dbt's
default concatenates (`ci_pr_42_staging`). We flatten CI on purpose
so teardown is `drop schema ci_pr_42 cascade`. You want that on
Snowflake too.

---

## 5. Smaller wheels, still real

**Seeds are not sources.** `raw_payments` is a CSV so the course has
no warehouse to extract from. A real project uses `source()`. Slim
CI does not care. `state:modified+` and `--defer` work the same way
on a source as on a seed.

**Six models, not six hundred.** Edit `stg_payments` and four models
rebuild. That is why the DAG is tiny: you can hold the `+` in your
head. At work the `+` is the reason Slim CI exists. The command does
not change when the DAG gets wide.

**We never drop `ci_pr_42`.** On DuckDB the next CD upload is a fresh
file, so leftover CI schemas vanish. On Snowflake they pile up. Add
a cleanup job on PR close: `drop schema if exists ci_pr_42 cascade`.
Same statement Lesson 02 taught you. Automate it.

**Artifacts expire.** `retention-days: 30` in `cd.yml`. After that,
CI has no manifest. A real team stores `manifest.json` somewhere
durable — S3, the warehouse itself, dbt Cloud's "defer to
production." The idea is the same: yesterday's recipe, on disk.

**dbt Cloud is not a different idea.** It will keep the last prod
manifest for you and turn `--defer` on from a checkbox. Under the
box it is this course: compare checksums, build `state:modified+`,
read unselected parents from prod.

---

## 6. What you should be able to say

Lesson 00 asked:

> Someone opens a pull request that changes one model. How do you
> know it's safe to merge — without rebuilding your entire warehouse?

You know the answer, in one breath:

Checkout the PR. Diff it against last night's `manifest.json` with
`state:modified+`. Build that list into `ci_pr_42` with `--defer`
reading prod for everything else. If the check is green, a ruleset
lets you merge. Merge runs `cd.yml`, which rebuilds everything and
leaves a new manifest. Tomorrow's PR starts from that.

DuckDB was the set of wheels that let you run every word of that on
a laptop. Snowflake is the same sentence with a role and without a
`.duckdb` in the artifact.

---

Tiny mental model: the course built a theatre in a suitcase. The
script, the cues, and the two shows — dress rehearsal and opening
night — travel. The suitcase does not.

---

## Checkpoint

1. You move this project to Snowflake. Which two lines do you delete
   from `cd.yml`, and what breaks if you leave them in?

2. `profiles.yml` stays in the repo. What must not stay in it? Where
   do those values go?

3. A teammate has `transformer_ci` on their laptop and runs
   `dbt build --target prod`. What should happen, and which grant is
   doing the work?

4. Name three things from this course you **keep** on Snowflake, and
   one habit that only made sense because the warehouse was a file.

---

## Where this leaves you

You have the whole loop: targets, state, defer, `cd.yml`, `ci.yml`,
a gate, and a clear list of wheels to take off.

The next PR at work is the test. Change one model. If CI builds four
and leaves the rest on the prod shelf, this course did its job.
