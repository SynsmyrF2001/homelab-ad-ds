# Active Directory DS homelab — build log and troubleshooting synopsis

**Project:** Windows Server AD DS homelab on Apple Silicon MacBook Pro
**Environment:** UTM (x86 emulation) on M-series Mac
**Date:** August 2026
**Status:** In progress — DC01 promoted to domain controller for the `corp.local` forest; OU structure created. User accounts, security groups, and GPOs are next.

> For the authoritative current-state summary (VM specs, network settings, domain
> details, milestone checklist), see [`../README.md`](../README.md). This document is
> the chronological record of *problems encountered and how they were fixed*.

---

## Project overview

The goal of this project was to deploy a Windows Server domain controller with Active Directory Domain Services (AD DS) in a homelab environment, build an OU structure, configure GPOs, and join a client VM to the domain — all running on an Apple Silicon MacBook Pro using UTM as the hypervisor.

This document captures every issue encountered during setup, how each was diagnosed and resolved, and the current state of the lab. It serves as both a portfolio artifact and a reference for anyone attempting a similar setup on Apple Silicon.

---

## Lab architecture

| Component | Value |
|-----------|-------|
| Host machine | Apple Silicon MacBook Pro (M-series) |
| Hypervisor | UTM (QEMU-based, x86 emulation) |
| DC01 OS | Windows Server VNext Preview (x86_64) |
| DC01 IP | 192.168.64.10 (static) |
| Gateway | 192.168.64.1 (UTM Shared Network) |
| DNS | 192.168.64.10 (self) |
| Domain | corp.local |
| DC01 RAM | 4 GB |
| DC01 CPU | 2 cores |
| DC01 Disk | 60 GB |
| Network mode | UTM Shared Network (NAT via host) |

---

## Issue log

### Issue 1 — Wrong ISO download page

**What happened:**
Navigated to `microsoft.com/en-us/software-download/windowsinsiderpreviewiso` to download the Windows Server ISO. This is the Windows 11 client download page, not the Server page.

**How it was caught:**
The edition dropdown only showed Windows 11 client editions (Home, Pro, Education) with no Server options visible.

**Resolution:**
Navigated to the correct page: `microsoft.com/en-us/software-download/windowsinsiderpreviewserver` for the Windows Server Insider Preview builds.

**What I learned:**
Microsoft has separate download pages for Windows client and Windows Server ISOs. The Windows 11 client ISO will still be needed later for the client VM (step 11) — but it's the wrong starting point for the domain controller.

---

### Issue 2 — ARM vs x86 architecture conflict

**What happened:**
The Apple Silicon Mac (M-series chip) uses ARM64 architecture. The Windows Server ISO available from the Insider Program was x86_64 only — no ARM64 Server build was offered in the edition dropdown.

**How it was caught:**
After selecting the Windows Server VNext ISO and confirming, the download proceeded without prompting for architecture selection. This indicated the ISO was x86_64 only, not ARM64.

**Resolution:**
Switched from UTM's Virtualize mode (which runs ARM natively) to **Emulate mode** (which translates x86 instructions to ARM via QEMU). This allows the x86 Windows Server ISO to run on the Apple Silicon chip at the cost of performance.

**What I learned:**
- Apple Silicon (M1/M2/M3/M4) is ARM64. Most Windows Server ISOs are x86_64.
- UTM has two modes: Virtualize (native ARM, fast) and Emulate (x86 translation, slower).
- For this lab, Emulate is the correct choice when using an x86 ISO on an Apple Silicon Mac.
- The performance trade-off is acceptable for a learning lab — AD DS configuration is not compute-intensive.
- This is the same architectural challenge faced in production when running x86 workloads on ARM-based cloud instances.

---

### Issue 3 — Wrong machine type selected in UTM hardware config

**What happened:**
During UTM VM creation on the Hardware screen, "ARM64 virtual machine (2014, ARM64)" was pre-selected as the machine type. The ISO being used is x86_64.

**How it was caught:**
Caught before booting — the machine type and ISO architecture must match.

**Resolution:**
Changed the machine type to **Intel ICH9 based PC (2009, x86_64)** to match the x86_64 ISO. Also set CPU cores to 2 (was showing "Default" which means 1).

**Final hardware settings:**
- Machine: Standard PC (Q35 + ICH9, 2009) — x86_64
- RAM: 4096 MB
- CPU: 2 cores
- Storage: 60 GB
- Network: Shared Network (e1000)

**What I learned:**
The machine type in UTM must match the architecture of the ISO. Mismatching them results in a VM that either fails to boot or runs with severe degradation. The Q35 + ICH9 machine type is the modern QEMU equivalent of a standard x86 PC — the correct choice for Windows Server.

---

### Issue 4 — "No drives found" during Windows Server installation

