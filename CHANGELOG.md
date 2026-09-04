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

## 2026-09-04

**Delegation of control, and proof that the boundary holds.** `IT-Admins` now has
OU-scoped administrative rights over the departmental OUs — and demonstrably *cannot*
touch the admin OU that was deliberately left out. Reaching a clean result took working
through four real issues, all now written up in the troubleshooting log.

### Added
- **OU-scoped delegation of control to `IT-Admins`**, granted through the Delegation of
  Control Wizard: *Create, delete, and manage user accounts* over the `HR`, `Finance`,
  `Contractors`, and `IT/Helpdesk` OUs. **`IT/Admins` was excluded on purpose** — a
  helpdesk-tier grant that could manage higher-privileged admin accounts is a
  privilege-escalation path, not a convenience.

### Verified
- **The delegation boundary is enforced, not just configured**, confirmed with a real
  allow/deny test pair run as `jsmith` (a member of `IT-Admins`) via an explicit
  `-Credential` object:
  - **Allow** — password reset against `edavis`, in the delegated `HR` OU: **succeeded**.
  - **Deny** — the identical reset against `mgarcia`, in the excluded `IT/Admins` OU:
    **failed** with `UnauthorizedAccessException: Access is denied`.

### Fixed
- Four issues stood between the delegation being configured and being *trustworthily*
  verified — see [`docs/troubleshooting-log.md`](docs/troubleshooting-log.md),
  Issues 29–32:
  - **RSAT never actually installed on the client** (Issue 29). `Add-WindowsCapability`
    reported success while the capability's real state was `NotPresent` with a 0-byte
    download — the Feature-on-Demand package is not published for this ARM64 Insider
    build. Verification moved to DC01, which has the tooling natively.
  - **`runas /netonly` silently never took effect** (Issue 30). The shell kept running as
    Administrator, so an excluded-OU reset "passed" — a false result that invalidated a
    whole round of testing. Replaced with a per-cmdlet `-Credential` object.
  - **A self-referential test proved nothing** (Issue 31). `jsmith` resetting `jsmith`'s
    own password exercises the built-in `SELF` *Change Password* right, not the OU
    delegation. Re-run against a different account in the excluded OU.
  - **A multi-line paste was swallowed by a masked prompt** (Issue 32). Once
    `Read-Host -AsSecureString` was reading, the rest of the pasted script was absorbed as
    literal password input and never ran. Interactive prompts now get one line at a time.

### Changed
- `README.md` — delegation of control added to *Milestones Completed*, including the
  excluded OU and the allow/deny verification result.

---

## 2026-09-03

**Both remaining open items are done.** The Screen Lock and USB Block GPOs are confirmed
applying on the Windows 11 client, and the AD user lifecycle drills are complete. The
README's *In Progress / Next Steps* list is now empty.

### Verified
- **Screen Lock Policy and USB Block Policy apply on the client**, confirmed with
  `gpresult /r` — both now listed under *Applied Group Policy Objects* alongside the
  domain-root-linked policies. This closes the gap noted previously: both GPOs target
  workstations, so verifying them on DC01 alone proved nothing about the client.
- **The domain Password Policy GPO is enforced on administrative resets, not just
  user-initiated changes.** Setting a short password through `Set-ADAccountPassword -Reset`
  was rejected until it met the 12-character minimum and complexity requirement — useful
  to know, since it is easy to assume an admin reset bypasses domain policy.

### Fixed
- **Client computer object was in the wrong place to receive OU-linked policy.** After the
  domain join the client landed in the default `Computers` container, which is a container
  rather than an OU — so the Screen Lock and USB Block GPOs, both linked to specific OUs,
  never reached it. Moving the computer object into the `Contractors` OU resolved it, and
  the policies applied on the next refresh.

### Added
- **`Disabled Accounts` OU**, created at the domain root as the archival target for
  offboarded accounts.
- **AD user lifecycle practice completed** against the two fixture accounts:
  - `sjohnson` — password reset via `Set-ADAccountPassword -Reset` (the admin path, which
    needs no prior password), flagged for a mandatory change at next logon with
    `-ChangePasswordAtLogon $true`, then re-enabled with `Enable-ADAccount`.
  - `kpark` — moved into the new `Disabled Accounts` OU and confirmed disabled with
    `Disable-ADAccount`, simulating an offboarding/archival workflow.

