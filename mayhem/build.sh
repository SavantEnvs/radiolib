#!/usr/bin/env bash
#
# mayhem/build.sh — build RadioLib's fuzz harnesses (sanitized) and its unit-test suite (normal flags).
# Runs as `mayhem` in /mayhem; re-runnable and offline (no fetches; deps are apt -dev packages).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
FUZZ_DIR="$SRC/extras/test/fuzz"

# 1) The library, sanitized + DWARF 3, built twice: build/fuzz carries libFuzzer coverage
#    instrumentation (fuzzer-no-link) so the fuzzer sees edges inside RadioLib itself, not just the
#    harness; build/standalone is the same without coverage, for the run-once reproducers (no libFuzzer
#    runtime to resolve the coverage callbacks). RADIOLIB_GODMODE exposes the private members the upstream
#    harnesses poke at (same as extras/test/fuzz/CMakeLists.txt).
for variant in fuzz standalone; do
  cov=""; [ "$variant" = fuzz ] && cov="-fsanitize=fuzzer-no-link"
  cmake -S . -B "build/$variant" -G Ninja \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_BUILD_TYPE= \
    -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $cov" \
    -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $cov -O2 -DRADIOLIB_GODMODE=1"
  cmake --build "build/$variant" -j"$MAYHEM_JOBS"
done

# 2) Harnesses: each target is a thin LLVMFuzzerTestOneInput over upstream's own Fuzz* functions
#    (extras/test/fuzz/tests), linked once with libFuzzer and once with the run-once driver.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o build/standalone_main.o
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o build/lsan_off.o

for h in fuzz_lorawan_downlink fuzz_lorawan_persist fuzz_pager; do
  common=(-std=c++20 -O2 -DRADIOLIB_GODMODE=1 -I"$SRC/src" -I"$FUZZ_DIR/include"
          "$SRC/mayhem/harnesses/$h.cpp" "$FUZZ_DIR/tests/FuzzLoRaWAN.cpp" "$FUZZ_DIR/tests/FuzzPager.cpp"
          build/lsan_off.o)
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "${common[@]}" build/fuzz/libRadioLib.a -o "/mayhem/$h"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS build/standalone_main.o "${common[@]}" build/standalone/libRadioLib.a -o "/mayhem/$h-standalone"
done

# 3) Unit-test suite (upstream extras/test/unit, boost.test) with NORMAL flags, no sanitizers.
#    Built from the same sources as upstream's CMake, minus its gcov instrumentation, and without its
#    `add_subdirectory(../../../../RadioLib)` (that path only exists in a checkout named RadioLib).
cmake -S . -B build/unit-lib -G Ninja \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_BUILD_TYPE= \
  -DCMAKE_CXX_FLAGS="-O0 -DRADIOLIB_GODMODE=1 $COVERAGE_FLAGS"
cmake --build build/unit-lib -j"$MAYHEM_JOBS"

UNIT_DIR="$SRC/extras/test/unit"
mkdir -p build/unit-obj
unit_srcs=(main ModuleFixture TestModule TestCalculateTimeOnAir TestPhyComplete TestCrypto TestReedSolomon)
printf '%s\n' "${unit_srcs[@]}" | xargs -P "$MAYHEM_JOBS" -I{} \
  $CXX -std=c++20 -O0 -DRADIOLIB_GODMODE=1 $COVERAGE_FLAGS -I"$SRC/src" -I"$UNIT_DIR/include" \
    -c "$UNIT_DIR/tests/{}.cpp" -o "build/unit-obj/{}.o"
$CXX $COVERAGE_FLAGS build/unit-obj/*.o build/unit-lib/libRadioLib.a -lfmt -o build/radiolib-unittest
