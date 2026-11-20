# Kraken Code Factory

> **Based on [Software Factory for Claude Code v2](https://github.com/zazencodes/zazencodes-season-3/tree/main/src/software-factory-claude-code-v2)
> by [ZazenCodes](https://zazencodes.com/)**, licensed under GPLv3. This is a
> modified version: see [What changed from the original](#what-changed-from-the-original).

A software factory that turns your prompts into reviewed feature branches. Run
`/factory new <request>` and agents decide whether it's worth building, write a
spec, build it (in parallel work packages when that's safe), test it with your
own checks, review it through up to nine specialist lenses, and approve or
deny it. The factory pushes the feature branch and drafts the PR description
in `PR.md`; **you** open the PR and merge it through your normal GitHub review.


## The loop

```
/factory new <request>
        │
        ▼
intake (opus) ── NEEDS-INFO → asks you in the session, runs again with your answers
        │        REJECT     → says why
        ▼ ACCEPT, maybe rescoped; rates risk, surfaces, split
route (script)    picks reviewers and models from config.json
        ▼
spec-writer (opus) → spec.md, optionally split into work packages with disjoint file ownership
        ▼
builders (opus)    one builder, or parallel package builders → merged in dependency order → integration builder
        ▼            ▲    pushes factory/<job-id>
gate (script) ─FAIL──┤  factory/checks.sh; no reviewer runs on a failing build
        ▼ PASS       │
reviewers ─CHANGES───┘  quality + bugs always; backend, dba, ops, ux, ui, appsec, opsec by surface and by changed paths
        ▼ all PASS
approver (opus) ── APPROVE → ready:        PR.md drafted, you open the PR
                └─ DENY    → needs-human:  PR.md drafted with the reasons
```

One Claude Code session orchestrates every job, `concurrency` at a time.
Each job gets its own git worktree and branch; each work package gets its own
too. All state lives in `factory/jobs/`, so if the session dies,
`/factory run` picks every job back up.

## Commands

```
/factory new <request>   queue a request (text, or a path to a file) and start it
/factory run             drain the queue; also resumes
/factory run <n>         one job now
/factory <anything>      ask about jobs, answer intake, give feedback (e.g. from your PR review), close or reject a job
```

## Reviewers

| Reviewer | Lens | Runs when |
|---|---|---|
| `quality` | functionality vs spec, optimisations, reuse, conventions, tests, docs | always |
| `bugs` | breaking changes, risky shortcuts, unintended behaviour, leaks and resource misuse, concurrency | always |
| `backend` | API contracts, validation, errors, idempotency, layering | `backend` |
| `dba` | migrations on live data, schema, indexes, queries, locking, integrity | `database` |
| `ops` | Docker/Podman images and runtime, compose/Quadlet/systemd, config, health, logs, upgrade and rollback | `ops` |
| `ux` | flows, states, copy, accessibility | `frontend` |
| `ui` | visual consistency | `frontend` |
| `appsec` | DoS, injection (SQL/API/command/SSRF), XSS, sessions and cookies, access control, identity and secret leakage, cross-user/tenant contamination | `frontend`, `backend`, `database`, `security` |
| `opsec` | operational security regressions: privileges, exposure, secrets handling, supply chain, mounts, TLS, CI | `ops`, `security` |

Intake predicts the surfaces; after the gate, `config.json` `path_surfaces`
adds reviewers for what the diff actually touched (a Dockerfile brings in
`ops` and `opsec`, a migration brings in `dba` and `appsec`).

## What's in here

```
.claude/
  settings.json               deny rules: no gh pr merge/create/ready, no force-push, no push to main
  skills/factory/SKILL.md     the orchestrator
  agents/                     intake, spec-writer, builder, approver, reviewer-{quality,bugs,backend,dba,ops,ux,ui,appsec,opsec}
factory/
  config.json                 concurrency, rounds, builders, routing, path surfaces, protected paths, prices
  checks.sh                   your repo's checks (fill it in)
  bin/job                     the only writer of job.json; refuses illegal moves; work packages; PR.md
  bin/gate                    runs checks.sh in a job's worktree → round-N/checks.md
  bin/route                   risk + surfaces → the job's reviewers and models
  dashboard.html              the board
INSTALL.md                    instructions for the installing agent
DESIGN.md                     how it works and why
```

## Dashboard

```bash
cd factory && python3 -m http.server
```

Open <http://localhost:8000/dashboard.html>.

## Safety

- Nothing merges. The factory pushes only `factory/<job-id>` branches, never
  force-pushes, and never runs `gh`; `.claude/settings.json` denies the
  commands that could. The human PR review is the approval.
- Requests reach agents as quoted data in `request.md`, never in a prompt.
  Intake, which reads it first, has no shell.
- The gate runs the main checkout's `checks.sh`, so a branch can't edit its
  own checks, and fails any branch that changes `protected_paths`.
- Package builders are refused if they change a file outside their `Owns`.

## What changed from the original

Modified in November 2026 from the upstream v2 release:

- Requests come from prompts (`/factory new`) instead of GitHub issues; there is
  no GitHub integration and no `gh` use.
- Intake runs on Opus instead of Fable.
- The approver approves or denies and never merges. The factory pushes the
  feature branch and drafts `PR.md`; a human opens and merges the PR.
- Specs can split into work packages built by parallel builders with enforced
  file ownership.
- The reviewer set is replaced: quality, bugs, backend, dba, ops, ux, ui,
  appsec and opsec, routed by intake's surfaces and by the paths the diff
  touches.
- The upstream example jobs and promotional assets are removed.

## License

[GPLv3](LICENSE), the same license as the original work. Any version you
distribute must also be released under GPLv3, with its source.
