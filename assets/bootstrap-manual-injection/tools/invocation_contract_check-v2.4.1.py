#!/usr/bin/env python3
"""Pre-delivery invocation-contract check for CLI Host Workflow v2.4.1.

Validates the five runtime records a generated launcher would produce against
the invocation contract, BEFORE the delivery set reaches the Human Operator.

Why this exists
---------------
The 2026-08-02 dwb-grid run produced five consecutive launchers that passed
guide-contract static validation 100% and then failed at `cli-agent-runner.zsh
validate` every time, because the guide described the runtime records in prose
while the runner enforced exact key names, value types, and approval booleans.
Recovery required reading the runner's source from the terminal, four times.

Why it executes the runner instead of reimplementing it
-------------------------------------------------------
A hand-maintained copy of the contract drifts. The suite already demonstrates
this: `runner_invocation_validator_v2.4.1.py` requires seven keys the shipped
`cli-agent-runner.zsh` does not, so using it as a delivery gate would reject
launchers the runtime accepts. This tool instead extracts the runner's own
embedded validation block and runs it, so the gate and the runtime cannot
disagree by construction.

Usage
-----
    invocation_contract_check-v2.4.1.py \\
        --runner   <path to cli-agent-runner.zsh> \\
        --runtime  <dir holding the five runtime records> \\
        --pass-id P01.1 --stem 26-08-02_P01.1_fix-metadata-finalization \\
        --family Codex --model gpt-5.5 --effort medium \\
        --project-root <abs path> [--report-root <abs path>] \\
        [--workflow-version v2.4.1]

Exit status: 0 contract satisfied; 1 violation (reason on stderr);
2 usage or extraction error.
"""

import argparse
import json
import os
import re
import sys
import types

RECORDS = {
    "manifest": "invocation-manifest.json",
    "arguments": "invocation-arguments.json",
    "authorization": "human-authorization.json",
    "selection": "selection-evidence.json",
    "contract": "invocation-contract.json",
}

# The runner passes these 18 positional arguments to its validation block, in
# this order. Mirrored from the `cli-agent-runner.zsh validate` invocation.
_ARG_ORDER = (
    "manifest_path", "arguments_path", "authorization_path", "selection_path",
    "contract_path", "workflow_version", "project_root", "report_root",
    "pass_id", "artifact_stem", "family", "model", "effort", "prompt_path",
    "launcher_path", "raw_log_path", "clean_log_path", "meta_log_path",
)


def extract_validation_block(runner_path):
    """Return the Python source of the runner's invocation-validation heredoc."""
    try:
        text = open(runner_path, encoding="utf-8").read()
    except OSError as exc:
        raise SystemExit(f"cannot read runner: {exc}")

    # The validate operation is the heredoc whose body defines the manifest
    # `required={...}` set; later heredocs handle collector completion.
    #
    # The heredoc opener sits on a multi-line shell command, so the body does
    # not begin on the line after `<<'PY'`: continuation lines ending in a
    # backslash belong to the shell, not to Python. Consume them first.
    lines = text.splitlines()
    candidates = []

    for index, line in enumerate(lines):
        if "<<'PY'" not in line:
            continue

        cursor = index
        while cursor < len(lines) and lines[cursor].rstrip().endswith("\\"):
            cursor += 1
        body_start = cursor + 1

        try:
            body_end = lines.index("PY", body_start)
        except ValueError:
            continue

        body = "\n".join(lines[body_start:body_end])
        if "missing manifest fields" in body:
            candidates.append(body)

    if len(candidates) != 1:
        raise SystemExit(
            f"expected exactly one invocation-validation block in {runner_path}; "
            f"found {len(candidates)}. The runner's structure changed — update this tool."
        )

    try:
        compile(candidates[0], "<extracted>", "exec")
    except SyntaxError as exc:
        raise SystemExit(
            f"extracted validation block does not compile ({exc.msg} at line "
            f"{exc.lineno}); the runner's heredoc structure changed — update this tool."
        )
    return candidates[0]


def run_contract(block_src, argv):
    """Execute the runner's validation block. Return None on success, else the reason."""
    module = types.ModuleType("_host_invocation_contract")
    module.__dict__["__name__"] = "_host_invocation_contract"

    saved = sys.argv
    sys.argv = ["<contract>"] + list(argv)
    try:
        exec(compile(block_src, "<cli-agent-runner.zsh:validate>", "exec"), module.__dict__)
    except SystemExit as exc:
        code = exc.code
        return None if code in (0, None) else str(code)
    except KeyError as exc:
        return f"missing manifest field: {exc}"
    except Exception as exc:
        return f"{type(exc).__name__}: {exc}"
    finally:
        sys.argv = saved
    return None