**What happened:**
During the Windows Server installer at the "Where do you want to install Windows?" screen, no drives appeared. The 60 GB virtual disk was invisible to the installer.

**How it was caught:**
The drive list was empty with a message indicating no drives were found.

**Resolution:**
Clicked "Load driver" → browsed to CD Drive (E:) UTM Guest Tools → navigated to the `vioscsi` folder → selected the appropriate driver subfolder → clicked OK. The 60 GB virtual disk immediately appeared and installation continued.

**What I learned:**
- UTM uses VirtIO virtual hardware for storage, which Windows doesn't have drivers for by default.
- The same issue occurs when installing Windows on AWS EC2 or Azure VMs — both use VirtIO storage and require driver loading during setup.
- UTM automatically mounts the VirtIO drivers alongside the ISO when "Install drivers and SPICE tools" is checked during VM creation — this is why the drivers were available on drive E:.
- This is not an error — it's a standard procedure for any hypervisor using paravirtualized storage.

---

### Issue 5 — Ctrl+Alt+Delete on Mac keyboard

**What happened:**
After Windows Server installed and showed the lock screen prompting "Press Ctrl+Alt+Delete to unlock," standard keyboard input didn't work as expected on a Mac.

**How it was caught:**
The lock screen persisted without response to keyboard shortcuts.

**Resolution:**
Used the UTM toolbar keyboard icon → "Send Ctrl+Alt+Delete" option. Alternatively: **Ctrl + Option + Delete** on Mac keyboard (Option = Alt).

**What I learned:**
macOS intercepts certain key combinations before they reach the VM. UTM provides a "Send Ctrl+Alt+Delete" option in its toolbar for this reason. This is a permanent difference to remember for all Windows VMs on Mac.

---

### Issue 6 — VM booting from ISO instead of hard disk (boot loop)

**What happened:**
Every time the VM restarted — whether from a normal reboot or a rename operation — it booted back into the Windows Server installer instead of the installed operating system. This appeared to be starting the installation over from scratch each time.

**How it was caught:**
The "Installing Windows Server" screen appeared repeatedly after restarts that should have booted into the configured OS.

**Root cause:**
UTM's boot order checks CD/DVD drives before the hard disk. The Windows Server ISO and UTM Guest Tools ISO were still mounted as drives in the VM configuration. Every restart, UTM found the bootable ISO and launched the installer.

**Resolution:**
1. Stopped the VM immediately before the installer could format the disk
2. Right-clicked DC01 → Edit → Drives
3. Identified three IDE drives:
   - IDE Drive 1: `Windows Server Insider Preview 29641.iso` (5.28 GB) — **cleared**
   - IDE Drive 2: `FCEBBCF9...qcow2` (15.86 GB) — **left alone** (this is the Windows installation)
   - IDE Drive 3: `utm-guest-tools-latest.iso` (128.3 MB) — **cleared**
4. Clicked Clear (not Delete) on drives 1 and 3 to remove the ISO paths
5. Saved and rebooted

After this fix, the boot sequence showed:
```
BdsDxe: failed to load Boot0001 "UEFI QEMU DVD-ROM" — Not Found
BdsDxe: loading Boot0005 "Windows Boot Manager" from HD(...)
BdsDxe: starting Boot0005 "Windows Boot Manager" from HD(...)
```

This confirmed UTM tried the DVD first (failed), then correctly fell through to the hard disk.

**What I learned:**
- Boot order is a fundamental concept: BIOS/UEFI checks boot devices in sequence and uses the first bootable one it finds.
- This is identical to why real servers and PCs say "remove installation media before restarting" at the end of OS setup.
- Clear removes the ISO path from a drive slot. Delete removes the drive slot entirely — the wrong choice here would have removed the boot disk.
- The qcow2 file is the virtual hard disk format QEMU uses — this is your actual Windows installation and must never be deleted.

---

### Issue 7 — Azure Arc agent error on boot (0xc0000142)

**What happened:**
After shutting down and restarting the VM, an error dialog appeared:
```
azcmagent.exe - Application Error
The application was unable to start correctly (0xc0000142).
Click OK to close the application.
```

**Root cause:**
During initial Server Manager setup, the Azure Arc setup wizard was launched and then cancelled partway through. This left a partially installed Azure Connected Machine agent that attempted to start on every boot but failed because the installation was incomplete.

**Resolution:**
Clicked OK to dismiss the error. This is a non-critical error that doesn't affect Windows Server functionality or the AD DS lab. The agent can be fully removed later via PowerShell:
```powershell
msiexec /x {AzureConnectedMachineAgent}
```

Or uninstalled via Settings → Apps → Azure Connected Machine Agent.

