#!/usr/bin/env python3
"""Capture-status contract checker for CLI Host Workflow Suite v2.4.1.

Implements exactly `darwin-script-child-status-propagation-v1` (Host Guide 0.4,
9.13, 11.5).

What this proves, and why the workflow needs it
-----------------------------------------------
v2.4.1 could not finalize an ordinary pass because the contract demanded an
independently observed Code Agent status that the suite has no way to obtain.
The repair accepts the foreground `/usr/bin/script` return value as the wrapped
command's status — but only under a named platform contract, and only after
live direct-child registration. This tool is what establishes that the named
contract actually holds on the target host, rather than assuming it.

It proves four things:

1. `/usr/bin/script` returns its wrapped command's status unchanged for a normal
   exit. Checked at `0`, `7`, `15`, and `42`.
2. A `SIGTERM`-terminated child returns a **bare** `15`, not the shell's `143`.
3. Normal exit `15` and `SIGTERM` therefore produce the identical number, so the
   two are indistinguishable in that value. That ambiguity is the reason
   `termination_detail=ambiguous-exit-or-signal` exists.
4. No value is rewritten to `128+n` anywhere in the path.

Why the child modes live inside this file
-----------------------------------------
`/usr/bin/script` needs a command to wrap. Passing `sh -c 'exit 7'` would
introduce exactly the shell-reparse layer the suite prohibits, so the controlled
children are invoked as `python3 <this file> --child-exit 7`: a structured
literal argv, no reparse, no reconstructed command string.

Run during fresh bootstrap, adoption, and release validation — not on every
ordinary pass.

Exit status: 0 contract satisfied; 1 contract violated or host unsupported,
with an actionable diagnostic; 2 usage error.
"""

import argparse
import json
import os
import platform
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone

CONTRACT_ID = "darwin-script-child-status-propagation-v1"
WORKFLOW_VERSION = "v2.4.1"
SYSTEM_SCRIPT = "/usr/bin/script"

# Normal exits that must survive the capture wrapper unchanged. 15 is included
# deliberately: it is the value that collides with SIGTERM.
NORMAL_EXIT_CASES = (0, 7, 15, 42)
SIGTERM_NUMBER = 15


def utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def child_exit(code):
    """Controlled child: terminate with an ordinary exit status."""
    sys.stdout.write("child-exit %d\n" % code)
    sys.stdout.flush()
    return code


def child_signal(name):
    """Controlled child: terminate by delivering a signal to itself."""
    number = getattr(signal, name, None)
    if number is None:
        sys.stderr.write("unknown signal: %s\n" % name)
        return 2
    sys.stdout.write("child-signal %s\n" % name)
    sys.stdout.flush()
    # Restore the default disposition so the process really dies by signal
    # rather than returning through a handler.
    signal.signal(number, signal.SIG_DFL)
    os.kill(os.getpid(), number)
    time.sleep(5)
    return 0


def platform_supported():
    """Return (supported, reason)."""
    if platform.system() != "Darwin":
        return False, ("host platform is %s; %s holds only on Darwin"
                       % (platform.system(), CONTRACT_ID))
    if not os.path.exists(SYSTEM_SCRIPT):
        return False, "the system %s is not present" % SYSTEM_SCRIPT
    if not os.access(SYSTEM_SCRIPT, os.X_OK):
        return False, "the system %s is not executable" % SYSTEM_SCRIPT
    return True, ""


