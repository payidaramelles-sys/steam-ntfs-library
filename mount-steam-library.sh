#!/usr/bin/env bash
# Mount an NTFS partition as a Steam library location on Linux.
#
#   sudo ./mount-steam-library.sh /dev/nvme1n1p2 /mnt/games
#
# Adds a persistent ntfs3 entry to /etc/fstab (UUID based), mounts it, and verifies.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: sudo ./mount-steam-library.sh <device> <mountpoint> [options]

  <device>       block device, e.g. /dev/nvme1n1p2 or /dev/disk/by-uuid/XXXX
  <mountpoint>   where to mount, e.g. /mnt/games

Options:
  --no-fstab        mount for this session only, do not touch /etc/fstab
  --fmask MASK      file permissions mask (default 0000)
  --dmask MASK      directory permissions mask (default 0022)
  -h, --help        show this help

The user that ran sudo keeps ownership of the mounted files (uid/gid are set
from SUDO_UID/SUDO_GID), which Steam needs in order to write to the library.
EOF
}

NO_FSTAB=0
FMASK="0000"
DMASK="0022"
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-fstab) NO_FSTAB=1; shift ;;
        --fmask) FMASK="${2:?--fmask needs a value}"; shift 2 ;;
        --dmask) DMASK="${2:?--dmask needs a value}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage; exit 2 ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done

if [[ ${#POSITIONAL[@]} -ne 2 ]]; then
    usage
    exit 2
fi

DEVICE="${POSITIONAL[0]}"
MOUNTPOINT="${POSITIONAL[1]}"

if [[ ${EUID} -ne 0 ]]; then
    echo "This script needs root. Re-running with sudo..." >&2
    exec sudo -- bash "$0" "$@"
fi

TARGET_UID="${SUDO_UID:-$(id -u)}"
TARGET_GID="${SUDO_GID:-$(id -g)}"

[[ -e "${DEVICE}" ]] || { echo "No such device: ${DEVICE}" >&2; exit 1; }

UUID="$(blkid -s UUID -o value "${DEVICE}" || true)"
FSTYPE_DETECTED="$(blkid -s TYPE -o value "${DEVICE}" || true)"

if [[ -z "${UUID}" ]]; then
    echo "Could not read a filesystem UUID from ${DEVICE}." >&2
    echo "Is the partition formatted? (mkfs.ntfs / Windows already initialised it?)" >&2
    exit 1
fi

if [[ "${FSTYPE_DETECTED}" != "ntfs" ]]; then
    echo "Warning: ${DEVICE} reports filesystem type '${FSTYPE_DETECTED}', not ntfs." >&2
    echo "Continuing anyway; using ntfs3 to mount it." >&2
fi

# ntfs3 is the in-kernel driver. ntfs-3g (FUSE) also works but is slower and
# handles permissions differently.
if ! modinfo ntfs3 >/dev/null 2>&1; then
    echo "Kernel module ntfs3 not found. On Fedora: sudo dnf install kernel-modules" >&2
    exit 1
fi

mountpoint -q "${MOUNTPOINT}" && { echo "${MOUNTPOINT} is already a mountpoint." >&2; exit 1; }
mkdir -p "${MOUNTPOINT}"

OPTIONS="uid=${TARGET_UID},gid=${TARGET_GID},fmask=${FMASK},dmask=${DMASK},nofail,x-gvfs-show"
FSTAB_LINE="UUID=${UUID} ${MOUNTPOINT} ntfs3 ${OPTIONS} 0 0"

if [[ ${NO_FSTAB} -eq 0 ]]; then
    if grep -qE "^[^#]*UUID=${UUID}[[:space:]]" /etc/fstab; then
        echo "An /etc/fstab entry for UUID=${UUID} already exists; leaving it untouched:" >&2
        grep -E "UUID=${UUID}" /etc/fstab >&2
    else
        BACKUP="/etc/fstab.bak.$(date +%Y%m%d-%H%M%S)"
        cp -a /etc/fstab "${BACKUP}"
        echo "Backed up /etc/fstab -> ${BACKUP}"
        printf '\n# Steam library (added by mount-steam-library.sh)\n%s\n' "${FSTAB_LINE}" >> /etc/fstab
        echo "Added to /etc/fstab:"
        echo "  ${FSTAB_LINE}"
        systemctl daemon-reload
    fi
fi

if mountpoint -q "${MOUNTPOINT}"; then
    umount "${MOUNTPOINT}"
fi

if [[ ${NO_FSTAB} -eq 0 ]]; then
    mount "${MOUNTPOINT}"
else
    mount -t ntfs3 -o "${OPTIONS}" "UUID=${UUID}" "${MOUNTPOINT}"
fi

echo
findmnt -T "${MOUNTPOINT}" -o TARGET,SOURCE,FSTYPE,OPTIONS

cat <<EOF

Mounted. Next:
  1. Steam -> Settings -> Storage -> Add Drive -> ${MOUNTPOINT}
     (create the folder as a normal user first, e.g. mkdir -p ${MOUNTPOINT}/SteamLibrary)
  2. Move Proton prefixes off NTFS before playing:
       ./relocate-compatdata.sh ${MOUNTPOINT}/SteamLibrary
EOF
