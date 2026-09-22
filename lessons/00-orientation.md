# Lesson 00 — What problem are we actually solving?

> **No code in this lesson.** Read it, answer the checkpoint at the bottom, and
> then go to Lesson 01. It's about ten minutes.

You already know dbt. You can write a model, add a test, run `dbt build`, and
reason about a DAG. This course is not about any of that.

It's about the question that comes *after* you know dbt:

> **Someone opens a pull request that changes one model. How do you know it's
> safe to merge — without rebuilding your entire warehouse to find out?**

Everything here is in service of answering that.

---

## The situation before CI/CD

Here's how a team without CI/CD usually works. See how much of it is familiar:

1. You edit `stg_payments.sql` on your laptop.
2. You run `dbt build` locally. It passes. 
3. You open a PR. A colleague reads the diff and says "looks good to me."
4. You merge.
5. Production runs that night.
6. At 6am, a dashboard is broken.

The failure isn't laziness — **every step there was done properly.** The problem
is structural. Three things went unverified:

- Your laptop ran against *your* data, which may not match production's.
- Your colleague reviewed **SQL text**, not **results**. Nobody can eyeball a
  join and know whether it fans out a row count.
- Nothing checked what your change did to the **17 models downstream** of the
  one you touched.

CI/CD closes exactly those three gaps. That's its whole job.

---

## The core idea: an environment is not a dbt feature

This is the single most important sentence in the course, so here it is on its
own line:

> **An "environment" is just a target: a place to write, and a name to write under.**

There is no `environment:` key in dbt. There's no special mode. When people say
"our CI environment," they mean *a set of connection details in `profiles.yml`
that happens to point somewhere disposable.* That's it. Once that clicks, the
rest of this course is mechanics.

We'll use three:

| | `dev` | `ci` | `prod` |
|---|---|---|---|
| **Who runs it** | you, on your laptop | GitHub Actions, on a PR | GitHub Actions, on merge to `main` |
| **Schema** | `dev` | `ci_pr_42` | `prod` |
| **What it builds** | whatever you select | only what changed | everything |
| **Lifetime** | as long as you want | deleted after the PR | it *is* the warehouse |
| **If it breaks** | nobody notices | the PR goes red | someone gets paged |

Note the last row. That's the real hierarchy: each environment exists to catch
mistakes before they reach the one below it.

### Where they live

We're using DuckDB, so our "warehouse" is a single file:
`database/database.duckdb`. All three environments live **inside that one
file**, separated only by schema:

```
database/database.duckdb
├── dev          ← you
├── ci_pr_42     ← a pull request, temporarily
├── raw          ┐
├── staging      │
├── intermediate ├── production
└── marts        ┘
```

(Production splits into layers because lots of people query it; dev and CI stay
flat because each has exactly one consumer. Lesson 02 covers why.)

This is not a DuckDB quirk — it's exactly how Snowflake, BigQuery and Redshift
teams do it. You don't get a separate warehouse per environment. You get one
warehouse, and you separate environments by **schema naming convention**.

---

## The second idea: production has two outputs

When your production job runs, you probably think of it as producing **tables**.

It produces two things:

```
dbt build --target prod
   │
   ├──> the tables          (what everyone thinks about)
   └──> target/manifest.json  (what makes CI possible)
```

`manifest.json` is a complete description of your project at the moment it ran:
every model, its compiled SQL, its dependencies, and — crucially — a **checksum
of each model's file contents.**

Hold onto that. Because if CI has production's manifest, it can compare it
against the current code and answer a question it otherwise couldn't:

> *"Which models actually changed?"*

And once you can answer that, you can build only those. That's "Slim CI," and
it's the payoff of this whole course.

---

## What we're going to build

```
  merge to main ──> prod.yml ──> dbt build --target prod   (build everything)
                                      │
                                      └──> upload artifact:
                                             manifest.json + database.duckdb
                                                    │
                                                    │  (GitHub stores it)
                                                    ▼
  open a PR ──────> ci.yml ───> download that artifact
                                      │
                                      └──> dbt build --target ci \
                                             --select state:modified+ \
                                             --defer --state ./state

                                    builds ONLY changed models  ──> ci_pr_42
                                    everything else resolves to ──> prod
```

Read the CI command once more, because those three flags are the entire trick:

- `--select state:modified+` — "only models that differ from production, **plus
  everything downstream of them**" (that's what the `+` means)
- `--state ./state` — "production's manifest is in this folder; compare against it"
- `--defer` — "for anything I did *not* build, use production's version instead"

Without these, a PR check has to rebuild your whole project. With them, a
one-model change builds one model.

---

## How this course runs

Nine short lessons. **Lessons 01–04 never touch GitHub Actions** — you'll do
slim CI by hand, on your laptop, until it's boring. Only then do we automate it.

That order is deliberate. If you meet `--defer` for the first time inside a
YAML file on a remote runner, it's magic. If you've already run it yourself and
watched it fail without the flag, it's just a command.

| # | Lesson |
|---|---|
| 00 | ← you are here |
| 01 | The project, and your `dev` environment |
| 02 | Adding `ci` and `prod` — what a target really is |
| 03 | State: what's actually inside `manifest.json` |
| 04 | Defer: making a build fail, then fixing it with one flag |
| 05 | Your first workflow — production (CD) |
| 06 | Slim CI on a real pull request |
| 07 | Feedback and guardrails |
| 08 | Where the training wheels are (and what's different on Snowflake) |

---

## ✅ Checkpoint

Answer these in your own words before moving on. If you're unsure, the answer
is above — go find it rather than guessing.

1. A colleague says: *"We should add a `ci` environment to our dbt project."*
   Concretely, what file would they edit, and what would they add to it?

2. Your production job finished successfully last night. It produced the tables.
   **What else did it produce**, and why does tomorrow's pull request care?

3. In `--select state:modified+`, what does the `+` do? What would break if you
   left it off?

When you've got these, open **Lesson 01**.
