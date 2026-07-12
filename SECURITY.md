# Security Policy

## Supported Versions

Istar Pack is a single-file PowerShell script. Only the latest released
version receives security updates. Older versions are supported on a
best-effort basis.

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |
| older   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in Istar Pack (for example, the
script writing unexpected files, executing untrusted commands, or failing to
respect its documented backup/rollback behavior), please **do not open a
public issue**.

Instead, report it privately:

- **GitHub Security Advisories:** use the
  [Report a vulnerability](https://github.com/Israleche/powershell-istar-pack/security/advisories/new)
  tab on the repository's Security page.
- **Email:** israleche@users.noreply.github.com

You can expect an acknowledgement within **72 hours**. Once the issue is
confirmed, we will work on a fix and coordinate a disclosure timeline with
you. Credit will be given in the fix unless you prefer to remain anonymous.

## Scope Notes

Istar Pack installs third-party software (Scoop, Oh My Posh, Zoxide, FZF,
7-Zip, Nerd Fonts) and modifies your PowerShell profile. Vulnerabilities in
those upstream projects should be reported to their respective maintainers;
this policy covers Istar Pack's own code only.
