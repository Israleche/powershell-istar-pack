# Istar Pack

A single-file PowerShell script that turns a fresh Windows machine into a fully
loaded terminal workstation in one run. It installs the Scoop package manager,
Oh My Posh, Zoxide, FZF, 7-Zip, a Nerd Font, the recommended PowerShell
modules, and writes a hardened profile tuned for both Windows PowerShell 5.1
and PowerShell 7+. It also ships a curated catalog of six Oh My Posh themes,
with the signature one being **Garden's Dream** (minimalist green).

The script is interactive: launch it, pick a theme, press Enter, and walk away.
No manual JSON editing, no copy-pasting profile snippets, no chasing down
which module goes where. It auto-detects your PowerShell edition and adapts
the profile it writes accordingly.

---

## Table of Contents

1. [Why Istar Pack](#why-istar-pack)
2. [Features](#features)
3. [Requirements](#requirements)
4. [Quick Start](#quick-start)
5. [How It Works](#how-it-works)
6. [Themes](#themes)
7. [Configuration](#configuration)
8. [What Gets Installed](#what-gets-installed)
9. [What the Profile Fixes](#what-the-profile-fixes)
10. [Uninstall and Rollback](#uninstall-and-rollback)
11. [Troubleshooting](#troubleshooting)
12. [FAQ](#faq)
13. [Contributing](#contributing)
14. [Changelog](#changelog)
15. [Project Layout](#project-layout)
16. [Disclaimer](#disclaimer)

---

## Why Istar Pack

Most PowerShell setup guides are scattered across five blog posts, three
GitHub gists, and a stale Reddit thread. You end up cobbling together a
profile from copy-pasted fragments, half of which are deprecated, and the
other half assume you are running PS 7 when you are actually on PS 5.1.
Istar Pack replaces that entire workflow with a single `.ps1` file that
you run once.

The script is opinionated. It picks tools that are well-maintained, free,
and work on both PowerShell editions. It writes a profile that fixes
long-standing annoyances (the UpArrow / ListView conflict, the missing
`7z` dependency in `extract()`, the deprecated `acrylicOpacity`, the
wrong PS version requirement). And it gives you six themes to choose
from, so your terminal does not have to look like everyone else's.

If you have ever spent an afternoon getting Oh My Posh to render correctly,
this script is for you.

---

## Features

- **One-shot install.** Scoop, Oh My Posh, Zoxide, FZF, 7-Zip, a Nerd
  Font, and the recommended PowerShell modules, all in one run.
- **Cross-edition support.** Auto-detects PowerShell 5.1 vs 7+ and emits
  the correct profile for each. PS 7 gets `HistoryAndPlugin` prediction
  and the native `` `e `` escape; PS 5.1 gets `History` prediction and
  `[char]27`.
- **Six built-in themes.** Garden's Dream, Midnight Cyber, Sakura Bloom,
  Solar Flare, Mono Slate, Dracula Reborn. Each is a self-contained
  Oh My Posh v2 JSON definition.
- **Theme-aware TUI.** The whole Istar Pack interface (banner, menu,
  progress bar, box titles) recolors to match the currently selected
  theme. Pick a theme and the setup tool itself changes color.
- **Smooth arrow-key navigation.** The menu uses differential redraw:
  only the two changed rows are repainted on each key press, not the
  entire screen. No flicker, no lag.
- **Auto-growing console.** On launch, Istar Pack tries to grow the
  console window to 50 rows (capped at your physical screen height)
  so the tall screens (Verification, Theme Catalog, About) fit
  without being cut off. If the window cannot grow, a tall scrollback
  buffer is left in place so you can still scroll to see everything.
- **Backup before overwrite.** Your existing profile is copied to
  `$HOME\.istar-pack\backups\` with a timestamp before it is replaced.
- **JSON settings persistence.** Your theme choice, toggles, and last
  install timestamp are saved to `$HOME\.istar-pack\settings.json` and
  restored on next launch.
- **Silent mode.** Run with `-Silent` for non-interactive installs
  (useful for box-setup scripts, Ansible, or DSC).
- **UTF-8 with BOM.** The `.ps1` file is saved as UTF-8 with BOM so
  that Windows PowerShell 5.1 parses the box-drawing characters
  correctly. Without BOM, PS 5.1 falls back to ANSI and the TUI breaks.

---

## Requirements

- **Operating System:** Windows 10 or Windows 11. The script relies on
  Scoop, which is Windows-only.
- **PowerShell:** 5.1 or later. Both Windows PowerShell 5.1 and
  PowerShell 7+ are supported. The script auto-detects the edition and
  adapts.
- **Execution Policy:** Must allow local script execution. Run
  `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
  in an elevated prompt if you have never done so.
- **Internet access:** Required for the first run (Scoop bootstrap,
  module downloads, font download). Subsequent runs are mostly offline.
- **No administrator privileges required.** Scoop installs into your
  user profile, so Istar Pack works without elevation. If you happen to
  be running as Administrator, the script will note it but will not
  change behavior.

---

## Quick Start

1. Download `Istar-Pack.ps1` from this repository.
2. Open PowerShell (5.1 or 7+).
3. If you have never run a local script before, allow local scripts:

   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

4. Navigate to the download folder and launch the script:

   ```powershell
   .\Istar-Pack.ps1
   ```

5. Use the arrow keys to pick **Full install (recommended)** and press
   Enter. Wait for the install to finish.
6. Close and reopen your terminal. You should see the new prompt with
   your selected theme.

For a non-interactive install with the default theme:

```powershell
.\Istar-Pack.ps1 -Silent
```

To skip loading or saving settings (truly ephemeral run):

```powershell
.\Istar-Pack.ps1 -NoPersist
```

---

## How It Works

Istar Pack is a single self-contained `.ps1` file. When you launch it,
the following happens in order:

1. **Bootstrap.** UTF-8 encoding is forced on the console layer. The
   PowerShell version is detected. The console window is grown to 50
   rows if possible.
2. **Settings load.** If `$HOME\.istar-pack\settings.json` exists, your
   previous theme choice and toggles are loaded.
3. **Main menu.** An interactive TUI renders the Istar Pack banner, a
   status bar (progress toggle, debug toggle, runtime version, active
   theme), and a list of menu options. Use arrow keys to navigate,
   Enter to select, Esc to cancel.
4. **Full install flow.** When you select Full install, the script runs
   seven steps in sequence:
   - Install Scoop if missing.
   - Install CLI tools (oh-my-posh, zoxide, fzf, 7zip, git) via Scoop.
   - Install PowerShell modules (Terminal-Icons, PSReadLine, PSFzf,
     and CompletionPredictor on PS 7+).
   - Install a Nerd Font (Cascadia Code) if not already present.
   - Back up your existing profile to `$HOME\.istar-pack\backups\`.
   - Write the selected theme's JSON to your PowerShell directory.
   - Write the new profile, with theme path, zoxide init, PSReadLine
     config, and safe module imports.
5. **Verification.** The Verification screen runs sanity checks on
   every tool, module, and path, and shows you a green / red status
   table.
6. **Settings save.** Your theme choice and last-install timestamp
   are persisted to `settings.json`.

You can re-run the script any time. It will detect what is already
installed and skip the work, which makes it safe to use as a "repair"
tool when something has gone wrong with your terminal.

---

## Themes

Istar Pack ships six themes. Each theme is a complete Oh My Posh v2
JSON definition embedded directly in the script; no theme files are
downloaded from the internet.

| Key              | Name              | Description                                                       |
|------------------|-------------------|-------------------------------------------------------------------|
| GardensDream     | Garden's Dream    | Minimalist green. User + path + git. The signature look.          |
| MidnightCyber    | Midnight Cyber    | Dark blue with neon cyan accents. Cyberpunk vibe, single block.   |
| SakuraBloom      | Sakura Bloom      | Pink / magenta pastel. Soft and warm, ideal for daytime coding.   |
| SolarFlare       | Solar Flare       | Orange-red gradient on dark background. Bold and energetic.       |
| MonoSlate        | Mono Slate        | Pure grayscale, no colors. Maximum focus, zero distraction.       |
| DraculaReborn    | Dracula Reborn    | Classic Dracula palette (purple / pink / cyan), single-line.      |

To preview all themes without committing to one, choose **Browse theme
catalog** from the main menu. To switch themes after install, choose
**Select theme**; the script writes the new theme JSON and rewrites
your profile to point at it.

When you select a theme, the Istar Pack TUI itself recolors to match.
The banner ASCII art, the progress bar, and the box accent colors all
follow the active theme. This makes it easier to preview how the theme
will feel before you commit.

---

## Configuration

Istar Pack stores its configuration in your user home directory so
that settings survive even if you move or re-download the script.

### File Locations

| Path                                  | Purpose                                                  |
|---------------------------------------|----------------------------------------------------------|
| `$HOME\.istar-pack\settings.json`     | Theme choice, toggles, last-install timestamp.           |
| `$HOME\.istar-pack\backups\`          | Timestamped copies of your previous PowerShell profile.  |
| `$HOME\Documents\PowerShell\`         | PS 7 profile directory.                                  |
| `$HOME\Documents\WindowsPowerShell\`  | PS 5.1 profile directory.                                |
| `<profile dir>\<ThemeKey>.omp.json`   | The Oh My Posh theme JSON for the selected theme.        |
| `<profile dir>\Microsoft.PowerShell_profile.ps1` | Your rewritten PowerShell profile.           |

### Settings Options

You can edit `settings.json` directly, or use the **Open settings**
menu item inside Istar Pack. The available options are:

- **ShowProgress** (true / false) - Show or hide the progress bar
  during installs.
- **DebugMode** (true / false) - Print extra log lines for
  troubleshooting.
- **SelectedTheme** (string) - One of the theme keys from the table
  above.
- **InstallModules** (true / false) - Whether the Full install flow
  should install PowerShell modules.
- **InstallScoop** (true / false) - Whether the Full install flow
  should install Scoop and CLI tools.
- **InstallFont** (true / false) - Whether the Full install flow
  should install a Nerd Font.
- **LastFullInstall** (timestamp) - When the Full install last
  completed successfully. Informational only.

### Command-Line Switches

| Switch          | Effect                                                       |
|-----------------|--------------------------------------------------------------|
| `-Silent`       | Run the full install non-interactively with the saved theme. |
| `-NoPersist`    | Do not load or save `settings.json` for this run.            |
| `-ShowProgress 0|1` | Override the ShowProgress setting for this run.          |
| `-EnableDebug 0|1`  | Override the DebugMode setting for this run.             |

---

## What Gets Installed

Istar Pack installs the following tools via Scoop (which is itself
installed if missing):

- **git** - Version control. Required by Scoop for bucket operations
  and generally useful to have on PATH.
- **oh-my-posh** - Prompt renderer. The whole point.
- **zoxide** - Smarter `cd` replacement. Type `z <part-of-path>` to
  jump to a frequently visited directory.
- **fzf** - Fuzzy finder. Wired into PSReadLine for `Ctrl+t` file
  search and `Ctrl+r` history search.
- **7zip** - Archive tool. Used by the `extract` function in the
  profile to handle `.7z`, `.zip`, `.tar.gz`, and similar formats.

The following PowerShell modules are installed from the PowerShell
Gallery:

- **Terminal-Icons** - Adds file-type icons to `Get-ChildItem` output
  in modern terminals (Windows Terminal, WezTerm, iTerm2).
- **PSReadLine** (latest) - Provides syntax highlighting, multi-line
  editing, and predictive IntelliSense. On PS 7, the
  `CompletionPredictor` plugin is also installed for ListView-style
  predictions.
- **PSFzf** - PowerShell wrapper around `fzf`. Replaces the default
  `Ctrl+t` and `Ctrl+r` handlers with fzf-powered fuzzy versions.

A **Nerd Font** (Cascadia Code) is installed so that the Oh My Posh
powerline glyphs and Terminal-Icons file icons render correctly. The
font is installed for the current user only, no elevation required.

---

## What the Profile Fixes

The profile that Istar Pack writes addresses several long-standing
issues found in typical PowerShell setup guides:

- **UpArrow / ListView conflict.** PSReadLine's `ListView` prediction
  view binds UpArrow to navigate the prediction list, which conflicts
  with using UpArrow for history navigation. The profile binds
  `Ctrl+UpArrow` and `Ctrl+DownArrow` for prediction navigation
  instead, leaving UpArrow free for history.
- **Missing `7z` dependency.** Many profiles define an `extract`
  function that calls `7z` without checking whether it is installed.
  The Istar Pack profile verifies `7z` is on PATH before calling it,
  and falls back to `Expand-Archive` for plain `.zip` files.
- **False async claim.** Some guides claim that `oh-my-posh` runs
  asynchronously with `--shell` mode. It does not, on Windows. The
  profile drops the flag and uses the synchronous initializer, which
  is more reliable.
- **Deprecated `acrylicOpacity`.** Windows Terminal deprecated this
  field; the profile does not emit it.
- **Wrong PS version requirement.** Some snippets require PS 7.1
  minimum even though they only need 5.1 features. The profile
  correctly gates PS 7-only features behind an edition check.

Additional quality-of-life improvements in the profile:

- `MaximumHistoryCount` raised to 4096.
- `HistoryNoDuplicates` enabled.
- `HistorySearchCursorMovesToEnd` enabled.
- Tab completion shows all matches on first Tab.
- Modules are loaded inside `try/catch` blocks so a missing module
  never breaks the prompt.
- `zoxide` is initialized with `--cmd cd` so the standard `cd` command
  gets the zoxide boost.

---

## Uninstall and Rollback

Istar Pack is designed to be reversible. To roll back to your previous
setup:

1. Open `$HOME\.istar-pack\backups\` in File Explorer.
2. Find the most recent `profile_PS7_<timestamp>.ps1` or
   `profile_PS5_<timestamp>.ps1` file.
3. Copy it to your profile path (see the Configuration section above)
   and rename it to `Microsoft.PowerShell_profile.ps1`.
4. Delete the `<ThemeKey>.omp.json` file from the same directory if
   you no longer want the theme JSON present.
5. Restart your terminal.

To fully uninstall the tools Istar Pack installed:

```powershell
scoop uninstall oh-my-posh zoxide fzf 7zip git
scoop uninstall scoop
Uninstall-Module Terminal-Icons -Force
Uninstall-Module PSFzf -Force
Uninstall-Module PSReadLine -Force  # PS 7 only - do not run on PS 5.1
Remove-Item -Recurse -Force $HOME\.istar-pack
```

Note: the Nerd Font is installed via a user-level font registration.
To remove it, open `Settings > Personalization > Fonts` and uninstall
"Cascadia Code NF" manually.

---

## Troubleshooting

### The TUI looks broken (weird characters, misaligned boxes)

Your console is not using a font that supports Unicode box-drawing
characters. Use Windows Terminal with Cascadia Code or any Nerd Font.
After Istar Pack finishes its install, the font issue will be solved
for future runs as well.

### The banner is cut off at the bottom

Istar Pack tries to grow the console to 50 rows on launch. If your
window manager refused to grow (some Windows Terminal configurations
lock the window size), the script leaves a tall scrollback buffer in
place. Use the scroll wheel (or `Shift+PageUp`) to scroll down and
see the rest of the screen. You can also manually resize the window
and re-run the script.

### `Set-ExecutionPolicy` errors when launching

You need to allow local scripts. Run, in an elevated PowerShell
prompt:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

This allows locally-created scripts to run without a signature, while
still requiring downloaded scripts to be signed. It is the standard
recommendation for developer machines.

### Oh My Posh shows "command not found" after install

The Scoop shim directory is not on your PATH for the current session.
Close and reopen your terminal. If the issue persists, run
`scoop reset oh-my-posh` and try again.

### The script fails with an encoding error on PS 5.1

The `.ps1` file must be saved as UTF-8 with BOM. If you re-saved it
with a text editor that strips the BOM (some editors do this by
default), PS 5.1 will mis-parse the box-drawing characters. Re-download
the file from this repository.

### `7z` is reported as missing even after install

Close and reopen your terminal so the PATH refresh takes effect. If
still missing, run `scoop install 7zip` manually and verify with
`Get-Command 7z`.

### I want to reset everything to defaults

Delete `$HOME\.istar-pack\settings.json` and re-launch the script. It
will start fresh with the Garden's Dream theme and all toggles at
their defaults.

---

## FAQ

**Is Istar Pack safe to run on my work machine?**

It installs only well-known, open-source tools (Scoop, Oh My Posh,
Zoxide, FZF, 7-Zip, Terminal-Icons, PSReadLine, PSFzf) from their
official sources. It does not phone home, does not collect telemetry,
and does not modify anything outside your user profile. It backs up
your existing profile before overwriting it. That said, you should
always review a script before running it, especially on a work
machine.

**Does it work on PowerShell Core on Linux or macOS?**

No. Istar Pack relies on Scoop, which is Windows-only. On Linux or
macOS, use your system package manager to install the equivalent
tools (oh-my-posh, zoxide, fzf) and configure your shell manually.

**Can I run it multiple times?**

Yes. Istar Pack is idempotent. Running it again detects what is
already installed and skips the work. This makes it safe to use as a
"repair" tool when something has gone wrong.

**Can I use my own theme?**

Not directly through the Istar Pack UI. The script ships six curated
themes. To use a custom theme, run Istar Pack once with any theme
to set up the profile scaffolding, then manually replace the
`<ThemeKey>.omp.json` file in your profile directory with your own
JSON. Edit the `oh-my-posh` line in your profile to point at the new
file name.

**Why is the script a single file?**

Because the goal is one-shot setup. A single `.ps1` file is easy to
download, easy to audit, and easy to share. There are no module
dependencies, no install scripts, no build step. Download, run, done.

**How do I update Istar Pack?**

Re-download the `.ps1` file from this repository and replace your
local copy. Your settings and backups in `$HOME\.istar-pack\` are
preserved. Run the script again to update your profile and theme
JSON to the latest version.

---

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md)
for the workflow, code style, and pull request process.

The short version:

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/my-feature`).
3. Make your changes. Keep the single-file structure of
   `Istar-Pack.ps1` intact.
4. Test on both PowerShell 5.1 and PowerShell 7 if possible.
5. Open a pull request with a clear description of what changed and
   why.

Bug reports and feature requests should be filed via the Issues tab.
Use the provided issue templates so we have the information needed
to reproduce or evaluate.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full version history.

---

## Project Layout

```
istar-pack/
├── Istar-Pack.ps1              # The single-file deliverable.
├── README.md                   # This document.
├── CHANGELOG.md                # Version history.
├── CONTRIBUTING.md             # How to contribute.
├── .gitignore                  # PowerShell / Windows gitignore.
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md       # Bug report template.
│   │   └── feature_request.md  # Feature request template.
│   └── workflows/
│       └── validate.yml        # CI: PowerShell syntax check on push.
└── docs/
    └── FILES.md                # Detailed repo layout reference.
```

See [docs/FILES.md](docs/FILES.md) for a description of every file
and folder in this repository.

---

## Disclaimer

This script modifies your PowerShell profile and installs third-party
software. While it backs up your existing profile before overwriting
it, you are responsible for reviewing the script before running it.
The maintainers are not liable for any data loss, system instability,
or other damage arising from the use of this software.

No license is currently attached to this repository. Until a license
is added, default copyright law applies: you may read and fork the
code for personal review, but redistribution or commercial use
requires explicit permission from the maintainer.
