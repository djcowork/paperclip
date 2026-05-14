# Violation Playbook — How the company drains djcowork2.0's debt

Status: 1.0 (2026-05-14)
Source baselines (canonical): `D:\code\djcowork2.0\audit\2026-05-13-*.md`
Source roadmap: `D:\code\djcowork2.0\docs\plans\djcowork2-compliance-roadmap.md`

This document tells the **Audit Lead → Delivery Lead** boundary exactly
how to turn the existing audit baselines into a batched, parallelisable,
non-overlapping engineer queue. It does not invent new compliance rules
— djcowork2.0 already has STANDARDS.md (66 dims), the audit baselines,
and the compliance roadmap. The playbook is the *consumption strategy*.

---

## 0. Real numbers (2026-05-13 baseline)

| Baseline file | Class | Hits | Severity | Hottest crates |
|---|---|---:|:---:|---|
| `expect-baseline.md` | unannotated `.expect()/panic!/let _ = /unreachable!/todo!/unimplemented!` | **4097 unannotated of 4129** | P0 | dj-audio 1158, dj-runtime 618, dj-library 438, core-djcowork 293, core-im 277 |
| `silent-error-baseline.md` | top-of-line `let _ = <fallible>` | **510** (workspace), 54 high-risk | P0 | DJ_player/dj-{audio,library,runtime,session} 350, crates/* 160 |
| `desktop-silent-fallback.md` | desktop silent fallback regressions | **294 / 0 annotated** | P0 | apps/desktop + crates/desktop-* |
| `panic-baseline.md` | explicit `panic!/unimplemented!/todo!/unreachable!` | (subset of expect-baseline 4129) | P0 | same hot crates |
| `edition-inheritance.md` | manifests missing `edition.workspace=true` | **89 / 90** | P1 | core-im, im-event-queue, desktop-shared-state, desktop-settings-module, … |
| `dependency-staleness.md` | stale dependency entries | TBD per baseline | P1 | workspace-wide |
| `reexport-chains.md` | 4–5 hop re-export chains | **REX-001..005+** | P2 | desktop-shared-services facade chain |
| `async-blocking-io.md` | sync syscalls inside `async fn` | **5 P2 confirmed** | P2 | core-djcowork dreaming, dj-library sidecar/metadata, dj-runtime stems |
| `cargo-deny-status.md` | bans / licenses / advisories | varies (14 deny.toml ignores w/ deadlines) | P0–P2 | manifest-only |
| `workflow-consistency.md` | .github/workflows drift | several | P1 | .github/workflows/* |

The Audit Lead's job is to take **exactly** these numbers as the cycle
scope and not invent new ones until a baseline is closed.

---

## 1. The seven cycle strategy

We do not run 4097 fixes as 4097 issues — that is administratively
impossible inside paperclip's 30-min/run window. We batch by
**(violation class) × (crate group)** so each issue is one PR
≤300 line changes, ≤1 worktree, ≤1 lane.

| Cycle | Wave | Output target | Why first |
|------:|-----|---|---|
| 1 | Edition inheritance | 89 manifests → 4 PRs (one per lane) | Highest ratio (4 PRs drains 89 violations); mechanical; near-zero risk |
| 2 | `cargo-deny` deadline misses | 0–3 advisory ignores past `deadline` in `deny.toml:57-75` | Time-bound, fails CI when missed |
| 3 | `silent-error` (54 high-risk subset) | ~8 PRs (one per top-hit crate) | Concentrated; clear pattern; finite |
| 4 | `desktop-silent-fallback` | ~8 PRs (apps/desktop + crates/desktop-*) | Single lane (Desktop) can drain solo while DJ lane works on cycle 5 |
| 5 | `async-blocking-io` | 5 PRs (one per finding) | Already triaged P2 in baseline with specific fixes named |
| 6 | `reexport-chains` REX-001..005 | 5 PRs | Touches the `desktop-shared-services` facade; one architect-reviewed batch |
| 7 | `expect-baseline` 4097 unannotated | ~60 PRs (15 hottest crates × 2-4 chunks each) | The mass drain; runs in parallel across all 4 lanes |

Cycle 7 is the dominant work. Cycles 1–6 are sequencable in 2 weeks of
real-world time; cycle 7 is 4–6 weeks at full lane utilisation.

---

## 2. The batching rule

For each (class × crate-group) batch, the Delivery Lead generates:

```
Issue title:
   [<class>][<lane>][<crate>] drain <N> rows from <baseline-file>

Issue body (template):
   Baseline:  audit/2026-05-13-<class>.md
   Crate(s):  packs/DJ_player/crates/dj-audio
   Row span:  approximately 300 (of 1158) unannotated .expect() calls
   Allowed scope: dj-audio crate only
   NOT allowed:   touching any other crate, modifying public re-exports,
                  bumping dependencies, refactoring beyond annotation
   Action:    add `// invariant: <reason>` comment 1-3 lines above each hit
              OR convert to `?` propagation if the function returns Result
   Done when: baseline scan on dj-audio crate drops by the row count

   Plugin tool sequence:
     1. github_open_pr (issueId, branch, title, body, draft=true, labels)
     2. (engineer waits — Validation/Build Verifier take over)
     3. (Merge Director takes over)

   Hard refusal references:
     - DO NOT use `gh pr create` shell. Plugin will reject if you try
       to bypass `github_open_pr`.
     - DO NOT exceed the row span. CTO will cancel the second concurrent
       task touching this crate.
```

Each engineer takes exactly one such batch per heartbeat. No fan-out
within a batch.

---

## 3. Lane allocation rule

| Lane | Crates this lane owns | Engineer pool |
|------|----------------------|--------------|
| Core | `crates/core-*`, `crates/store`, `crates/app-identity`, `crates/filecore*` | core-engineer-1, core-engineer-2 |
| Desktop | `apps/desktop`, `crates/desktop-*`, `crates/bridge-desktop`, `vendor/gpui-component-*` | desktop-engineer-1, desktop-engineer-2 |
| DJ | `packs/DJ_player/crates/dj-*`, `packs/DJ_player/crates/bridge-desktop-dj` | dj-engineer-1, dj-engineer-2 |
| Integration | cross-crate glue, `crates/desktop-shared-services` facade, any PR touching ≥2 lanes | integration-engineer-1, integration-engineer-2 |

CTO veto rule: never two PRs on the same crate at the same time. Cross-
lane PRs go to the Integration lane.

---

## 4. Parallelism envelope

| Resource | Cap |
|---|---|
| Live codex children (company-wide) | 15 (Runner Coordinator hard rule) |
| Reserved for governance (CEO/CTO/Audit/Validation/Build/Merge Directors) | 6 |
| Available for engineer work | **9** |
| Engineers in roster | 8 |
| Effective concurrency | **8 engineer tasks simultaneously** |
| Wall-time per engineer task | 30 min (Runner Coord) |
| 8 h working window per day | 16 × 30-min slots × 8 engineers = 128 task-slots |
| Expected utilisation (cold start) | ~50% (CI + review + worktree provisioning overhead) |
| Realistic drain rate, day 1 | **~60 PRs / day** in steady state |
| Realistic drain rate, day ≥2 | ~80 PRs / day |

Cycle-7 target (60 PRs total) → **1 day** at steady state, plus
1–2 days for merge queue drain.

Total Phase-1 cycle through 7 cycles: **2–3 weeks** of company wall-time.

---

## 5. Seeding the queue

We do not hand-write 100 paperclip issues. The Delivery Lead runs the
seeder script:

```
scripts/seed-violations-from-baselines.py \
  --company bd235017-16ce-4e6f-9c95-2e9b2971829b \
  --project 85379338-88ec-4b80-aa11-ca438c78f6ba \
  --baseline-dir D:/code/djcowork2.0/audit \
  --cycle 1   # which strategy table row to materialize
```

(Seeder script lands as part of this playbook PR — see
`scripts/seed-violations-from-baselines.py`.)

The seeder:
1. Reads one baseline file
2. Splits its hits by (lane, crate)
3. Computes batch sizes so no batch > 300 row units
4. POSTs `/api/companies/<id>/issues` with the template above
5. Records the (issue_id, baseline_row_span) pairing in
   `D:\paperclip\tmp\seed-cycle-<n>.json` so re-running is idempotent

The Audit Lead reviews the seeded queue once. Delivery Lead then
processes it FIFO within (lane × class).

---

## 6. Cycle conclusion criterion

A cycle is "done" when:

| Check | Source of truth |
|------|----------------|
| Every seeded issue is `done` or `cancelled` | paperclip issue list |
| The baseline scan re-run drops by the targeted row count | `scripts/expect_baseline.py` on djcowork2.0 |
| `main` branch is green on all 9 required quality contexts | branch protection on djcowork/djcowork2.0 |
| `cargo-deny` advisory count did not grow | `cargo +1.88.0 deny check` on main |

Audit Lead marks the class complete only when all four pass.

---

## 7. Risk register and counter-measures

| Risk | Trigger | Counter-measure |
|------|--------|-----------------|
| Two engineers touch same crate | CTO did not gate concurrent allocation | CTO must hold an in-memory `(crate → active-engineer)` table; reject the second allocation, requeue |
| Worktree disk grows past 20 GB | High concurrency × large repo | Workspace Operator prunes worktrees > 7 d on each heartbeat |
| codex `process_lost` from MAX_PATH | Windows long-path not enabled OR new path that exceeds even 32k chars | A) confirm `scripts/enable-windows-longpaths.ps1` ran. B) if recurring, migrate to WSL2 per `doc/plans/2026-05-14-wsl2-cross-compile-migration.md` |
| Engineer drive-by edits exceeding scope | "Allowed scope" line in template ignored | Reviewer (Validation Director) rejects PR; Audit Lead re-files |
| Mass PR backlog at merge | auto-merge.yml + auto-update-prs.yml sequential; user-owned repo has no real Merge Queue | Accept it — the auto-update-prs.yml 5-min schedule keeps each PR rebased. Cap concurrent open PRs at 24 (3 × engineer pool) |
| CI flakes block cycle close | Self-hosted Linux runner saturation | Runner Coordinator surfaces queue depth, CTO temporarily lowers concurrency to 4 |
| Baseline regenerated mid-cycle | Audit Lead reruns scan; numbers drift | Lock the baseline file with `last_review` frontmatter; only Audit Lead's "close" event allows re-baseline |

---

## 8. Out-of-scope for v1 of this playbook

- Automated regression detection on merged PRs (currently relies on
  post-merge-canary.yml in djcowork2.0)
- Cross-repo issues (e.g. upstream gpui patches)
- v0.2 plugin webhook receiver (Merge Director still polls v0.1)
- Org-level merge queue (djcowork is a User account, not Organization)
- Live dashboard — use `gh pr list` + paperclip UI for now

When these unlock, this playbook gets a v2.

---

## 9. Roles touched by this playbook

| Role | Reads this file | Acts on this file |
|------|----|----|
| Audit Lead | yes | yes — sets cycle scope |
| Delivery Lead | yes | yes — runs seeder, owns queue |
| CTO | yes | yes — concurrent-crate gating |
| CEO | yes | yes — cycle order |
| Workspace Director / Operator | yes | indirectly — per-batch worktree |
| Engineers | yes — they need the row span | yes — one batch at a time |
| Validation Director / Build Verifier / Merge Director | yes | yes — gate per PR not per cycle |
| Lane Leads | yes | yes — engineer allocation |
| Specialist leads (Architecture / Audio-RT / etc.) | yes | only when scope intersects their lane |
