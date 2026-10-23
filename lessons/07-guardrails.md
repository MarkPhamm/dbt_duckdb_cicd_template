# Lesson 07 — Feedback and guardrails

**Goal:** make a red check mean something, and name the hole `ci.yml`
cannot close.

The pipeline already runs. A red PR can still merge. A laptop can still
type `--target prod`. Those are two different holes. They need two
different locks.

---

## 1. Two holes, not one

Take `stg_payments`. You break a test. Two bad endings:

| Hole | What you did | What `ci.yml` does | What still happens |
|---|---|---|---|
| Merge a red PR | open a PR that fails Slim CI | the check goes red | you click Merge anyway |
| Write prod from a laptop | `uv run dbt build --target prod` | nothing. no PR. | `marts.customers` is gone |

The wrong picture: *"We have CI, so production is safe."*

CI is a light on the dashboard. A light you can drive through is
feedback. A gate that will not open is a guardrail.

| | Feedback | Guardrail |
|---|---|---|
| What it is | the `ci / slim-ci` check on the PR | Settings that refuse merge until that check is green |
| Lives in | `.github/workflows/ci.yml` (git) | the repo's branch rules (not git) |
| Stops a red merge? | no | yes |
| Stops `dbt build --target prod` on your laptop? | no | no |

That last row is Lesson 02's risk. We will name what replaces it. We
cannot install it in DuckDB.

---

## 2. Feedback is the check, not the diff

Lesson 00: a colleague reading SQL is not a review of results. The
check is.

Open any PR that touched a model. **Checks** → **ci / slim-ci**.

That name is `{workflow} / {job}`. The file is `ci.yml`. The job is
`slim-ci`. When you pin a required check later, type it exactly.

A useful log looks like Lesson 06:

```
OK created sql view model ci_pr_42.stg_payments
OK created sql table model ci_pr_42.orders
Done. PASS=16 ERROR=0
```

A useful failure looks like Lesson 04:

```
ERROR creating sql view model ci_pr_42.stg_payments
Catalog Error: Table with name raw_payments does not exist!
```

or a test:

```
FAIL 1 not_null_stg_payments_payment_id
```

Read the model name and the error. Do not reread the YAML. The
workflow already did its job: it ran the command. The log is the
review.

---

## 3. Latest push wins. Old runs die.

`ci.yml` now has:

```yaml
concurrency:
  group: ci-${{ github.event.pull_request.number }}
  cancel-in-progress: true
```

You push a fix. The run for the broken commit is cancelled. The new
run is the one that matters.

`cd.yml` is the opposite:

```yaml
concurrency:
  group: cd
  cancel-in-progress: false
```

Cancel a prod build mid-upload and tomorrow's CI has no box to open.
CI wants the latest script. CD wants the show to finish.

| File | Cancel in progress? | Why |
|---|---|---|
| `ci.yml` | yes | feedback on the latest commit, not the one you already fixed |
| `cd.yml` | no | the artifact must land |

---

## 4. The guardrail that lives outside git

`ci.yml` going red does not block merge. GitHub will happily merge a
PR with a failed check. You have to turn that off.

The wrong picture: *"I added `ci.yml`, so we are protected."*

A fork of this repo gets the workflow. It does **not** get your
branch rules. Rules live on the repo, not in the tree. Every
environment you care about — this repo, a student fork, a work clone —
needs the rule turned on once.

GitHub → **Settings** → **Rules** → **Rulesets** → **New branch
ruleset**:

1. Target `main`.
2. Require a pull request before merging. Direct pushes to `main`
   skip CI.
3. Require status checks to pass. Add `ci / slim-ci`.
4. Do not tick "bypass for administrators" if you want the rule to
   apply to you too. The person who knows `--target prod` is the
   person who will merge a red PR "just this once."

After that, a red `stg_payments` PR cannot land. The Merge button
waits. That is the gate.

Require a review if your team is more than one person. The check
reviews results. A human still reviews "did we mean to change this."

---

## 5. What this does not lock

Required checks close hole one. Hole two is still open.

```bash
uv run dbt build --target prod
```

That command works on your laptop right now. Same file as production.
Same `profiles.yml`. No password. Lesson 02 put all three targets in
one DuckDB file on purpose, so Slim CI and defer could share a
warehouse. The cost is this: **the database will not refuse you.**

| Guardrail | This course | A real warehouse |
|---|---|---|
| Default target | `dev`. forgetting `--target` writes `dev`, not prod | same idea, still just a default |
| Merge a red PR | branch rule on `ci / slim-ci` | same GitHub rule |
| `dbt build --target prod` from a laptop | nothing. the file is local | the `prod` target uses a **prod role**. your user does not have `create table` on `marts` |
| `ci.yml` writes prod | it uses `--target ci` | the CI role cannot write `marts` even if someone edits the YAML |

The replacement for "please do not type `--target prod`" is not a
dbt flag. It is **grants**. Different credentials on the `prod`
target. The CI user can write `ci_pr_42` and read `marts`. It cannot
replace `marts.customers`.

We cannot demo that grant on DuckDB. One file, no roles. That is a
training wheel. Lesson 08 takes it off.

What you *do* have here, and should not undo:

```yaml
# profiles.yml
target: dev
```

That is a seatbelt. Fat-finger `uv run dbt build` lands in `dev`.
It is not a lock. Anyone who types `--target prod` is still in.

---

## 6. A red PR, on purpose

Optional, if you want to feel the gate.

```bash
git checkout -b lesson-07-red
echo "select 1 as payment_id where false" > models/staging/stg_payments.sql
git add models/staging/stg_payments.sql
git commit -m "Break stg_payments so the required check has something to block."
git push -u origin HEAD
gh pr create --title "Lesson 07: a red check" --body "Throwaway. Close it."
```

Wait for `ci / slim-ci` to go red. If the ruleset is on, Merge is
blocked. If Merge still works, the rule is not on — or you are
bypassing it.

Close the PR. Restore `main`. Do not merge this.

---

Tiny mental model: `ci.yml` is the smoke alarm. The ruleset is the
door that will not open until the alarm is quiet. Neither of them
locks the side door labelled `--target prod`. That lock is a
warehouse role. We do not have one yet.

---

## Checkpoint

1. You add `ci.yml` and open a failing PR. The check is red. You can
   still merge. **Which of the two holes is that, and what actually
   closes it?**

2. Why does a student who forks this repo get Slim CI, but not the
   merge gate? Where does each one live?

3. `ci.yml` cancels in-progress runs. `cd.yml` does not. What breaks
   if you flip either one?

4. Required checks are on. Someone runs `uv run dbt build --target
   prod` on their laptop. Does the ruleset stop them? What would, on
   Snowflake?

---

## Where this leaves us

The two files run the two jobs. The ruleset makes CI a gate, not a
decoration. The laptop can still write prod. That is the last
training wheel.

Lesson 08 is what changes when the warehouse is real: credentials,
who uploads what, and which of these DuckDB habits you must drop.

---

Next: **Lesson 08 — Where the training wheels are.**
