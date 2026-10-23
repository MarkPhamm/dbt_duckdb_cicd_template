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

| # | Lesson | Status |
|---|---|---|
| 00 | [Orientation — what problem are we solving?](lessons/00-orientation.md) | check |
| 01 | [The project, and your `dev` environment](lessons/01-the-project-and-dev.md) | check |
| 02 | [Adding `ci` and `prod`, and layered schemas](lessons/02-ci-and-prod-targets.md) | check |
| 03 | [State: what's actually inside `manifest.json`](lessons/03-state-and-manifest.md) | check |
| 04 | [Defer: making a build fail, then fixing it with one flag](lessons/04-defer.md) | check |
| 05 | [Your first workflow — production (CD)](lessons/05-cd.md) | check |
| 06 | [Slim CI on a real pull request](lessons/06-ci.md) | check |
| 07 | [Feedback and guardrails](lessons/07-guardrails.md) | check |
| 08 | [Where the training wheels are](lessons/08-training-wheels.md) | check |

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
  merge to main ──> cd.yml ───> dbt build --target prod
                                      │
                                      └──> upload artifact:
                                             manifest.json + database.duckdb
                                                    ▼
  open a PR ──────> ci.yml ───> download that artifact
                                      │
                                      └──> dbt build --target ci \
                                             --select state:modified+ \
                                             --defer --state ./prod_dbt_artifacts

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
erd/                 generated schema diagram source — committed, checked by CI
scripts/             build-erd.sh — regenerates erd/
lessons/             the course
.github/workflows/   cd.yml (Lesson 05) and ci.yml (Lesson 06 + the ERD check)
```

## The second CI check: what changed *shape*?

`slim-ci` answers *"are the numbers still right?"*. A second, independent job
answers the question a reviewer reading a SQL diff is worst at: **did a table or
column appear, vanish or get renamed?**

It runs [qdbd](https://github.com/MarkPhamm/quickdbd-cli), which reads dbt's own
two description files and writes a text description of every table into `erd/`:

| file | what it knows |
|---|---|
| `target/manifest.json` | every table, every documented column, every test |
| `target/catalog.json` | the column **types**, read back out of the warehouse |

`erd/` is **committed**, so a pull request shows the schema change as a plain
diff — and the action posts it as a comment, with an interactive diagram
attached to the run as the `erd` artifact.

Change a model's columns and CI will fail until you regenerate:

```bash
./scripts/build-erd.sh
git add erd/
```

dbt can only write `catalog.json` for relations that **exist**, so both the
script and the CI job build first. The job still shares nothing with `slim-ci` —
no prod artifact, no `--state`, no `--defer` — it builds the whole project from
the seeds into its own throwaway schema, which means it works on a repo that has
never run CD. Lesson 08 covers what you'd do instead on a warehouse where a full
build isn't free.

The ERD comes out **byte-identical** for `dev`, `ci` and `prod`. Same reason
`state:modified` does: both describe the code, not the address it lands at.
