# flatpak-backup.sh

A bash script that backs up all installed Flatpak applications and runtimes as self-contained `.flatpak` bundle files — ready for offline reinstallation without internet access.

---

## Features

- Backs up every installed **app** and **runtime** as a standalone `.flatpak` bundle
- Optional `--userdata` flag to also archive `~/.var/app/<app-id>/` per app
- **Incremental** — already existing bundles are skipped, so re-running is safe
- Live **progress bar** with MB counter while each bundle is being created
- Detailed **log file** per backup run
- Works with both system-wide (`/var/lib/flatpak`) and user (`~/.local/share/flatpak`) installations
- Safe to run with `sudo` — correctly resolves the real user's home directory

---

## Usage

```bash
chmod +x flatpak-backup.sh

# Back up apps + runtimes
./flatpak-backup.sh

# Back up apps + runtimes + user data (~/.var/app/)
./flatpak-backup.sh --userdata
```

Output is written to `~/Downloads/flatpak-backup/`:

```
~/Downloads/flatpak-backup/
├── apps/
│   ├── com.spotify.Client__x86_64__stable.flatpak
│   ├── org.gimp.GIMP__x86_64__stable.flatpak
│   └── …
├── runtimes/
│   ├── org.gnome.Platform__x86_64__46.flatpak
│   └── …
├── userdata/                  # only with --userdata
│   ├── com.spotify.Client.tar.gz
│   └── …
└── backup-2025-06-18.log
```

---

## Restore

### Reinstall an app from bundle

```bash
flatpak install --bundle ~/Downloads/flatpak-backup/apps/com.spotify.Client__x86_64__stable.flatpak
```

### Reinstall a runtime from bundle

```bash
flatpak install --bundle ~/Downloads/flatpak-backup/runtimes/org.gnome.Platform__x86_64__46.flatpak
```

### Restore user data

```bash
tar -xzf ~/Downloads/flatpak-backup/userdata/com.spotify.Client.tar.gz -C ~/.var/app/
```

---

## Requirements

- `bash`
- `flatpak` (with at least one app or runtime installed)

No additional tools required. The script uses only standard `flatpak` commands (`flatpak list`, `flatpak build-bundle`).

---

## How it works

For each installed app and runtime, the script calls:

```bash
flatpak build-bundle <repo> <output.flatpak> <app-id> <branch>
```

This creates a fully self-contained bundle that can be installed on any machine — even without internet access or Flathub configured.

User data (config, saves, cache) lives in `~/.var/app/<app-id>/` and is archived separately as a `tar.gz` when `--userdata` is passed.

Bundles are never overwritten — re-running the script skips files that already exist. This makes it safe to add newly installed apps to an existing backup folder without re-bundling everything.

---

## Notes

- **Bundle size**: Each `.flatpak` file contains the app or runtime in its entirety. Runtimes (e.g. `org.gnome.Platform`) can be several GB each.
- **Shared runtimes**: When restoring, install the required runtimes before the apps — just like a fresh Flatpak setup.
- **sudo**: Running with `sudo` is supported. The script detects `$SUDO_USER` and writes to the correct home directory.
- **Bazzite / Aurora / Fedora Silverblue**: Works on immutable systems — no host modifications required.
