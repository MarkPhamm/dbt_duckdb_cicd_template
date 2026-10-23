#!/usr/bin/env bash
# Regenerate erd/ from the dbt project.
#
# Run this whenever you add, remove or rename a model, a seed or a column —
# then commit erd/ with the rest of your change. CI runs the same import with
# --check and fails the PR if what you committed is out of date.
#
# The version is pinned to match .github/workflows/ci.yml. If you bump one,
# bump the other, or local and CI will disagree about what "up to date" means.
set -euo pipefail

QDBD_VERSION="0.2.3"

cd "$(dirname "$0")/.."

# Two files come out of this, and the ERD needs both:
#   target/manifest.json  every table, every documented column, every test
#   target/catalog.json   the column TYPES, read back out of the warehouse
# dbt can only write the catalog for relations that exist, which is why this
# builds first. It is also why the build has to happen in CI — see ci.yml.
#
# No --target: the ERD is byte-identical for dev, ci and prod. Same SQL, same
# engine, same column types. The target only decides which schema holds them.
uv run dbt build
uv run dbt docs generate

# qdbd finds target/catalog.json on its own, because it sits next to the manifest.
uvx --from "quickdbd-cli==${QDBD_VERSION}" qdbd import dbt target/manifest.json -o erd/

echo
echo "erd/ regenerated. Commit it:  git add erd/ && git commit"
