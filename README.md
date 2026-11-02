# steam-ntfs-library

Use an **NTFS partition as a Steam library on Linux** without breaking Proton.

Two small scripts that do the two things every dual-boot Steam user has to figure out by hand:

1. `mount-steam-library.sh` — mount an NTFS partition with permissions Steam can actually write to, and persist it in `/etc/fstab` by UUID.
2. `relocate-compatdata.sh` — move Proton prefixes (`steamapps/compatdata`) onto your Linux filesystem and symlink them back.

## Why the second script exists

Steam happily stores **game files** on NTFS. Proton does not store **prefixes** there well.

A Proton prefix is a fake Windows drive: `drive_c/`, symlinks into the game directory, Unix permissions, sometimes hard links. NTFS gives you none of that in a form Wine can use:

- no Unix ownership/permissions, only a `uid=`/`fmask=` mapping at mount time,
- no real symlinks on a plain NTFS mount,
- case-insensitive lookups, which a few games and installers trip over.

The failure looks like a game that starts from `C:` but dies when Proton tries to create `compatdata/<appid>/pfx`, or a fully black window, or:

```
wine: could not create directory '/path/to/SteamLibrary/steamapps/compatdata/1234/pfx'
```

Moving `compatdata` to ext4/btrfs and symlinking it back gives Proton a real Linux filesystem while the (large) game files stay on the NTFS disk. Steam follows the symlink without noticing.

## Requirements

- A kernel with `ntfs3` (in-tree since Linux 5.15; Fedora, Arch, Ubuntu all ship it).
- `blkid`, `findmnt` (`util-linux`) and `mountpoint` (`util-linux`).
- The NTFS partition must be unmounted first — Windows' fast startup / hibernation keeps it in a dirty state. Boot Windows once with fast startup disabled, or run `ntfsfix`.

## 1. Mount the NTFS partition

```bash
sudo ./mount-steam-library.sh /dev/nvme1n1p2 /mnt/games
```

The script:

- reads the partition's UUID and writes a `nofail` fstab entry using `ntfs3`,
- sets `uid`/`gid` to the user who ran `sudo` — Steam refuses libraries it cannot write to,
- backs up `/etc/fstab` before touching it,
- mounts and prints the resulting `findmnt` line.

Resulting entry, in this form:

```
UUID=F20CF4870CF4485D /mnt/games ntfs3 uid=1000,gid=1000,fmask=0000,dmask=0022,nofail,x-gvfs-show 0 0
```

`fmask=0000` and `dmask=0022` matter: the defaults (`fmask=0177`, `dmask=0077`) make everything root-only or read-only, and Steam then reports the drive as full or unwritable.

Then add the library in Steam: **Settings → Storage → Add Drive** → `/mnt/games`.

## 2. Move the Proton prefixes

Close Steam, then:

```bash
./relocate-compatdata.sh /mnt/games/SteamLibrary
```

It moves existing prefixes to `~/.local/share/steam-compatdata` (override with a second argument) and replaces

```
/mnt/games/SteamLibrary/steamapps/compatdata
```

with a symlink to that directory. It refuses to run while Steam is open, and refuses to merge two non-empty locations instead of guessing.

New games installed later write their prefix to the symlink target automatically.

## Verify

```bash
findmnt -T /mnt/games
ls -ld /mnt/games/SteamLibrary/steamapps/compatdata     # should be a symlink
ls -ld ~/.local/share/steam-compatdata                  # on btrfs/ext4
```

Launch a Proton game. The game files are read from NTFS; the prefix is created on your Linux filesystem.

## Troubleshooting

**Steam does not list the drive, or says it is not writable.** The mount's `uid=` must be your user, not root. Check `findmnt -T /mnt/games -o OPTIONS` and `touch /mnt/games/test`.

**`mount: unknown filesystem type 'ntfs3'`.** Kernel module missing. On Fedora install `kernel-modules`; on Ubuntu use `ntfs-3g` instead and mount with `-t ntfs-3g` (the script's fstab line would then need `ntfs-3g`).

**Games crash right after launch, prefix path in the log.** The symlink is missing or points somewhere unwritable. Re-run `relocate-compatdata.sh`.

**Steam says "Invalid platform" when installing a Proton version.** Unrelated to NTFS — that is a Steam client/runtime issue, not a permission problem.

**Windows sees the disk as dirty / Linux mounts it read-only.** Windows fast startup left the filesystem in a hibernated state. Disable fast startup in Windows power settings.

## License

MIT
