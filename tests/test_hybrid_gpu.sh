#!/usr/bin/env bash
# tests/test_hybrid_gpu.sh — Tests for GPU detection logic in data/gpu_database.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export _NIXOS_INSTALLER=1 LIB_DIR="${SCRIPT_DIR}/lib" DATA_DIR="${SCRIPT_DIR}/data"
export LOG_FILE="/tmp/nixos-test-hybrid-gpu.log"
: > "${LOG_FILE}"

source "${LIB_DIR}/constants.sh"
source "${LIB_DIR}/logging.sh"
source "${DATA_DIR}/gpu_database.sh"

PASS=0 FAIL=0
assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "${expected}" == "${actual}" ]]; then echo "  PASS: ${desc}"; (( PASS++ )) || true
    else echo "  FAIL: ${desc} — expected '${expected}', got '${actual}'"; (( FAIL++ )) || true; fi
}
assert_contains() {
    if [[ "$3" == *"$2"* ]]; then echo "  PASS: $1"; (( PASS++ )) || true
    else echo "  FAIL: $1 — '$2' not found"; (( FAIL++ )) || true; fi
}

echo "=== Test 1: nvidia_generation() ==="

# Kepler: device IDs >= 0x0fc0 and < 0x1340
assert_eq "Kepler (GTX 780)" "kepler" "$(nvidia_generation "0fc0")"
assert_eq "Kepler (GTX 680)" "kepler" "$(nvidia_generation "1180")"

# Pascal: device IDs >= 0x1580 and < 0x1e00
assert_eq "Pascal (GTX 1080)" "pascal" "$(nvidia_generation "1b80")"
assert_eq "Pascal (GTX 1060)" "pascal" "$(nvidia_generation "1c03")"

# Turing: device IDs >= 0x1e00 and < 0x2200
assert_eq "Turing (RTX 2080)" "turing" "$(nvidia_generation "1e04")"
assert_eq "Turing (RTX 2060)" "turing" "$(nvidia_generation "1f08")"

# Ampere: device IDs >= 0x2200 and < 0x2700
assert_eq "Ampere (RTX 3080)" "ampere" "$(nvidia_generation "2206")"
assert_eq "Ampere (RTX 3060)" "ampere" "$(nvidia_generation "2503")"

# Ada: device IDs >= 0x2700 and < 0x2900
assert_eq "Ada (RTX 4090)" "ada" "$(nvidia_generation "2704")"
assert_eq "Ada (RTX 4060)" "ada" "$(nvidia_generation "2882")"

# Blackwell: device IDs >= 0x2900
assert_eq "Blackwell (RTX 5090)" "blackwell" "$(nvidia_generation "2900")"
assert_eq "Blackwell (high ID)" "blackwell" "$(nvidia_generation "2b00")"

echo ""
echo "=== Test 2: get_nvidia_open_recommendation() ==="

# Pre-Turing: no open kernel module support
assert_eq "Kepler -> no" "no" "$(get_nvidia_open_recommendation "0fc0")"
assert_eq "Pascal -> no" "no" "$(get_nvidia_open_recommendation "1b80")"

# Turing: supported
assert_eq "Turing -> supported" "supported" "$(get_nvidia_open_recommendation "1e04")"

# Ampere: supported
assert_eq "Ampere -> supported" "supported" "$(get_nvidia_open_recommendation "2206")"

# Ada: yes (recommended)
assert_eq "Ada -> yes" "yes" "$(get_nvidia_open_recommendation "2704")"

# Blackwell: yes (recommended)
assert_eq "Blackwell -> yes" "yes" "$(get_nvidia_open_recommendation "2900")"

# Empty device ID: no
assert_eq "Empty -> no" "no" "$(get_nvidia_open_recommendation "")"

echo ""
echo "=== Test 3: get_hybrid_gpu_recommendation() ==="

assert_eq "Intel iGPU + NVIDIA dGPU -> nvidia" "nvidia" "$(get_hybrid_gpu_recommendation "intel" "nvidia")"
assert_eq "Intel iGPU + AMD dGPU -> amdgpu" "amdgpu" "$(get_hybrid_gpu_recommendation "intel" "amd")"
assert_eq "AMD iGPU + NVIDIA dGPU -> nvidia" "nvidia" "$(get_hybrid_gpu_recommendation "amd" "nvidia")"
assert_eq "Unknown dGPU -> modesetting" "modesetting" "$(get_hybrid_gpu_recommendation "intel" "unknown")"

echo ""
echo "=== Test 4: get_gpu_recommendation() ==="

assert_eq "nvidia vendor -> nvidia" "nvidia" "$(get_gpu_recommendation "nvidia")"
assert_eq "amd vendor -> amdgpu" "amdgpu" "$(get_gpu_recommendation "amd")"
assert_eq "intel vendor -> modesetting" "modesetting" "$(get_gpu_recommendation "intel")"
assert_eq "unknown vendor -> empty" "" "$(get_gpu_recommendation "unknown")"

echo ""
echo "=== Test 5: CONFIG_VARS includes hybrid GPU vars ==="

config_vars_str="${CONFIG_VARS[*]}"
assert_contains "HYBRID_GPU in CONFIG_VARS" "HYBRID_GPU" "${config_vars_str}"
assert_contains "IGPU_BUS_ID in CONFIG_VARS" "IGPU_BUS_ID" "${config_vars_str}"
assert_contains "DGPU_BUS_ID in CONFIG_VARS" "DGPU_BUS_ID" "${config_vars_str}"
assert_contains "IGPU_VENDOR in CONFIG_VARS" "IGPU_VENDOR" "${config_vars_str}"
assert_contains "DGPU_VENDOR in CONFIG_VARS" "DGPU_VENDOR" "${config_vars_str}"
assert_contains "GPU_NVIDIA_OPEN in CONFIG_VARS" "GPU_NVIDIA_OPEN" "${config_vars_str}"

rm -f "${LOG_FILE}"
echo ""
echo "=== Results: Passed: ${PASS}, Failed: ${FAIL} ==="
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