# The only accepted contract identifiers. A manifest naming anything else is a
# launcher defect, not a newer variant to be tolerated (Host Guide 0.4, 8.4,
# 8.12, 8.14, 9.10 item 27-29).
CONTRACT_IDS = {
    "capture_status_contract_id": "darwin-script-child-status-propagation-v1",
    "provider_telemetry_contract": "provider-telemetry-v1",
    "metadata_format_contract": "full-provisional-v1",
    "evidence_index_contract": "metadata-evidence-index-v1",
    "lifecycle_mode": "ordinary",
}

# Installed tool paths, relative to the project root, addressed through the
# stable root `tools/` adapter.
CONTRACT_TOOL_PATHS = {
    "provider_telemetry_tool_path": "tools/provider_telemetry_extract-v2.4.1.py",
    "provider_telemetry_fixtures_path": "tools/provider_telemetry_fixtures-v2.4.1.json",
    "metadata_contract_fixtures_path": "tools/metadata_contract_fixtures-v2.4.1.json",
    "capture_status_contract_check_path": "tools/capture_status_contract_check-v2.4.1.py",
}

SEED_PASS_TYPES = {"bootstrap", "adoption"}


def check_declared_contracts(manifest, root, report_root, stem, pass_type):
    """Return a list of contract violations. Empty means satisfied.

    Every check is a declaration check performed against the manifest and the
    canonical path layout. No tool is executed here.
    """
    violations = []

    for field, expected in CONTRACT_IDS.items():
        if field not in manifest:
            violations.append(f"manifest does not declare {field}")
            continue
        observed = manifest[field]
        if field == "lifecycle_mode":
            permitted = {"ordinary"} | ({"seed"} if pass_type in SEED_PASS_TYPES else set())
            if observed not in permitted:
                violations.append(
                    f"lifecycle_mode {observed!r} is not permitted for pass type "
                    f"{pass_type!r}; permitted: {sorted(permitted)}"
                )
            continue
        if observed != expected:
            violations.append(
                f"{field} is {observed!r}; the only accepted value is {expected!r}"
            )

    for field, relative in CONTRACT_TOOL_PATHS.items():
        if field not in manifest:
            violations.append(f"manifest does not declare {field}")
            continue
        observed = manifest[field]
        if not isinstance(observed, str) or not observed:
            violations.append(f"{field} must be a nonempty string")
            continue
        expected_absolute = os.path.join(root, relative)
        if os.path.isabs(observed):
            if os.path.normpath(observed) != os.path.normpath(expected_absolute):
                violations.append(
                    f"{field} is {observed!r}; expected {expected_absolute!r}"
                )
        elif os.path.normpath(observed) != os.path.normpath(relative):
            violations.append(f"{field} is {observed!r}; expected {relative!r}")
        if ".." in str(observed).split("/"):
            violations.append(f"{field} escapes the project root: {observed!r}")

    # Seed mode is authorized only for bootstrap and adoption, and only with a
    # canonical, pass-scoped manifest path.
    seed_path = manifest.get("runtime_seed_manifest_path")
    seed_declared = manifest.get("lifecycle_mode") == "seed"
    if seed_path or seed_declared:
        if pass_type not in SEED_PASS_TYPES:
            violations.append(
                f"runtime seed evidence is declared for pass type {pass_type!r}; "
                "seed mode is authorized only for bootstrap and adoption"
            )
        if seed_declared and not seed_path:
            violations.append("lifecycle_mode is seed but runtime_seed_manifest_path is absent")
        if seed_path and not seed_declared:
            violations.append("runtime_seed_manifest_path is declared but lifecycle_mode is not seed")
        if seed_path:
            expected_seed = os.path.join(
                report_root, "tmp", stem, "runtime", "runtime-seed-manifest.json")
            observed_seed = seed_path if os.path.isabs(seed_path) \
                else os.path.join(root, seed_path)
            if os.path.normpath(observed_seed) != os.path.normpath(expected_seed):
                violations.append(
                    f"runtime_seed_manifest_path is {seed_path!r}; expected {expected_seed!r}"
                )
    elif pass_type in SEED_PASS_TYPES:
        violations.append(
            f"pass type {pass_type!r} declares no runtime seed; a seeded engine is "
            "required before the ordinary lifecycle can run"
        )

    # The normalized telemetry result and the evidence index are pass-scoped
    # runtime records; a launcher that redirects either outside the pass tmp
    # root breaks the evidence contract.
    for field, filename in (
        ("normalized_telemetry_path", "provider-telemetry.json"),
        ("metadata_evidence_index_path", "metadata-evidence-index.json"),
    ):
        if field not in manifest:
            violations.append(f"manifest does not declare {field}")
            continue
        observed = manifest[field]
        expected_absolute = os.path.join(report_root, "tmp", stem, "runtime", filename)
        candidate = observed if os.path.isabs(observed) else os.path.join(root, observed)
        if os.path.normpath(candidate) != os.path.normpath(expected_absolute):
            violations.append(f"{field} is {observed!r}; expected {expected_absolute!r}")

    # A manifest that mixes contract versions is rejected outright rather than
    # partially honoured.
    declared_versions = {
        value for key, value in manifest.items()
        if isinstance(value, str) and re.fullmatch(r"v\d+\.\d+\.\d+", value)
    }
    if declared_versions - {"v2.4.1"}:
        violations.append(
            "manifest mixes workflow contract versions: "
            + ", ".join(sorted(declared_versions))
        )

    return violations


