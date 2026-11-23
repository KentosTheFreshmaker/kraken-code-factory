# Design

How this factory works, and why. It keeps the spine of
[ZazenCodes' Software Factory v2](https://github.com/zazencodes/zazencodes-season-3/tree/main/src/software-factory-claude-code-v2) (one
orchestrator, one file per agent, first-line verdicts, a scripted state
machine and a deterministic gate) and changes both ends: requests come from
prompts, and the factory stops at a drafted PR that a human merges.

## The idea

A software factory turns a queue of requests into reviewed code with a fixed
pipeline. Scripts handle the deterministic stages: running the checks, moving
state, merging work packages, writing the PR description. Agents do the
judgment in between. Each stage leaves a file behind, so you can see what
happened and why. Every step's file opens with a `## Summary` of three to five
bullets, so a human can skim a job on the dashboard.

## Pieces

| Piece | File | Job |
|---|---|---|
| Queue | `factory/jobs/*` in stage `queued` | What to build. `/factory new` creates a job from your prompt. |
| Orchestrator | `.claude/skills/factory/SKILL.md` | The session that runs `/factory`. Starts jobs, spawns agents, calls the scripts. Writes nothing itself. |
| Agents | `.claude/agents/*.md` | One file per role. Each reads files, writes exactly one file, and replies with one line. |
| State | `factory/jobs/<job-id>/` | `job.json` plus every agent's file. Gitignored. |
| Spine | `factory/bin/job`, `gate`, `route` | Deterministic. `job` is the only writer of `job.json` and refuses illegal moves. |
| Checks | `factory/checks.sh` | The repo's test, lint, typecheck and build commands. |
| Exit | the pushed branch + `PR.md` (+ `REVIEW.md` for you) | You open the PR and merge it through your own review. |

## Stages

```
queued → intake → spec → spec-review → build → gate → review → approve → ready
            │                      │       │          └──→ needs-human (DENY)
            └→ needs-info ─┐       └───────┴→ build (next round) / needs-human (rounds exhausted)
               (answer) ←──┘
spec-review → build (approved) | spec (changes) | rejected
ready → build (feedback from your PR review) | closed
needs-human → build (feedback) | rejected
```

The legal moves are `TRANSITIONS` at the top of `factory/bin/job`. `queued`,
`needs-info`, `spec-review`, `needs-human` and `ready` wait on you and hold no
concurrency slot; `closed` and `rejected` are done. When you answer a waiting
job and no slot is free, the move is recorded as `pending` and `job start`
makes it once a slot frees.

## Decisions

**Prompts are the queue.** `/factory new` writes `request.md` (the prompt,
quoted as data) and queues the job. Intake's questions come back to you in the
session, and `job answer` appends your answers to `request.md` before intake
runs again. Nothing depends on an issue tracker.

**Opus at the door.** Intake runs on Opus. It decides whether the request is
worth building, rescopes it, rates risk and surfaces, and says whether it
splits.

**You make the spec's decisions.** The spec writer surfaces product, data,
ops, security and scope choices as Decisions for the operator, with options
and a recommendation, and writes the spec as if the recommendation holds. The
job parks in `spec-review` until you approve or send changes. The approval
records the spec's SHA-256, so an edited spec can't slip into the build; the
builder blocks rather than make a new operator-level choice, and the approver
denies a change that rests on one you never saw.

**Multiple builders only where it's safe.** The spec writer splits the spec
into work packages only when their file ownership (`Owns` globs) is disjoint
and the contracts between them are written under `## Interfaces`. Each
package builds in its own worktree on `factory/<id>-wp<k>`, branched from the
job branch once its dependencies are merged, at most `max_builders` at a time.
`job wp-done` refuses a package that touched files outside its `Owns`, then
merges it into the job branch. A single integration builder then wires the
pieces together and tests the whole spec; later rounds use only that builder,
because review findings rarely respect package boundaries.

