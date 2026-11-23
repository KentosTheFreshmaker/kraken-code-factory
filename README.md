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

## Install

Open Claude Code in your project and ask it to install the factory from a
local copy of this repository, following [`INSTALL.md`](INSTALL.md):

```text
Install the software factory from /path/to/kraken-code-factory into this project, following its INSTALL.md.
```

The installing agent copies the files, fills in `factory/checks.sh` with your
project's real checks, adapts the PR template, the reviewers and
`config.json`, and verifies the result. To bring an older install up to date,
see **Upgrading an existing install** in `INSTALL.md`. You need `python3` 3.10+
and a git remote you can push feature branches to; no `gh` is needed.

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
spec-writer (opus) → spec.md, optionally split into work packages with disjoint file ownership;
        │            lists the decisions that are yours instead of making them
        ▼
spec review (you) ── overview + your decisions → approve, or send changes back to the spec writer
        ▼ approved (pinned to the spec's hash)
builders (opus)    one builder, or parallel package builders → merged in dependency order → integration builder
        ▼            ▲    pushes factory/<job-id>
gate (script) ─FAIL──┤  factory/checks.sh; no reviewer runs on a failing build
        ▼ PASS       │
reviewers ─CHANGES───┘  quality + bugs always; backend, dba, ops, ux, ui, appsec, opsec by surface and by changed paths
        ▼ all PASS
approver (opus) ── APPROVE → ready:        PR.md (+ REVIEW.md) drafted, you open the PR
                └─ DENY    → needs-human:  same files, REVIEW.md says why
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
/factory preview <n>     run factory/preview.sh for a job's branch (… down to stop); only when you ask
/factory <anything>      ask about jobs, answer intake, give feedback (e.g. from your PR review), close or reject a job
```

## Spec review

Every spec stops for you before anything is built (`config.json`
`spec_review`: `always`, `decisions` to stop only when the spec lists open
decisions or the risk is high, or `never`). The spec writer lists the choices
that are yours (behaviour users see, data, dependencies and ops, security and
cost trade-offs, scope) under **Decisions for the operator**, each with
options and a recommendation. The orchestrator shows a short overview from
`job spec-overview` and asks you each decision plus approve / request changes
/ reject. Your approval is saved in `spec-approval.md` with the spec's
SHA-256, so the build is refused if the spec changes afterwards, and your
decisions appear in `REVIEW.md`.

## Approval and REVIEW.md

The approver writes `decision.md`: `APPROVE` or `DENY`, then a `TITLE:` line
with the PR title in its final form, written from the diff rather than the
spec (whose title can predate your feedback). It approves only when:

- every acceptance criterion is met, with evidence it spot-checks;
- the gate passed and every review is PASS;
- no review Note, in any round, still describes a real defect in code the
  branch touches. A 500 that should be a 400, a race, missing locking or
  orphaned rows count, however rare; they are fixed in the job, not deferred;
- new behaviour has tests (on the QA branch when `qa_repo` is set);
- the change follows the decisions you approved at spec review.

It also writes **Upgrade notes** (what whoever deploys must do: config, migrations,
restarts, anything irreversible), **QA changes** and **Companion changes**,
which go into the PR description, and **Follow-ups**: work outside the job,
phrased as new requests. At the end of a run the orchestrator offers to queue
the Follow-ups you pick with `/factory new`.

`REVIEW.md` in the job folder is the factory's record for you, kept out of the
PR body: the verdict and why, what to look at closely, the review table, the
acceptance criteria, your spec approval, Follow-ups, the QA branch, and the
assumptions still in force (restated by the approver once feedback has changed
the work).

## PR descriptions

`PR.md` is rendered from `factory/pr_template.md`, which you adapt to your
format. Placeholders: `{title}` (the approver's final `TITLE:`),
`{compare_url}`, `{summary}`, `{changes}`, `{upgrade_notes}`, `{testing}`,
`{qa_changes}`, `{companion_changes}`, `{qa_branch}`, `{qa_commit}`,
`{assumptions}`, `{out_of_scope}`, `{branch}`, `{template_branch}`,
`{template_base}`, `{base}`, `{commit}`, `{repo_name}`, `{job_id}`, `{verdict}`.
`{?name}...{/name}` keeps a block only when `name` has a value.

`{testing}` is built, not written: a ticked line per `step "<label>"` in
`checks.sh` that passed (with counts from `pr.counts`, e.g. "Unit tests (41
passed, 2 skipped)"), a ticked line per test group the builder listed, and
your `pr.manual_checks` unticked. `PR-qa.md` comes from
`factory/pr_qa_template.md` (the `pr.templates` entry with `"repo": "qa"`) and
is written only when the job's QA branch has commits. Add more `pr.templates`
entries for more outputs; `only_if_remote_branch` writes one only when another
repository has the branch. Compare links are derived from GitHub remotes
(`"compare_url": "auto"`) or set explicitly. The factory's own notes go to
`REVIEW.md`, not the PR.

## QA repository and companion changes

The factory fits a dev → QA → staging → production pipeline in two separate
ways:

- **QA repository** (optional, `config.json` `qa_repo`): a second repository
  that holds the project's automated tests. Each job gets a paired QA
  worktree on a branch with the same name, the builder writes the tests
  there and pushes it, and the gate passes the QA worktree to `checks.sh`
  (`FACTORY_QA_WORKTREE`, `FACTORY_QA_BASE`), which runs that suite against
  the job's worktree, so the QA tests gate the change. The gate records the
  QA commit it tested: a QA branch that is dirty, unpushed or moved after the
  gate is refused, like the main branch. `PR-qa.md` is drafted alongside
  `PR.md`.
- **Companion changes**: work the change needs elsewhere (another repo's
  docs, infrastructure or deploy config, staging or production settings).
  The builder notes it and the approver writes it into its own PR section,
  kept apart from QA.

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

A real defect in code the branch touches is a CHANGES finding even when it
predates the branch; problems in untouched code go under Notes. The bug
reviewer also searches for the same pattern in sibling code (the other
handlers or operations that do the same job), and the builder fixes those
too.

## What's in here

```
.claude/
  settings.json               deny rules (no gh pr merge/create/ready, no force-push, no push to main); ask rules for preview.sh
  skills/factory/SKILL.md     the orchestrator
  agents/                     intake, spec-writer, builder, approver, reviewer-{quality,bugs,backend,dba,ops,ux,ui,appsec,opsec}
factory/
  config.json                 concurrency, rounds, spec review, builders, qa_repo, routing, path surfaces, pr, protected paths, ports, prices
  checks.sh                   your repo's checks (fill it in)
  preview.sh                  optional: start/stop a local preview of a job's branch (fill it in)
  pr_template.md              your PR description format (adapt it)
  pr_qa_template.md           the QA repository's PR description (used only with qa_repo)
  bin/job                     the only writer of job.json; refuses illegal moves; work packages, QA worktrees, PR files, REVIEW.md
  bin/gate                    runs checks.sh in a job's worktree → round-N/checks.md; --check runs it without writing
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
- Agents never deploy or preview. `factory/preview.sh` runs only from the
  orchestrator session when you ask for it, and `.claude/settings.json` makes
  each run ask for your approval. It runs unmerged code, so keep it local and
  away from production config.
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
- Every spec stops for operator review before it is built.
- The approver approves or denies and never merges. The factory pushes the
  feature branch and drafts `PR.md`; a human opens and merges the PR.
- Specs can split into work packages built by parallel builders with enforced
  file ownership.
- The reviewer set is replaced: quality, bugs, backend, dba, ops, ux, ui,
  appsec and opsec, routed by intake's surfaces and by the paths the diff
  touches. Defects in touched code are fixed in the job, and the approver
  denies while any review Note still describes one.
- PR descriptions are rendered from your template, with a Testing list built
  from the gate log; the factory's own notes go to `REVIEW.md`.
- An optional paired QA repository holds the tests and gates every change;
  companion changes (docs, infra, other environments) are reported
  separately.
- An optional, operator-only `factory/preview.sh` runs a local preview of a
  job's branch.
- The upstream example jobs and promotional assets are removed.

## License

[GPLv3](LICENSE), the same license as the original work. Any version you
distribute must also be released under GPLv3, with its source.
