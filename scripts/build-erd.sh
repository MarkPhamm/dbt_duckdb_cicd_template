#!/usr/bin/env bash
# Regenerate erd/ from the dbt project.
#
# Run this whenever you add, remove or rename a model, a seed, or a documented
# column — then commit erd/ with the rest of your change. CI runs the same
# import with --check and fails the PR if what you committed is out of date.
#
# The version is pinned to match .github/workflows/ci.yml. If you bump one,
# bump the other, or local and CI will disagree about what "up to date" means.
set -euo pipefail

QDBD_VERSION="0.2.3"

cd "$(dirname "$0")/.."

# No --target: the ERD is identical for dev, ci and prod. `state:modified`
# compares code, and so does this — neither cares where the tables land.
uv run dbt parse

uvx --from "quickdbd-cli==${QDBD_VERSION}" qdbd import dbt target/manifest.json -o erd/

echo
echo "erd/ regenerated. Commit it:  git add erd/ && git commit"
