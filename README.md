# Homelab Active Directory Domain Services (AD DS) Deployment

A Windows Server domain controller running Active Directory Domain Services, built
from scratch in a homelab environment on Apple Silicon, to convert a resume gap
("no AD experience") into a demonstrable, documented project.

This simulates the core infrastructure a junior sysadmin or IT ops engineer would
manage in a real small-to-mid-size organization: a domain, organizational units,
users, groups, and Group Policy.

---

## Contents

| Path | What's in it |
|---|---|
| [`README.md`](README.md) | This file — build overview, specs, and current status |
| [`CHANGELOG.md`](CHANGELOG.md) | Dated, reverse-chronological log of project progress |
| [`docs/troubleshooting-log.md`](docs/troubleshooting-log.md) | Every issue hit during the build, with root cause and resolution |
| [`scripts/new-ou-structure.ps1`](scripts/new-ou-structure.ps1) | PowerShell recreation of the OU hierarchy |
| [`scripts/new-users-and-groups.ps1`](scripts/new-users-and-groups.ps1) | PowerShell provisioning of the security groups and user accounts |

---

## Environment / Hypervisor

- **Host:** MacBook Pro, Apple Silicon (M-series)
- **Hypervisor:** UTM ([utm.app](https://mac.getutm.app/)) — not VirtualBox, since
  VirtualBox's ARM support is experimental/unreliable.
- **Mode:** Emulate (x86_64 via QEMU), **not** Virtualize — necessary because the
  only available Windows Server ISO (Microsoft Insider Program) is x86_64, while
  Apple Silicon is natively ARM64. This trades performance for compatibility.

---

## VM Specifications — DC01

| Setting | Value |
|---|---|
| Name | DC01 |
| UTM mode | Emulate |
| Machine type | Standard PC (Q35 + ICH9, 2009) x86_64 |
| RAM | 4 GB |
| CPU cores | 2 |
| Disk | 60 GB (qcow2) |
| Network | Shared Network / e1000 (UTM NAT via Mac) |
| OS | Windows Server VNext Preview (Insider Program), reporting internally as Windows Server 2025 Standard |

---

## Network Configuration

| Setting | Value |
|---|---|
| IPv4 address | 192.168.64.10 (static) |
| Subnet mask | 255.255.255.0 |
| Default gateway | 192.168.64.1 |
| DNS server | 192.168.64.10 (self-hosted — required for AD DS) |
| DHCP | Disabled |

---

## Domain Details (post-promotion)

| Setting | Value |
|---|---|
| Domain (FQDN) | corp.local |
| NetBIOS name | CORP |
| Domain functional level | Windows2028Domain |
| Forest | corp.local (single-domain forest) |
| Domain controller | DC01.corp.local, holds all 5 FSMO roles (single-DC lab) |
| Global Catalog | Yes |
| LDAP / LDAPS ports | 389 / 636 |

---

## Milestones Completed

- [x] UTM installed and configured
- [x] Windows Server VNext Preview installed via x86 emulation
- [x] VirtIO drivers loaded during install (UTM Guest Tools CD)
- [x] UTM Guest Tools (SPICE) installed — clipboard/display integration working
- [x] Boot loop fixed (cleared mounted ISO paths post-install)
- [x] Static IP, self-hosted DNS, and default gateway configured
- [x] Server renamed to DC01
- [x] AD DS role installed (`Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools`)
- [x] Promoted to domain controller for a new forest (`Install-ADDSForest`) — domain `corp.local`, NetBIOS `CORP`
- [x] Promotion verified via `Get-ADDomain` and `Get-ADDomainController`
- [x] OU structure created: `IT` (with `Admins` and `Helpdesk` sub-OUs), `HR`, `Finance`, `Contractors`, and `Disabled Accounts` (created later at the **domain root**, during the account-lifecycle practice below)
- [x] Security groups created: `IT-Admins`, `HR-Staff`, `VPN-Users`
- [x] 10 user accounts created and distributed across the `IT/Admins`, `IT/Helpdesk`, `HR`, `Finance`, and `Contractors` OUs — two (`sjohnson`, `kpark`) intentionally left disabled as fixtures for account-lifecycle practice
- [x] User placement and group membership verified via `Get-ADUser` and `Get-ADGroupMember`
- [x] Three GPOs created and linked in GPMC:
  - **Password Policy** — 12-character minimum, complexity enabled, 90-day maximum age — linked at the **domain root**
  - **Screen Lock Policy** — `Interactive logon: Machine inactivity limit` = 600s — linked to `IT`, `HR`, `Finance`, `Contractors`
  - **USB Block Policy** — Removable Storage Access denied — linked to `Contractors` **only**
- [x] GPO application verified on DC01 with `gpresult /r`
- [x] Windows 11 ARM64 client (`WIN-NSHG0FCOL9Q`) built in UTM **Virtualize** mode, with the NIC set to `virtio-net-pci` before install
- [x] Client network adapter working — Red Hat VirtIO Ethernet Adapter bound automatically by UTM Guest Tools
- [x] Client DNS pointed at DC01 (`192.168.64.10`) — required disabling IPv6 on the adapter to stop an auto-discovered IPv6 resolver from answering first
- [x] **`WIN-NSHG0FCOL9Q` joined to `corp.local`** via `Add-Computer`, verified end to end: `whoami` returns `corp\administrator`, `(Get-WmiObject Win32_ComputerSystem).Domain` returns `corp.local`, and `.PartOfDomain` returns `True`
- [x] **GPO application verified on the Windows 11 client** with `gpresult /r` — this first required **moving the client's computer object out of the default `Computers` container into the `Contractors` OU**: newly joined machines land in `Computers`, which is a container rather than an OU, so GPOs linked to specific OUs never reach it. After the move, both **Screen Lock Policy** and **USB Block Policy** appeared under *Applied Group Policy Objects* alongside the domain-root-linked policies
- [x] **AD user lifecycle operations practiced** on the two fixture accounts:
  - **`sjohnson`** — password reset with `Set-ADAccountPassword -Reset` (the administrative reset path, which requires no knowledge of the old password), flagged for a mandatory change at next logon with `-ChangePasswordAtLogon $true`, then re-enabled with `Enable-ADAccount`
  - **`kpark`** — moved into a newly created **`Disabled Accounts`** OU and confirmed disabled with `Disable-ADAccount`, simulating an offboarding/archival workflow

> **Note on the client hostname.** `WIN-NSHG0FCOL9Q` is the name Windows generated
> automatically during installation — it is the machine's real hostname, not a chosen
> one. Renaming it to `WIN11-CLIENT01` to match this document's original naming was
> attempted and then **deliberately abandoned**: the attempt surfaced an orphaned AD
> computer object flagged internally as a domain controller account, left behind by an
> earlier abandoned build of this VM, and safely clearing it would have meant
> `ntdsutil` metadata cleanup or direct `userAccountControl` edits — more risk than a
> cosmetic hostname mismatch justified. Full write-up in
> [Issue 28](docs/troubleshooting-log.md) of the troubleshooting log.

## In Progress / Next Steps

No open items — both previously tracked steps (client-side GPO verification and AD user
lifecycle practice) are complete and now recorded under *Milestones Completed* above.

---

## Resume Bullets (drafted from this project)

- "Deployed Windows Server domain controller in UTM homelab on Apple Silicon; built
  OU hierarchy, configured Group Policy Objects for password enforcement and device
  restrictions, and joined a Windows 11 ARM client to the domain."
- "Managed Active Directory user lifecycle — provisioning, group membership, account
  lockout resolution, and OU-based access delegation across a simulated department
  structure."

---

## Why This Project Exists

Built as part of a structured transition into IT/sysadmin roles (junior sysadmin, IT
operations, cloud support, NOC), alongside CompTIA cert prep, to close a hands-on AD
experience gap with a fully documented, reproducible build.
