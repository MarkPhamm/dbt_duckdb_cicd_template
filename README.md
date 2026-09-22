# dbt CI/CD — a hands-on course

A small, complete dbt project that exists to teach **how dbt CI/CD actually
works**: what `dev` / `ci` / `prod` environments really are, what `manifest.json`
is for, and how a pull request can test only the models you changed.

Built with **dbt-core + DuckDB + GitHub Actions**. No cloud account, no
credentials, no warehouse to provision — `uv sync` and you're running.

**For:** people who are comfortable writing dbt models but have never set up
environments or a CI pipeline.

---

## Start here

```bash
uv sync
uv run dbt build
```

Then read [`lessons/00-orientation.md`](lessons/00-orientation.md) and work
forward. Each lesson ends with a checkpoint — answer it before moving on.

| # | Lesson | |
|---|---|---|
| 00 | [Orientation — what problem are we solving?](lessons/00-orientation.md) | ✅ |
| 01 | [The project, and your `dev` environment](lessons/01-the-project-and-dev.md) | ✅ |
| 02 | [Adding `ci` and `prod`, and layered schemas](lessons/02-ci-and-prod-targets.md) | ✅ |
| 03 | State: what's actually inside `manifest.json` | soon |
| 04 | Defer: making a build fail, then fixing it with one flag | soon |
| 05 | Your first workflow — production (CD) | soon |
| 06 | Slim CI on a real pull request | soon |
| 07 | Feedback and guardrails | soon |
| 08 | Where the training wheels are | soon |

Lessons 01–04 are **entirely local**. We don't touch GitHub Actions until you've
already done slim CI by hand — so that when you do, it's automation of something
you understand rather than magic in a YAML file.

---

## The shape of it

Three environments, **one** `database/database.duckdb` file, separated by
schema — which is exactly how Snowflake and BigQuery teams do it:

```
database/database.duckdb
├── dev         ← you, on your laptop
├── ci_pr_42    ← a pull request, temporarily
└── prod        ← the real thing
```

And the pipeline those environments plug into:

```
  merge to main ──> prod.yml ──> dbt build --target prod
                                      │
                                      └──> upload artifact:
                                             manifest.json + database.duckdb
                                                    ▼
  open a PR ──────> ci.yml ───> download that artifact
                                      │
                                      └──> dbt build --target ci \
                                             --select state:modified+ \
                                             --defer --state ./state

                                    builds ONLY changed models  ──> ci_pr_42
                                    everything else resolves to ──> prod
```

## The project itself

Six models, kept deliberately tiny so the DAG fits in your head:

```
raw_customers ──> stg_customers ──────────────────────────┐
                                                           ├──> customers
raw_orders ─────> stg_orders ──────────┐                   │
                                       ├──> orders ────────┘
raw_payments ───> stg_payments ──> int_order_payments ─────┘
```

Edit `stg_payments` and four of the six models need rebuilding; the other two
don't. That asymmetry is what makes the CI lessons demonstrable rather than
theoretical.

## Layout

```
pyproject.toml       pinned dbt-core 1.12.5 + dbt-duckdb 1.11.0 (uv)
dbt_project.yml      what the project is
profiles.yml         where it writes — the three environments live here
database/            where database.duckdb is built (the file is gitignored)
seeds/               3 CSVs standing in for source tables
models/staging/      3 views
models/intermediate/ 1 view
models/marts/        2 tables
macros/              generate_schema_name.sql — decides every model's schema
lessons/             the course
.github/workflows/   ci.yml and prod.yml (from Lesson 05)
```