### Changed
- `README.md` — the two completed items moved from *In Progress / Next Steps* into
  *Milestones Completed*, and the OU structure line now includes `Disabled Accounts`,
  which did not exist when that line was first written.

---

## 2026-09-03

**The client keeps its real hostname.** An attempt to rename the domain-joined client
from its Windows-assigned name to `WIN11-CLIENT01`, purely to match the documentation,
uncovered stale directory metadata from an earlier abandoned VM build. The rename was
deliberately abandoned and the documentation was corrected to match the machine instead.

### Changed
- **`README.md` now uses the client's actual hostname, `WIN-NSHG0FCOL9Q`, throughout** —
  VM description, milestone checklist, and the pending client-side GPO verification step.
  The docs previously referred to the client as `WIN11-CLIENT01`, which was the intended
  name, never the real one.
- Added a note beside the client's details in `README.md` recording that
  `WIN-NSHG0FCOL9Q` is the Windows-generated default rather than a chosen name, and that
  renaming it was attempted and abandoned on purpose.

### Added
- **Troubleshooting log Issue 28** — the full write-up of the rename attempt, the
  orphaned AD object it exposed, and the reasoning behind stopping.

### Decisions
- **Abandoned the client rename.** `Rename-Computer` failed with "The account already
  exists"; the blocking object turned out to be an orphaned `WIN11-CLIENT01` account
  flagged internally as a **domain controller**, sitting in the Domain Controllers OU
  with a creation date from the original pre-rebuild client VM — left behind when that
  build was promoted (or partially promoted) as a second DC before being scrapped during
  the Issue 19–23 network/boot failures. Neither `Remove-ADComputer` nor ADUC would
  delete it, since it was never a properly promoted, demotable DC.
- **Did not pursue `ntdsutil` metadata cleanup or a direct `userAccountControl` edit.**
  Both would likely have worked, but editing forest metadata to fix a cosmetic naming
  mismatch is a poor risk trade in a working single-DC forest.
- The orphaned `WIN11-CLIENT01` object stays in AD as a **known, documented artifact** —
  no privileges, no replication role, no effect on DC01's FSMO roles.

**Step 5 is complete.** `WIN11-CLIENT01` is joined to the `corp.local` domain and
verified end to end — DNS resolution, machine trust, and domain-credential login all
confirmed working.

### Fixed
- **IPv6 DNS conflict (Issue 25).** After pointing the client's DNS at DC01,
  `nslookup corp.local` still returned "Non-existent domain" — because the query was
  going to a link-local IPv6 resolver (`fe80::...`), not to `192.168.64.10`.
  `Set-DnsClientServerAddress` manages only the IPv4 DNS list, while UTM's virtual
  network advertises an IPv6 DNS server via Router Advertisement RDNSS that Windows
  learns automatically and prefers. Resolved with
  `Disable-NetAdapterBinding -InterfaceAlias "Ethernet" -ComponentID ms_tcpip6`,
  after which `nslookup` resolved correctly against DC01.
- **Credential prompt failure (Issue 26).** `Add-Computer ... -Credential (Get-Credential)`
  failed because CredUI could not render its dialog in the VM console; passing a
  plain username string failed identically, since that path calls `Get-Credential`
  internally too. Resolved by building the `PSCredential` manually with
  `Read-Host -AsSecureString` plus
  `New-Object System.Management.Automation.PSCredential`, avoiding any GUI dependency.

### Added
- **`WIN11-CLIENT01` joined to `corp.local`** via
  `Add-Computer -DomainName "corp.local" -Credential $cred -Restart`.
- Troubleshooting log Issues 25–27 documenting the DNS conflict, the credential
  failure, and the verified join.

### Verified
- Logged in with domain credentials as `CORP\Administrator` — an account distinct
  from the local `localadmin`, so the login itself is a meaningful test.
- `whoami` → `corp\administrator` (user authenticated against the domain).
- `(Get-WmiObject Win32_ComputerSystem).Domain` → `corp.local` (machine membership).
- `(Get-WmiObject Win32_ComputerSystem).PartOfDomain` → `True` (joined to a domain,
  not a workgroup with a matching name).
- Together these confirm the full chain end to end: DNS resolution located the domain
  controller, the machine's secure-channel trust is established, and Kerberos user
  authentication succeeds.

