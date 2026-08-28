#!/usr/bin/env python3
"""Provider telemetry extraction for CLI Host Workflow Suite v2.4.1.

Implements exactly the `provider-telemetry-v1` contract (Host Guide 8.4-8.7).

What this tool is
-----------------
The single component that reads provider terminal text. `cli-post-pass.zsh`
invokes it once per pass, after collector clean-log readiness and before
metadata validation. It is a tool, not a Host script: it never invokes a Code
Agent, never reconstructs a shell command, and never reads anything outside the
declared pass's own evidence.

Why a dedicated tool rather than the restored v2.4.0 shell fragment
-------------------------------------------------------------------
The v2.4.0 rule searched the clean log for two alternatives, fell back to
`strings` over the raw recording, and took the last match. It worked for Codex,
worked mechanically for Claude, and was **wrong for Antigravity**: it stored a
per-thought `Thought for 1s, 1.1k tokens` display as the session total. Three
retained recordings prove that defect. Restoration is therefore provider-gated
rather than byte-for-byte universal, which needs versioned adapters, per-field
source tracking, and fixtures — not a one-line regex.

Source order
------------
Each field is resolved independently: clean evidence first, then normalized raw
evidence. Fields do not share one source decision. Tokens arriving from the raw
fallback while a resume command arrives from the clean log is a normal, correct
result, and `field_sources` records which source supplied each value.

Failure behaviour
-----------------
Missing or unrecognized provider output is a **successful** parse with null
optional values plus limitation codes; the pass finalizes on that basis. Only a
broken evidence pipeline is fatal: identity mismatch, path escape, unreadable
declared evidence, or two contradictory recognized final summaries.

Exit status: 0 success (including "nothing recognized"); 1 contract or evidence
failure with an actionable diagnostic; 2 usage error.
"""

import argparse
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone

CONTRACT = "provider-telemetry-v1"
WORKFLOW_VERSION = "v2.4.1"

ESC = chr(27)
BEL = chr(7)
CR = chr(13)

# Terminal control sequences. Removed before matching so a redraw does not
# masquerade as distinct output.
CSI_RE = re.compile(ESC + r"\[[0-9;?]*[ -/]*[@-~]")
OSC_RE = re.compile(ESC + r"\][^" + BEL + r"]*(?:" + BEL + r"|" + ESC + r"\\)")
OTHER_ESC_RE = re.compile(ESC + r"[@-Z\\-_]")
CTRL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")

# ---------------------------------------------------------------------------
# Provider patterns. Each is anchored on the exact retained-fixture form; a
# provider format with no reviewed fixture stays disabled.
# ---------------------------------------------------------------------------

# Codex final summary, e.g.
#   Token usage: total=239,904 input=216,752 (+ 4,128,896 cached) output=23,152 (reasoning 2,826)
CODEX_SUMMARY_RE = re.compile(
    r"Token usage:\s*total=(?P<total>[0-9][0-9,]*)"
    r"(?:\s+input=(?P<input>[0-9][0-9,]*))?"
    r"(?:\s*\(\+\s*(?P<cached>[0-9][0-9,]*)\s*cached\))?"
    r"(?:\s+output=(?P<output>[0-9][0-9,]*))?"
    r"(?:\s*\(reasoning\s+(?P<reasoning>[0-9][0-9,]*)\))?"
)
CODEX_RESUME_RE = re.compile(r"\bcodex\s+resume\s+(?P<id>[0-9a-fA-F-]{8,})\b")

# Claude's unlabelled visible counter. This is the v2.4.0 generic rule, kept
# only as the legacy compatibility source. It proves a number was displayed; it
# proves nothing about what that number measures.
GENERIC_TOKENS_RE = re.compile(
    r"(?<![0-9.])(?P<value>[0-9]+(?:\.[0-9]+)?)(?P<k>k?)\s+tokens\b", re.IGNORECASE)
CLAUDE_RESUME_RE = re.compile(r"\bclaude\s+--resume\s+(?P<id>[^\s]+)")

# Antigravity per-thought display. Matched in order to be REJECTED as a total.
ANTIGRAVITY_THOUGHT_RE = re.compile(
    r"Thought\s+for\s+[^,]+,\s*(?P<value>[0-9]+(?:\.[0-9]+)?)(?P<k>k?)\s+tokens\b",
    re.IGNORECASE)
