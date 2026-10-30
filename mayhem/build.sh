#!/usr/bin/env bash
#
# mayhem/build.sh — build MAVSDK's fuzz harness (sanitized, DWARF 3) and its unit-test suite (normal flags).
# Runs in the commit image as `mayhem` in /mayhem. Dependencies come from /opt/toolchains/mavsdk-deps
# (populated once by mayhem/deps.sh), so a re-run needs no network.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${MAVSDK_DEPS:=/opt/toolchains/mavsdk-deps}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS MAVSDK_DEPS

cd "$SRC"

# 0) Third-party dependencies (no-op once /opt/toolchains/mavsdk-deps/{san,plain}/.complete exist).
bash mayhem/deps.sh

# Compilers come from $CC/$CXX (resolved by name on PATH): passing -DCMAKE_C_COMPILER=clang makes a re-run
# see a "changed" compiler (the cache holds /usr/bin/clang), wipe the cache and drop every other -D option.

# 1) The project itself, sanitized + SanCov-instrumented, as a static library installed into build-fuzz/install.
# -fno-sanitize=alignment only when UBSan is on: MAVSDK binds references to members of the packed
# mavlink_message_t (e.g. connection.cpp Connection::receive_message), which trips the alignment check on
# every message while being harmless on the targets we run. Every other ASan/UBSan check stays halting.
case "$SANITIZER_FLAGS" in *undefined*) RELAX="-fno-sanitize=alignment" ;; *) RELAX="" ;; esac
FUZZ_FLAGS="-O1 $SANITIZER_FLAGS $RELAX -fsanitize=fuzzer-no-link $DEBUG_FLAGS"
cmake -S cpp -B build-fuzz -G Ninja \
  -DCMAKE_C_FLAGS="$FUZZ_FLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS" -DCMAKE_SHARED_LINKER_FLAGS="$SANITIZER_FLAGS" \
  -DCMAKE_INSTALL_PREFIX="$SRC/build-fuzz/install" \
  -DCMAKE_PREFIX_PATH="$MAVSDK_DEPS/san" \
  -DSUPERBUILD=OFF -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DBUILD_WITHOUT_CURL=ON \
  -DMAVLINK_DIALECT=ardupilotmega
cmake --build build-fuzz -j"$MAYHEM_JOBS"
cmake --install build-fuzz

# 2) The harness: a libFuzzer binary and a run-once standalone reproducer, both with leak detection off.
FUZZER_NO_MAIN_LIB="$($CC -print-file-name=libclang_rt.fuzzer_no_main-"$(uname -m)".a)"
cmake -S mayhem/harness -B build-harness -G Ninja \
  -DCMAKE_C_FLAGS="$FUZZ_FLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS" \
  -DCMAKE_PREFIX_PATH="$SRC/build-fuzz/install;$MAVSDK_DEPS/san" \
  -DMAVSDK_SRC="$SRC" -DLSAN_OFF_SRC="$SRC/mayhem/lsan_off.cc" -DSTANDALONE_FUZZ_MAIN="$STANDALONE_FUZZ_MAIN" \
  -DFUZZER_NO_MAIN_LIB="$FUZZER_NO_MAIN_LIB" -DLIB_FUZZING_ENGINE="$LIB_FUZZING_ENGINE"
cmake --build build-harness -j"$MAYHEM_JOBS"
cp build-harness/mavlink_fuzzer /mayhem/mavlink_fuzzer
cp build-harness/mavlink_fuzzer-standalone /mayhem/mavlink_fuzzer-standalone

# 3) The unit-test suite with the project's NORMAL flags (no sanitizers, no DWARF override).
cmake -S cpp -B build-tests -G Ninja \
  -DCMAKE_C_FLAGS="-O1 $COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="-O1 $COVERAGE_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$COVERAGE_FLAGS" \
  -DCMAKE_PREFIX_PATH="$MAVSDK_DEPS/plain" \
  -DSUPERBUILD=OFF -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=ON -DBUILD_WITHOUT_CURL=ON \
  -DMAVLINK_DIALECT=ardupilotmega
cmake --build build-tests -j"$MAYHEM_JOBS" --target unit_tests_runner
