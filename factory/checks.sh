#!/usr/bin/env bash
# The repo's checks. Exit 0 only when the branch is fit to review.
#
# The gate runs this script from the main checkout with the job's worktree as
# the working directory. Keep it fast, deterministic and non-interactive: no
# watch modes, no prompts, nothing that rewrites files.
#
# Run each check through `step "<label>" <command...>`. The label becomes a
# ticked line under Testing in the PR description, and config.json pr.counts
# can parse test counts out of that step's output ("Unit tests (41 passed,
# 2 skipped)"). Keep labels short and stable: pr.counts is keyed by them.
#
# With a paired QA repository (config.json qa_repo), the gate also sets:
#   FACTORY_JOB_ID       the job id
#   FACTORY_QA_REPO      the QA repository checkout
#   FACTORY_QA_WORKTREE  the job's paired QA worktree (work packages use their
#                        job's), or empty before round 1
#   FACTORY_QA_BASE      the QA base ref, e.g. origin/main
# Run the QA suite from FACTORY_QA_WORKTREE when it is set, otherwise from a
# checkout of FACTORY_QA_BASE, against the job's worktree (the current
# directory), so tests on the paired branch gate the change.
#
# INSTALL.md replaces the placeholder below with this project's real steps, e.g.:
#
#   step "Install dependencies" npm ci --prefer-offline --no-audit
#   step "Lint"                 npm run lint
#   step "Typecheck"            npm run typecheck
#   step "Unit tests"           npm test -- --run
#   step "Frontend build"       npm run build
set -euo pipefail

step() {
  local label="$1"; shift
  echo "==> RUN: $label"
  "$@"
  echo "==> PASS: $label"
}

echo "factory/checks.sh has no checks yet. Add this repo's test, lint, typecheck and build steps." >&2
exit 1