ANTIGRAVITY_CONVERSATION_RE = re.compile(
    r"\bagy\s+--conversation=(?P<id>[0-9a-fA-F-]{8,})\b")

LIMITATION_NO_PROVIDER_OUTPUT = "no-recognized-provider-output"
LIMITATION_NO_TOKEN_EVIDENCE = "no-recognized-token-evidence"
LIMITATION_NO_SESSION_EVIDENCE = "no-recognized-session-evidence"
LIMITATION_LEGACY_SCOPE_UNKNOWN = "legacy-counter-scope-unknown"
LIMITATION_ANTIGRAVITY_PER_THOUGHT = "per-thought-values-not-session-total"
LIMITATION_UNSUPPORTED_PROVIDER = "provider-adapter-not-enabled"
LIMITATION_CLEAN_LOG_ABSENT = "clean-log-absent"
LIMITATION_RAW_LOG_ABSENT = "raw-log-absent"


class ContractError(Exception):
    """A broken evidence pipeline. Fatal; never a silent null."""


def utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def normalize_text(payload):
    """Turn raw terminal bytes into comparable lines without a shell pipeline.

    Carriage-return redraws are resolved by keeping the last segment of each
    physical line, which is what the terminal would have displayed. Escape
    sequences and other control bytes are removed so an identical redraw
    compares equal to its original.
    """
    if isinstance(payload, bytes):
        text = payload.decode("utf-8", errors="replace")
    else:
        text = payload
    text = OSC_RE.sub("", text)
    text = CSI_RE.sub("", text)
    text = OTHER_ESC_RE.sub("", text)
    lines = []
    for physical in text.split("\n"):
        if CR in physical:
            physical = physical.split(CR)[-1]
        physical = CTRL_RE.sub("", physical)
        lines.append(physical.rstrip())
    return lines


def read_evidence(path, limitation, limitations):
    """Read one declared evidence file. Absence is a limitation, not a failure."""
    if not path:
        limitations.append(limitation)
        return []
    if not os.path.isfile(path):
        limitations.append(limitation)
        return []
    try:
        with open(path, "rb") as handle:
            return normalize_text(handle.read())
    except OSError as exc:
        raise ContractError("cannot read declared evidence %s: %s" % (path, exc))


def to_int(raw, is_k=False):
    if raw is None:
        return None
    value = raw.replace(",", "")
    if is_k:
        return int(round(float(value) * 1000))
    if "." in value:
        return int(round(float(value)))
    return int(value)


def scan(lines, pattern):
    """Return de-duplicated matches in order of appearance.

    Repeated TUI redraws produce identical matched text. Identical repeats are
    the expected case and are collapsed; only genuinely different recognized
    finals are a contradiction.
    """
    seen = []
    for line in lines:
        for match in pattern.finditer(line):
            token = match.group(0)
            if token not in [existing[0] for existing in seen]:
                seen.append((token, match))
    return seen


def resolve(field_sources, field, clean_hits, raw_hits):
    """Clean evidence first, normalized raw evidence second, per field."""
    if clean_hits:
        field_sources[field] = "clean-log"
        return clean_hits
    if raw_hits:
        field_sources[field] = "normalized-raw-log"
        return raw_hits
    field_sources[field] = None
    return []


def one_recognized(hits, label):
    """Collapse to a single recognized final, or fail with a named contradiction."""
    if not hits:
        return None
    distinct = {hit[0] for hit in hits}
    if len(distinct) > 1:
        raise ContractError(
            "contradictory recognized final %s summaries: %s"
            % (label, "; ".join(sorted(distinct))))
    return hits[-1][1]