**Risk and paths route the work, a script does the routing.** Intake's risk
picks the models for the always-on `quality` and `bugs` reviewers; its
surfaces add specialists. After the gate passes, `path_surfaces` in
`config.json` adds reviewers for what the diff really touched, so a missed
surface can't skip, say, the ops and opsec review of a Dockerfile.

**Separate lenses, narrow prompts.** Quality (functionality, efficiency,
conventions) and bug hunting (breakage, shortcuts, leaks) are different
reviewers, as are code security (`appsec`) and operational security
(`opsec`), ops, backend, DBA, UX and UI. Each prompt says what is out of its
lane so findings don't duplicate.

**Scripts decide whether it works.** The gate runs `checks.sh` before any
reviewer is spawned. The gate runs the main checkout's copy of `checks.sh`
and fails any branch that changes `protected_paths` (the factory itself), so
a branch can't edit the checks it is judged by.

**The approver approves or denies; it never merges.** APPROVE moves the job to
`ready` and DENY to `needs-human`; both write `PR.md`. No script contains a
merge into the base branch, the builder never runs `gh`, and
`.claude/settings.json` denies the merge, PR and force-push commands as a
backstop.

**Previews are the operator's.** `factory/preview.sh <job> [up|down]` is
optional, project-specific like `checks.sh`, and protected so a branch can't
change what its preview runs. It isn't a pipeline stage. The orchestrator runs
it only when you ask for a specific job, every run needs your approval (an
`ask` permission rule), and every agent prompt forbids it, so "the factory
never deploys" holds for agents and a preview of your own stack stays your
action. It gets its own port per job (`ports.offsets.preview`) and a unique
`$NAME` for the compose project, so previews of different jobs don't collide.

**Defects in touched code get fixed here.** Reviewers raise a real defect in
code the branch touches as CHANGES even if it predates the branch, the bug
reviewer looks for the same pattern in sibling code, the builder fixes it
there too, and the approver denies while any review Note still describes one.
Problems in untouched code and hardening ideas become Follow-ups in
REVIEW.md, which the orchestrator offers to queue as new requests. This came
from real runs where defects that reviewers had noted were approved as
"follow-ups" and came back as operator feedback.

**A QA repository can gate the change.** With `qa_repo`, tests live in a
second repository: the factory pairs a QA worktree and branch with each job,
the gate passes its path to `checks.sh` and records the QA commit it tested,
so a QA branch that moves after the gate is caught like the main branch, and
`ready` needs both branches pushed. Companion changes (docs, infra, other
environments) are a separate section, not QA.

**The PR description is assembled, not written, and only holds what a PR
needs.** `job pr` renders `factory/pr_template.md` (project-specific and
protected, like `checks.sh`) with placeholders filled from the files: the
approver's `TITLE:`, build.md's Summary and Changes, the approver's Upgrade
notes, and a Testing list the script builds. Testing ticks each labelled
`checks.sh` step that passed in the gate log, with test counts parsed by
`pr.counts`, ticks one line per test group in build.md's Unit tests and Manual
tests, and leaves `pr.manual_checks` unticked for the human. `pr.templates`
can add more outputs, such as a description for a paired QA repo written only
when that repo has the branch. The factory's own material (job id, verdict and
why, review table, acceptance criteria, spec approval, assumptions) goes to
`REVIEW.md` in the job folder instead. Once operator feedback has changed the
work, the spec's Assumptions and Out of scope may be stale, so REVIEW.md and
the `{assumptions}` / `{out_of_scope}` placeholders use the approver's
restatement instead.

**State is files, so runs resume.** If the session dies, `/factory run` reads
`factory/jobs/` and resumes every job from its stage, including half-built
work packages.

**Cost is measured per job** from Claude Code's subagent transcripts, priced
with `prices_usd_per_mtok`. Models without a price count as zero and are
listed by `job summary`. The transcript format isn't a documented interface.