def main():
    p = argparse.ArgumentParser(add_help=True)
    p.add_argument("--runner", required=True)
    p.add_argument("--runtime", required=True,
                   help="directory containing the five runtime records")
    p.add_argument("--pass-id", required=True)
    p.add_argument("--stem", required=True)
    p.add_argument("--family", required=True)
    p.add_argument("--model", required=True)
    p.add_argument("--effort", default="")
    p.add_argument("--project-root", required=True)
    p.add_argument("--report-root", default=None)
    p.add_argument("--workflow-version", default="v2.4.1")
    p.add_argument("--pass-type", default="implementation",
                   choices=["implementation", "bootstrap", "adoption",
                            "maintenance", "skill_bootstrap"],
                   help="governs whether seed mode is authorized")
    args = p.parse_args()

    root = os.path.abspath(args.project_root)
    report_root = os.path.abspath(args.report_root) if args.report_root \
        else os.path.join(root, "build-report-logs")
    runtime = os.path.abspath(args.runtime)

    paths = {k: os.path.join(runtime, v) for k, v in RECORDS.items()}
    missing = [v for k, v in paths.items() if not os.path.isfile(v)]
    if missing:
        print("FAIL: runtime records not found:", file=sys.stderr)
        for m in missing:
            print(f"  {m}", file=sys.stderr)
        return 1

    records = {}
    for label, path in paths.items():
        try:
            records[label] = json.load(open(path, encoding="utf-8"))
        except (OSError, ValueError) as exc:
            print(f"FAIL: {label} record is not readable JSON: {exc}", file=sys.stderr)
            return 1

    stem = args.stem

    # Declared-contract checks run before the runner's own block, and their
    # results are aggregated so a launcher author sees every violation at once
    # rather than one per delivery attempt.
    manifest = records["manifest"]
    if not isinstance(manifest, dict):
        print("FAIL: invocation manifest root must be an object", file=sys.stderr)
        return 1
    contract_violations = check_declared_contracts(
        manifest, root, report_root, stem, args.pass_type)
    if contract_violations:
        print("FAIL: declared-contract validation rejected this delivery set.",
              file=sys.stderr)
        for violation in contract_violations:
            print(f"  - {violation}", file=sys.stderr)
        print("  Correct the launcher before delivery; do not deliver and patch "
              "from the terminal.", file=sys.stderr)
        return 1
    argv = [
        paths["manifest"], paths["arguments"], paths["authorization"],
        paths["selection"], paths["contract"],
        args.workflow_version, root, report_root,
        args.pass_id, stem, args.family, args.model, args.effort,
        os.path.join(report_root, "prompts", f"{stem}-prompt.txt"),
        os.path.join(report_root, "launchers", f"{stem}-launcher.zsh"),
        os.path.join(report_root, "logs", "raw-logs", f"{stem}-raw.log"),
        os.path.join(report_root, "logs", "clean-logs", f"{stem}-clean.log"),
        os.path.join(report_root, "logs", "meta-logs", f"{stem}-meta.log"),
    ]
    assert len(argv) == len(_ARG_ORDER), "positional argument list is malformed"

    block = extract_validation_block(args.runner)
    reason = run_contract(block, argv)

    if reason:
        print("FAIL: asset-contract validation rejected this delivery set.", file=sys.stderr)
        print(f"  reason: {reason}", file=sys.stderr)
        print("  Correct the launcher before delivery; do not deliver and patch "
              "from the terminal.", file=sys.stderr)
        return 1

    print("PASS: asset-contract validation satisfied "
          f"({args.family} {args.model} {args.effort or 'no-effort'}, {args.pass_id}).")
    print("      Validated by executing cli-agent-runner.zsh's own validation block.")
    print(f"      Declared contracts satisfied: status={CONTRACT_IDS['capture_status_contract_id']}, "
          f"parser={CONTRACT_IDS['provider_telemetry_contract']}, "
          f"metadata={CONTRACT_IDS['metadata_format_contract']}, "
          f"evidence-index={CONTRACT_IDS['evidence_index_contract']}, "
          f"lifecycle_mode={manifest.get('lifecycle_mode')}.")
    print("      No tool was executed by this gate; parser, fixture catalogs, and "
          "status checker remain unrun here.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
