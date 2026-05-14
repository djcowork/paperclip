# Compliance-First AI Company — Standard Operating Procedure

Status: 1.0 (2026-05-14)
Audience: every agent in this company, plus the human board.
Source of truth: this file overrides any conflicting prose in individual
`agents/*/AGENTS.md`. Per-agent files describe *role*, this file describes
*flow*.

---

## 0. The two contracts

This company runs on two written contracts. If anything in this SOP
contradicts them, the contracts win and this file must be patched.

1. `COMPANY.md` — mission ("Phase 1 compliance is the product").
2. `README.md` — org chart and the 9-step workflow at lines 70–79.

This SOP is the executable expansion of those 9 steps, with concrete
inputs, outputs, plugin tools, and refusal conditions per role.

---

## 1. Cycle picture

```
                    ┌───────────────────┐
   board / metrics  │      CEO          │  picks lane priority each cycle
        │           └──┬────────┬───────┘
        ▼              │        │
                       ▼        ▼
              ┌──────────┐  ┌──────────────┐
              │   CTO    │  │  Audit Lead  │  gates lanes ←→ Architecture / Audio-RT /
              └──┬───────┘  └──┬───────────┘   Desktop / Dependency-Security /
                 │             │               GitNexus / Docs-Blind-Spots
                 ▼             ▼
              ┌──────────────────────────────┐
              │      Delivery Lead           │  turns audit findings into
              └──────┬───────────────────────┘  single-concept fix tasks
                     ▼
       ┌─────────────────────────┐
       │   Workspace Director     │  one issue → one worktree → one branch
       │     + Operator           │
       │     + Runner Coordinator │
       └────────────┬─────────────┘
                    ▼
          ┌────────────────┐         engineer pool (Core / Desktop / DJ / Integration)
          │  Lane Lead     │ ─────►  takes branch, writes the fix, opens DRAFT PR
          └────────────────┘                                │ via github_open_pr
                                                            ▼
                            ┌─────────────────────────────────┐
                            │  Validation Director            │
                            │    + Test Engineer              │
                            │    + Performance Baseline Eng.  │
                            │    + Build Verifier             │
                            └──────────────┬──────────────────┘
                                           │  github_create_check_run with evidence
                                           ▼
                                  ┌────────────────────┐
                                  │   Merge Director   │  github_get_pr → enqueue
                                  └─────────┬──────────┘
                                            ▼
                                ┌───────────────────────┐
                                │  Workspace Operator   │  worktree remove + branch -D
                                │   (cleanup)           │
                                └─────────┬─────────────┘
                                          ▼
                              back to Delivery Lead — next single-concept task
```

---

## 2. Per-role contract

