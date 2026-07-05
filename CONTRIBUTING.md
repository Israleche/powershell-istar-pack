# Contributing to Istar Pack

First of all, thank you for taking the time to contribute. Istar Pack is a
small project, but every bug report, theme suggestion, and pull request
makes it better for the next person.

This document explains the workflow, code style, and review process so
that your contribution can be merged quickly.

---

## Table of Contents

1. [Project Philosophy](#project-philosophy)
2. [Ground Rules](#ground-rules)
3. [How to Report a Bug](#how-to-report-a-bug)
4. [How to Suggest a Feature](#how-to-suggest-a-feature)
5. [Development Setup](#development-setup)
6. [Code Style](#code-style)
7. [Testing Your Changes](#testing-your-changes)
8. [Pull Request Process](#pull-request-process)
9. [Adding a New Theme](#adding-a-new-theme)
10. [Maintainer Notes](#maintainer-notes)

---

## Project Philosophy

Istar Pack is intentionally a **single-file** script. The whole point is
that a user can download one `.ps1` file, run it, and be done. We will
resist any attempt to split the script into multiple modules, even when
the file gets long. If the file ever gets too long to maintain, the
answer is to refactor sections inside the file, not to split it.

The second principle is **cross-edition support**. Everything in the
script must work on both Windows PowerShell 5.1 and PowerShell 7+.
PS 7-only features are allowed, but they must be guarded by an edition
check so that PS 5.1 users get a graceful degraded experience, not a
crash.

The third principle is **no surprises**. The script should never
silently modify files outside the user's profile directory. Every
destructive action (overwriting the profile, deleting a backup) must be
preceded by a backup and explained to the user.

---

## Ground Rules

- Be respectful in issues and pull requests. Personal attacks will not
  be tolerated.
- Test your changes on both PowerShell 5.1 and PowerShell 7 if at all
  possible. If you can only test on one, say so in the PR description.
- Do not introduce dependencies on third-party modules that are not
  already in the install list. The script should remain self-contained.
- Do not add telemetry, analytics, or any kind of phone-home behavior.
  Istar Pack is private by design.
- Keep the UTF-8 with BOM encoding. Windows PowerShell 5.1 will
  mis-parse box-drawing characters without the BOM. Most text editors
  can preserve BOM if configured correctly.
- Do not add emojis to the script or to documentation files. The
  project style is plain text only.

---

## How to Report a Bug

Open a new issue using the **Bug report** template. The template will
ask you for:

- Your Windows version.
- Your PowerShell edition (`$PSVersionTable.PSVersion`).
- The exact Istar Pack version (shown in the banner).
- What you expected to happen.
- What actually happened.
- The full error message, if any.
- Whether you have run Istar Pack before on this machine.

The more of this information you provide upfront, the faster we can
reproduce and fix the issue. Screenshots are welcome if they help
illustrate the problem.

Before filing, please search the existing issues to avoid duplicates.
If you find an issue that matches yours, add a thumbs-up reaction and
a comment with any additional context, rather than opening a new one.

---

## How to Suggest a Feature

Open a new issue using the **Feature request** template. Explain:

- The problem you are trying to solve.
- How you currently solve it (or fail to).
- Your proposed solution.
- Any alternatives you have considered.

Feature requests are evaluated against the project philosophy above.
A feature that requires splitting the script into multiple files, or
that only works on one PowerShell edition without a graceful
fallback, is unlikely to be accepted.

---

## Development Setup

You do not need any special tooling to develop Istar Pack. A Windows
machine with both PowerShell 5.1 and PowerShell 7 installed is ideal,
but you can develop with only one edition and rely on the CI workflow
to catch edition-specific issues.

To set up a local clone:

```powershell
git clone https://github.com/<your-fork>/istar-pack.git
cd istar-pack
```

Open `Istar-Pack.ps1` in your editor of choice. Visual Studio Code with
the PowerShell extension is recommended for syntax highlighting and
inline parsing, but any text editor that preserves UTF-8 with BOM will
work.

To run the script in test mode (define all functions but do not enter
the menu loop):

```powershell
$env:ISTAR_TEST_MODE = '1'
.\Istar-Pack.ps1
$env:ISTAR_TEST_MODE = ''
```

This is useful for inspecting function definitions or running individual
functions by hand without triggering the full TUI.

---

## Code Style

- Use PascalCase for function names: `Install-ScoopIfNeeded`, not
  `install-scoop-if-needed`.
- Use camelCase for local variables: `$themeKey`, not `$ThemeKey`.
- Use `$Script:` scope for script-wide variables: `$Script:Settings`,
  `$Script:Palette`.
- Use full parameter names in `param()` blocks. Always include
  `[CmdletBinding()]`.
- Use here-strings (`@'...'@` for literal, `@"..."@` for interpolated)
  for any multi-line string. Make sure the closing `'@` or `"@` is at
  column 0.
- Use `[Console]::Write*` for low-level TUI work where you need
  cursor control. Use `Write-Host` for normal output.
- Comment every function with a `<#.SYNOPSIS ... #>` block. Document
  parameters and return values where they are not obvious.
- Keep functions under 80 lines where possible. If a function grows
  longer, look for a natural split point.
- Indent with 4 spaces. Do not use tabs.
- Limit lines to 120 characters where possible. The box-drawing helper
  functions are exempt from this rule because they construct long
  strings by design.

---

## Testing Your Changes

There is no automated test suite yet. For now, manual testing is the
expected workflow:

1. Run `.\Istar-Pack.ps1` and walk through every menu option. Verify
   each one works.
2. Run `.\Istar-Pack.ps1 -Silent` and verify the install completes
   without prompts.
3. Run `.\Istar-Pack.ps1 -NoPersist` and verify settings are not
   loaded or saved.
4. Delete `$HOME\.istar-pack\settings.json` and re-run the script.
   Verify it starts with defaults.
5. Run the script a second time immediately after a successful Full
   install. Verify it skips already-installed components.
6. Test on both PowerShell 5.1 and PowerShell 7 if possible.

If your change adds or modifies a theme, also verify:

- The theme JSON is valid (use `ConvertFrom-Json` on the here-string
  content).
- The theme renders correctly in Oh My Posh after install.
- The theme's accent color propagates to the Istar Pack TUI when
  selected.

---

## Pull Request Process

1. Fork the repository and create a feature branch:
   ```powershell
   git checkout -b feature/my-feature
   ```
2. Make your changes. Commit with clear, descriptive messages:
   ```
   Add Midnight Cyber theme with cyan accent
   Fix UpArrow conflict in PS5 prediction view
   Refactor Write-BoxLine to handle multi-byte chars
   ```
3. Push to your fork and open a pull request against `main`.
4. In the PR description, explain:
   - What changed and why.
   - How you tested.
   - Any known limitations or follow-up work.
5. The CI workflow will run a PowerShell syntax check. If it fails,
  fix the issue and push again.
6. A maintainer will review your PR. Be prepared to address feedback
  or make revisions.

Small, focused PRs are easier to review and merge faster. If you have
several unrelated changes, open separate PRs for each.

---

## Adding a New Theme

Themes are defined in the `$Script:Themes`, `$Script:ThemeDescriptions`,
and `$Script:ThemeAccents` hashtables, plus a `Get-ThemeJson` switch
case that returns the Oh My Posh v2 JSON. To add a new theme:

1. Pick a key. Use PascalCase with no spaces: `AuroraBorealis`, not
   `aurora borealis` or `Aurora Borealis`.
2. Pick a display name. This is what users see in the menu.
3. Write the Oh My Posh v2 JSON. Start from an existing theme and
  modify the colors and segments. Validate the JSON with
  `ConvertFrom-Json`.
4. Pick an accent color for the Istar Pack TUI. Use one of the
  standard PowerShell color names: `Black`, `DarkBlue`, `DarkGreen`,
  `DarkCyan`, `DarkRed`, `DarkMagenta`, `DarkYellow`, `Gray`,
  `DarkGray`, `Blue`, `Green`, `Cyan`, `Red`, `Magenta`, `Yellow`,
  `White`.
5. Add the theme to all three hashtables and add a `switch` case in
  `Get-ThemeJson` that returns the JSON string via a `@'...'@`
  here-string.
6. Test by selecting the new theme in the Istar Pack UI and verifying
  both the TUI and the installed Oh My Posh prompt render correctly.

---

## Maintainer Notes

Maintainers should:

- Triage new issues within a week.
- Label issues with `bug`, `feature`, `theme`, `question`, or
  `wontfix` as appropriate.
- Close stale issues after 30 days of inactivity.
- Ensure the CI workflow passes before merging any PR.
- Update `CHANGELOG.md` for every merged PR that changes behavior.
- Tag releases with semantic versioning: `v1.0.0`, `v1.0.1`,
  `v1.1.0`, etc.
- Never force-push to `main`.

When releasing a new version:

1. Update `$Script:AppVersion` in `Istar-Pack.ps1`.
2. Add a `CHANGELOG.md` entry under a new version heading.
3. Tag the commit: `git tag v1.x.y && git push --tags`.
4. Create a GitHub Release with the changelog entry as the body and
  attach the `.ps1` file as a release artifact.
