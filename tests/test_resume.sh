#!/usr/bin/env bash
# tests/test_resume.sh — Tests for try_resume_from_disk() in lib/utils.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TEST_TMPDIR="$(mktemp -d)"
export _NIXOS_INSTALLER=1 LIB_DIR="${SCRIPT_DIR}/lib" LOG_FILE="/tmp/nixos-test-resume.log"
export DRY_RUN=1 NON_INTERACTIVE=1
export CHECKPOINT_DIR="${TEST_TMPDIR}/recovered-checkpoints"
export CHECKPOINT_DIR_SUFFIX="/tmp/nixos-installer-checkpoints"
export CONFIG_FILE="${TEST_TMPDIR}/nixos-installer.conf"
export MOUNTPOINT="${TEST_TMPDIR}/mnt"
: > "${LOG_FILE}"

source "${LIB_DIR}/constants.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/config.sh"

PASS=0 FAIL=0
assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "${expected}" == "${actual}" ]]; then echo "  PASS: ${desc}"; (( PASS++ )) || true
    else echo "  FAIL: ${desc} — expected '${expected}', got '${actual}'"; (( FAIL++ )) || true; fi
}

echo "=== Test 1: Config + checkpoints -> returns 0 ==="

# Set up fake resume test directory with both config and checkpoints
RESUME_DIR_1="$(mktemp -d)"
export _RESUME_TEST_DIR="${RESUME_DIR_1}"

# Create partitions list
echo "/dev/sda2 ext4" > "${RESUME_DIR_1}/partitions.list"

# Create fake mount point with checkpoints AND config
fake_mp="${RESUME_DIR_1}/mnt/sda2"
mkdir -p "${fake_mp}${CHECKPOINT_DIR_SUFFIX}"
touch "${fake_mp}${CHECKPOINT_DIR_SUFFIX}/disks"
touch "${fake_mp}${CHECKPOINT_DIR_SUFFIX}/nixos_config"

mkdir -p "${fake_mp}/tmp"
cat > "${fake_mp}/tmp/nixos-installer.conf" << 'CONF'
#!/usr/bin/env bash
HOSTNAME='recovered-host'
FILESYSTEM='ext4'
CONF

# Reset checkpoint dir for recovery
rm -rf "${CHECKPOINT_DIR}"
export CHECKPOINT_DIR="${TEST_TMPDIR}/recovered-checkpoints-1"

rc=0; try_resume_from_disk || rc=$?
assert_eq "Returns 0 (config + checkpoints)" "0" "${rc}"
assert_eq "RESUME_FOUND_PARTITION" "/dev/sda2" "${RESUME_FOUND_PARTITION}"
assert_eq "RESUME_HAS_CONFIG" "1" "${RESUME_HAS_CONFIG}"

# Verify checkpoints were recovered
if [[ -f "${CHECKPOINT_DIR}/disks" ]]; then
    echo "  PASS: disks checkpoint recovered"; (( PASS++ )) || true
else
    echo "  FAIL: disks checkpoint not recovered"; (( FAIL++ )) || true
fi

# Verify config was recovered
if [[ -f "${CONFIG_FILE}" ]]; then
    echo "  PASS: config file recovered"; (( PASS++ )) || true
else
    echo "  FAIL: config file not recovered"; (( FAIL++ )) || true
fi

rm -rf "${RESUME_DIR_1}"

echo ""
echo "=== Test 2: Only checkpoints (no config) -> returns 1 ==="

RESUME_DIR_2="$(mktemp -d)"
export _RESUME_TEST_DIR="${RESUME_DIR_2}"

echo "/dev/sdb3 btrfs" > "${RESUME_DIR_2}/partitions.list"

fake_mp="${RESUME_DIR_2}/mnt/sdb3"
mkdir -p "${fake_mp}${CHECKPOINT_DIR_SUFFIX}"
touch "${fake_mp}${CHECKPOINT_DIR_SUFFIX}/disks"
# No config file this time

rm -rf "${CHECKPOINT_DIR}"
rm -f "${CONFIG_FILE}"
export CHECKPOINT_DIR="${TEST_TMPDIR}/recovered-checkpoints-2"

rc=0; try_resume_from_disk || rc=$?
assert_eq "Returns 1 (only checkpoints)" "1" "${rc}"
assert_eq "RESUME_FOUND_PARTITION" "/dev/sdb3" "${RESUME_FOUND_PARTITION}"
assert_eq "RESUME_HAS_CONFIG" "0" "${RESUME_HAS_CONFIG}"

rm -rf "${RESUME_DIR_2}"

echo ""
echo "=== Test 3: Nothing found -> returns 2 ==="

RESUME_DIR_3="$(mktemp -d)"
export _RESUME_TEST_DIR="${RESUME_DIR_3}"

# Empty partitions list
: > "${RESUME_DIR_3}/partitions.list"

rm -rf "${CHECKPOINT_DIR}"
export CHECKPOINT_DIR="${TEST_TMPDIR}/recovered-checkpoints-3"

rc=0; try_resume_from_disk || rc=$?
assert_eq "Returns 2 (nothing)" "2" "${rc}"
assert_eq "RESUME_FOUND_PARTITION empty" "" "${RESUME_FOUND_PARTITION}"

rm -rf "${RESUME_DIR_3}"

echo ""
echo "=== Test 4: Skips non-Linux filesystem types ==="

RESUME_DIR_4="$(mktemp -d)"
export _RESUME_TEST_DIR="${RESUME_DIR_4}"

# Only ntfs and vfat partitions (should be skipped)
cat > "${RESUME_DIR_4}/partitions.list" << 'LIST'
/dev/sda1 vfat
/dev/sda2 ntfs
/dev/sda3 swap
LIST

rm -rf "${CHECKPOINT_DIR}"
export CHECKPOINT_DIR="${TEST_TMPDIR}/recovered-checkpoints-4"

rc=0; try_resume_from_disk || rc=$?
assert_eq "Skips non-Linux FS -> returns 2" "2" "${rc}"

rm -rf "${RESUME_DIR_4}"

echo ""
echo "=== Test 5: Multiple partitions, finds first with checkpoints ==="

RESUME_DIR_5="$(mktemp -d)"
export _RESUME_TEST_DIR="${RESUME_DIR_5}"

cat > "${RESUME_DIR_5}/partitions.list" << 'LIST'
/dev/sda2 ext4
/dev/sda3 ext4
LIST

# Only second partition has checkpoints
mkdir -p "${RESUME_DIR_5}/mnt/sda2"
# sda2 has no checkpoints

fake_mp="${RESUME_DIR_5}/mnt/sda3"
mkdir -p "${fake_mp}${CHECKPOINT_DIR_SUFFIX}"
touch "${fake_mp}${CHECKPOINT_DIR_SUFFIX}/preflight"

rm -rf "${CHECKPOINT_DIR}"
export CHECKPOINT_DIR="${TEST_TMPDIR}/recovered-checkpoints-5"

rc=0; try_resume_from_disk || rc=$?
assert_eq "Returns 1 (checkpoints only on sda3)" "1" "${rc}"
assert_eq "Found on sda3" "/dev/sda3" "${RESUME_FOUND_PARTITION}"

rm -rf "${RESUME_DIR_5}"

# Cleanup
unset _RESUME_TEST_DIR
rm -rf "${TEST_TMPDIR}" "${LOG_FILE}"
echo ""
echo "=== Results: Passed: ${PASS}, Failed: ${FAIL} ==="
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