**What I learned:**
- Azure Arc is Microsoft's service for connecting on-premises servers to Azure for centralized cloud management — a real enterprise tool but out of scope for this lab.
- Error code 0xc0000142 means a DLL initialization failure — the agent's dependencies weren't fully installed because setup was cancelled.
- Always complete or fully cancel third-party agent installations — partial installs cause persistent errors.
- In production, this type of error would appear in Event Viewer under Windows Logs → Application, which is where sysadmins diagnose startup failures.

---

### Issue 8 — "We're getting things ready" after rename appeared to be a reinstall

**What happened:**
After running `Rename-Computer -NewName "DC01" -Restart` in PowerShell, the VM rebooted and showed the Windows Server Setup screen with "We're getting things ready — Please wait."

**How it was caught:**
This screen looks identical to the post-install configuration phase, causing concern that the rename triggered a reinstall.

**Resolution:**
This was not a reinstall. When a Windows Server computer is renamed and restarted, it runs a brief OOBE (Out of Box Experience) preparation phase to apply the new hostname system-wide. All configuration, static IP settings, and installed software remain intact.

The real issue was that the ISO was still mounted (Issue 6), which caused subsequent restarts to boot the installer. The rename screen itself was harmless.

**What I learned:**
- Windows Server applies hostname changes during a specialized restart phase that looks like setup but isn't.
- The distinction between "OOBE configuration" and "fresh installation" is important — OOBE runs from the existing Windows installation, not from the ISO.
- Renaming a computer is a common sysadmin task and always requires a restart to propagate the change through the OS and network stack.

---

### Issue 9 — Default gateway missing after setting static IP

**What happened:**
After running `New-NetIPAddress` to set the static IP, `ipconfig /all` showed the Default Gateway field as blank, even though the command included the `-DefaultGateway` parameter.

**Resolution:**
Added the gateway route manually:
```powershell
New-NetRoute -DestinationPrefix "0.0.0.0/0" -NextHop 192.168.64.1 -InterfaceAlias "Ethernet"
```

**What I learned:**
- A missing default gateway means the machine can communicate on its local subnet but can't reach anything outside it — internet access and DNS resolution to external servers would fail.
- `0.0.0.0/0` is the default route — it means "send all traffic not matching a more specific route to this next hop."
- This is a foundational networking concept: local subnet traffic routes directly, everything else goes to the gateway.
- In production this would cause AD DS promotion to fail if it needs to reach external DNS servers.

---

### Issue 10 — "Activate Windows" watermark persists on the desktop

**What happened:**
An "Activate Windows" watermark remained visible in the corner of the desktop and did not clear after installation and configuration.

**Root cause:**
Expected behavior for Windows Server Insider Preview builds, which are time-limited evaluation releases rather than licensed installations.

**Resolution:**
No action required. The watermark does not affect AD DS functionality or lab usability.

**What I learned:**
Cosmetic licensing indicators are easy to mistake for a failed install. Confirming that a symptom is *expected* for the build in use is a legitimate troubleshooting outcome — not every anomaly needs a fix.

---

### Issue 11 — VM snapshots not available in UTM

**What happened:**
Attempted to take a snapshot of DC01 before making major changes, so the VM could be rolled back if something broke. The expected right-click → Snapshots option was not exposed for this VM.

**Root cause:**
The UTM/QEMU VM as configured did not surface snapshot support in the interface.

**Resolution:**
Used **Clone** as the rollback mechanism instead — duplicating the VM before risky operations, so the copy can be reverted to if needed.

**What I learned:**
- A clone is a full copy of the VM rather than a lightweight point-in-time delta, so it costs proportionally more disk space and takes longer to create than a snapshot.
- Having *some* rollback path before a destructive or irreversible operation matters more than which mechanism provides it. Domain controller promotion is exactly the kind of operation worth protecting against.

---

### Issue 12 — `Install-ADDSForest` failed prerequisite check (DSRM password complexity)

**What happened:**
Running `Install-ADDSForest` to promote DC01 to a domain controller failed during the prerequisite check. The Directory Services Restore Mode (DSRM) password entered during promotion was rejected.

**Root cause:**
The DSRM password did not meet Windows password complexity requirements. The password must be at least 8 characters and contain at least 3 of the following 4 categories: uppercase letters, lowercase letters, numbers, and symbols. The initial password lacked sufficient character variety.

**Resolution:**
Re-ran `Install-ADDSForest` with a stronger DSRM password meeting the complexity rules. The prerequisite check passed and promotion succeeded.

**What I learned:**
- The DSRM password is set during promotion and is separate from the domain administrator password — it's the credential used to boot into Directory Services Restore Mode for offline AD database recovery.
- Prerequisite checks run *before* any changes are made, so a failure here is safe: the server is left in its prior state and the command can simply be re-run with corrected input.
- The 3-of-4 complexity rule is the same default enforced on domain user accounts, which makes it a useful thing to internalize early.

