#!/usr/bin/env bash
# Run one NPU validation example in simulator mode inside the CANN Docker image.
# Full flow: optionally .pto -> ptoas -> .cpp -> generate_testcase -> build -> run sim.
#
# Usage (from repo root, after building image):
#   docker run --rm -v "$(pwd)":/workspace -w /workspace ptoas:py3.11 bash docker/run_sim_example.sh
#
# Optional first argument:
#   - .pto path: run ptoas to produce .cpp (with macro guard), then run testcase + sim.
#   - .cpp path: use that kernel and run testcase + sim (default: /sources/test/Abs/abs.cpp).
#
# Examples:
#   docker run --rm -v "$(pwd)":/workspace -w /workspace ptoas:py3.11 bash docker/run_sim_example.sh
#   docker run ... bash docker/run_sim_example.sh /workspace/test/samples/Abs/abs.pto
#   docker run ... bash docker/run_sim_example.sh /sources/test/Abs/abs.cpp
#
# Requires the repo mounted at /workspace (for generate_testcase.py and templates).
# Uses in-image pto-isa at /sources/pto-isa.

set -euo pipefail

INPUT="${1:-/sources/test/Abs/abs.cpp}"
GENERATE="${WORKSPACE:-/workspace}/test/npu_validation/scripts/generate_testcase.py"

if [[ ! -f "${GENERATE}" ]]; then
  echo "ERROR: generate_testcase.py not found at ${GENERATE}. Mount repo: -v \$PWD:/workspace" >&2
  exit 1
fi

# If input is .pto, assemble to .cpp then use that.
if [[ "${INPUT}" == *.pto ]]; then
  if [[ ! -f "${INPUT}" ]]; then
    echo "ERROR: .pto not found: ${INPUT}" >&2
    exit 1
  fi
  INPUT_CPP="${INPUT%.pto}.cpp"
  echo "[run_sim_example] Assembling .pto -> .cpp: ${INPUT} -> ${INPUT_CPP}"
  ptoas --enable-insert-sync "${INPUT}" -o "${INPUT_CPP}"
  # Macro guard so kernel compiles for the CCE arch used by generate_testcase (220 / 2201).
  (echo '#if defined(__CCE_AICORE__)'; cat "${INPUT_CPP}"; echo '#endif') > "${INPUT_CPP}.tmp" && mv "${INPUT_CPP}.tmp" "${INPUT_CPP}"
else
  INPUT_CPP="${INPUT}"
fi

if [[ ! -f "${INPUT_CPP}" ]]; then
  echo "ERROR: kernel not found: ${INPUT_CPP}" >&2
  exit 1
fi

echo "[run_sim_example] Using kernel: ${INPUT_CPP}"
echo "[run_sim_example] Generating NPU validation testcase (sim mode)..."
python3 "${GENERATE}" \
  --input "${INPUT_CPP}" \
  --run-mode sim \
  --soc-version Ascend910B1

INPUT_DIR="$(dirname "${INPUT_CPP}")"
TESTCASE="$(basename "${INPUT_CPP}" .cpp)"
NV_DIR="${INPUT_DIR}/npu_validation/${TESTCASE}"
if [[ ! -d "${NV_DIR}" ]]; then
  echo "ERROR: npu_validation dir not found at ${NV_DIR}" >&2
  exit 1
fi

echo "[run_sim_example] Building and running simulator (GOLDEN_MODE=sim)..."
cd "${NV_DIR}"
export PTO_ISA_ROOT="${PTO_ISA_ROOT:-/sources/pto-isa}"
GOLDEN_MODE=sim ./run.sh
echo "[run_sim_example] Done."

