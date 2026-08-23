# Changelog

Progress log for the homelab AD DS build. Newest entries at the top.

Each entry is dated (`YYYY-MM-DD`) and grouped under the headings below, so the
history reads as a build journal rather than a software release log. Only include
the headings that apply to a given day.

- **Added** — new infrastructure, objects, scripts, or documentation
- **Changed** — reconfiguration of something that already existed
- **Fixed** — problems resolved (cross-reference [`docs/troubleshooting-log.md`](docs/troubleshooting-log.md))
- **Verified** — checks run to confirm a milestone actually works

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

## 2026-08-22

### Added
- Initialized the `homelab-ad-ds` repository to document the build as a portfolio
  project: `README.md`, `CHANGELOG.md`, `.gitignore`, `docs/troubleshooting-log.md`,
  and `scripts/new-ou-structure.ps1`.
- Documented the full environment: UTM on Apple Silicon running DC01 in x86_64
  **Emulate** mode, static IP `192.168.64.10` with self-hosted DNS, and the
  `corp.local` / `CORP` single-domain forest.
- Recorded seven build issues and their resolutions in the troubleshooting log,
  covering the post-install boot loop, the DSRM password complexity failure during
  `Install-ADDSForest`, and the post-promotion reboot dialogs.
- Added `scripts/new-ou-structure.ps1`, a PowerShell recreation of the OU hierarchy
  originally built by hand in ADUC.

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