def adapter_codex(clean, raw, field_sources, limitations):
    telemetry = dict.fromkeys(
        ("total_tokens", "input_tokens", "cached_input_tokens",
         "output_tokens", "reasoning_tokens"))
    session = dict.fromkeys(
        ("session_id", "conversation_id", "session_slug", "resume_command"))
    legacy_total = None
    legacy_source = None
    verified_scope = "unknown"

    summary = one_recognized(
        resolve(field_sources, "tokens",
                scan(clean, CODEX_SUMMARY_RE), scan(raw, CODEX_SUMMARY_RE)),
        "Codex token usage")
    if summary is not None:
        # Labelled values are copied exactly. The total is never recomputed:
        # cached input is not added to total, reasoning is not added to output.
        telemetry["total_tokens"] = to_int(summary.group("total"))
        telemetry["input_tokens"] = to_int(summary.group("input"))
        telemetry["cached_input_tokens"] = to_int(summary.group("cached"))
        telemetry["output_tokens"] = to_int(summary.group("output"))
        telemetry["reasoning_tokens"] = to_int(summary.group("reasoning"))
        verified_scope = "cumulative-session"
        # The legacy value here IS the labelled total, so its scope is known.
        # This is the one adapter where legacy and verified agree by evidence
        # rather than by coincidence.
        legacy_scope = "cumulative-session"
        legacy_total = telemetry["total_tokens"]
        legacy_source = "codex-labelled-final-summary"
    else:
        legacy_scope = "unknown"
        limitations.append(LIMITATION_NO_TOKEN_EVIDENCE)

    resume = one_recognized(
        resolve(field_sources, "session",
                scan(clean, CODEX_RESUME_RE), scan(raw, CODEX_RESUME_RE)),
        "Codex resume")
    if resume is not None:
        session["session_id"] = resume.group("id")
        session["resume_command"] = "codex resume " + resume.group("id")
    else:
        limitations.append(LIMITATION_NO_SESSION_EVIDENCE)

    return telemetry, session, legacy_total, legacy_source, legacy_scope, verified_scope


def adapter_claude(clean, raw, field_sources, limitations):
    telemetry = dict.fromkeys(
        ("total_tokens", "input_tokens", "cached_input_tokens",
         "output_tokens", "reasoning_tokens"))
    session = dict.fromkeys(
        ("session_id", "conversation_id", "session_slug", "resume_command"))
    legacy_total = None
    legacy_source = None

    # The retained recordings prove a number was displayed and that the resume
    # command survives cleaning. They do not identify what the counter measures,
    # so verified totals and every component stay null and the scope stays
    # unknown. Promoting this value would invent a meaning the evidence does
    # not support.
    hits = resolve(field_sources, "tokens",
                   scan(clean, GENERIC_TOKENS_RE), scan(raw, GENERIC_TOKENS_RE))
    if hits:
        last = hits[-1][1]
        legacy_total = to_int(last.group("value"), bool(last.group("k")))
        legacy_source = "claude-visible-counter"
        limitations.append(LIMITATION_LEGACY_SCOPE_UNKNOWN)
    else:
        limitations.append(LIMITATION_NO_TOKEN_EVIDENCE)

    resume = one_recognized(
        resolve(field_sources, "session",
                scan(clean, CLAUDE_RESUME_RE), scan(raw, CLAUDE_RESUME_RE)),
        "Claude resume")
    if resume is not None:
        session["session_id"] = resume.group("id")
        session["resume_command"] = "claude --resume " + resume.group("id")
    else:
        limitations.append(LIMITATION_NO_SESSION_EVIDENCE)

    return telemetry, session, legacy_total, legacy_source, "unknown", "unknown"


def adapter_antigravity(clean, raw, field_sources, limitations):
    telemetry = dict.fromkeys(
        ("total_tokens", "input_tokens", "cached_input_tokens",
         "output_tokens", "reasoning_tokens"))
    session = dict.fromkeys(
        ("session_id", "conversation_id", "session_slug", "resume_command"))

    # Explicit negative rule. `Thought for ..., N tokens` labels one thought
    # operation. The v2.4.0 generic fallback stored exactly these values as
    # session totals, and three retained recordings prove that was wrong. The
    # display is matched here only so it can be rejected, and neither the legacy
    # nor the verified total is populated from it. Values are never summed.
    thought_hits = scan(clean, ANTIGRAVITY_THOUGHT_RE) or scan(raw, ANTIGRAVITY_THOUGHT_RE)
    if thought_hits:
        limitations.append(LIMITATION_ANTIGRAVITY_PER_THOUGHT)
    else:
        limitations.append(LIMITATION_NO_TOKEN_EVIDENCE)
    field_sources["tokens"] = None

    conversation = one_recognized(
        resolve(field_sources, "session",
                scan(clean, ANTIGRAVITY_CONVERSATION_RE),
                scan(raw, ANTIGRAVITY_CONVERSATION_RE)),
        "Antigravity conversation")
    if conversation is not None:
        session["conversation_id"] = conversation.group("id")
        session["resume_command"] = "agy --conversation=" + conversation.group("id")
    else:
        limitations.append(LIMITATION_NO_SESSION_EVIDENCE)

    return telemetry, session, None, None, "unknown", "unknown"


