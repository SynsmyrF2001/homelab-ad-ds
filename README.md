# Homelab Active Directory Domain Services (AD DS) Deployment

A Windows Server domain controller running Active Directory Domain Services, built
from scratch in a homelab environment on Apple Silicon, to convert a resume gap
("no AD experience") into a demonstrable, documented project.

This simulates the core infrastructure a junior sysadmin or IT ops engineer would
manage in a real small-to-mid-size organization: a domain, organizational units,
users, groups, and Group Policy.

> **State last verified against the live domain: 2026-09-30.** See
> [Verified state](#verified-state-2026-09-30) for what was checked.
> Earlier revisions of this README called the domain controller `DC01`. That is only
> the UTM VM name; the Windows hostname is `WIN11-CLIENT01`. See [Naming](#naming).

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

## VM Specifications — Domain Controller

| Setting | Value |
|---|---|
| UTM VM name | DC01 |
| Windows computer name | WIN11-CLIENT01 |
| UTM mode | Emulate |
| Machine type | Standard PC (Q35 + ICH9, 2009) x86_64 |
| RAM | 4 GB |
| CPU cores | 2 |
| Disk | 60 GB (qcow2) |
| Network | Shared Network / e1000 (UTM NAT via Mac) |
| OS | Windows Server VNext Preview (Insider Program), reporting internally as Windows Server 2025 Standard (build 10.0.29641) |

### Naming

| Object | Name |
|---|---|
| UTM VM | `DC01` |
| Domain controller (Windows hostname and AD computer account) | `WIN11-CLIENT01` (FQDN `WIN11-CLIENT01.corp.local`) |
| Windows 11 client (AD computer account) | `WIN-NSHG0FCOL9Q` (default generated name) |

An earlier revision of this README listed the milestone "Server renamed to DC01" and
named the controller `DC01.corp.local`. Live checks on 2026-09-30 found no `DC01`
computer object in AD and the controller reporting `WIN11-CLIENT01`, so that was
incorrect. The hostname has not been changed: renaming a domain controller is a
multi-step operation (DNS records, service principal names) with no benefit for this lab.

---

## Network Configuration

| Setting | Value |
|---|---|
| IPv4 address | 192.168.64.10 (static) |
| Subnet mask | 255.255.255.0 |
| Default gateway | 192.168.64.1 |
| DNS server (DC's NIC) | 127.0.0.1 (the DC's own DNS server — required for AD DS) |
| DHCP | Disabled |

---

## Domain Details (post-promotion)

| Setting | Value |
|---|---|
| Domain (FQDN) | corp.local |
| NetBIOS name | CORP |
| Domain functional level | Windows2028Domain |
| Forest | corp.local (single-domain forest) |
| Domain controller | WIN11-CLIENT01.corp.local — the only DC, so it holds all 5 FSMO roles (single-DC lab) |
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
- [x] AD DS role installed (`Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools`)
- [x] Promoted to domain controller for a new forest (`Install-ADDSForest`) — domain `corp.local`, NetBIOS `CORP`
- [x] Promotion verified via `Get-ADDomain` and `Get-ADDomainController`
- [x] OU structure created: `IT` (with `Admins` and `Helpdesk` sub-OUs), `HR`, `Finance`, `Contractors`, and `Disabled Accounts` (created later at the **domain root**, during the account-lifecycle practice below)
- [x] Security groups created: `IT-Admins`, `HR-Staff`, `VPN-Users`
- [x] 10 user accounts created and distributed across the `IT/Admins`, `IT/Helpdesk`, `HR`, `Finance`, and `Contractors` OUs — two (`sjohnson`, `kpark`) intentionally left disabled as fixtures for account-lifecycle practice. Two further accounts (`amartinez`, `jlee2`) exist beyond the original ten
- [x] User placement and group membership verified via `Get-ADUser` and `Get-ADGroupMember`
- [x] Three GPOs created and linked in GPMC:
  - **Password Policy** — 12-character minimum, complexity enabled, 90-day maximum age — linked at the **domain root**
  - **Screen Lock Policy** — `Interactive logon: Machine inactivity limit` = 600s — linked to `IT`, `HR`, `Finance`, `Contractors`
  - **USB Block Policy** — Removable Storage Access denied — linked to `Contractors` **only**
- [x] GPO application verified on the domain controller with `gpresult /r`
- [x] Windows 11 ARM64 client (`WIN-NSHG0FCOL9Q`, Windows 11 Pro) built in UTM **Virtualize** mode, with the NIC set to `virtio-net-pci` before install
- [x] Client network adapter working — Red Hat VirtIO Ethernet Adapter bound automatically by UTM Guest Tools
- [x] Client DNS pointed at the domain controller (`192.168.64.10`) — required disabling IPv6 on the adapter to stop an auto-discovered IPv6 resolver from answering first
- [x] **`WIN-NSHG0FCOL9Q` joined to `corp.local`** via `Add-Computer`, verified end to end: `whoami` returns `corp\administrator`, `(Get-WmiObject Win32_ComputerSystem).Domain` returns `corp.local`, and `.PartOfDomain` returns `True`
- [x] **GPO application verified on the Windows 11 client** with `gpresult /r` — this first required **moving the client's computer object out of the default `Computers` container into the `Contractors` OU**: newly joined machines land in `Computers`, which is a container rather than an OU, so GPOs linked to specific OUs never reach it. After the move, both **Screen Lock Policy** and **USB Block Policy** appeared under *Applied Group Policy Objects* alongside the domain-root-linked policies
- [x] **AD user lifecycle operations practiced** on the two fixture accounts:
  - **`sjohnson`** — password reset with `Set-ADAccountPassword -Reset` (the administrative reset path, which requires no knowledge of the old password), flagged for a mandatory change at next logon with `-ChangePasswordAtLogon $true`, then re-enabled with `Enable-ADAccount`
  - **`kpark`** — moved into a newly created **`Disabled Accounts`** OU and confirmed disabled with `Disable-ADAccount`, simulating an offboarding/archival workflow
- [x] **OU-scoped administrative control delegated to `IT-Admins`** through the Delegation
  of Control Wizard — *Create, delete, and manage user accounts* over the `HR`, `Finance`,
  `Contractors`, and `IT/Helpdesk` OUs, **deliberately excluding `IT/Admins`** so that a
  helpdesk-tier grant can never reach the accounts of higher-privileged admins. Verified
  end to end using an explicit `-Credential` object for `jsmith` (a member of `IT-Admins`):
  a password reset against `edavis`, in the delegated `HR` OU, **succeeded**, while an
  identical reset against `mgarcia`, in the excluded `IT/Admins` OU, **failed** with
  `UnauthorizedAccessException: Access is denied` — proving the delegation boundary is
  actually enforced, not merely present

> **Note on the client hostname.** `WIN-NSHG0FCOL9Q` is the name Windows generated
> automatically during installation — it is the machine's real hostname, not a chosen
> one. Renaming it to `WIN11-CLIENT01` was attempted and then **deliberately abandoned**
> because that name was already taken by a computer object flagged as a domain
> controller account ([Issue 28](docs/troubleshooting-log.md)). Issue 28 records that
> object as an orphan left by an earlier abandoned VM build, but the 2026-09-30 checks
> show `WIN11-CLIENT01` is the **live domain controller's own** computer account: the
> only DC in the domain and the holder of every FSMO role. The name clash was real; the
> "orphan" diagnosis was not. Issue 28 now carries a correction.

## Known Issues

- **Domain controller's computer account is in the wrong container.** It sits in the default
  `CN=Computers` container instead of `OU=Domain Controllers`, so `dcdiag /test:machineaccount`
  fails and the Default Domain Controllers Policy is not applying to it. Found 2026-09-30;
  fix in progress ([Issue 33](docs/troubleshooting-log.md)).
- **`dcdiag` SystemLog test fails** on recent error events (an unclean shutdown, an Azure Arc
  Proxy service timeout, and others). Under review.

## In Progress / Next Steps

- [ ] Move the domain controller's computer account into `OU=Domain Controllers` and re-run `dcdiag`
- [ ] Confirm the screen lock and USB restrictions actually take effect on the client, beyond
  `gpresult /r` listing them as applied
- [ ] Extend to Azure and Microsoft Entra ID — tracked in a separate repo, `hybrid-identity-lab` (link once published)

---

## Verified State (2026-09-30)

Checked with PowerShell on the domain controller.

| Check | Result |
|---|---|
| Windows computer name | `WIN11-CLIENT01` |
| Domain controllers in the domain | 1 (`WIN11-CLIENT01.corp.local`, 192.168.64.10) |
| Domain functional level | Windows2028Domain |
| FSMO roles (schema, domain naming, PDC) | All on `WIN11-CLIENT01.corp.local` |
| DC computer account location | `CN=Computers,DC=corp,DC=local` (expected `OU=Domain Controllers`; see Known Issues) |
| Computer accounts in AD | 2: the DC, and `WIN-NSHG0FCOL9Q` (Windows 11 Pro, `OU=Contractors`) |
| User accounts | 15 total: 3 built-in, the original 10, plus `amartinez` and `jlee2` |
| Disabled non-built-in users | `kpark` (`sjohnson` was re-enabled during lifecycle practice) |
| DNS client setting on the DC | 127.0.0.1 |

---

## Resume Bullets (drafted from this project)

- "Deployed Windows Server domain controller in UTM homelab on Apple Silicon; built
  OU hierarchy, configured Group Policy Objects for password enforcement and device
  restrictions, and joined a Windows 11 ARM client to the domain."
- *Draft, finalize later:* "Managed Active Directory user lifecycle — provisioning, group
  membership, account lockout resolution, and OU-based access delegation across a simulated
  department structure." Account lockout resolution is not yet recorded as completed above;
  drop it from the bullet or complete it before using this on a resume.

---

## Why This Project Exists

Built as part of a structured transition into IT/sysadmin roles (junior sysadmin, IT
operations, cloud support, NOC), alongside CompTIA cert prep, to close a hands-on AD
experience gap with a fully documented, reproducible build.