### Changed
- Promoted the completed client work into the README's Milestones Completed list;
  the remaining open items are client-side GPO verification and AD user lifecycle
  practice.
- Refreshed the troubleshooting log's status header, configuration table, and
  next-steps list.

### Next
- Run `gpresult /r` on `WIN11-CLIENT01` to confirm the Screen Lock and USB Block GPOs
  actually take effect — both target workstations, so DC01 alone cannot demonstrate
  them.
- Practise AD user lifecycle operations — password reset, enable/disable, and moving
  accounts between OUs — starting with `sjohnson` and `kpark`.

---

## 2026-09-02

Step 5 milestone — the client VM's network adapter is fully working after an
extended troubleshooting session and a full VM rebuild. **Step 5 is not complete:**
client DNS configuration and the domain join both remain outstanding.

### Fixed
- **Diagnosed the network driver mismatch that blocked the previous checkpoint.**
  Reading the device's Hardware Ids showed `PCI\VEN_8086&DEV_100E` — Intel's vendor
  ID, identifying the emulated NIC as an Intel 82540EM ("e1000"), not VirtIO
  hardware. The NetKVM driver being tried matches `VEN_1AF4` (Red Hat) and was never
  going to bind to it, and Windows 11 ARM64 has no inbox driver for the legacy Intel
  e1000 at all. This corrects the partly-wrong root cause recorded for Issue 19 on
  2026-08-31.
- **Rebuilt `WIN11-CLIENT01` from scratch** in UTM (ARM64, Virtualize mode) with the
  emulated NIC set to `virtio-net-pci` **from the very first boot**, so Windows would
  never need to be moved onto different hardware after installation.
- Windows 11 Enterprise ARM64 installed cleanly on the rebuilt VM.
- **UTM Guest Tools installed the Red Hat VirtIO Ethernet Adapter driver
  automatically** — no manual driver-folder browsing required, because the hardware
  and the bundled driver finally matched.
- Adapter verified with `ipconfig /all`: real DHCP IPv4 address **192.168.64.4**,
  with working default gateway and DNS servers.

### Added
- Troubleshooting log Issues 20–24 covering the full arc:
  - **20** — Ethernet Controller stuck as an unrecognized device; wrong driver family
    entirely, caught by reading Hardware Ids.
  - **21** — changing the NIC on an already-installed VM caused a cascading boot
    failure: unresponsive firmware boot picker, Automatic Repair, a
    `PAGE_FAULT_IN_NONPAGED_AREA` BSOD, and ultimately VM corruption that made a
    rebuild cheaper than continued debugging.
  - **22** — on the rebuilt VM, the UEFI shell's `FS0:` mapped to a blank EFI System
    Partition instead of the installer; `map` revealed the ISO was not attached at
    all.
  - **23** — the "Start boot option" firmware hang recurred on the clean VM, but from
    a benign UTM/QEMU ARM64 firmware quirk rather than corruption — safe to force
    stop, since it is a pre-boot state with no active disk writes.
  - **24** — adapter fully resolved and verified.

### Changed
- Closed out Issue 19, which was still marked `IN PROGRESS`, with a pointer to Issues
  20–24 and a note that its originally recorded root cause was partly wrong. The
  original text is preserved rather than rewritten, so the diagnostic path stays
  visible alongside the correction.
- Refreshed the troubleshooting log's status header, configuration table, and
  next-steps list to reflect the working adapter.

### Next
- **Point the client's DNS at DC01 (`192.168.64.10`).** DHCP-issued DNS from UTM's
  NAT will not resolve the AD-specific SRV records (`_ldap._tcp.dc._msdcs.corp.local`
  and similar) that a client uses to locate a domain controller, so the join would
  fail despite working internet connectivity.
- Join `WIN11-CLIENT01` to `corp.local` and verify end-to-end domain login with one
  of the ten provisioned accounts.
- Verify the Screen Lock and USB Block GPOs actually take effect on the joined
  client with `gpresult /r`.

---

## 2026-08-31

Step 5 progress checkpoint — the client VM is built and installed, but **not yet
joined to the domain**. Work is paused mid-troubleshooting on a network adapter
driver.

### Added
- Created `WIN11-CLIENT01`, a Windows 11 Enterprise ARM64 client VM in UTM. Unlike
  DC01, this VM uses **Virtualize** mode rather than Emulate — Windows 11 ships a
  native ARM64 build, so no x86 translation is needed and the VM runs at native
  speed.