---

### Issue 13 — Stacked "Shutdown Event Tracker" and "Azure Arc Configuration" dialogs after promotion reboot

**What happened:**
After the automatic reboot triggered by forest promotion, two dialogs appeared stacked on top of each other: Windows Server's Shutdown Event Tracker prompting for a reason for the restart, with Server Manager's Azure Arc onboarding wizard behind it.

**Root cause:**
Normal Windows Server behavior, not an error state:
- The **Shutdown Event Tracker** logs the reason for unplanned server restarts. The promotion reboot had no pre-logged "planned" reason, so it prompted on next login.
- **Server Manager** auto-prompts Azure Arc onboarding on first load.

Neither affects AD DS.

**Resolution:**
Entered a comment ("AD DS forest promotion reboot") and clicked OK to dismiss the Shutdown Event Tracker. Clicked Cancel on the Azure Arc Configuration wizard.

**What I learned:**
- Shutdown Event Tracker is a Windows Server–specific feature (it's not present on Windows client editions) — it exists so that unexplained server restarts leave an audit trail.
- Two unrelated dialogs appearing together after a reboot can look like a single compound failure. Dismissing them one at a time and identifying each independently is the faster diagnosis.

---

## Current configuration state

| Setting | Value | Status |
|---------|-------|--------|
| Hostname | DC01 | Confirmed |
| IPv4 address | 192.168.64.10 | Configured |
| Subnet mask | 255.255.255.0 | Configured |
| Default gateway | 192.168.64.1 | Configured |
| DNS server | 192.168.64.10 (self) | Configured |
| DHCP | Disabled | Confirmed |
| UTM Guest Tools | Installed | Confirmed |
| ISO boot loop | Fixed | Confirmed |
| AD DS role | Installed | Confirmed |
| Domain controller promotion | `corp.local` forest, NetBIOS `CORP` | Confirmed via `Get-ADDomain` / `Get-ADDomainController` |
| OU structure | IT (Admins, Helpdesk), HR, Finance, Contractors | Created |
| User accounts & security groups | Not yet created | Next step |
| GPOs | Not yet configured | Pending |
| Windows 11 ARM client VM | Not yet built | Pending |

---

## Next steps

1. ~~Boot DC01 and confirm hostname shows `DC01`~~ — done
2. ~~Install AD DS role~~ — done
3. ~~Promote to domain controller (create new forest `corp.local`)~~ — done
4. ~~Build OU structure: IT, HR, Finance, Contractors~~ — done (see [`../scripts/new-ou-structure.ps1`](../scripts/new-ou-structure.ps1))
5. Create 10+ user accounts and security groups (`IT-Admins`, `HR-Staff`, `VPN-Users`)
6. Practice AD user lifecycle operations: password reset, disable/enable, unlock, move between OUs
7. Configure 3 GPOs (password policy, screen lock, USB restriction on Contractors OU)
8. Create Windows 11 ARM client VM and join to `corp.local`
9. Verify GPOs applying with `gpresult /r` on client

---

## Key commands reference

```powershell
# Check current IP configuration
ipconfig /all

# Set static IP
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.64.10 -PrefixLength 24 -DefaultGateway 192.168.64.1

# Set DNS to self
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.64.10

# Add default gateway route if missing
New-NetRoute -DestinationPrefix "0.0.0.0/0" -NextHop 192.168.64.1 -InterfaceAlias "Ethernet"

# Rename computer and restart
Rename-Computer -NewName "DC01" -Restart

# Install AD DS role
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Verify hostname
hostname

# Verify domain and domain controller after promotion
Get-ADDomain
Get-ADDomainController

# Check GPO application on client
gpresult /r

# Force GPO update
gpupdate /force
```

---

## Lessons learned summary

This setup involved significantly more friction than a standard x86 PC lab due to the Apple Silicon architecture. Every issue encountered maps to a real concept in systems administration:

- **Boot order** — the mechanism that determined which device the VM loaded from
- **VirtIO drivers** — paravirtualized storage drivers used by QEMU, AWS, and Azure
- **Architecture compatibility** — x86 vs ARM, the same challenge faced in cloud migrations
- **Default routes** — how IP traffic flows when no specific route matches
- **DNS self-reference** — why a domain controller must be its own DNS server
- **OOBE vs reinstall** — understanding Windows Server startup phases
- **Password complexity enforcement** — the 3-of-4 rule that blocked forest promotion until the DSRM password satisfied it
- **Rollback planning** — using clones when snapshots aren't available, before irreversible operations

None of these issues were dead ends. Each one was a real troubleshooting scenario with a diagnosable root cause and a clean fix — exactly the kind of problem-solving that IT roles require daily.
