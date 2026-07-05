# Repository File Reference

This document describes every file and folder in the Istar Pack
repository. If you are new to the project, read this first.

---

## Top-Level Files

### `Istar-Pack.ps1`

The single deliverable. This is the file users download and run. It
contains every function, theme definition, and the entry point. The
file is encoded as UTF-8 with BOM so that Windows PowerShell 5.1 can
parse the box-drawing characters correctly.

Internally the script is organized into 25 numbered sections:

| Section | Purpose                                                  |
|---------|----------------------------------------------------------|
| 1       | Bootstrap: encoding, error preferences, version detect.  |
| 2       | Metadata and paths (app name, version, config location). |
| 3       | Settings JSON persistence (load and save).               |
| 4       | Color palette and box-drawing glyph definitions.         |
| 5       | Inline status markers (`Write-Step`, `Write-Ok`, etc.).  |
| 6       | Box rendering (top, line, separator, subtitle, bottom).  |
| 7       | Progress bar (four styles).                              |
| 8       | Spinner (synchronous, repaint-in-place).                 |
| 9       | Input helpers (yes/no, any key, menu selection).         |
| 10      | Banner (6-line ASCII art, fade-in).                      |
| 11      | Environment checks (admin, command, module availability).|
| 12      | Theme catalog (six themes, accent colors, JSON getter).  |
| 13      | Scoop install helpers.                                   |
| 14      | Scoop bucket and package installers.                     |
| 15      | Nerd Font installer.                                     |
| 16      | PowerShell module installer.                             |
| 17      | Profile content generator (PS 5.1 vs PS 7 branches).     |
| 18      | Full install orchestrator (seven steps).                 |
| 19      | Theme browser and theme selector.                        |
| 20      | Verification screen.                                     |
| 21      | Backup menu.                                             |
| 22      | Settings menu.                                           |
| 23      | About screen.                                            |
| 24      | Main menu loop.                                          |
| 25      | Entry point (`Start-App`) and global try/catch.           |

### `README.md`

The user-facing documentation. New visitors to the repository should
be able to read the README and know what the project does, how to
install it, and how to use it, without needing to open any other
file.

### `CHANGELOG.md`

Version history. Every merged pull request that changes user-visible
behavior must add an entry under a version heading. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

### `CONTRIBUTING.md`

Instructions for contributors. Covers the project philosophy, ground
rules, bug reporting, pull request process, and how to add a new
theme.

### `.gitignore`

Standard PowerShell and Windows gitignore, plus Istar Pack runtime
artifacts (`.istar-pack/`, `Istar-Pack-Backups/`) so that local
testing does not pollute the repository.

---

## `.github/` Directory

### `.github/ISSUE_TEMPLATE/bug_report.md`

Template for bug reports. Asks the user for Windows version,
PowerShell version, Istar Pack version, the menu option they
selected, and the full error message. Using the template ensures
we have enough information to reproduce the issue.

### `.github/ISSUE_TEMPLATE/feature_request.md`

Template for feature requests. Asks the user for the problem they
are trying to solve, their proposed solution, alternatives they have
considered, and the scope of the change.

### `.github/workflows/validate.yml`

Continuous integration workflow that runs on every push and pull
request. It does three things:

1. Parses `Istar-Pack.ps1` with the official PowerShell parser on
   PowerShell 7 (pwsh shell). Fails the build if any syntax errors
   are found.
2. Parses the same file on Windows PowerShell 5.1 (powershell shell).
   This catches edition-specific issues that the PS 7 parser might
   tolerate.
3. Verifies the file starts with the UTF-8 BOM bytes (`EF BB BF`).
   This is critical because PS 5.1 will mis-parse box-drawing
   characters without the BOM.

The workflow runs on `windows-latest` (for the PowerShell checks)
and `ubuntu-latest` (for the encoding check). Total runtime is
typically under two minutes.

---

## `docs/` Directory

### `docs/FILES.md`

This file. A reference for new contributors and maintainers.

---

## Files That Should Never Be Committed

The following are runtime artifacts generated on the user's machine.
They are listed in `.gitignore` and should never appear in the
repository:

- `$HOME\.istar-pack\settings.json` - per-user settings.
- `$HOME\.istar-pack\backups\` - per-user profile backups.
- `Istar-Pack-Backups\` - legacy backup location (pre-1.0.0).
- `*.ps1.bak`, `*.ps1.old` - editor backup files.
- `TestResults\`, `*.trx` - Pester test output (if added later).

If you see any of these in a pull request, the contributor has
accidentally committed local testing state. Ask them to remove the
files and re-push.
