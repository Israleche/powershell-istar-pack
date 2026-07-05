# Changelog

All notable changes to Istar Pack are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2025-07-05

Initial public release.

### Added

- Single-file `Istar-Pack.ps1` script with 25 functional sections
  covering bootstrap, settings persistence, TUI rendering, environment
  checks, theme catalog, installation, and the main menu.
- Six built-in Oh My Posh v2 themes: Garden's Dream, Midnight Cyber,
  Sakura Bloom, Solar Flare, Mono Slate, Dracula Reborn.
- Theme-aware TUI: banner ASCII art, progress bar, and box accent
  colors follow the active theme.
- Differential redraw for arrow-key menu navigation: only the two
  changed rows are repainted per key press, eliminating full-screen
  flicker.
- Auto-growing console window on launch (targets 50 rows, capped at
  physical screen height) so tall screens like Verification and Theme
  Catalog fit without being cut off.
- Configuration stored at `$HOME\.istar-pack\settings.json` so settings
  survive re-downloads and script moves.
- Profile backups stored at `$HOME\.istar-pack\backups\` with timestamp
  and PowerShell edition in the file name.
- Cross-edition support: auto-detects PowerShell 5.1 vs 7+ and emits
  the correct profile (with `HistoryAndPlugin` and `` `e `` on PS 7,
  `History` and `[char]27` on PS 5.1).
- Silent mode (`-Silent`) for non-interactive installs.
- No-persist mode (`-NoPersist`) for ephemeral runs.
- Command-line overrides for `ShowProgress` and `DebugMode`.
- Verification screen with green / red status table for every tool,
  module, and file path.
- Settings menu to toggle progress, debug, Scoop install, module
  install, and font install flags.
- Backup menu to manually back up the current profile on demand.
- About screen documenting what the script fixes and crediting the
  upstream projects (Oh My Posh, Scoop, Zoxide, PSReadLine, FZF).
- UTF-8 with BOM file encoding for correct rendering on PowerShell 5.1.

### Fixed

- UpArrow / ListView prediction conflict in PSReadLine. The profile
  now binds `Ctrl+UpArrow` and `Ctrl+DownArrow` for prediction
  navigation, leaving UpArrow free for history.
- Missing `7z` dependency in the `extract` function. The profile
  verifies `7z` is on PATH before calling it, with `Expand-Archive`
  as a fallback for plain `.zip` files.
- False async claim about `oh-my-posh --shell`. The flag is dropped
  in favor of the synchronous initializer, which is more reliable
  on Windows.
- Deprecated `acrylicOpacity` field removed from any generated
  Windows Terminal snippets.
- Wrong PowerShell version requirement corrected. PS 7-only features
  are now guarded by an edition check, not a version gate.
- MaximumHistoryCount raised to 4096 with `HistoryNoDuplicates`
  enabled.
- Modules loaded inside `try/catch` blocks so a missing module never
  breaks the prompt.

### Known Limitations

- Windows-only. Scoop is not available on Linux or macOS.
- The Nerd Font is installed for the current user only. System-wide
  font installation would require elevation.
- The auto-grow console feature may not work on terminals that lock
  the window size (some Windows Terminal configurations). In those
  cases, a tall scrollback buffer is left in place so the user can
  scroll to see everything.
- Custom themes are not supported through the Istar Pack UI. Users
  who want a custom theme must manually replace the theme JSON file
  after running Istar Pack.
