#!/usr/bin/env python3
import argparse
import subprocess
import sys
from pathlib import Path
from datetime import datetime


def read_tests(test_file: Path) -> list[str]:
    tests = []
    for line in test_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        tests.append(line)
    return tests


def safe_name(name: str) -> str:
    return "".join(c if c.isalnum() or c in "._-" else "_" for c in name)


def run_one_test(
    python_bin: str,
    gdbserver_py: Path,
    target_cfg: Path,
    test_name: str,
    log_dir: Path,
) -> int:
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / f"{safe_name(test_name)}.log"

    cmd = [
        python_bin,
        str(gdbserver_py),
        str(target_cfg),
        test_name,
    ]

    header = (
        f"\n{'=' * 80}\n"
        f"TEST: {test_name}\n"
        f"TIME: {datetime.now().isoformat(timespec='seconds')}\n"
        f"CMD : {' '.join(cmd)}\n"
        f"{'=' * 80}\n"
    )

    print(header, end="", flush=True)

    with log_file.open("w", encoding="utf-8") as f:
        f.write(header)
        f.flush()

        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

        assert process.stdout is not None
        for line in process.stdout:
            print(line, end="", flush=True)
            f.write(line)
            f.flush()

        return_code = process.wait()

        footer = (
            f"\n[RESULT] {test_name}: "
            f"{'PASS' if return_code == 0 else 'FAIL'} "
            f"(exit_code={return_code})\n"
        )
        print(footer, end="", flush=True)
        f.write(footer)
        f.flush()

    return return_code


def main() -> int:
    parser = argparse.ArgumentParser(description="Run multiple gdbserver.py tests from a file.")
    parser.add_argument(
        "test_file",
        help="File containing test names, one per line.",
    )
    parser.add_argument(
        "--python",
        default="python3",
        help="Python executable to use. Default: python3",
    )
    parser.add_argument(
        "--gdbserver",
        default="./gdbserver.py",
        help="Path to gdbserver.py. Default: ./gdbserver.py",
    )
    parser.add_argument(
        "--target",
        default="/debug/targets/RISC-V/config_target.py",
        help="Path to config_target.py",
    )
    parser.add_argument(
        "--log-dir",
        default="./test_logs",
        help="Directory to store per-test logs. Default: ./test_logs",
    )
    parser.add_argument(
        "--stop-on-fail",
        action="store_true",
        help="Stop immediately when a test fails.",
    )

    args = parser.parse_args()

    test_file = Path(args.test_file)
    gdbserver_py = Path(args.gdbserver)
    target_cfg = Path(args.target)
    log_dir = Path(args.log_dir)

    if not test_file.exists():
        print(f"[ERROR] Test file not found: {test_file}", file=sys.stderr)
        return 2

    tests = read_tests(test_file)
    if not tests:
        print(f"[ERROR] No test names found in: {test_file}", file=sys.stderr)
        return 2

    results: list[tuple[str, int]] = []

    for test_name in tests:
        rc = run_one_test(
            python_bin=args.python,
            gdbserver_py=gdbserver_py,
            target_cfg=target_cfg,
            test_name=test_name,
            log_dir=log_dir,
        )
        results.append((test_name, rc))

        if rc != 0 and args.stop_on_fail:
            break

    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)

    passed = 0
    failed = 0
    for test_name, rc in results:
        status = "PASS" if rc == 0 else "FAIL"
        print(f"{status:4}  {test_name}")
        if rc == 0:
            passed += 1
        else:
            failed += 1

    print("-" * 80)
    print(f"Total : {len(results)}")
    print(f"Pass  : {passed}")
    print(f"Fail  : {failed}")

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())