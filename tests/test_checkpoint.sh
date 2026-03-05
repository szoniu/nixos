#!/usr/bin/env bash
# tests/test_checkpoint.sh — Tests for checkpoint functions in lib/utils.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TEST_TMPDIR="$(mktemp -d)"
export _NIXOS_INSTALLER=1 LIB_DIR="${SCRIPT_DIR}/lib" LOG_FILE="/tmp/nixos-test-checkpoint.log"
export DRY_RUN=1 NON_INTERACTIVE=1
export CHECKPOINT_DIR="${TEST_TMPDIR}/checkpoints"
export CHECKPOINT_DIR_SUFFIX="/tmp/nixos-installer-checkpoints"
export MOUNTPOINT="${TEST_TMPDIR}/mnt"
: > "${LOG_FILE}"

source "${LIB_DIR}/constants.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/utils.sh"

PASS=0 FAIL=0
assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "${expected}" == "${actual}" ]]; then echo "  PASS: ${desc}"; (( PASS++ )) || true
    else echo "  FAIL: ${desc} — expected '${expected}', got '${actual}'"; (( FAIL++ )) || true; fi
}

echo "=== Test 1: checkpoint_set creates file ==="
checkpoint_set "test1"
if [[ -f "${CHECKPOINT_DIR}/test1" ]]; then
    echo "  PASS: checkpoint file created"; (( PASS++ )) || true
else
    echo "  FAIL: checkpoint file not created"; (( FAIL++ )) || true
fi

echo ""
echo "=== Test 2: checkpoint_reached returns 0 for existing ==="
rc=0; checkpoint_reached "test1" || rc=$?
assert_eq "checkpoint_reached existing" "0" "${rc}"

echo ""
echo "=== Test 3: checkpoint_reached returns 1 for nonexistent ==="
rc=0; checkpoint_reached "nonexistent" || rc=$?
assert_eq "checkpoint_reached nonexistent" "1" "${rc}"

echo ""
echo "=== Test 4: Multiple checkpoints ==="
checkpoint_set "test2"
checkpoint_set "test3"
rc1=0; checkpoint_reached "test1" || rc1=$?
rc2=0; checkpoint_reached "test2" || rc2=$?
rc3=0; checkpoint_reached "test3" || rc3=$?
assert_eq "test1 still exists" "0" "${rc1}"
assert_eq "test2 exists" "0" "${rc2}"
assert_eq "test3 exists" "0" "${rc3}"

echo ""
echo "=== Test 5: checkpoint_clear removes all ==="
checkpoint_clear
rc=0; checkpoint_reached "test1" || rc=$?
assert_eq "test1 removed after clear" "1" "${rc}"
rc=0; checkpoint_reached "test2" || rc=$?
assert_eq "test2 removed after clear" "1" "${rc}"
rc=0; checkpoint_reached "test3" || rc=$?
assert_eq "test3 removed after clear" "1" "${rc}"

echo ""
echo "=== Test 6: checkpoint_migrate_to_target ==="
# Re-create checkpoints
export CHECKPOINT_DIR="${TEST_TMPDIR}/checkpoints"
mkdir -p "${CHECKPOINT_DIR}"
checkpoint_set "migrate_test1"
checkpoint_set "migrate_test2"

# Create target directory
mkdir -p "${MOUNTPOINT}"
checkpoint_migrate_to_target

# Verify checkpoints migrated to target
target_dir="${MOUNTPOINT}${CHECKPOINT_DIR_SUFFIX}"
if [[ -f "${target_dir}/migrate_test1" ]]; then
    echo "  PASS: migrate_test1 copied to target"; (( PASS++ )) || true
else
    echo "  FAIL: migrate_test1 not found at target"; (( FAIL++ )) || true
fi
if [[ -f "${target_dir}/migrate_test2" ]]; then
    echo "  PASS: migrate_test2 copied to target"; (( PASS++ )) || true
else
    echo "  FAIL: migrate_test2 not found at target"; (( FAIL++ )) || true
fi

# CHECKPOINT_DIR should now point to the target
assert_eq "CHECKPOINT_DIR updated" "${target_dir}" "${CHECKPOINT_DIR}"

# Original should be removed
if [[ ! -d "${TEST_TMPDIR}/checkpoints" ]]; then
    echo "  PASS: original checkpoint dir removed"; (( PASS++ )) || true
else
    echo "  FAIL: original checkpoint dir still exists"; (( FAIL++ )) || true
fi

# Verify checkpoint_reached works with new dir
rc=0; checkpoint_reached "migrate_test1" || rc=$?
assert_eq "checkpoint_reached after migrate" "0" "${rc}"

# Cleanup
rm -rf "${TEST_TMPDIR}" "${LOG_FILE}"
echo ""
echo "=== Results: Passed: ${PASS}, Failed: ${FAIL} ==="
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
