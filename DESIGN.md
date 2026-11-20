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
| Exit | the pushed branch + `PR.md` | You open the PR and merge it through your own review. |

## Stages

```
queued → intake → spec → build → gate → review → approve → ready
            │                      │       │          └──→ needs-human (DENY)
            └→ needs-info ─┐       └───────┴→ build (next round) / needs-human (rounds exhausted)
               (answer) ←──┘
ready → build (feedback from your PR review) | closed
needs-human → build (feedback) | rejected
```

The legal moves are `TRANSITIONS` at the top of `factory/bin/job`. `queued`,
`needs-info`, `needs-human` and `ready` wait on you and hold no concurrency
slot; `closed` and `rejected` are done.

## Decisions

**Prompts are the queue.** `/factory new` writes `request.md` (the prompt,
quoted as data) and queues the job. Intake's questions come back to you in the
session, and `job answer` appends your answers to `request.md` before intake
runs again. Nothing depends on an issue tracker.

**Opus at the door.** Intake runs on Opus. It decides whether the request is
worth building, rescopes it, rates risk and surfaces, and says whether it
splits.

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

**The PR description is assembled, not written.** `job pr` builds `PR.md`
from the files: build.md's Summary, Changes, Unit tests and Manual tests;
the approver's verdict, Why and For the human; the gate's result and commit;
the review table; and the spec's Assumptions and Out of scope. The approval
status and test results come from the verdict files, so they can't be
paraphrased.

**State is files, so runs resume.** If the session dies, `/factory run` reads
`factory/jobs/` and resumes every job from its stage, including half-built
work packages.

**Cost is measured per job** from Claude Code's subagent transcripts, priced
with `prices_usd_per_mtok`. Models without a price count as zero and are
listed by `job summary`. The transcript format isn't a documented interface.
