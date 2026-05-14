#!/usr/bin/env python3
"""Seed paperclip with single-concept fix tasks from djcowork2.0 audit baselines.

Reads `audit/2026-05-13-<class>.md` baseline files, splits each baseline's
hits by (lane, crate), and POSTs one paperclip issue per batch so engineers
can drain them in parallel without exceeding the 300-row-per-PR cap.

Usage:
    python scripts/seed-violations-from-baselines.py \\
        --company  bd235017-16ce-4e6f-9c95-2e9b2971829b \\
        --project  85379338-88ec-4b80-aa11-ca438c78f6ba \\
        --baseline-dir D:/code/djcowork2.0/audit \\
        --cycle 1 \\
        --dry-run                  # preview without POSTing

Cycles map to the seven-cycle strategy in
`doc/company-packages/compliance-first-ai-company/VIOLATION-PLAYBOOK.md`:
    1 = edition-inheritance     (4 PRs)
    2 = cargo-deny deadlines    (manual, no batching needed)
    3 = silent-error            (~8 PRs)
    4 = desktop-silent-fallback (~8 PRs)
    5 = async-blocking-io       (5 PRs)
    6 = reexport-chains         (5 PRs)
    7 = expect-baseline         (~60 PRs)

The script is idempotent per cycle: it writes the seed plan + posted issue
IDs to D:\\paperclip\\tmp\\seed-cycle-<n>.json. Re-running with --resume
skips already-posted batches.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

# ---------------------------------------------------------------------------
# Lane allocation table (kept in code so the seeder is the single source of
# truth for paperclip Delivery Lead -> Lane Lead routing).
# ---------------------------------------------------------------------------
LANE_RULES: list[tuple[str, str, str]] = [
    # (lane, glob-prefix, agent-name-hint)
    ("Desktop", "apps/desktop", "Desktop Lead"),
    ("Desktop", "crates/desktop-", "Desktop Lead"),
    ("Desktop", "crates/bridge-desktop", "Desktop Lead"),
    ("Desktop", "vendor/gpui-component", "Desktop Lead"),
    ("DJ", "packs/DJ_player/crates/dj-", "DJ Lead"),
    ("DJ", "packs/DJ_player/crates/bridge-desktop-dj", "DJ Lead"),
    ("Integration", "crates/desktop-shared-services", "Integration Lead"),
    ("Core", "crates/core-", "Core Lead"),
    ("Core", "crates/store", "Core Lead"),
    ("Core", "crates/app-identity", "Core Lead"),
    ("Core", "crates/filecore", "Core Lead"),
    ("Core", "crates/", "Core Lead"),
]


def lane_for_crate(crate_path: str) -> tuple[str, str]:
    p = crate_path.replace("\\", "/")
    for lane, prefix, hint in LANE_RULES:
        if p.startswith(prefix):
            return lane, hint
    return "Integration", "Integration Lead"


# ---------------------------------------------------------------------------
# Cycle parsers — each returns a list of batches. A batch is one paperclip
# issue.
# ---------------------------------------------------------------------------
@dataclass
class Batch:
    cycle: int
    title: str
    body: str
    lane: str
    target_crate: str
    row_count: int
    labels: list[str] = field(default_factory=list)
    assignee_hint: str = ""

    def to_issue_body(self) -> dict[str, object]:
        return {
            "title": self.title,
            "description": self.body,
            "priority": "medium",
        }


def parse_expect_baseline_top_crates(baseline_text: str) -> list[tuple[str, int]]:
    """Parse the 'Top 50 crate by unannotated count' table.

    Returns list of (crate_path, unannotated_count).
    """
    rows: list[tuple[str, int]] = []
    in_table = False
    for line in baseline_text.splitlines():
        if line.startswith("CRATE") and "UNANN" in line:
            in_table = True
            continue
        if not in_table:
            continue
        if line.startswith("```") or not line.strip():
            if rows:
                break
            continue
        # rows look like:
        #   packs/DJ_player/crates/dj-audio                                1159     1   1158  expect=...
        parts = line.split()
        if len(parts) < 5:
            continue
        crate = parts[0]
        try:
            unann = int(parts[3])
        except ValueError:
            continue
        if unann > 0:
            rows.append((crate, unann))
    return rows


def split_into_chunks(crate: str, unann: int, max_per_pr: int = 300) -> list[int]:
    """Split unann count into chunk sizes that each fit a PR."""
    n_chunks = max(1, (unann + max_per_pr - 1) // max_per_pr)
    base = unann // n_chunks
    extra = unann % n_chunks
    return [base + (1 if i < extra else 0) for i in range(n_chunks)]


def build_cycle_1_edition(baseline_text: str) -> list[Batch]:
    """Cycle 1: edition.workspace=true on 89 Cargo.toml. 1 PR per lane."""
    manifests = re.findall(r"`([^`]*Cargo\.toml)`\s*\|\s*[^|]+\|\s*改为", baseline_text)
    by_lane: dict[str, list[str]] = {}
    for m in manifests:
        crate_dir = m.rsplit("/", 1)[0]
        lane, _ = lane_for_crate(crate_dir)
        by_lane.setdefault(lane, []).append(m)
    out: list[Batch] = []
    for lane, files in sorted(by_lane.items()):
        if not files:
            continue
        body = (
            "Baseline:  audit/2026-05-13-edition-inheritance.md\n"
            f"Lane:      {lane}\n"
            f"Manifests: {len(files)} files\n"
            "Action:    set `edition.workspace = true` in each manifest below. "
            "Remove any redundant explicit edition lines.\n"
            "Scope:     Cargo.toml only. Do NOT touch source files, do NOT bump deps.\n\n"
            "Files:\n"
            + "\n".join(f"  - {f}" for f in files)
            + "\n\nPlugin tool sequence:\n"
            "  1. github_open_pr (issueId, branch, title, body, draft=true,\n"
            "                     labels=['compliance','phase1'," + repr(lane.lower()) + "])\n"
            "  2. Validation Director batches with other cycle-1 PRs.\n"
            "  3. Build Verifier publishes cargo-check evidence.\n"
            "  4. Merge Director enqueues via github_enqueue_merge."
        )
        out.append(
            Batch(
                cycle=1,
                title=f"[edition][{lane}] set edition.workspace=true on {len(files)} manifests",
                body=body,
                lane=lane,
                target_crate=f"{lane}-lane",
                row_count=len(files),
                labels=["compliance", "phase1", lane.lower(), "edition-inheritance"],
            )
        )
    return out


def build_cycle_7_expect(baseline_text: str) -> list[Batch]:
    """Cycle 7: drain 4097 unannotated expect/panic/let _/unreachable hits."""
    crates = parse_expect_baseline_top_crates(baseline_text)
    out: list[Batch] = []
    for crate, unann in crates:
        lane, lead = lane_for_crate(crate)
        chunks = split_into_chunks(crate, unann, max_per_pr=300)
        for idx, chunk_size in enumerate(chunks, start=1):
            crate_short = crate.split("/")[-1]
            body = (
                "Baseline:  audit/2026-05-13-expect-baseline.md\n"
                f"Crate:     {crate}\n"
                f"Chunk:     {idx} of {len(chunks)}\n"
                f"Row span:  approximately {chunk_size} of {unann} unannotated hits\n"
                "Action:    for each hit, either add\n"
                "             // invariant: <one-line reason>\n"
                "           1-3 lines above it, OR convert to `?` propagation if\n"
                "           the enclosing fn returns Result.\n"
                "Hit types: .expect() / panic!() / unreachable!() / todo!() / "
                "unimplemented!() / `let _ = <fallible>`\n"
                f"Scope:     {crate} ONLY. Do not touch any other crate, do not\n"
                "           modify public re-exports, do not bump deps.\n"
                "Done when: scripts/expect_baseline.py re-run on this crate shows the\n"
                f"           unannotated count drop by ≥ {chunk_size}.\n\n"
                "Plugin tool sequence:\n"
                "  1. github_open_pr (issueId, branch, title, body, draft=true,\n"
                f"                     labels=['compliance','phase1','{lane.lower()}'])\n"
                "  2. Validation Director runs unified test batch.\n"
                "  3. Build Verifier publishes evidence per COMPANY-SOP §2.12.\n"
                "  4. Merge Director enqueues via github_enqueue_merge."
            )
            out.append(
                Batch(
                    cycle=7,
                    title=f"[expect][{lane}][{crate_short}] drain ~{chunk_size} of {unann} unannotated (chunk {idx}/{len(chunks)})",
                    body=body,
                    lane=lane,
                    target_crate=crate,
                    row_count=chunk_size,
                    labels=["compliance", "phase1", lane.lower(), "expect-baseline"],
                    assignee_hint=lead,
                )
            )
    return out


CYCLE_BUILDERS: dict[int, tuple[str, callable]] = {
    1: ("2026-05-13-edition-inheritance.md", build_cycle_1_edition),
    7: ("2026-05-13-expect-baseline.md", build_cycle_7_expect),
}


# ---------------------------------------------------------------------------
# paperclip POST
# ---------------------------------------------------------------------------
def post_issue(base: str, company_id: str, project_id: str, batch: Batch, assignee_id: str | None) -> dict:
    body = {
        "title": batch.title,
        "description": batch.body,
        "projectId": project_id,
        "priority": "medium",
        "workMode": "standard",
    }
    if assignee_id:
        body["assigneeAgentId"] = assignee_id
    req = urllib.request.Request(
        f"{base}/api/companies/{company_id}/issues",
        data=json.dumps(body).encode(),
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


def resolve_lane_lead_id(base: str, company_id: str, lane_lead_name: str) -> str | None:
    if not lane_lead_name:
        return None
    with urllib.request.urlopen(f"{base}/api/companies/{company_id}/agents") as r:
        agents = json.loads(r.read())
    for a in agents if isinstance(agents, list) else agents.get("agents", []):
        if (a.get("name") or "").strip().lower() == lane_lead_name.lower():
            return a.get("id")
    return None


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--company", required=True, help="paperclip company UUID")
    ap.add_argument("--project", required=True, help="paperclip project UUID")
    ap.add_argument("--baseline-dir", required=True, type=Path)
    ap.add_argument("--cycle", type=int, required=True, choices=list(CYCLE_BUILDERS))
    ap.add_argument("--base", default="http://localhost:3100", help="paperclip API base")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--resume", action="store_true", help="skip batches already posted")
    ap.add_argument("--max-batches", type=int, default=0, help="cap (0 = no cap)")
    args = ap.parse_args()

    baseline_file, builder = CYCLE_BUILDERS[args.cycle]
    bp = args.baseline_dir / baseline_file
    if not bp.exists():
        print(f"ERR: baseline file not found: {bp}", file=sys.stderr)
        return 2
    text = bp.read_text(encoding="utf-8", errors="replace")
    batches = builder(text)
    if args.max_batches:
        batches = batches[: args.max_batches]
    print(f"cycle {args.cycle}: {len(batches)} batches from {bp.name}")

    plan_path = Path("D:/paperclip/tmp") / f"seed-cycle-{args.cycle}.json"
    plan_path.parent.mkdir(parents=True, exist_ok=True)
    posted: dict[str, str] = {}
    if args.resume and plan_path.exists():
        posted = json.loads(plan_path.read_text(encoding="utf-8")).get("posted", {})

    summary = []
    lead_cache: dict[str, str | None] = {}
    for b in batches:
        key = b.title
        if key in posted:
            summary.append((b, posted[key], "skip"))
            continue
        if args.dry_run:
            summary.append((b, "(dry-run)", "would-post"))
            continue
        if b.assignee_hint and b.assignee_hint not in lead_cache:
            lead_cache[b.assignee_hint] = resolve_lane_lead_id(args.base, args.company, b.assignee_hint)
        assignee_id = lead_cache.get(b.assignee_hint)
        try:
            d = post_issue(args.base, args.company, args.project, b, assignee_id)
            issue_id = d.get("id")
            posted[key] = issue_id
            summary.append((b, issue_id, "posted"))
        except urllib.error.HTTPError as e:
            err_body = e.read().decode(errors="replace")[:300]
            summary.append((b, f"HTTP {e.code}: {err_body}", "fail"))

    plan_path.write_text(
        json.dumps(
            {"cycle": args.cycle, "baseline": baseline_file, "posted": posted},
            indent=2,
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    print()
    print(f"{'STATUS':<10}{'LANE':<12}{'ROWS':<7}TITLE")
    print("-" * 100)
    for b, ref, status in summary:
        print(f"{status:<10}{b.lane:<12}{b.row_count:<7}{b.title[:70]}")
    counts = {}
    for _, _, s in summary:
        counts[s] = counts.get(s, 0) + 1
    print()
    print("summary:", counts)
    print("plan saved to:", plan_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
