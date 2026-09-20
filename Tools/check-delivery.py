#!/usr/bin/env python3
"""Local preflight/evidence/document gate. Does not execute CI or judge evidence truth."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
KINDS = {"unit", "simulator", "device", "inspection"}
BASE_UNITS = {f"{p}-{i}" for p in ("P0", "P1") for i in range(1, 7)}
P2_UNITS = {f"P2-{i}" for i in range(1, 14)}
CONDITIONAL_UNITS = {"P2-6", "P2-12", "P2-13"}
CONDITIONAL_VERIFICATION_CRITERIA = {
    "P2-8.signed-service",
    "P2-10.signed-service",
    # Explicit owner acceptance on 2026-09-19; never represented as device passes.
    "P2-3.device", "P2-4.device", "P2-11.device", "P2-12.device",
}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def unique(items, label):
    require(len(items) == len(set(items)), f"duplicate {label}")


def source(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{40}", value)


def validate_plan(plan):
    require(plan["schema"] in {1, 2}, "unsupported plan schema")
    v1 = plan["schema"] == 2
    units = {u["id"]: u for u in plan["units"]}
    waves = {w["id"]: w for w in plan["waves"]}
    unique([u["id"] for u in plan["units"]], "unit")
    unique([w["id"] for w in plan["waves"]], "wave")
    require(set(units) == BASE_UNITS | (P2_UNITS if v1 else set()),
            "missing/extra units: Issue #5 P0/P1 and adopted Issue #6 P2 scope must be preserved")
    if v1:
        require(plan.get("v1_decision") == "adopted-issue6-2026-09-15", "v1 boundary not decided")
    criteria = []
    for uid, unit in units.items():
        require(unit["priority"] in ({"P0", "P1", "P2"} if v1 else {"P0", "P1"}), f"{uid}: invalid priority")
        require(uid.startswith(unit["priority"] + "-"), f"{uid}: priority differs from Issue #5")
        require(unit["state"] in {"partial", "complete"}, f"{uid}: invalid state")
        milestone = {"P0": "0.7.0", "P1": "0.8.0", "P2": "1.0.0"}[unit["priority"]]
        require(unit["milestone"] == milestone, f"{uid}: incorrect milestone")
        require(unit["parents"] and all(re.fullmatch(r"D(0[1-9]|[12][0-9]|3[0-2])", d)
                for d in unit["parents"]), f"{uid}: invalid parent")
        require(unit["criteria"], f"{uid}: no acceptance criteria")
        if unit["priority"] == "P2":
            by_suffix = {c["id"].removeprefix(uid + "."): c for c in unit["criteria"]}
            require({"ownership", "integration", "device", "docs"} <= by_suffix.keys(),
                    f"{uid}: P2 normal execution/device/docs criteria missing")
            require(by_suffix["ownership"]["kinds"] == ["unit"] and
                    set(by_suffix["integration"]["kinds"]) == {"simulator", "device"} and
                    by_suffix["device"]["kinds"] == ["device"] and
                    by_suffix["docs"]["kinds"] == ["inspection"], f"{uid}: P2 evidence types weakened")
        if uid in CONDITIONAL_UNITS:
            decision = unit.get("scope_decision", {})
            require(decision.get("status") in {"pending", "adopted", "excluded"}, f"{uid}: invalid scope decision")
            if decision["status"] == "pending":
                require(unit["state"] == "partial", f"{uid}: undecided scope cannot be complete")
            else:
                require(nonempty(decision.get("reason")), f"{uid}: scope decision reason missing")
                if decision["status"] == "adopted":
                    require(nonempty(decision.get("adopted_scope")), f"{uid}: adopted scope missing")
            require(any(c.get("adopted_only") and set(c["kinds"]) <= {"unit", "simulator", "device"}
                        for c in unit["criteria"]), f"{uid}: adopted scope needs execution evidence")
            require(any(not c.get("adopted_only") and c["kinds"] == ["inspection"]
                        for c in unit["criteria"]), f"{uid}: scope review evidence missing")
        for criterion in unit["criteria"]:
            require(criterion["id"].startswith(uid + "."), f"{uid}: foreign criterion")
            require(nonempty(criterion["description"]), f"{uid}: empty criterion")
            require(criterion["kinds"] and set(criterion["kinds"]) <= KINDS,
                    f"{uid}: invalid evidence kinds")
            require(not criterion.get("adopted_only") or uid in CONDITIONAL_UNITS,
                    f"{uid}: mandatory functionality cannot be conditional")
            decision = criterion.get("conditional_verification")
            if decision is not None:
                require(isinstance(decision, dict),
                        f"{criterion['id']}: invalid conditional verification decision")
                require(criterion["id"] in CONDITIONAL_VERIFICATION_CRITERIA,
                        f"{criterion['id']}: conditional verification is not permitted")
                require(criterion["kinds"] == ["device"],
                        f"{criterion['id']}: conditional verification must remain device-only")
                require(decision.get("status") in {"required", "approved-unverified"},
                        f"{criterion['id']}: invalid conditional verification decision")
                if decision["status"] == "approved-unverified":
                    require(nonempty(decision.get("scope")) and nonempty(decision.get("reason")),
                            f"{criterion['id']}: approved unverified scope/reason missing")
            criteria.append(criterion["id"])
    unique(criteria, "criterion")
    require(set(plan["milestones"]) == ({"0.7.0", "0.8.0", "1.0.0"} if v1 else {"0.7.0", "0.8.0"}), "unexpected milestones")
    for version, members in plan["milestones"].items():
        unique(members, "milestone member")
        expected = {uid for uid, u in units.items() if
                    version == "1.0.0" or u["priority"] == "P0" or
                    (version == "0.8.0" and u["priority"] == "P1")}
        require(set(members) == expected, f"{version}: missing or extra milestone units")
    assigned = []
    for wid, wave in waves.items():
        require(wave["units"] and set(wave["units"]) <= set(wave["checks"]) <= units.keys(),
                f"{wid}: invalid unit/check scope")
        unique(wave["checks"], f"{wid} check")
        unique(wave["requires"], f"{wid} dependency")
        require(set(wave["requires"]) <= waves.keys(), f"{wid}: unknown dependency")
        require(type(wave["ci_budget"]) is int and wave["ci_budget"] > 0, f"{wid}: invalid budget")
        assigned.extend(wave["units"])
    unique(assigned, "wave assignment")
    require(set(assigned) == units.keys(), "unassigned unit")
    def visit(wid, stack):
        require(wid not in stack, "wave dependency cycle")
        for dep in waves[wid]["requires"]:
            visit(dep, stack | {wid})
    for wid in waves:
        visit(wid, set())
    return units, waves


def active_criteria(unit):
    """Only an explicitly excluded optional scope can omit its execution checks."""
    excluded = unit.get("scope_decision", {}).get("status") == "excluded"
    return [c for c in unit["criteria"] if not (excluded and c.get("adopted_only")) and
            c.get("conditional_verification", {}).get("status") != "approved-unverified"]


def approved_unverified_criteria(unit):
    """Explicitly approved observation limits stay unverified and are never passed evidence."""
    return [c for c in unit["criteria"]
            if c.get("conditional_verification", {}).get("status") == "approved-unverified"]


def current_docs(root, version):
    """Dynamic inventory: current prose, not archived research or historical release notes."""
    fixed = {"README.md", "CHANGELOG.md", "CONTRIBUTING.md", "SECURITY.md",
             "THIRD_PARTY_NOTICES.md", "docs/superpowers/plans/2026-09-08-jibunkit-1.0.md",
             f"docs/releases/release-notes-{version}.md"}
    for pattern in ("docs/*.md", "docs/guides/**/*.md", "docs/delivery/**/*.md", "Modules/**/README.md"):
        fixed.update(p.relative_to(root).as_posix() for p in root.glob(pattern))
    return sorted(fixed)


def validate_docs(records, review, root, version):
    require(isinstance(review, dict) and source(review.get("source")),
            "document review requires a full reviewed commit")
    require(nonempty(review.get("summary")), "document review summary missing")
    require(isinstance(review.get("unresolved"), list) and
            all(nonempty(item) for item in review["unresolved"]),
            "document review unresolved issues must be a list (empty if none)")
    unique([r["path"] for r in records], "document review")
    by_path = {r["path"]: r for r in records}
    paths = current_docs(root, version)
    for path in paths:
        require(path in by_path, f"missing document review: {path}")
        record = by_path[path]
        file = root / path
        require(file.is_file(), f"missing current document: {path}")
        require(record["outcome"] in {"updated", "reviewed-unchanged"},
                f"incomplete document review: {path}")
    # Git owns the snapshot; no duplicate per-file hashes in the review record.
    # A checklist cannot prove semantic accuracy, which still requires reading.
    commit = review["source"] + "^{commit}"
    tree = subprocess.run(["git", "-C", str(root), "ls-tree", "-r", "-z", "--name-only", commit],
                          capture_output=True, text=True, encoding="utf-8")
    require(tree.returncode == 0, "document review commit unavailable")
    tracked = set(tree.stdout.split("\0"))
    for path in paths:
        require(path in tracked, f"document absent from reviewed commit: {path}")
    diff = subprocess.run(["git", "-C", str(root), "diff", "--quiet", "--no-ext-diff",
                           commit, "--", *paths], capture_output=True)
    require(diff.returncode == 0, "stale document review: current documents differ from reviewed commit")


def validate_report(plan, report, stage, root=ROOT, version=None):
    units, waves = validate_plan(plan)
    require(report["schema"] == 1 and source(report["source"]), "invalid report source/schema")
    wid = report["wave"]
    require(wid in waves, "unknown wave")
    wave = waves[wid]
    if stage == "release":
        require(version in plan["milestones"], "release boundary not decided (including v1.0)")
        members = plan["milestones"][version]
        require(set(members) <= set(wave["checks"]), "wave does not cover release")
        require(all(units[u]["state"] == "complete" for u in members), "release units still partial")
    else:
        members = wave["checks"]
    criteria = {c["id"]: c for u in members for c in active_criteria(units[u])}
    approved = {c["id"]: c["conditional_verification"]
                for u in members for c in approved_unverified_criteria(units[u])}
    approvals = report.get("approved_unverified", [])
    unique([item["criterion"] for item in approvals], "approved unverified criterion")
    require({item["criterion"] for item in approvals} == set(approved),
            "approved unverified report does not match plan")
    for item in approvals:
        decision = approved[item["criterion"]]
        require(item.get("result") == "unverified-approved-exclusion",
                f"{item['criterion']}: approved exclusion must remain unverified")
        require(item.get("scope") == decision["scope"] and item.get("reason") == decision["reason"],
                f"{item['criterion']}: approved exclusion scope/reason differs from plan")
    for uid in set(members) & CONDITIONAL_UNITS:
        require(units[uid]["scope_decision"]["status"] != "pending", f"{uid}: scope decision pending")
    contract = report["contract"]
    require(all(nonempty(contract[k]) for k in ("baseline", "interfaces", "ownership", "failure_cases",
            "normal_entrypoints", "invalidation", "review")), "contract/review not ready")
    require(source(contract["baseline"]), "baseline must be a full commit")
    for dep in wave["requires"]:
        require(nonempty(report["dependencies"].get(dep)), f"missing dependency evidence: {dep}")
    jobs = report["jobs"]
    unique([j["id"] for j in jobs], "job")
    scheduled = set()
    for job in jobs:
        require(job["kind"] in KINDS - {"device"}, "invalid CI/local job kind")
        require(nonempty(job["command"]) and job["criteria"], "empty job command/scope")
        require(0 < job["expected_minutes"] <= 30 and job["expected_minutes"] <= job["timeout_minutes"] <= 45,
                "split long jobs: expected <=30, timeout <=45 minutes")
        for cid in job["criteria"]:
            require(cid in criteria and job["kind"] in criteria[cid]["kinds"], f"invalid job coverage: {cid}")
            scheduled.add(cid)
    require(type(report["planned_ci_runs"]) is int and report["planned_ci_runs"] > 0, "missing CI run plan")
    if any(units[uid]["priority"] == "P2" for uid in wave["units"]):
        execution = report.get("ci_execution", [])
        require(len(execution) == report["planned_ci_runs"], "P2 needs one execution plan per planned run")
        unique([r["id"] for r in execution], "execution plan")
        for run in execution:
            require(nonempty(run.get("inputs_and_filters")) and nonempty(run.get("estimate_basis")),
                    "P2 execution inputs/filter or elapsed-time basis missing")
            require(0 < run.get("expected_elapsed_minutes", 0) <= 25,
                    "P2 expected elapsed time must include dependencies and fit 25 minutes")
    runs = report["runs"]
    unique([r["id"] for r in runs], "run/attempt")
    if max(report["planned_ci_runs"], len(runs)) > wave["ci_budget"]:
        require(nonempty(report["budget_exception"]), "CI budget exceeded without explanation")
    for run in runs:
        require(nonempty(run["url"]) and source(run["source"]) and nonempty(run["conclusion"]), "incomplete run record")
    evidence = report["evidence"]
    unique([e["criterion"] for e in evidence], "evidence criterion")
    proven = set()
    for item in evidence:
        cid = item["criterion"]
        require(cid in criteria, f"unknown evidence criterion: {cid}")
        require(item["kind"] in criteria[cid]["kinds"], f"wrong evidence kind: {cid}")
        require(item["result"] == "passed" and source(item["source"]), f"not passed: {cid}")
        require(all(nonempty(item[k]) for k in ("reference", "observation", "review")), f"empty evidence: {cid}")
        if item["source"] != report["source"]:
            require(nonempty(item.get("reuse_reason")), f"different source requires reviewed reuse: {cid}")
        proven.add(cid)
    deferred = report["deferred_device"]
    # A criterion may permit either Simulator or device evidence. Planning its
    # remaining OS interactions on the candidate device is not a passed result
    # or a deferral of a CI-only criterion.
    device_checks = report.get("planned_device_checks", [])
    unique([check["criterion"] for check in device_checks], "planned device criterion")
    planned_device = set()
    for check in device_checks:
        cid = check["criterion"]
        require(cid in criteria and "device" in criteria[cid]["kinds"], f"invalid planned device check: {cid}")
        require(nonempty(check["procedure"]) and source(check["source"]), f"incomplete planned device check: {cid}")
        require(check["checkpoint"] == units[cid.split(".")[0]]["milestone"], f"wrong planned device checkpoint: {cid}")
        planned_device.add(cid)
    for cid, target in deferred.items():
        require(cid in criteria and set(criteria[cid]["kinds"]) == {"device"}, f"invalid device deferral: {cid}")
        uid = cid.split(".")[0]
        require(target == units[uid]["milestone"], f"wrong device checkpoint: {cid}")
    for cid, criterion in criteria.items():
        if cid in proven:
            continue
        device_only = set(criterion["kinds"]) == {"device"}
        if stage != "release" and device_only and cid in deferred:
            continue
        require(stage == "preflight" and not device_only and (cid in scheduled or cid in planned_device),
                f"missing {'planned check' if stage == 'preflight' else 'passed evidence'}: {cid}")
    if stage != "preflight":
        require(runs, "no CI runs recorded")
    if stage == "release":
        require(not deferred, "release cannot defer device checks")
        require(all(nonempty(report["release"][k]) for k in ("candidate_ipa", "normal_regression",
                "generated_host", "metadata", "compatibility", "physical_review")), "release evidence missing")
        validate_docs(report["documents"], report.get("document_review"), root, version)
    return f"{wid}: {stage} structure/coverage passed; evidence truth requires human review"


def template(plan, wid, sha):
    units, waves = validate_plan(plan)
    require(wid in waves and source(sha), "template needs known wave and full source commit")
    wave = waves[wid]
    approved = [c for u in wave["checks"] for c in approved_unverified_criteria(units[u])]
    return {"schema": 1, "wave": wid, "source": sha,
            "contract": {k: "" for k in ("baseline", "interfaces", "ownership", "failure_cases",
                         "normal_entrypoints", "invalidation", "review")},
            "dependencies": {d: "" for d in wave["requires"]},
            "planned_ci_runs": wave["ci_budget"], "budget_exception": "", "jobs": [], "runs": [],
            "evidence": [], "deferred_device": {c["id"]: units[u]["milestone"]
                for u in wave["checks"] for c in active_criteria(units[u]) if set(c["kinds"]) == {"device"}},
            "approved_unverified": [{"criterion": c["id"], "result": "unverified-approved-exclusion",
                "scope": c["conditional_verification"]["scope"],
                "reason": c["conditional_verification"]["reason"]} for c in approved],
            "documents": [], "document_review": {"source": "", "summary": "", "unresolved": []},
            "release": {},
            "metrics": {"review_rounds": 0, "parent_messages": 0, "ci_job_minutes": 0},
            "acceptance": {c["id"]: c["description"] for u in wave["checks"] for c in active_criteria(units[u])}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, default=ROOT / "docs/delivery/plan.json")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--stage", choices=("preflight", "ci", "release"), default="preflight")
    parser.add_argument("--release", dest="version")
    parser.add_argument("--template", metavar="WAVE")
    parser.add_argument("--source")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--list-docs", metavar="VERSION")
    args = parser.parse_args()
    try:
        plan = json.loads(args.plan.read_text(encoding="utf-8-sig"))
        validate_plan(plan)
        require(args.version is None or (args.report is not None and args.stage == "release"),
                "--release requires --report and --stage release")
        if args.list_docs:
            print("\n".join(current_docs(ROOT, args.list_docs)))
        elif args.template:
            require(args.output is not None, "template requires --output")
            draft = template(plan, args.template, args.source)
            # Exclusive creation protects existing evidence from accidental replacement.
            with args.output.open("x", encoding="utf-8", newline="\n") as output:
                json.dump(draft, output, ensure_ascii=False, indent=2)
                output.write("\n")
            print(f"Created incomplete template: {args.output}")
        elif args.report:
            report = json.loads(args.report.read_text(encoding="utf-8-sig"))
            print(validate_report(plan, report, args.stage, version=args.version))
        else:
            require(args.stage == "preflight" and args.version is None, "stage/release requires --report")
            print(f"Plan valid: {len(plan['units'])} units, {len(plan['waves'])} CI boundaries")
    except (ValueError, KeyError, TypeError, OSError) as error:
        print(f"Delivery gate failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