def run_capture(argv, typescript):
    """Invoke /usr/bin/script in the foreground over a structured literal argv.

    No shell is involved: no `sh -c`, no `zsh -c`, no `eval`, no reconstructed
    command string, and no background operator.
    """
    command = [SYSTEM_SCRIPT, "-q", typescript] + list(argv)
    completed = subprocess.run(command, stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
    return completed.returncode


def build_case(name, description, expected, observed, satisfied, note=""):
    return {
        "case": name,
        "description": description,
        "expected_status": expected,
        "observed_status": observed,
        "result": "passed" if satisfied else "failed",
        "note": note,
    }


def run_contract(interpreter, self_path):
    cases = []
    workspace = tempfile.mkdtemp(prefix="capture-status-contract-")
    try:
        for code in NORMAL_EXIT_CASES:
            typescript = os.path.join(workspace, "normal-%d.typescript" % code)
            observed = run_capture(
                [interpreter, self_path, "--child-exit", str(code)], typescript)
            cases.append(build_case(
                "normal-exit-%d" % code,
                "A child exiting normally with %d is reported unchanged." % code,
                code, observed, observed == code))

        typescript = os.path.join(workspace, "sigterm.typescript")
        observed_signal = run_capture(
            [interpreter, self_path, "--child-signal", "SIGTERM"], typescript)
        cases.append(build_case(
            "sigterm-bare-number",
            "A SIGTERM-terminated child is reported as the bare signal number, "
            "not the shell convention 143.",
            SIGTERM_NUMBER, observed_signal, observed_signal == SIGTERM_NUMBER,
            "128+n conversion is prohibited; 143 here would violate the contract."))

        normal_fifteen = next(
            (case["observed_status"] for case in cases
             if case["case"] == "normal-exit-15"), None)
        ambiguous = (normal_fifteen == observed_signal == SIGTERM_NUMBER)
        cases.append(build_case(
            "exit-signal-ambiguity",
            "Normal exit 15 and SIGTERM termination produce the identical "
            "number, so the two cannot be distinguished from the value alone.",
            SIGTERM_NUMBER, observed_signal, ambiguous,
            "This is why termination_detail records ambiguous-exit-or-signal "
            "rather than naming a termination type."))
    finally:
        _cleanup(workspace)
    return cases


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


def emit(record, output):
    if output:
        atomic_write_json(output, record)
    json.dump(record, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


def main():
    parser = argparse.ArgumentParser(
        add_help=True,
        description="Capture-status contract checker (%s)." % CONTRACT_ID)
    parser.add_argument("--child-exit", type=int, metavar="CODE",
                        help="internal controlled-child mode: exit with CODE")
    parser.add_argument("--child-signal", metavar="SIGNAL",
                        help="internal controlled-child mode: terminate by SIGNAL")
    parser.add_argument("--output", help="path for the machine-readable evidence record")
    parser.add_argument("--pass-id", default=None)
    parser.add_argument("--stem", default=None)
    parser.add_argument("--require-platform", action="store_true",
                        help="treat an unsupported host as a hard failure (default)")
    parser.add_argument("--expect-unsupported", action="store_true",
                        help="assert the host does NOT satisfy the contract; "
                             "for verifying refusal behaviour off Darwin")
    args = parser.parse_args()

    if args.child_exit is not None and args.child_signal:
        print("ERROR[capture-status][usage]: --child-exit and --child-signal "
              "are mutually exclusive", file=sys.stderr)
        return 2
    if args.child_exit is not None:
        return child_exit(args.child_exit)
    if args.child_signal:
        return child_signal(args.child_signal)

    supported, reason = platform_supported()
    base = {
        "workflow_version": WORKFLOW_VERSION,
        "contract_id": CONTRACT_ID,
        "checker_version": "v2.4.1",
        "executed_at": utc_now(),
        "platform": platform.system(),
        "platform_release": platform.release(),
        "machine": platform.machine(),
        "system_script": SYSTEM_SCRIPT,
        "pass_id": args.pass_id,
        "artifact_stem": args.stem,
    }

    if not supported:
        record = dict(base, supported=False, overall="unsupported-platform",
                      reason=reason, cases=[])
        emit(record, args.output)
        if args.expect_unsupported:
            # Deterministic refusal confirmed. Used to verify the guard itself
            # on a non-Darwin host; it does not assert the contract holds.
            print("PASS: host correctly refused the contract (%s)" % reason,
                  file=sys.stderr)
            return 0
        print("ERROR[capture-status][platform]: %s. The workflow must record the "
              "Code Agent status as unavailable rather than adopting the capture "
              "value." % reason, file=sys.stderr)
        return 1

    if args.expect_unsupported:
        record = dict(base, supported=True, overall="unexpectedly-supported",
                      reason="host satisfies the platform preconditions", cases=[])
        emit(record, args.output)
        print("ERROR[capture-status][usage]: --expect-unsupported was requested "
              "but this host satisfies the contract preconditions", file=sys.stderr)
        return 1

    try:
        cases = run_contract(sys.executable, os.path.abspath(__file__))
    except OSError as exc:
        record = dict(base, supported=True, overall="failed",
                      reason="cannot execute %s: %s" % (SYSTEM_SCRIPT, exc), cases=[])
        emit(record, args.output)
        print("ERROR[capture-status][runtime]: cannot execute %s: %s"
              % (SYSTEM_SCRIPT, exc), file=sys.stderr)
        return 1

    failures = [case for case in cases if case["result"] != "passed"]
    record = dict(base, supported=True,
                  overall="passed" if not failures else "failed",
                  reason="", cases=cases,
                  total=len(cases), passed=len(cases) - len(failures),
                  failed=len(failures))
    emit(record, args.output)

    if failures:
        print("ERROR[capture-status][contract]: %d of %d contract cases failed:"
              % (len(failures), len(cases)), file=sys.stderr)
        for case in failures:
            print("  - %s: expected %s, observed %s"
                  % (case["case"], case["expected_status"],
                     case["observed_status"]), file=sys.stderr)
        print("  The host does not satisfy %s. Do not adopt the capture value "
              "as the Code Agent status." % CONTRACT_ID, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