- Installed Windows 11 successfully after working through four boot and setup
  issues, documented as Issues 15–18 in the troubleshooting log:
  - UEFI Interactive Shell on first boot, resolved by launching `bootaa64.efi`
    manually from the `FS0:` prompt.
  - VM storage misconfigured at 4.86 GB, caught on the creation Summary screen and
    corrected — ultimately to 64 GB, Windows 11's actual minimum.
  - Setup's "it looks like you started an upgrade" prompt on a blank disk, answered
    "No" for a clean install.
  - Setup repeatedly restarting from the ISO after its own mid-install reboot,
    broken by clearing leftover partitions and ejecting the ISO early in the install
    phase rather than at the end.

### In progress
- **Issue 19 — no network adapter detected on the client.** `ipconfig /all` shows no
  Ethernet section at all, and Device Manager lists the virtual chipset as
  unrecognized devices. Windows 11 ARM64 has no inbox driver for QEMU/UTM
  paravirtualized hardware; both `virtio-net-pci` and emulated `e1000` were tried
  without success. The `utm-guest-tools-0.1.271` installer resolved display, disk,
  HID, and audio, but not the Ethernet Controller. Currently pointing Device Manager
  at the ISO's `Drivers\NetKVM` folder manually, since its recursive search did not
  find a match.
- Client DNS configuration and the domain join are **both blocked** until the adapter
  appears — neither has started.

### Changed
- Refreshed the troubleshooting log's status header, current-configuration table, and
  next-steps list, which still described users, groups, and GPOs as pending after
  those steps were completed on 2026-08-23.

### Next
- Point Device Manager directly at the correct `NetKVM\<version>\ARM64` subfolder to
  install the network driver.
- Once the adapter appears: set the client's DNS to `192.168.64.10` (DC01), join it
  to `corp.local`, and verify domain login end to end.
- Confirm the Screen Lock and USB Block GPOs actually take effect on the joined
  client — they target workstations, so DC01 alone cannot demonstrate them.

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
- Created and linked three Group Policy Objects in GPMC:
  - **Password Policy** — minimum password length 12 characters, complexity
    requirements enabled, maximum password age 90 days. Linked at the **domain
    root**, so it applies to every account in `corp.local`.
  - **Screen Lock Policy** — `Interactive logon: Machine inactivity limit` set to
    600 seconds (10 minutes). Linked to the `IT`, `HR`, `Finance`, and
    `Contractors` OUs.
  - **USB Block Policy** — Removable Storage Access set to deny all. Linked to the
    `Contractors` OU **only**, so the restriction is scoped to contractors rather
    than applied domain-wide.

### Changed
- Checked off group and user creation in the README milestone list, and listed the
  new script in the repository contents table.
- Checked off GPO creation and DC01 verification in the README milestone list, and
  narrowed the remaining GPO work to client-side confirmation.

### Security
- `new-users-and-groups.ps1` takes the initial account password as a mandatory
  `[SecureString]` parameter instead of a hardcoded literal, so no credential enters
  this public repository's history. Running the script with no arguments prompts for
  the value with masked input.

### Verified
- **Step 3 of the build plan is complete** — three security groups and ten user
  accounts exist across the five OUs.
- Account placement and enabled/disabled state confirmed with `Get-ADUser`: ten
  accounts distributed across `IT/Admins`, `IT/Helpdesk`, `HR`, `Finance`, and
  `Contractors`, with `sjohnson` and `kpark` correctly showing as disabled.
- Group membership confirmed with `Get-ADGroupMember` against `IT-Admins`,
  `HR-Staff`, and `VPN-Users`.
- **Step 4 of the build plan is complete** — all three GPOs are built and linked.
- GPO application confirmed on DC01 with `gpresult /r`.

### Next
- Practice AD user lifecycle operations — password reset, enable/disable, and moving
  accounts between OUs — starting with `sjohnson` and `kpark`.
- Build the Windows 11 ARM client VM in UTM (Virtualize / native ARM this time),
  join it to `corp.local`, and verify end-to-end domain login.
- Confirm the GPOs apply to a domain-joined client rather than only to DC01 — the
  screen lock and USB restrictions are user/workstation policies, so the client VM
  is where they can actually be observed taking effect.

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
