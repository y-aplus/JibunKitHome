import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import subprocess
import sys
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("delivery", Path(__file__).resolve().parents[1] / "check-delivery.py")
delivery = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(delivery)
SHA = "a" * 40


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.plan = json.loads((delivery.ROOT / "docs/delivery/plan.json").read_text(encoding="utf-8"))

    def report(self, wave="P0-A", with_device=False):
        result = delivery.template(self.plan, wave, SHA)
        result["contract"] = {k: "reviewed contract reference" for k in result["contract"]}
        result["contract"]["baseline"] = SHA
        result["dependencies"] = {d: "prior reviewed evidence" for d in result["dependencies"]}
        selected = next(w for w in self.plan["waves"] if w["id"] == wave)["checks"]
        for u in self.plan["units"]:
            if u["id"] not in selected:
                continue
            for c in delivery.active_criteria(u):
                if c["kinds"] == ["device"] and not with_device:
                    continue
                result["evidence"].append({"criterion": c["id"], "kind": c["kinds"][0],
                    "source": SHA, "result": "passed", "reference": "test fixture reference",
                    "observation": "expected owner data retained", "review": "reviewed"})
        if with_device:
            result["deferred_device"] = {}
        result["runs"] = [{"id": "run-1/attempt-1", "url": "test-fixture://run-1", "source": SHA, "conclusion": "success"}]
        if wave.startswith("P2-"):
            result["ci_execution"] = [{"id": f"run-{i}", "inputs_and_filters": "test fixture exact workflow inputs/filter",
                "estimate_basis": "test fixture estimate including prepare/build/test/upload", "expected_elapsed_minutes": 20}
                for i in range(result["planned_ci_runs"])]
        return result

    def test_owner_accepted_observations_are_not_device_passes(self):
        units, _ = delivery.validate_plan(self.plan)
        for uid in ("P2-3", "P2-4", "P2-11", "P2-12"):
            excluded = delivery.approved_unverified_criteria(units[uid])
            self.assertEqual([c["id"] for c in excluded], [uid + ".device"])
            active = {c["id"] for c in delivery.active_criteria(units[uid])}
            self.assertTrue({uid + ".ownership", uid + ".integration", uid + ".docs"} <= active)
        unit = units["P2-9"]
        criterion = next(c for c in unit["criteria"] if c["id"] == "P2-9.device")
        criterion["conditional_verification"] = {
            "status": "approved-unverified", "scope": "unapproved BLE omission", "reason": "not accepted"}
        with self.assertRaisesRegex(ValueError, "conditional verification is not permitted"):
            delivery.validate_plan(self.plan)

    def test_real_plan_and_incomplete_template(self):
        delivery.validate_plan(self.plan)
        with self.assertRaisesRegex(ValueError, "contract/review"):
            delivery.validate_report(self.plan, delivery.template(self.plan, "P0-A", SHA), "preflight")

    def test_ci_allows_scheduled_device_without_claiming_release(self):
        report = self.report()
        delivery.validate_report(self.plan, report, "ci")
        report["deferred_device"] = {}
        with self.assertRaisesRegex(ValueError, "missing passed evidence"):
            delivery.validate_report(self.plan, report, "ci")

    def test_preflight_schedules_checks_but_ci_requires_results(self):
        report = self.report()
        e = report["evidence"].pop()
        report["jobs"] = [{"id": "local", "kind": e["kind"], "criteria": [e["criterion"]],
                           "command": "review local case", "expected_minutes": 10, "timeout_minutes": 20}]
        delivery.validate_report(self.plan, report, "preflight")
        with self.assertRaisesRegex(ValueError, "missing passed evidence"):
            delivery.validate_report(self.plan, report, "ci")

    def test_mixed_os_criterion_can_plan_device_but_cannot_claim_ci_pass(self):
        report = self.report(wave="P1-B", with_device=True)
        report["evidence"] = [e for e in report["evidence"] if e["criterion"] != "P1-4.os"]
        check = {"criterion": "P1-4.os", "source": SHA, "checkpoint": "0.8.0",
                 "procedure": "Candidate notification card mark/reply, foreground and other-owner retention"}
        report["planned_device_checks"] = [check]
        delivery.validate_report(self.plan, report, "preflight")
        ready_plan = copy.deepcopy(self.plan)
        for unit in ready_plan["units"]:
            if unit["priority"] in {"P0", "P1"}:
                unit["state"] = "complete"
        for stage in ["ci", "release"]:
            with self.assertRaisesRegex(ValueError, "missing passed evidence: P1-4.os"):
                delivery.validate_report(ready_plan, report, stage, version="0.8.0")
        for key, value, error in [("source", "short", "incomplete planned"),
                                  ("procedure", "", "incomplete planned"),
                                  ("checkpoint", "0.9.0", "wrong planned"),
                                  ("criterion", "P1-4.ownership", "invalid planned")]:
            bad = copy.deepcopy(report)
            bad["planned_device_checks"][0][key] = value
            with self.assertRaisesRegex(ValueError, error):
                delivery.validate_report(self.plan, bad, "preflight")
        report["planned_device_checks"].append(check)
        with self.assertRaisesRegex(ValueError, "duplicate"):
            delivery.validate_report(self.plan, report, "preflight")

    def test_evidence_type_and_duplicate_and_unknown(self):
        report = self.report(with_device=True)
        device = next(e for e in report["evidence"] if e["kind"] == "device")
        device["kind"] = "unit"
        with self.assertRaisesRegex(ValueError, "wrong evidence kind"):
            delivery.validate_report(self.plan, report, "ci")
        report = self.report()
        report["evidence"].append(copy.deepcopy(report["evidence"][0]))
        with self.assertRaisesRegex(ValueError, "duplicate evidence"):
            delivery.validate_report(self.plan, report, "ci")
        report["evidence"][-1]["criterion"] = "P9-1.fake"
        with self.assertRaisesRegex(ValueError, "unknown evidence"):
            delivery.validate_report(self.plan, report, "ci")

    def test_old_source_requires_explicit_reviewed_reuse(self):
        report = self.report()
        report["evidence"][0]["source"] = "b" * 40
        with self.assertRaisesRegex(ValueError, "reviewed reuse"):
            delivery.validate_report(self.plan, report, "ci")
        report["evidence"][0]["reuse_reason"] = "Reviewed diff; docs only, runtime and dependencies unchanged"
        delivery.validate_report(self.plan, report, "ci")

    def test_failed_evidence_is_not_success(self):
        report = self.report()
        report["evidence"][0]["result"] = "failed"
        with self.assertRaisesRegex(ValueError, "not passed"):
            delivery.validate_report(self.plan, report, "ci")

    def test_ci_budget_and_long_jobs(self):
        report = self.report()
        report["planned_ci_runs"] = 3
        with self.assertRaisesRegex(ValueError, "budget exceeded"):
            delivery.validate_report(self.plan, report, "ci")
        report["budget_exception"] = "One additional independent regression shard needed"
        delivery.validate_report(self.plan, report, "ci")
        report["jobs"] = [{"id": "oversized", "kind": "unit", "criteria": ["P0-1.lifetime"],
                           "command": "tests", "expected_minutes": 60, "timeout_minutes": 90}]
        with self.assertRaisesRegex(ValueError, "split long jobs"):
            delivery.validate_report(self.plan, report, "preflight")

    def test_bad_graph_missing_milestone_and_duplicate_units(self):
        invalid = copy.deepcopy(self.plan)
        invalid["waves"][0]["requires"] = ["P0-C"]
        with self.assertRaisesRegex(ValueError, "cycle"):
            delivery.validate_plan(invalid)
        invalid = copy.deepcopy(self.plan)
        invalid["milestones"]["0.8.0"].pop()
        with self.assertRaisesRegex(ValueError, "milestone units"):
            delivery.validate_plan(invalid)
        invalid = copy.deepcopy(self.plan)
        invalid["units"].append(invalid["units"][0])
        with self.assertRaisesRegex(ValueError, "duplicate unit"):
            delivery.validate_plan(invalid)

    def test_release_requires_complete_units_and_v1_decision(self):
        self.plan["units"][0]["state"] = "partial"
        report = self.report("P0-C", with_device=True)
        with self.assertRaisesRegex(ValueError, "still partial"):
            delivery.validate_report(self.plan, report, "release", version="0.7.0")
        with self.assertRaisesRegex(ValueError, "wave does not cover release"):
            delivery.validate_report(self.plan, report, "release", version="1.0.0")

    def test_legacy_plan_and_reports_keep_original_boundaries(self):
        legacy = copy.deepcopy(self.plan)
        legacy["schema"] = 1
        legacy["units"] = [u for u in legacy["units"] if u["priority"] != "P2"]
        legacy["waves"] = [w for w in legacy["waves"] if not w["id"].startswith("P2-")]
        del legacy["milestones"]["1.0.0"]
        legacy["v1_decision"] = "deferred-until-0.8.0-completion"
        delivery.validate_plan(legacy)
        delivery.validate_report(legacy, self.report("P1-B", with_device=True), "ci")
        with self.assertRaisesRegex(ValueError, "boundary not decided"):
            delivery.validate_report(legacy, self.report("P1-B", with_device=True), "release", version="1.0.0")

    def test_adopted_scope_cannot_drop_units_milestone_or_os_criteria(self):
        for uid in ["P0-1", "P1-1", "P2-7", "P2-8", "P2-13"]:
            invalid = copy.deepcopy(self.plan)
            invalid["units"] = [u for u in invalid["units"] if u["id"] != uid]
            with self.assertRaisesRegex(ValueError, "missing/extra units"):
                delivery.validate_plan(invalid)
        invalid = copy.deepcopy(self.plan)
        invalid["milestones"]["1.0.0"].remove("P2-8")
        with self.assertRaisesRegex(ValueError, "milestone units"):
            delivery.validate_plan(invalid)
        invalid = copy.deepcopy(self.plan)
        unit = next(u for u in invalid["units"] if u["id"] == "P2-7")
        unit["criteria"] = [c for c in unit["criteria"] if c["id"] != "P2-7.integration"]
        with self.assertRaisesRegex(ValueError, "criteria missing"):
            delivery.validate_plan(invalid)

    def test_p2_ci_requires_actual_execution_plan_and_elapsed_budget(self):
        report = self.report("P2-W", with_device=True)
        delivery.validate_report(self.plan, report, "ci")
        invalid = copy.deepcopy(report)
        invalid["ci_execution"] = []
        with self.assertRaisesRegex(ValueError, "one execution plan"):
            delivery.validate_report(self.plan, invalid, "preflight")
        for field, value, error in [("inputs_and_filters", "", "inputs/filter"),
                                    ("estimate_basis", "", "elapsed-time basis"),
                                    ("expected_elapsed_minutes", 31, "25 minutes")]:
            invalid = copy.deepcopy(report)
            invalid["ci_execution"][0][field] = value
            with self.assertRaisesRegex(ValueError, error):
                delivery.validate_report(self.plan, invalid, "preflight")

    def ready_v1(self):
        for unit in self.plan["units"]:
            unit["state"] = "complete"
            if unit["id"] in delivery.CONDITIONAL_UNITS:
                unit["scope_decision"] = {"status": "adopted", "reason": "verified reuse makes this ordinary scope low burden",
                                           "adopted_scope": "specified ordinary scope including interruption/ownership"}
        report = self.report("P2-F", with_device=True)
        report["release"] = {k: "reviewed test fixture" for k in ("candidate_ipa", "normal_regression",
            "generated_host", "metadata", "compatibility", "physical_review")}
        return report

    def test_v1_requires_all_units_and_execution_evidence_not_just_scope_review(self):
        report = self.ready_v1()
        with patch.object(delivery, "validate_docs"):
            delivery.validate_report(self.plan, report, "release", version="1.0.0")
        incomplete = copy.deepcopy(self.plan)
        next(u for u in incomplete["units"] if u["id"] == "P2-8")["state"] = "partial"
        with self.assertRaisesRegex(ValueError, "still partial"):
            delivery.validate_report(incomplete, report, "release", version="1.0.0")
        for cid in ["P2-7.integration", "P2-8.device", "P2-12.integration"]:
            missing = copy.deepcopy(report)
            missing["evidence"] = [e for e in missing["evidence"] if e["criterion"] != cid]
            with self.assertRaisesRegex(ValueError, "missing passed evidence"):
                delivery.validate_report(self.plan, missing, "release", version="1.0.0")

    def test_conditional_exclusion_needs_reason_and_review_and_cannot_exclude_mandatory(self):
        self.ready_v1()
        unit = next(u for u in self.plan["units"] if u["id"] == "P2-12")
        unit["scope_decision"] = {"status": "excluded", "reason": "comparison found substantial additional work beyond camera reuse"}
        report = self.report("P2-F", with_device=True)
        self.assertFalse(any(e["criterion"] == "P2-12.integration" for e in report["evidence"]))
        delivery.validate_report(self.plan, report, "ci")
        report["evidence"] = [e for e in report["evidence"] if e["criterion"] != "P2-12.scope"]
        with self.assertRaisesRegex(ValueError, "missing passed evidence"):
            delivery.validate_report(self.plan, report, "ci")
        unit["scope_decision"]["reason"] = ""
        with self.assertRaisesRegex(ValueError, "reason missing"):
            delivery.validate_plan(self.plan)
        unit["scope_decision"]["reason"] = "reviewed reason"
        mandatory = next(u for u in self.plan["units"] if u["id"] == "P2-8")
        mandatory["criteria"][0]["adopted_only"] = True
        with self.assertRaisesRegex(ValueError, "mandatory functionality"):
            delivery.validate_plan(self.plan)

    def test_pending_conditional_scope_cannot_be_complete_or_enter_final_ci(self):
        unit = next(u for u in self.plan["units"] if u["id"] == "P2-12")
        # Exercise an undecided fixture even after the real plan adopts AR.
        unit["scope_decision"] = {"status": "pending", "reason": "", "adopted_scope": ""}
        unit["state"] = "partial"
        report = self.report("P2-F", with_device=True)
        with self.assertRaisesRegex(ValueError, "scope decision pending"):
            delivery.validate_report(self.plan, report, "ci")
        unit["state"] = "complete"
        with self.assertRaisesRegex(ValueError, "undecided scope"):
            delivery.validate_plan(self.plan)

    def test_signed_service_verification_can_be_approved_unverified_without_waiving_unit(self):
        decisions = {
            "P2-8": ("CloudKit live communication using a paid signing and service environment",
                     "Free-signing normal use does not provide the required CloudKit environment"),
            "P2-10": ("APNs registration and live delivery using provider credentials",
                      "Free-signing normal use does not provide the required APNs environment"),
        }
        for uid, (scope, reason) in decisions.items():
            unit = next(u for u in self.plan["units"] if u["id"] == uid)
            unit["criteria"] = [c for c in unit["criteria"] if c["id"] != f"{uid}.signed-service"]
            unit["criteria"].append({
                "id": f"{uid}.signed-service",
                "description": scope,
                "kinds": ["device"],
                "conditional_verification": {
                    "status": "approved-unverified", "scope": scope, "reason": reason,
                },
            })
        delivery.validate_plan(self.plan)
        report = self.report("P2-I", with_device=True)
        delivery.validate_report(self.plan, report, "ci")
        self.assertEqual({item["criterion"] for item in report["approved_unverified"]},
                         {"P2-8.signed-service", "P2-10.signed-service"})
        self.assertTrue(any(e["criterion"] == "P2-8.device" for e in report["evidence"]))
        self.assertTrue(any(e["criterion"] == "P2-10.integration" for e in report["evidence"]))
        self.assertFalse(any(e["criterion"].endswith(".signed-service") for e in report["evidence"]))

        missing = copy.deepcopy(report)
        missing["approved_unverified"].pop()
        with self.assertRaisesRegex(ValueError, "does not match plan"):
            delivery.validate_report(self.plan, missing, "ci")
        disguised = copy.deepcopy(report)
        disguised["approved_unverified"][0]["result"] = "passed"
        with self.assertRaisesRegex(ValueError, "must remain unverified"):
            delivery.validate_report(self.plan, disguised, "ci")
        passed = copy.deepcopy(report)
        passed["evidence"].append({"criterion": "P2-8.signed-service", "kind": "device",
            "source": SHA, "result": "passed", "reference": "not actually run",
            "observation": "not actually observed", "review": "not accepted"})
        with self.assertRaisesRegex(ValueError, "unknown evidence criterion"):
            delivery.validate_report(self.plan, passed, "ci")

    def test_conditional_verification_cannot_waive_general_or_nonservice_criteria(self):
        unit = next(u for u in self.plan["units"] if u["id"] == "P2-8")
        unit["criteria"][0]["conditional_verification"] = {
            "status": "approved-unverified", "scope": "all ownership", "reason": "too broad",
        }
        with self.assertRaisesRegex(ValueError, "not permitted"):
            delivery.validate_plan(self.plan)

        del unit["criteria"][0]["conditional_verification"]
        unit["criteria"] = [c for c in unit["criteria"] if c["id"] != "P2-8.signed-service"]
        unit["criteria"].append({"id": "P2-8.signed-service", "description": "CloudKit live service",
            "kinds": ["device"], "conditional_verification": {
                "status": "approved-unverified", "scope": "", "reason": "approved"}})
        with self.assertRaisesRegex(ValueError, "scope/reason missing"):
            delivery.validate_plan(self.plan)

        unit["criteria"][-1]["conditional_verification"] = {"status": "required"}
        delivery.validate_plan(self.plan)
        report = self.report("P2-I", with_device=True)
        report["evidence"] = [e for e in report["evidence"] if e["criterion"] != "P2-8.signed-service"]
        with self.assertRaisesRegex(ValueError, "missing passed evidence: P2-8.signed-service"):
            delivery.validate_report(self.plan, report, "ci")

    def test_p1_release_requires_p0_and_missing_dependency(self):
        self.plan["units"][0]["state"] = "partial"
        report = self.report("P1-B", with_device=True)
        for unit in self.plan["units"]:
            if unit["priority"] == "P1":
                unit["state"] = "complete"
        with self.assertRaisesRegex(ValueError, "still partial"):
            delivery.validate_report(self.plan, report, "release", version="0.8.0")
        report["dependencies"] = {}
        with self.assertRaisesRegex(ValueError, "missing dependency"):
            delivery.validate_report(self.plan, report, "ci")

    def test_cli_does_not_clobber_evidence_or_create_invalid_template(self):
        command = [sys.executable, str(delivery.ROOT / "Tools/check-delivery.py")]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "report.json"
            result = subprocess.run(command + ["--template", "P0-A", "--source", "bad", "--output", str(path)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(path.exists())
            result = subprocess.run(command + ["--template", "P0-A", "--source", SHA, "--output", str(path)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            before = path.read_bytes()
            result = subprocess.run(command + ["--template", "P0-A", "--source", "b" * 40, "--output", str(path)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(path.read_bytes(), before)
            result = subprocess.run(command + ["--report", str(path), "--release", "0.7.0"], capture_output=True)
            self.assertNotEqual(result.returncode, 0)

    def test_release_docs_missing_stale_and_new_current_guide(self):
        report = self.report("P0-C", with_device=True)
        for unit in self.plan["units"]:
            if unit["priority"] == "P0":
                unit["state"] = "complete"
        report["release"] = {k: "reviewed evidence reference" for k in ("candidate_ipa", "normal_regression",
                             "generated_host", "metadata", "compatibility", "physical_review")}
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for path in delivery.current_docs(root, "0.7.0"):
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("current prose", encoding="utf-8")
                report["documents"].append({"path": path, "outcome": "reviewed-unchanged"})
            def git(*args):
                return subprocess.run(["git", "-C", str(root), *args], check=True,
                                      capture_output=True, text=True).stdout.strip()
            git("init")
            git("add", ".")
            git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                "-c", "commit.gpgsign=false", "commit", "-m", "Reviewed documents")
            report["document_review"] = {"source": git("rev-parse", "HEAD"),
                                         "summary": "All current prose read; no changes needed", "unresolved": []}
            delivery.validate_report(self.plan, report, "release", root, "0.7.0")
            for field, value, error in [("source", "", "full reviewed commit"),
                                        ("source", SHA, "commit unavailable"),
                                        ("summary", "", "summary missing"),
                                        ("unresolved", "", "must be a list")]:
                bad = copy.deepcopy(report)
                bad["document_review"][field] = value
                with self.assertRaisesRegex(ValueError, error):
                    delivery.validate_report(self.plan, bad, "release", root, "0.7.0")
            old = copy.deepcopy(report)
            del old["document_review"]
            with self.assertRaisesRegex(ValueError, "full reviewed commit"):
                delivery.validate_report(self.plan, old, "release", root, "0.7.0")
            (root / "README.md").write_text("changed", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "stale document"):
                delivery.validate_report(self.plan, report, "release", root, "0.7.0")
            (root / "README.md").write_text("current prose", encoding="utf-8")
            (root / "docs/guides").mkdir()
            (root / "docs/guides/new.md").write_text("new guide", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "missing document review"):
                delivery.validate_report(self.plan, report, "release", root, "0.7.0")
            report["documents"].append({"path": "docs/guides/new.md", "outcome": "updated"})
            with self.assertRaisesRegex(ValueError, "absent from reviewed commit"):
                delivery.validate_report(self.plan, report, "release", root, "0.7.0")
            git("add", ".")
            git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                "-c", "commit.gpgsign=false", "commit", "-m", "Review added guide")
            report["document_review"]["source"] = git("rev-parse", "HEAD")
            report["document_review"]["summary"] = "Added guide reviewed together with existing documents"
            delivery.validate_report(self.plan, report, "release", root, "0.7.0")


if __name__ == "__main__":
    unittest.main()