ADAPTERS = {
    "codex": adapter_codex,
    "claude": adapter_claude,
    "antigravity": adapter_antigravity,
}


def build_result(pass_id, stem, code_agent, clean_path, raw_path,
                 clean_lines, raw_lines, project_root, prior_limitations):
    limitations = list(prior_limitations)
    field_sources = {}
    family = (code_agent or "").strip().lower()

    adapter = ADAPTERS.get(family)
    if adapter is None:
        # A provider with no reviewed fixture stays disabled rather than
        # guessing at its format.
        limitations.append(LIMITATION_UNSUPPORTED_PROVIDER)
        telemetry = dict.fromkeys(
            ("total_tokens", "input_tokens", "cached_input_tokens",
             "output_tokens", "reasoning_tokens"))
        session = dict.fromkeys(
            ("session_id", "conversation_id", "session_slug", "resume_command"))
        legacy_total = legacy_source = None
        legacy_scope = verified_scope = "unknown"
        field_sources = {"tokens": None, "session": None}
    else:
        (telemetry, session, legacy_total, legacy_source,
         legacy_scope, verified_scope) = adapter(
            clean_lines, raw_lines, field_sources, limitations)

    populated = [v for v in telemetry.values() if v is not None]
    has_session = any(v is not None for v in session.values())
    if legacy_total is None and not populated and not has_session:
        completeness = "unavailable"
        if LIMITATION_NO_PROVIDER_OUTPUT not in limitations:
            limitations.append(LIMITATION_NO_PROVIDER_OUTPUT)
    elif len(populated) == 5 and has_session:
        completeness = "complete"
    else:
        completeness = "partial"

    def as_reference(path):
        """Project-relative where possible; never containing a parent segment."""
        if not path:
            return path
        absolute = os.path.abspath(path)
        try:
            relative = os.path.relpath(absolute, project_root)
        except ValueError:
            return absolute
        if relative.startswith("..") or os.path.isabs(relative):
            return absolute
        return relative

    return {
        "workflow_version": WORKFLOW_VERSION,
        "parser_contract": CONTRACT,
        "parser_version": "v2.4.1",
        "pass_id": pass_id,
        "artifact_stem": stem,
        "code_agent": code_agent,
        "provider_family": family,
        "clean_log_path": as_reference(clean_path),
        "raw_log_path": as_reference(raw_path),
        "captured_at": utc_now(),
        "legacy_total_tokens": legacy_total,
        "legacy_total_source": legacy_source,
        "telemetry": telemetry,
        "session": session,
        "field_sources": field_sources,
        "scopes": {"legacy_total": legacy_scope, "verified_total": verified_scope},
        "completeness": completeness,
        "limitations": sorted(set(limitations)),
    }


