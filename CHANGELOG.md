# Changelog

Progress log for the homelab AD DS build. Newest entries at the top.

Each entry is dated (`YYYY-MM-DD`) and grouped under the headings below, so the
history reads as a build journal rather than a software release log. Only include
the headings that apply to a given day.

- **Added** — new infrastructure, objects, scripts, or documentation
- **Changed** — reconfiguration of something that already existed
- **Fixed** — problems resolved (cross-reference [`docs/troubleshooting-log.md`](docs/troubleshooting-log.md))
- **Verified** — checks run to confirm a milestone actually works
- **Security** — credential handling and anything affecting what is safe to publish

<!--
TEMPLATE — copy this block, fill it in, and paste it directly beneath the
"---" separator below so the newest entry always sits at the top.

## YYYY-MM-DD

### Added
- ...

### Changed
- ...

### Fixed
- ...

### Verified
- ...
-->

---

## 2026-08-23

### Added
- Created three security groups in `corp.local`: `IT-Admins`, `HR-Staff`, and
  `VPN-Users`.
- Created 10 user accounts distributed across the `IT/Admins`, `IT/Helpdesk`, `HR`,
  `Finance`, and `Contractors` OUs.
- Left two accounts (`sjohnson`, `kpark`) intentionally disabled at creation, as
  fixtures for the account-lifecycle practice in the next phase.
- Added `scripts/new-users-and-groups.ps1`, the PowerShell provisioning script for
  the groups and accounts above, alongside the existing `new-ou-structure.ps1`.

### Changed
- Checked off group and user creation in the README milestone list, and listed the
  new script in the repository contents table.

### Security
- `new-users-and-groups.ps1` takes the initial account password as a mandatory
  `[SecureString]` parameter instead of a hardcoded literal, so no credential enters
  this public repository's history. Running the script with no arguments prompts for
  the value with masked input.

### Next
- Practice AD user lifecycle operations — password reset, unlock, enable/disable,
  and moving accounts between OUs — starting with `sjohnson` and `kpark`.
- Create the three GPOs: domain-linked password policy, idle screen lock on the user
  OUs, and USB storage block scoped to the `Contractors` OU.

---

## 2026-08-22

### Added
- Initialized the `homelab-ad-ds` repository to document the build as a portfolio
  project: `README.md`, `CHANGELOG.md`, `.gitignore`, `docs/troubleshooting-log.md`,
  and `scripts/new-ou-structure.ps1`.
- Documented the full environment: UTM on Apple Silicon running DC01 in x86_64
  **Emulate** mode, static IP `192.168.64.10` with self-hosted DNS, and the
  `corp.local` / `CORP` single-domain forest.
- Merged the existing build notes with additional entries into
  `docs/troubleshooting-log.md` — 13 documented issues spanning the wrong ISO
  download page, the ARM/x86 architecture conflict, VirtIO storage drivers, the
  post-install boot loop, the DSRM password complexity failure during
  `Install-ADDSForest`, and the post-promotion reboot dialogs.
- Added `scripts/new-ou-structure.ps1`, a PowerShell recreation of the OU hierarchy
  originally built by hand in ADUC.
- Added Issue 14 (`New-NetAddress` typo raising `CommandNotFoundException`), bringing
  the troubleshooting log to 14 documented issues.
- Added `docs/images/` with a manifest mapping nine build screenshots to their
  timestamps and the issues they evidence.

### Changed
- Corrected the root cause recorded for troubleshooting Issue 9 (missing default
  gateway) after cross-checking the build screenshots: the `-DefaultGateway`
  parameter was omitted from `New-NetIPAddress` as run, rather than being supplied
  and ignored. The `New-NetRoute` fix is unchanged.
- Annotated the static-IP command in the log's reference block so the omission that
  caused Issue 9 is visible at the point of use.

### Verified
- Build reached the **"OU structure created"** milestone: `IT` (with `Admins` and
  `Helpdesk` sub-OUs), `HR`, `Finance`, and `Contractors` all exist under
  `DC=corp,DC=local`.
- Domain controller promotion confirmed via `Get-ADDomain` and
  `Get-ADDomainController` — DC01.corp.local holds all five FSMO roles and is a
  Global Catalog server.

### Next
- Create 10+ user accounts across the OUs, then the `IT-Admins`, `HR-Staff`, and
  `VPN-Users` security groups.
