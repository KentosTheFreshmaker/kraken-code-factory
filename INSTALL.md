# Install the software factory

You are a coding agent installing this factory into the user's project. Copy
what's generic, adapt what's repo-specific, verify it, and report. Work in the
project's root. The source is the folder the user pointed you at.

## 0. Check the project

Stop and tell the user if any of these fail:

- It's a git repo with a remote (`origin` by default) the user can push
  feature branches to, and its default branch exists on that remote.
- `python3 --version` is 3.10 or later. The scripts use only the standard
  library.
- None of the files in step 1 already exist. If one does, show the user the
  clash and ask before overwriting.

The factory needs no `gh` and no GitHub API access.

## 1. Copy

Copy these files to the same paths in the project, unchanged:

```
.claude/settings.json
.claude/skills/factory/SKILL.md
.claude/agents/intake.md
.claude/agents/spec-writer.md
.claude/agents/builder.md
.claude/agents/approver.md
.claude/agents/reviewer-quality.md
.claude/agents/reviewer-bugs.md
.claude/agents/reviewer-backend.md
.claude/agents/reviewer-dba.md
.claude/agents/reviewer-ops.md
.claude/agents/reviewer-ux.md
.claude/agents/reviewer-ui.md
.claude/agents/reviewer-appsec.md
.claude/agents/reviewer-opsec.md
factory/config.json
factory/checks.sh
factory/preview.sh
factory/bin/job
factory/bin/gate
factory/bin/route
factory/dashboard.html
```

If the project already has `.claude/settings.json`, merge the `permissions.deny`
entries into it instead of replacing it. Then
`chmod +x factory/checks.sh factory/preview.sh factory/bin/job factory/bin/gate factory/bin/route`.

Don't copy `README.md`, `DESIGN.md`, `INSTALL.md` or `LICENSE`.

## 2. Adapt

**`factory/checks.sh`.** Replace the placeholder with the project's real
checks: install dependencies if a fresh worktree needs them, then lint,
typecheck, unit tests and build, whichever the project has. Find them in
`AGENTS.md`, `CLAUDE.md`, `package.json`, `Makefile`, `pyproject.toml` and CI
config. The script runs with a job's worktree as its working directory. It
must be non-interactive, must not rewrite files, and must exit non-zero on
any failure. Keep `set -euo pipefail`.

**`factory/preview.sh`** (optional). If the user wants previews of a job's
branch, replace its two placeholder branches with the project's commands: `up`
starts the stack from the job's worktree, detached, and prints the URL(s);
`down` stops it and removes what `up` created. Use the variables the script
provides: `$NAME` as the compose project and container/image prefix, so
previews of different jobs never collide, and `$PORT` for the published port,
bound to `127.0.0.1`. The worktree holds unmerged code, so the preview must
use local, throwaway config and data: never production services, databases or
credentials, and nothing that deploys or publishes. Ask the user what a
preview of their stack should be. If they don't want one, leave the
placeholder: it only says it isn't configured. Don't remove the `ask` rules
for it from `.claude/settings.json`; they make each run need the user's
approval.

**`factory/config.json`.**

- `base_branch` and `remote`: the default branch and its remote.
- `push`: `true` to require the job branch pushed before the gate and before
  `ready`.
- `path_surfaces`: add the project's real paths for ops (deploy, infra,
  Quadlet, CI), database (migrations, schema) and, where useful, `security`
  (auth modules). fnmatch patterns, where `*` also matches `/`.
- `protected_paths`: keep the factory entries; don't add tests.
- `ports`: move `base` if the project already uses ports 5100–5199. Each job
  uses `base + step·n` plus an offset; `offsets.preview` is the preview's.
- Leave `concurrency`, `max_rounds`, `max_builders`, `routing` and
  `surface_reviewers` as they are unless the user asks.

**Agents.** Tailor the checklists to the stack without changing their
structure, file names, first-line formats or one-line replies:

- `reviewer-appsec.md`: the project's auth, session, tenant and data-access
  code; where user input meets queries, shells or HTML.
- `reviewer-opsec.md` and `reviewer-ops.md`: the container runtime (Docker or
  Podman, rootless or not), orchestration (compose, Quadlet, systemd), where
  secrets live, and how deploys and rollbacks happen.
- `reviewer-dba.md`: the database engine and migration tool.
- `reviewer-backend.md`: the framework and its layering.
- `reviewer-ui.md`: where design tokens and shared components live.
- `reviewer-ux.md`: the kinds of users the app has.
- `approver.md`: what a human must always see in this project.
- `intake.md`: one line under **Decide** saying what the project is for.

**`AGENTS.md`** (or `CLAUDE.md`; create `AGENTS.md` if neither exists). Make
sure it says how to set up a fresh checkout, how to start the dev server on a
given port, and the validation commands matching `factory/checks.sh`. Then add:

```markdown
## Software factory

`/factory new <request>` builds a request through intake → spec → build →
gate → review → approve, ending with a pushed `factory/<job-id>` branch and a
drafted `factory/jobs/<job-id>/PR.md`; a human opens and merges the PR. State
is in `factory/jobs/` (gitignored); `factory/bin/job` is its only writer.
Checks: `factory/checks.sh`. Dashboard: `cd factory && python3 -m http.server`.

Jobs and work packages work in git worktrees under `.worktrees/` (gitignored).
A tool run from the repo root that doesn't read `.gitignore` sees those
copies too; exclude `.worktrees/` in its config.
```

**`.gitignore`.** Append:

```gitignore
/factory/jobs/
/.worktrees/
```

## 3. Verify

1. `bash factory/checks.sh` exits 0 on the current branch.
2. `factory/bin/job queue` runs without an error, and `factory/preview.sh`
   with no arguments prints its usage line and exits 1. Don't run a real
   preview while installing.
3. Each file in `.claude/agents/` has only the frontmatter keys `name`,
   `description`, `tools`, `model`, and `hooks` on the builder.
4. `python3 -m json.tool factory/config.json` and
   `python3 -m json.tool .claude/settings.json` succeed.
5. `git check-ignore factory/jobs/x .worktrees/x` prints both paths.

## 4. Hand over

Stay on the user's branch. Commit the install with a one-line message, show
the diff, and ask before pushing: jobs branch from `<remote>/<base_branch>`,
so the install must be there before the first run. Then tell the user:

- Run `/factory new <request>` in Claude Code from the project root.
- Every job ends `ready` (pushed branch + `PR.md` to paste into a PR) or
  `needs-human` (the approver's reasons). Feedback from their PR review goes
  back with `/factory <feedback>`; `/factory close <n>` once a PR is merged.
- Start with `concurrency: 1` and `max_builders: 1` until they trust it.
- If `factory/preview.sh` is set up, `/factory preview <n>` runs a job's branch
  locally (and `/factory preview <n> down` stops it). Only they trigger it,
  and Claude Code asks them to approve each run.
