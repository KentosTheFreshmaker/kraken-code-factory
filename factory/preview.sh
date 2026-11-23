#!/usr/bin/env bash
# Preview a job's branch on this machine. Optional.
#
# Usage: factory/preview.sh <job-id or number> [up|down]
#
# Only the operator triggers this. The orchestrator runs it when the human
# explicitly asks ("/factory preview 4"), from the orchestrator session, and
# .claude/settings.json makes every run ask for approval. No agent ever runs
# it: agents never deploy or preview.
#
# It runs the main checkout's copy (factory/* is in protected_paths), so a
# branch can't change what its own preview does, with the job's worktree as the
# working directory. That worktree holds unmerged code: run it locally,
# isolated, and never against production services, data or credentials.
#
# Contract for the commands INSTALL.md puts below:
#   up    start the preview detached (it must return), print the URL(s), exit 0
#   down  stop it and remove everything `up` created (containers, volumes, networks)
#   Both must be idempotent and exit non-zero on failure.
#
# Available to them:
#   JOB_ID    e.g. 004-dark-mode
#   WORKTREE  the job's worktree (the current directory)
#   BRANCH    the job's branch
#   PORT      this job's preview port (config.json ports: base + step·n + offsets.preview)
#   NAME      unique per job, e.g. preview-004-dark-mode: use it as the compose
#             project, container and image name prefix so previews never collide
#
# INSTALL.md replaces the two placeholder branches below with this project's
# preview, e.g. for a compose stack:
#
#   up)   PREVIEW_PORT="$PORT" podman compose -p "$NAME" up -d --build
#         echo "http://127.0.0.1:$PORT" ;;
#   down) podman compose -p "$NAME" down -v ;;
set -euo pipefail

FACTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "preview: $*" >&2; exit 1; }

[ $# -ge 1 ] && [ $# -le 2 ] || die "usage: factory/preview.sh <job-id or number> [up|down]"
ACTION="${2:-up}"
[ "$ACTION" = up ] || [ "$ACTION" = down ] || die "action must be up or down, not '$ACTION'"

# Resolve the job from job.json and config.json; prints JOB_ID, WORKTREE, BRANCH, PORT, STAGE.
mapfile -t FIELDS < <(python3 -I - "$FACTORY" "$1" <<'EOF'
import json, sys
from pathlib import Path
factory, arg = Path(sys.argv[1]), sys.argv[2]
jobs = factory / "jobs"
if arg.isdigit():
    found = sorted(jobs.glob(f"{int(arg):03d}-*/job.json"))
else:
    found = [jobs / arg / "job.json"] if (jobs / arg / "job.json").exists() else []
if not found:
    sys.exit(f"preview: no job {arg}")
job = json.loads(found[0].read_text())
ports = json.loads((factory / "config.json").read_text())["ports"]
print(job["id"], job["worktree"], job["branch"],
      ports["base"] + ports["step"] * job["number"] + ports["offsets"]["preview"], job["stage"], sep="\n")
EOF
)
[ "${#FIELDS[@]}" -eq 5 ] || exit 1
JOB_ID="${FIELDS[0]}" WORKTREE="${FIELDS[1]}" BRANCH="${FIELDS[2]}" PORT="${FIELDS[3]}" STAGE="${FIELDS[4]}"
NAME="preview-$JOB_ID"
export JOB_ID WORKTREE BRANCH PORT NAME

if [ "$ACTION" = up ]; then
  [ -d "$WORKTREE" ] || die "$JOB_ID has no worktree (stage: $STAGE); there is nothing to preview"
  cd "$WORKTREE"
elif [ -d "$WORKTREE" ]; then
  cd "$WORKTREE"
fi

case "$ACTION" in
  up)
    die "factory/preview.sh has no preview yet. Add this project's preview commands (see INSTALL.md)." ;;
  down)
    die "factory/preview.sh has no preview yet. Add this project's teardown commands (see INSTALL.md)." ;;
esac
