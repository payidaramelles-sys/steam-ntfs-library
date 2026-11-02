#!/usr/bin/env bash
# Keep Proton prefixes (compatdata) on a Linux filesystem while the game library
# stays on NTFS, by replacing steamapps/compatdata with a symlink.
#
#   ./relocate-compatdata.sh /mnt/games/SteamLibrary
#
# Run as your normal user (NOT with sudo). Close Steam first.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./relocate-compatdata.sh <path-to-SteamLibrary> [target-dir]

  <path-to-SteamLibrary>   a folder that contains steamapps/ (e.g. /mnt/games/SteamLibrary)
  [target-dir]             where prefixes will live (default: ~/.local/share/steam-compatdata)

Steam must be closed. Existing prefixes are moved, not copied and deleted from
the original location, so the operation is reversible by moving them back and
removing the symlink.
EOF
}

[[ $# -ge 1 && $# -le 2 ]] || { usage; exit 2; }

LIBRARY="${1%/}"
TARGET="${2:-$HOME/.local/share/steam-compatdata}"

if [[ ! -d "${LIBRARY}/steamapps" ]]; then
    echo "Not a Steam library: ${LIBRARY}/steamapps does not exist." >&2
    exit 1
fi

if pgrep -x steam >/dev/null 2>&1 || pgrep -f "steamwebhelper" >/dev/null 2>&1; then
    echo "Steam is running. Close it completely and run this again." >&2
    exit 1
fi

# NTFS cannot hold Wine prefixes: no Unix permissions, no symlinks, and Wine
# needs both. Keeping them on the NTFS library makes games fail to launch.
case "$(stat -f -c %T "${LIBRARY}")" in
    ntfs|fuseblk|vfat|exfat)
        : # good: the library is the "slow" filesystem we are moving away from
        ;;
    *)
        echo "Note: ${LIBRARY} is already on $(stat -f -c %T "${LIBRARY}"), not NTFS."
        echo "This script is only useful for libraries on NTFS/exFAT."
        ;;
esac

case "$(stat -f -c %T "$(dirname "${TARGET}")")" in
    ext4|xfs|btrfs|zfs|ext2/ext3|tmpfs)
        : ;;
    *)
        echo "Warning: ${TARGET} is on $(stat -f -c %T "$(dirname "${TARGET}")"), which may not support Unix permissions." >&2
        echo "Pick a target on your Linux filesystem instead." >&2
        exit 1
        ;;
esac

OLD="${LIBRARY}/steamapps/compatdata"

if [[ -L "${OLD}" ]]; then
    echo "${OLD} is already a symlink -> $(readlink -f "${OLD}")"
    echo "Nothing to do."
    exit 0
fi

mkdir -p "${TARGET}"

old_has_content=0
new_has_content=0
[[ -d "${OLD}" ]] && [ -n "$(ls -A "${OLD}" 2>/dev/null)" ] && old_has_content=1
[ -n "$(ls -A "${TARGET}" 2>/dev/null)" ] && new_has_content=1

if [[ ${old_has_content} -eq 1 && ${new_has_content} -eq 1 ]]; then
    echo "Both locations contain prefixes:" >&2
    echo "  ${OLD}" >&2
    echo "  ${TARGET}" >&2
    echo "Merge them manually (rsync -aHAX) and remove the source, then re-run." >&2
    exit 1
fi

if [[ ${old_has_content} -eq 1 ]]; then
    echo "Moving existing prefixes: ${OLD} -> ${TARGET}"
    # -a is -dR --preserve=all: symlinks, permissions, ACLs and xattrs all kept.
    # Proton prefixes rely on all of them.
    cp -a "${OLD}/." "${TARGET}/"
    rm -rf "${OLD}"
fi

ln -s "${TARGET}" "${OLD}"

echo "Done:"
ls -ld "${OLD}"
findmnt -T "${TARGET}" -o TARGET,SOURCE,FSTYPE | tail -1
echo
echo "Start Steam and launch a Proton game to verify."