def atomic_write_json(path, payload):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    handle_fd, tmp = tempfile.mkstemp(
        prefix="." + os.path.basename(path) + ".tmp-", dir=directory)
    try:
        with os.fdopen(handle_fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise


PASS_ID_RE = re.compile(r"^P[0-9]*[1-9][0-9]*(?:\.[0-9]*[1-9][0-9]*)?$")
STEM_RE = re.compile(
    r"^[0-9]{2}-[0-9]{2}-[0-9]{2}_P[0-9]*[1-9][0-9]*"
    r"(?:\.[0-9]*[1-9][0-9]*)?_[a-z0-9]+(?:-[a-z0-9]+)*$")


def validate_inputs(args):
    if not PASS_ID_RE.match(args.pass_id):
        raise ContractError("invalid pass ID: " + args.pass_id)
    if not STEM_RE.match(args.stem):
        raise ContractError("invalid artifact stem: " + args.stem)
    if ("_" + args.pass_id + "_") not in args.stem:
        raise ContractError(
            "artifact stem %s does not carry pass ID %s" % (args.stem, args.pass_id))
    root = os.path.abspath(args.project_root)
    if not os.path.isdir(root):
        raise ContractError("project root is not a directory: " + root)
    for label, path in (("clean log", args.clean_log), ("raw log", args.raw_log),
                        ("output", args.output)):
        # The literal path is inspected before normalization. os.path.normpath
        # collapses "a/b/../../c" back inside the root, so a post-normalization
        # check would silently accept a traversal the caller actually wrote.
        # cli-post-pass.zsh applies the same literal test to the emitted paths.
        if os.pardir in str(path).replace(os.sep, "/").split("/"):
            raise ContractError("%s path contains a parent segment: %s" % (label, path))
        absolute = os.path.abspath(path)
        if os.path.commonpath([absolute, root]) != root:
            raise ContractError("%s path escapes the project root: %s" % (label, path))
    expected_clean = args.stem + "-clean.log"
    expected_raw = args.stem + "-raw.log"
    if os.path.basename(args.clean_log) != expected_clean:
        raise ContractError(
            "clean log does not belong to this pass: expected %s" % expected_clean)
    if os.path.basename(args.raw_log) != expected_raw:
        raise ContractError(
            "raw log does not belong to this pass: expected %s" % expected_raw)
    return root


def run_extraction(args):
    root = validate_inputs(args)
    limitations = []
    clean_lines = read_evidence(args.clean_log, LIMITATION_CLEAN_LOG_ABSENT, limitations)
    raw_lines = read_evidence(args.raw_log, LIMITATION_RAW_LOG_ABSENT, limitations)
    result = build_result(args.pass_id, args.stem, args.code_agent,
                          args.clean_log, args.raw_log, clean_lines, raw_lines,
                          root, limitations)
    atomic_write_json(args.output, result)
    return result


# ---------------------------------------------------------------------------
# Fixture mode
# ---------------------------------------------------------------------------

def compare(expected, observed, path=""):
    """Return a list of human-readable differences, deepest key first."""
    differences = []
    if isinstance(expected, dict):
        if not isinstance(observed, dict):
            return ["%s: expected object, observed %s" % (path or "<root>", type(observed).__name__)]
        for key in sorted(expected):
            differences.extend(
                compare(expected[key], observed.get(key), (path + "." + key).lstrip(".")))
        return differences
    if isinstance(expected, list):
        if sorted(map(str, expected)) != sorted(map(str, observed or [])):
            differences.append("%s: expected %r, observed %r" % (path, expected, observed))
        return differences
    if expected != observed:
        differences.append("%s: expected %r, observed %r" % (path, expected, observed))
    return differences


def run_fixture_mode(args):
    try:
        with open(args.fixtures, encoding="utf-8") as handle:
            catalog = json.load(handle)
    except (OSError, ValueError) as exc:
        print("FAIL: cannot read fixture catalog: %s" % exc, file=sys.stderr)
        return 1

    if catalog.get("parser_contract") != CONTRACT:
        print("FAIL: fixture catalog declares contract %r; expected %r"
              % (catalog.get("parser_contract"), CONTRACT), file=sys.stderr)
        return 1

    cases = catalog.get("cases") or []
    identifiers = [case.get("id") for case in cases]
    if len(set(identifiers)) != len(identifiers):
        print("FAIL: fixture catalog contains duplicate case identifiers", file=sys.stderr)
        return 1

    passed = []
    failed = []
    workspace = tempfile.mkdtemp(prefix="provider-telemetry-fixtures-")
    try:
        for case in cases:
            outcome, detail = run_single_fixture(case, workspace)
            (passed if outcome else failed).append((case.get("id"), detail))
            print("[%s] %s%s" % ("PASS" if outcome else "FAIL", case.get("id"),
                                 "" if outcome else "  -> " + detail))
    finally:
        _cleanup(workspace)

    summary = {
        "workflow_version": WORKFLOW_VERSION,
        "parser_contract": CONTRACT,
        "catalog_version": catalog.get("catalog_version"),
        "executed_at": utc_now(),
        "total": len(cases),
        "passed": len(passed),
        "failed": len(failed),
        "failures": [{"id": i, "detail": d} for i, d in failed],
        "overall": "passed" if not failed else "failed",
    }
    if args.results:
        atomic_write_json(args.results, summary)
    print()
    print("%d/%d provider fixture cases behaved as required" % (len(passed), len(cases)))
    return 0 if not failed else 1


def _cleanup(directory):
    for base, dirs, files in os.walk(directory, topdown=False):
        for name in files:
            try:
                os.unlink(os.path.join(base, name))
            except OSError:
                pass
        for name in dirs:
            try:
                os.rmdir(os.path.join(base, name))
            except OSError:
                pass
    try:
        os.rmdir(directory)
    except OSError:
        pass


def run_single_fixture(case, workspace):
    """Materialize one fixture into a disposable tree and check the result."""
    stem = case.get("artifact_stem")
    pass_id = case.get("pass_id")
    root = os.path.join(workspace, case["id"])
    logs_clean = os.path.join(root, "build-report-logs", "logs", "clean-logs")
    logs_raw = os.path.join(root, "build-report-logs", "logs", "raw-logs")
    runtime = os.path.join(root, "build-report-logs", "tmp", stem, "runtime")
    for directory in (logs_clean, logs_raw, runtime):
        os.makedirs(directory, exist_ok=True)

    clean_path = os.path.join(logs_clean, stem + "-clean.log")
    raw_path = os.path.join(logs_raw, stem + "-raw.log")
    if case.get("clean_log") is not None:
        _write_lines(clean_path, case["clean_log"])
    if case.get("raw_log") is not None:
        _write_lines(raw_path, case["raw_log"])

    output = os.path.join(runtime, "provider-telemetry.json")
    namespace = argparse.Namespace(
        pass_id=case.get("override_pass_id", pass_id),
        stem=case.get("override_stem", stem),
        code_agent=case.get("code_agent"),
        clean_log=case.get("override_clean_log_path") or clean_path,
        raw_log=case.get("override_raw_log_path") or raw_path,
        output=output,
        project_root=root,
        fixtures=None,
        results=None,
    )
    if namespace.clean_log and not os.path.isabs(namespace.clean_log):
        namespace.clean_log = os.path.join(root, namespace.clean_log)
    if namespace.raw_log and not os.path.isabs(namespace.raw_log):
        namespace.raw_log = os.path.join(root, namespace.raw_log)

    expected_result = case.get("expected_result")
    try:
        observed = run_extraction(namespace)
    except ContractError as exc:
        if expected_result == "contract-failure":
            expected_code = case.get("expected_diagnostic")
            if expected_code and expected_code not in str(exc):
                return False, "expected diagnostic %r, observed %r" % (expected_code, str(exc))
            return True, ""
        return False, "unexpected contract failure: %s" % exc
    except Exception as exc:  # pragma: no cover - defensive
        return False, "unexpected %s: %s" % (type(exc).__name__, exc)

    if expected_result == "contract-failure":
        return False, "expected a contract failure; the parse succeeded"

    differences = compare(case.get("expected_output") or {}, observed)
    if differences:
        return False, "; ".join(differences[:4])
    return True, ""


def _write_lines(path, lines):
    with open(path, "w", encoding="utf-8", newline="") as handle:
        for line in lines:
            handle.write(line)
            handle.write("\n")


def main():
    parser = argparse.ArgumentParser(
        add_help=True,
        description="Provider telemetry extraction (%s)." % CONTRACT)
    parser.add_argument("--pass-id")
    parser.add_argument("--stem")
    parser.add_argument("--code-agent")
    parser.add_argument("--clean-log")
    parser.add_argument("--raw-log")
    parser.add_argument("--output")
    parser.add_argument("--project-root")
    parser.add_argument("--fixtures", help="provider fixture catalog")
    parser.add_argument("--self-test", action="store_true",
                        help="run the fixture catalog and report deterministically")
    parser.add_argument("--results", help="optional path for a machine-readable fixture result record")
    args = parser.parse_args()

    if args.self_test:
        if not args.fixtures:
            print("ERROR: --self-test requires --fixtures", file=sys.stderr)
            return 2
        return run_fixture_mode(args)

    required = ("pass_id", "stem", "code_agent", "clean_log", "raw_log",
                "output", "project_root")
    missing = [name for name in required if not getattr(args, name)]
    if missing:
        print("ERROR: missing required arguments: "
              + ", ".join("--" + name.replace("_", "-") for name in missing),
              file=sys.stderr)
        return 2

    try:
        run_extraction(args)
    except ContractError as exc:
        # Human-facing failures are actionable one-liners, never tracebacks.
        print("ERROR[provider-telemetry][contract]: %s" % exc, file=sys.stderr)
        return 1
    except OSError as exc:
        print("ERROR[provider-telemetry][io]: %s" % exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
