#!/usr/bin/env bash
#
# mayhem/test.sh — RUN MAVSDK's OWN gtest unit suite (already built by mayhem/build.sh into build-tests/).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

RUNNER="$SRC/build-tests/src/unit_tests/unit_tests_runner"
[ -x "$RUNNER" ] || { echo "missing $RUNNER — mayhem/build.sh should have built it" >&2; exit 1; }

# Several tests read sample files relative to cpp/ (e.g. src/mavsdk/plugins/*/*.json).
cd "$SRC/cpp"
OUT="$(mktemp)"
"$RUNNER" 2>&1 | tee "$OUT"

# gtest summary: "[==========] N tests from M test suites ran.", "[  PASSED  ] P tests.",
# "[  FAILED  ] F tests, listed below:", "[  SKIPPED ] S tests, listed below:".
RAN="$(sed -n 's/^\[==========\] \([0-9]\+\) tests\? from .* ran\..*/\1/p' "$OUT" | tail -1)"
PASSED="$(sed -n 's/^\[  PASSED  \] \([0-9]\+\) tests\?\..*/\1/p' "$OUT" | tail -1)"
FAILED="$(sed -n 's/^\[  FAILED  \] \([0-9]\+\) tests\?, listed below.*/\1/p' "$OUT" | tail -1)"
SKIPPED="$(sed -n 's/^\[  SKIPPED \] \([0-9]\+\) tests\?, listed below.*/\1/p' "$OUT" | tail -1)"
rm -f "$OUT"
: "${PASSED:=0}" "${FAILED:=0}" "${SKIPPED:=0}"

# A runner that produced no gtest summary (crashed, or neutered to `exit 0`) is a failure, not a pass.
if [ -z "$RAN" ] || [ "$RAN" -lt 400 ]; then
  echo "unit_tests_runner printed no/short gtest summary (ran='${RAN:-}'); expected >= 400 tests" >&2
  emit_ctrf "gtest" "$PASSED" $(( FAILED > 0 ? FAILED : 1 )) "$SKIPPED"
  exit 1
fi
emit_ctrf "gtest" "$PASSED" "$FAILED" "$SKIPPED"