For each role: **inputs** (what triggers it), **must do**, **must NOT do**,
**outputs** (the next role's input), and **plugin tools authorised**.

### 2.1 CEO

| | |
|--|--|
| **Inputs** | board goals; quarterly KPI; previous cycle status from Delivery Lead. |
| **Must do** | (a) translate board goal into ordered lane priorities for the cycle; (b) approve CTO's "technical order of attack"; (c) read each cycle's heartbeat-run rollup once a day; (d) escalate to the board if budget burn-rate or violation-count regressions hit thresholds. |
| **Must NOT** | open PRs, write code, manipulate worktrees, talk to GitHub directly. |
| **Outputs** | a numbered list of lane priorities written into Delivery Lead's intake. |
| **Plugin tools** | none — CEO is a planning role. May *read* `github_list_issues` to sanity-check Delivery Lead intake matches reality. |
| **Cadence** | every cycle (a cycle = one validation/merge round of the active lanes). Default cycle length: 24 h. |

### 2.2 CTO

| | |
|--|--|
| **Inputs** | CEO's lane priority list; Audit Lead's risk findings; Architecture Lead's v2-phase gate decisions. |
| **Must do** | (a) decide which lanes can run in parallel this cycle without crate-area concurrency conflicts (rule: never two engineers writing the same crate at once); (b) approve / postpone large refactors (>3 crate scope); (c) sign off on rust-toolchain / cargo-deny policy changes by responding to the Dependency-Security Lead. |
| **Must NOT** | merge PRs (that's Merge Director); open PRs. |
| **Outputs** | a "lanes active this cycle" decision recorded as a comment on the CEO intake issue. |
| **Plugin tools** | `github_get_pr` (status sanity-check only). |
| **Refusal** | block a lane if Architecture Lead flags v2-phase regression; block a lane if Dependency-Security Lead flags a license/advisory deadline overdue. |

### 2.3 Audit Lead

| | |
|--|--|
| **Inputs** | all 6 audit-* leads (GitNexus, Desktop-Compliance, Audio-RT, Dependency-Security, Architecture, Docs-Blind-Spots); the audit baseline files at `D:\code\djcowork2.0\audit\2026-05-13-*.md`. |
| **Must do** | (a) maintain the canonical "active violations" list, sourced from the audit baseline files plus any *new* baseline an Audit-* lead surfaces; (b) before each cycle, pick which violation classes are "in scope" for the cycle and hand them to Delivery Lead; (c) refuse to release a fix lane back to "active" if its post-fix baseline did not drop. |
| **Must NOT** | open code-modifying PRs (read-only PR comments are fine). |
| **Outputs** | a *scope-of-this-cycle* manifest passed to Delivery Lead. |
| **Plugin tools** | `github_list_issues`, `github_get_pr` (read-only). |
| **Refusal** | reject any Delivery Lead task that does not name the baseline file + line range it is supposed to drain. |

### 2.4 Architecture Lead / GitNexus Lead / Desktop Compliance Lead / Audio RT Lead / Dependency-Security Lead / Docs-Blind-Spots Lead

| | |
|--|--|
| **Inputs** | Audit Lead's "do you see anything new?" prompt every cycle; specific Delivery Lead questions ("is this refactor safe?"). |
| **Must do** | each lead owns one slice of compliance (architecture v2-gate / symbol blast radius / desktop hard-floors / RT safety / license & advisory hygiene / blind-spot documentation). Surface new violations or risks within 24 h of detection. |
| **Must NOT** | write code or change manifests directly. |
| **Outputs** | structured comments on the cycle scope manifest; veto on individual Delivery Lead tasks within their lane. |
| **Plugin tools** | none required v0.1 — they operate on local source + GitNexus index. |

### 2.5 Delivery Lead

| | |
|--|--|
| **Inputs** | Audit Lead's cycle scope manifest; specialist leads' vetoes. |
| **Must do** | (a) for each violation class in scope, split it into **single-concept fix tasks** sized to ≤1 working session; (b) every fix task body MUST cite the baseline file:line (e.g. `audit/2026-05-13-expect-baseline.md` row "dj-audio 1158 unannotated"); (c) assign each task to the matching Lane Lead via `assigneeAgentId`. |
| **Must NOT** | bypass Audit Lead's scope; lump multiple violation classes into one task. |
| **Outputs** | a queue of paperclip issues with `assigneeAgentId = <lane-lead>` and label `compliance` + `phase1` + `<lane>`. |
| **Plugin tools** | `github_list_issues` (pull intake from GitHub if a violation was filed there first). |
| **Refusal** | any task that does not have an Audit Lead approval reference in its body. |

### 2.6 Workspace Director

| | |
|--|--|
| **Inputs** | Delivery Lead's task queue. |
| **Must do** | (a) for each task, instruct Workspace Operator to provision an isolated worktree at `<repo-root>-wt/<branch>`; (b) confirm `issueId` was carried into the worktree dispatch envelope; (c) before the run starts, verify (`git -C <main> branch --list <branch>` returns nothing) so no two agents share a branch. |
| **Must NOT** | run the engineer's codex itself; touch source files. |
| **Outputs** | a "ready to dispatch" record handed to the Lane Lead. |
| **Refusal** | refuse the task if a worktree against the same branch already exists. |

### 2.7 Workspace Operator

| | |
|--|--|
| **Inputs** | Workspace Director ready-to-dispatch record. |
| **Must do** | (a) `git worktree add D:\opt\paperclip-wsl-worktrees\djcowork2.0\<branch>` (Windows long paths now enabled); (b) rewrite the engineer's codex `cwd` to the worktree path; (c) on Linux/WSL2 wrap dispatch in `systemd-run --user --scope --unit=codex-<run-id> -p MemoryMax=8G -p CPUQuota=200%`; on Windows attach the codex process to a Job Object with the same caps (when the JobObject helper lands; until then accept that an OOM child will not be reaped reliably); (d) after the run finishes (success or failure), trigger Cleanup. |
| **Must NOT** | run more than one worktree per branch; reuse a worktree across tasks. |
| **Outputs** | cwd-rewritten dispatch the Lane Lead can hand to the engineer. |

### 2.8 Runner Coordinator

| | |
|--|--|
| **Inputs** | every `heartbeat.wakeup` event for this company. |
| **Must do** | (a) hard-cap live codex children to 15 (default `HEARTBEAT_MAX_CONCURRENT_RUNS_DEFAULT`), reserve 2 of those for governance roles (CEO/CTO/Audit Lead); (b) enforce per-task wall-time (engineer 30 min, validation 45 min, build verify 60 min); (c) when a run exceeds wall-time send SIGTERM then SIGKILL after 5 s grace. |
| **Must NOT** | silently drop rejected dispatches — log them for the next heartbeat. |

### 2.9 Lane Lead (Core / Desktop / DJ / Integration)

| | |
|--|--|
| **Inputs** | Delivery Lead's task targeting this lane; Workspace Director's ready-to-dispatch record. |
| **Must do** | pick which engineer in the lane takes the task. Lane Leads do not write code; they decide allocation. |
| **Plugin tools** | none. |

### 2.10 Engineer (Core/Desktop/DJ/Integration Engineer 1/2)

| | |
|--|--|
| **Inputs** | Lane Lead allocation; worktree path; issue body citing the baseline file:line. |
| **Must do** | (a) make the smallest change that drains the cited baseline rows; (b) commit with message `<lane>: <single concept> (refs <baseline-file>)`; (c) `git push` the branch; (d) call `github_open_pr` with `issueId`, branch, title, body referencing `Fixes #<issue>`, `draft=true`, labels `compliance, phase1, <lane>`. |
| **Must NOT** | run `gh pr create` in a shell; modify files outside the cited baseline scope; do drive-by cleanups; merge own PR; rebase onto another engineer's branch. |
| **Outputs** | PR number returned by `github_open_pr`. |
| **Refusal** | the plugin refuses `github_open_pr` without an `issueId`; do not retry without one. |

### 2.11 Validation Director / Test Engineer / Performance Baseline Engineer

| | |
|--|--|
| **Inputs** | new draft PR notification (Merge Director currently polls; v0.2 plugin webhook will push). |
| **Must do** | (a) batch unified test runs across the open lane PRs (no per-PR shard explosion); (b) write performance baseline comparison if the PR touches DSP / audio / GPU paths; (c) hand evidence to Build Verifier. |
| **Plugin tools** | `github_get_check_runs` (read existing CI signal). |

### 2.12 Build Verifier

| | |
|--|--|
| **Inputs** | Validation Director's signed-off PRs. |
| **Must do** | (a) cargo build per the lane's matrix (Linux + windows-desktop-gate); (b) hash the produced binary; (c) call `github_create_check_run` with `name="paperclip/build-verify"`, `status="completed"`, `conclusion="success"` or `"failure"`, **details ≥ 200 chars** containing: build command, target triple, sha256, artifact size in bytes, test pass/fail counts; (d) on failure attach first 100 lines of stderr to `details`. |
| **Plugin tools** | `github_create_check_run`, `github_get_check_runs`. |
| **Refusal** | the plugin refuses thin (`<200 char`) details by design — do not pad; either you have evidence or you do not. |

### 2.13 Merge Director

| | |
|--|--|
| **Inputs** | Build Verifier's "evidence on PR" notification. |
| **Must do** | (a) call `github_get_pr` once per candidate; (b) `failingChecks.length > 0` → refuse; (c) `reviewDecision !== APPROVED && reviewDecision !== null` → refuse; (d) `mergeStateStatus` ∈ `{BLOCKED, BEHIND}` → ask for sync, don't enqueue; (e) `mergeStateStatus === CLEAN` → call `github_enqueue_merge`. |
| **Must NOT** | call `github_squash_merge` (refused by plugin unconditionally in v0.1 anyway); merge a PR Build Verifier did not sign. |
| **Plugin tools** | `github_get_pr`, `github_get_check_runs`, `github_enqueue_merge`. |
| **Refusal** | the plugin re-validates state before enqueue. Trust the plugin's refusal — never argue. |

### 2.14 Workspace Operator (cleanup half)

| | |
|--|--|
| **Inputs** | Merge Director's "merged" or "abandoned" event. |
| **Must do** | (a) `git worktree remove --force <worktree-path>`; (b) `git branch -D <branch>` on the main checkout if it still exists locally; (c) reclaim sccache slice for the worktree; (d) signal Delivery Lead "engineer X is free for next task". |

### 2.15 Closing the loop

Delivery Lead's queue is FIFO within (lane × violation class). When the
queue for a (lane × class) drains to zero, Delivery Lead pings Audit Lead
"this class is done in this lane; please re-run the baseline scan." Audit
Lead either marks the class complete or re-opens with new findings.

---

## 3. Hard rules summary (audit-lead checklist)

| Rule | Where enforced |
|------|---------------|
| One issue → one branch → one worktree → one PR | Workspace Director + Workspace Operator (declared); plugin refuses `github_open_pr` without `issueId` |
| No two engineers in same crate at once | CTO must reject the second task this cycle |
| `github_open_pr` is the only PR-creation path | Engineer AGENTS.md; codex shell `gh pr create` is a documented violation |
| No `github_squash_merge` outside emergency capability | Plugin refuses unconditionally in v0.1 |
| Completed check-run details ≥ 200 chars | Plugin refuses (`evidence_too_thin`) |
| Merge only via `github_enqueue_merge` (refuses on failingChecks / draft / non-APPROVED review) | Plugin enforced |
| One worktree per branch, no cross-branch reuse | Workspace Operator AGENTS.md |
| Per-task wall-time (engineer 30 / validation 45 / build 60 min) | Runner Coordinator AGENTS.md |
| Worktree pruned on merge or abandon, max 7 days stale | Workspace Operator AGENTS.md |

---

## 4. What an off-baseline event looks like

A normal cycle goes Audit → Delivery → Workspace → Engineer → Validation
→ Build → Merge → cleanup → next.

Off-baseline:

| Event | Who handles | What |
|------|-------------|------|
| Plugin refuses `github_open_pr` with `missing_issue_ref` | Engineer | re-check task body; if Workspace Director did not carry the issueId, file a Workspace Director escalation, do **not** retry without one |
| Plugin refuses `github_enqueue_merge` with `failing_checks` | Merge Director | hand back to Validation Director with the failing-checks list |
| `process_lost` on a heartbeat run | Runner Coordinator | check Windows long-path config, check `D:\opt\paperclip-wsl-worktrees\` cleanliness, check codex installation; if still failing → CTO escalation |
| Worktree disk usage > 20 GB | Workspace Operator | prune stale worktrees > 7 d; if still > 20 GB after prune → CTO escalation (rebuild target sharing) |
| Codex run exceeds wall-time | Runner Coordinator | SIGTERM then SIGKILL, record as `wall_time_exceeded`, Delivery Lead re-files as a smaller task |
| Same crate touched by two concurrent tasks | CTO | cancel the second one, re-queue at next cycle boundary |
| Audit baseline did not drop after a lane "completed" | Audit Lead | re-open the class; Delivery Lead re-issues; engineer reads previous PR + new baseline |

---

## 5. Cadence summary

| Role | Trigger |
|------|---------|
| CEO | once per cycle (24 h default) |
| CTO | once per cycle + on demand for cross-lane risk |
| Audit Lead | once per cycle + on each "lane complete" claim |
| Specialist leads (architecture / audio-rt / etc.) | watch their lane continuously, escalate only |
| Delivery Lead | continuous — drains Audit Lead's scope into engineer queue |
| Workspace Director / Operator / Runner Coordinator | per task |
| Lane Leads | continuous task allocation |
| Engineers | continuous — one task at a time, no multitasking |
| Validation / Build Verifier | per draft PR + batched |
| Merge Director | continuous polling (v0.1) / push (v0.2 webhook) |

---

## 6. What the human board owes the company

- approve the scope manifest the Audit Lead produces each Monday (or reject with a reason);
- raise the violation-count regression threshold or budget threshold if the
  company is hitting it spuriously;
- pause the company (PATCH `/api/companies/<id>` `{status:"paused"}`) for
  any cross-cutting refactor that needs to land outside the standard flow.

The board does not write code, review PRs, or rebase branches. If those
slip, the company's process is broken — fix the process, not the cycle.
