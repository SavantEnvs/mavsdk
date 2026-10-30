#!/usr/bin/env bash
#
# mayhem/deps.sh — fetch and build MAVSDK's third-party dependencies ONCE into fixed, $HOME-independent
# prefixes under /opt/toolchains/mavsdk-deps, using upstream's own superbuild (cpp/third_party).
# The first (online) build populates the prefixes; every later build.sh run resolves from them with
# SUPERBUILD=OFF, so the air-gapped PATCH re-run never needs the network.
#   san/   deps compiled with $SANITIZER_FLAGS $DEBUG_FLAGS (libmav, tinyxml2, libevents, ...) and SanCov for the fuzz build
#   plain/ deps compiled with the project's normal flags, plus googletest, for the unit-test build
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${SRC:=/mayhem}"
: "${MAVSDK_DEPS:=/opt/toolchains/mavsdk-deps}"

build_deps() {
  local name="$1" flags="$2" testing="$3"
  local prefix="$MAVSDK_DEPS/$name"
  [ -f "$prefix/.complete" ] && return 0
  rm -rf "$MAVSDK_DEPS/build-$name" "$prefix"
  mkdir -p "$MAVSDK_DEPS"
  CC="$CC" CXX="$CXX" CFLAGS="$flags" CXXFLAGS="$flags" \
    cmake -S "$SRC/cpp/third_party" -B "$MAVSDK_DEPS/build-$name" \
      -DSUPERBUILD=ON -DBUILD_TESTING="$testing" -DBUILD_WITHOUT_CURL=ON -DBUILD_MAVSDK_SERVER=OFF \
      -DMAVLINK_DIALECT=ardupilotmega \
      -DDEPS_BUILD_PATH="$MAVSDK_DEPS/build-$name" -DDEPS_INSTALL_PATH="$prefix"
  touch "$prefix/.complete"
}

case "$SANITIZER_FLAGS" in *undefined*) RELAX="-fno-sanitize=alignment" ;; *) RELAX="" ;; esac
build_deps san "-O1 $SANITIZER_FLAGS $RELAX -fsanitize=fuzzer-no-link $DEBUG_FLAGS" OFF
build_deps plain "-O1" ON
