# Active Directory DS homelab — build log and troubleshooting synopsis

**Project:** Windows Server AD DS homelab on Apple Silicon MacBook Pro
**Environment:** UTM (x86 emulation) on M-series Mac
**Date:** August 2026
**Status:** Core build complete — DC01 promoted with OUs, users, groups and GPOs in place, and `WIN11-CLIENT01` joined to `corp.local` and verified end to end (Issue 27). Remaining: confirm the Screen Lock and USB Block GPOs apply on the client, and practise AD user lifecycle operations.

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
After setting the static IP with `New-NetIPAddress`, `ipconfig /all` showed no IPv4 Default Gateway. Only an IPv6 link-local gateway (`fe80::842f:57ff:fea3:db64%4`) was listed. The IPv4 address itself had applied correctly — `192.168.64.10(Preferred)`, `DHCP Enabled: No`.

**How it was caught:**
Running `ipconfig /all` after pointing DNS at the server itself. The interface showed a valid IPv4 address and the correct DNS server, but the Default Gateway line carried no IPv4 entry. See `images/04-set-dns-and-ipconfig-all.png`.

**Root cause:**
The `-DefaultGateway` parameter was omitted from the `New-NetIPAddress` command as it was actually run:

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.64.10 -PrefixLength 24
```

`New-NetIPAddress` assigns the address and prefix length. Without `-DefaultGateway` it does not create a default route, so nothing was ever configured to carry off-subnet traffic. Confirmed by two captures of the command — `images/03-new-netipaddress-static-ip.png` and `images/05-new-netaddress-typo.png` — neither of which includes the parameter.

**Resolution:**
Added the default route manually rather than reconfiguring the address:

```powershell
New-NetRoute -DestinationPrefix "0.0.0.0/0" -NextHop 192.168.64.1 -InterfaceAlias "Ethernet"
```

Passing `-DefaultGateway 192.168.64.1` to `New-NetIPAddress` in the first place would have achieved the same result in a single step.

**What I learned:**
- A missing default gateway means the machine can communicate on its local subnet but can't reach anything outside it — internet access and DNS resolution to external servers would fail.
- `0.0.0.0/0` is the default route — it means "send all traffic not matching a more specific route to this next hop."
- This is a foundational networking concept: local subnet traffic routes directly, everything else goes to the gateway.
- A default gateway is a **route**, not a property of the IP address. That is why the address applied cleanly without one, and why `New-NetRoute` can supply it after the fact instead of requiring the address to be torn down and rebuilt.
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

### Issue 14 — `New-NetAddress` cmdlet not found (typo)

**What happened:**
Re-running the static IP configuration produced an error before the command executed:

```
New-NetAddress : The term 'New-NetAddress' is not recognized as the name of a cmdlet,
function, script file, or operable program. Check the spelling of the name, or if a
path was included, verify that the path is correct and try again.
    + CategoryInfo          : ObjectNotFound: (New-NetAddress:String) [], CommandNotFoundException
    + FullyQualifiedErrorId : CommandNotFoundException
```

**Root cause:**
The cmdlet name was mistyped. The correct name is `New-NetIPAddress` — there is no cmdlet called `New-NetAddress`.

**Resolution:**
Re-ran the same command with the correct cmdlet name, which completed normally. See `images/05-new-netaddress-typo.png`.

**What I learned:**
- `CommandNotFoundException` / `ObjectNotFound` means PowerShell could not resolve the name at all. That is a different failure from a cmdlet that exists but rejects its arguments, which raises a parameter-binding error instead. The distinction tells you immediately whether to check spelling or check syntax.
- Tab completion prevents this class of error: typing `New-NetIP` and pressing Tab resolves to real cmdlet names only.
- PowerShell cmdlet names are case-insensitive, which is why `Set-DnsclientServerAddress` ran without complaint despite the irregular capitalization. Spelling matters; casing does not.

---

## Issue log — Step 5: Windows 11 ARM64 client (WIN11-CLIENT01)

The entries below cover the client VM build. Unlike DC01, this VM uses UTM's
**Virtualize** mode rather than Emulate, since Windows 11 is available as a native
ARM64 build — no x86 translation needed, and the VM runs at native speed as a result.

---

### Issue 15 — UEFI Interactive Shell on first boot instead of Windows Setup

**What happened:**
On first boot the VM dropped into EDK II's UEFI Interactive Shell rather than
launching Windows Setup from the mounted ISO.

**Root cause:**
UTM/QEMU's ARM64 firmware has no NVRAM boot entry on a brand-new VM. With no
persisted entry telling it what to boot, the firmware falls through to the
interactive shell rather than guessing which attached device to try.

**Resolution:**
Booted the ISO's ARM64 boot loader manually from the shell prompt:

```
FS0:
cd EFI\boot
bootaa64.efi
```

**What I learned:**
- `FS0:` is the firmware's name for the first recognized filesystem — here, the
  mounted installation ISO. The shell addresses devices by handle, not drive letter.
- `bootaa64.efi` is the ARM64 EFI boot loader. The x86_64 equivalent is
  `bootx64.efi` — the filename encodes the architecture, which is a quick way to
  confirm you have media matching the VM.
- This is the same class of problem as the DC01 boot loop (Issue 6), approached
  from the opposite direction: there the firmware found bootable media it should
  have ignored, here it found media it did not know to use.

---

### Issue 16 — VM storage misconfigured as 4.86 GB instead of 40 GB

**What happened:**
The UTM VM creation Summary screen showed a storage size of 4.86 GB rather than the
intended 40 GB.

**How it was caught:**
Reviewing the Summary screen before starting the install — the last checkpoint the
wizard offers before the VM is created.

**Root cause:**
The storage size step in the creation wizard was not set correctly on the first pass
through.

**Resolution:**
Went back to the storage step and corrected the value. Later increased it again to
64 GB, to clear Windows 11's actual minimum requirement with room to spare.

**What I learned:**
- Windows 11 requires a 64 GB minimum disk — notably larger than Windows Server's
  32 GB, and larger than the 40 GB originally planned.
- Catching this on the Summary screen cost one wizard step. Catching it after
  installation would have meant expanding the virtual disk *and* extending the
  partition inside Windows — a far more involved fix for the same mistake.

---

### Issue 17 — "It looks like you started an upgrade and booted from installation media" prompt

**What happened:**
Windows Setup displayed a prompt asking whether an upgrade had been started, despite
the target disk being blank with no prior operating system installed.

**Resolution:**
Selected **No** to perform a clean installation — the correct path, since there was
no existing installation to upgrade.

**What I learned:**
Setup asks this defensively rather than because it detected an actual upgrade in
progress. On a blank disk the answer is always "No"; answering "Yes" would send
Setup looking for an existing Windows installation that does not exist.

---

### Issue 18 — Setup repeatedly restarted from the ISO instead of continuing installation

**What happened:**
After Setup's first automatic mid-install reboot, the VM dropped back into the UEFI
shell and defaulted to booting `FS0:` — the ISO — again, relaunching Setup from
scratch instead of continuing the in-progress installation on the hard disk. This
repeated across multiple attempts, and each aborted attempt left additional partition
structure behind on the disk.

**Root cause:**
UTM's ARM64 firmware and its `startup.nsh` default to the CD-ROM boot device when no
persisted boot entry exists. Windows only writes its own boot entry once the
installation is far enough along; every automatic restart before that point therefore
found the ISO first and started over. The loop was self-sustaining — Setup could never
reach the stage where it would have created the entry that breaks the loop.

**Resolution:**
Two parts, in order:

1. Deleted the leftover partitions from previous aborted attempts, returning the disk
   to clean unallocated space.
2. **Ejected the installation ISO from UTM's CD/DVD drive early in the install phase**
   — as soon as Setup had copied files and no longer needed the media — rather than
   waiting until the install neared completion. With no bootable media on `FS0:`, no
   subsequent automatic restart had an ISO to latch onto.

Confirmed by the UEFI boot log showing:

```
BdsDxe: starting Boot0006 "Windows Boot Manager"
```

loading correctly from the hard disk.

**What I learned:**
- Setup's mid-install reboots are the vulnerable window. The installer depends on the
  firmware coming back to the *disk*, but has not yet created the boot entry that
  makes that happen — so the boot order has to be right by default, or the media has
  to be removed.
- Each failed attempt compounded the problem by leaving partition structure behind.
  Returning to clean unallocated space before each retry mattered as much as fixing
  the boot order itself.
- This is Issue 6 on DC01 in a harsher form. There, the ISO caused a boot loop
  *after* a completed install and was fixed by clearing the drive path afterward.
  Here it prevented the install from ever completing, so the media had to come out
  mid-flight.

---

### Issue 19 — No network adapter visible in Windows after install

**What happened:**
After installation completed, `ipconfig /all` showed no Ethernet adapter section at
all — not a disconnected adapter, but no adapter present. Device Manager showed the
entire virtual chipset as unrecognized entries under "Other devices" / "Unknown
device".

**Root cause:**
Windows 11 ARM64 ships no inbox driver for QEMU/UTM's paravirtualized hardware. Both
NIC types available in UTM's VM settings were tried — `virtio-net-pci` and the
emulated `e1000` — and neither has a built-in ARM64 driver in Windows 11.

**Progress so far:**
Running the `utm-guest-tools-0.1.271` installer from the mounted UTM Guest Tools ISO
resolved most of the unrecognized devices — display, disk, HID, audio — but **not**
the Ethernet Controller, which remains unrecognized.

Currently locating the driver manually from the ISO's `Drivers\NetKVM` folder via
Device Manager → Update driver → Browse my computer. The automatic recursive
subfolder search did not find a match on its own.

**Status: RESOLVED — see Issues 20–24.**
The `NetKVM` approach recorded above never succeeded, and the reason turned out to
be a misdiagnosis rather than a missing subfolder: checking the device's Hardware
Ids (Issue 20) showed the emulated NIC was an **Intel** e1000, not VirtIO hardware,
so the VirtIO driver was never going to bind to it no matter which folder Device
Manager was pointed at. The fix was to change the NIC type rather than to keep
hunting for a driver — which in turn led to Issues 21–24 and, ultimately, a full VM
rebuild.

Note the root cause as originally written above is **partly wrong**: it states that
both `virtio-net-pci` and `e1000` were tried and neither had an ARM64 driver. The
hardware ID evidence in Issue 20 shows the VM was presenting Intel e1000 hardware at
the time, so the VirtIO driver was being tested against hardware it could not match.
The entry is left as written to preserve the actual diagnostic path; the correction
belongs with the evidence that produced it.

**What I learned so far:**
- This is the ARM64 counterpart to Issue 4 on DC01, where VirtIO storage drivers had
  to be loaded from the same Guest Tools ISO mid-install. Same root problem —
  Windows has no inbox driver for paravirtualized QEMU hardware — surfacing at a
  different point in the build.
- Switching from `virtio-net-pci` to the emulated `e1000` is worth trying because
  emulated devices often *do* have inbox drivers. That it did not help here reflects
  ARM64's much thinner inbox driver set compared to x86_64.
- "No adapter listed at all" and "adapter listed but disconnected" are different
  failures. The first is a driver problem; the second is a network configuration
  problem. `ipconfig /all` showing no Ethernet section at all pointed at drivers
  immediately.
- Device Manager's recursive search can miss architecture-specific subfolders. When
  it does, pointing it at the exact folder containing the `.inf` for your
  architecture is the reliable fallback.

---

### Issue 20 — Ethernet Controller stuck as unrecognized device: wrong driver family entirely

**What happened:**
Following the initial Windows 11 ARM64 install, Device Manager showed the Ethernet
Controller as an unrecognized "Other device". Installing the NetKVM driver from the
UTM Guest Tools ISO failed regardless of which subfolder was pointed at.

**How it was caught:**
Checking the device's **Hardware Ids** under Device Manager → Properties → Details,
rather than continuing to guess at driver folders. It showed:

```
PCI\VEN_8086&DEV_100E...
```

**Root cause:**
`VEN_8086` is Intel's PCI vendor ID, identifying the emulated NIC as an Intel
82540EM — the "e1000". NetKVM is the **VirtIO** network driver and matches
`VEN_1AF4`, Red Hat's vendor ID. It was never going to bind to Intel hardware no
matter which subfolder was selected. Compounding this, Windows 11 ARM64 has no inbox
driver for the legacy Intel e1000 chip at all, so the device had no path to working
in that configuration.

**Resolution:**
Identified that the VM's emulated NIC needed to be changed to `virtio-net-pci` in
UTM's VM settings, so the hardware would match the driver that was actually
available. Making that change on an already-installed VM is what triggered Issues
21–24 below.

**What I learned:**
- **Hardware Ids are the ground truth for any unknown device.** `VEN_xxxx` is the
  vendor and `DEV_xxxx` the device; a driver only binds if its `.inf` claims that
  exact pair. Reading them first would have ruled out NetKVM immediately and saved
  the entire manual folder-hunting effort in Issue 19.
- Vendor IDs worth recognizing here: `8086` = Intel (an old joke on the 8086 CPU),
  `1AF4` = Red Hat / VirtIO.
- "The driver won't install" and "this is the wrong driver family" look identical
  from the outside. The difference is only visible in the hardware IDs.

---

### Issue 21 — Changing the NIC on a live VM triggered cascading boot failure and corruption

**What happened:**
After switching the emulated Network Card to `virtio-net-pci` in UTM's settings on
the already-installed VM, the VM hit a graphical firmware "boot option" picker screen
that was completely unresponsive — to clicks, Enter, Space, and multi-minute waits
alike.

The failure then escalated across several attempts:

1. Changing UTM's USB Support setting (USB 3.0 XHCI → USB 2.0, on the theory that
   firmware-level input polling was at fault) did not help.
2. A forced restart broke through to Windows **Automatic Repair** ("Your PC did not
   start correctly").
3. Restarting from Automatic Repair produced a full **BSOD:
   `PAGE_FAULT_IN_NONPAGED_AREA`**.
4. After the BSOD's automatic restart, the VM landed back on the same frozen boot
   picker — this time for several hours with zero progress.

**Root cause:**
Changing a VM's core hardware after the OS is installed alters the virtual PCI bus
enumeration, which can invalidate the firmware's NVRAM boot order. Combined with
several forced stops during active boot and install phases, this most likely left the
disk's filesystem and/or NVRAM state genuinely corrupted — not merely slow.

**Resolution:**
Rather than continuing to debug an instance carrying accumulated, stacked damage,
**deleted the VM and rebuilt it from scratch** — this time setting `virtio-net-pci`
as the emulated NIC *before* installing Windows, so the OS would never need to be
moved onto different hardware after the fact.

**What I learned:**
- Hardware changes are cheap **before** an OS is installed and expensive after.
  Windows binds drivers and boot configuration to the hardware it finds at install
  time; swapping a device underneath a running installation is closer to moving a
  physical disk into a different machine than to changing a setting.
- `PAGE_FAULT_IN_NONPAGED_AREA` means the kernel referenced memory that was not
  present — commonly a faulty driver or corrupted system files, both plausible after
  a hardware swap plus forced stops.
- **Knowing when to stop debugging is a real skill.** Once several distinct failures
  had stacked on one instance, each additional fix attempt risked adding damage
  rather than removing it. A rebuild took less time than continuing would have, and
  produced a clean baseline instead of an uncertain one.
- The rebuild was not a defeat: it converted an unknown-state VM into a known-good
  one, and the correct configuration was known in advance this time.

---

### Issue 22 — Rebuilt VM's UEFI shell showed an empty target disk instead of the install ISO

**What happened:**
On the freshly rebuilt VM, after selecting the install location during Windows Setup,
an automatic reboot dropped into the UEFI Interactive Shell as expected — but this
time `FS0:` mapped to the new virtual disk's blank **EFI System Partition** (0 files,
0 dirs) rather than the installer media, and `cd EFI\boot` failed.

**How it was caught:**
Running `map` at the shell prompt to redisplay the full filesystem and block-device
table. It showed **no CD-ROM or ISO device present at all** — the Windows 11 install
ISO was not attached to the VM's CD/DVD drive at that point.

**Root cause:**
The ISO was unmounted from the VM's drive settings, so there was no installer media
for the firmware to find or for the shell to address.

**Resolution:**
Confirmed the unmounted state in UTM's VM drive settings, reattached the ISO, and
Setup continued normally from there.

**What I learned:**
- `FS0:` is positional, **not** a stable name for the installer. It is simply the
  first filesystem the firmware recognizes — the ISO in Issue 15, a blank EFI System
  Partition here. Assuming it always means "the install media" is how this looked
  confusing at first.
- `map` is the diagnostic command in the UEFI shell: it answers "what devices does
  the firmware actually see?" before any assumption about what should be there.
- An empty ESP with 0 files is itself informative — it says the disk exists and is
  partitioned but nothing has been written to it yet.

---

### Issue 23 — "Start boot option" firmware hang recurred on the clean rebuilt VM, from a different cause

**What happened:**
Later in the same install — after ejecting the installation ISO mid-setup (the fix
carried over from Issue 18) and letting Setup restart itself — the VM again hit the
same unresponsive graphical "Start boot option" screen. It stayed there a full 5
minutes, with both click/Enter attempts and idle waiting tried, with no change.

**Root cause:**
This VM had **no history of forced shutdowns or hardware swaps**, so the disk and
NVRAM corruption that explained Issue 21 could be ruled out. That leaves a
reproducible UTM/QEMU ARM64 **Virtualize**-mode firmware quirk, occurring at the
specific moment between Setup's automatic restarts — before Windows has registered a
persistent NVRAM boot entry.

**Resolution:**
Because this screen is a **pre-boot firmware state with no active disk writes**, it
was safe to Force Stop and restart the VM — unlike interrupting an active install
phase, which is what caused damage in Issue 21. The restart immediately resolved it
and the VM proceeded straight into the Windows out-of-box setup screens.

**What I learned:**
- **The same symptom can have different causes, and the safe response depends on
  which.** This screen looked identical to the Issue 21 hang, but the surrounding
  history made the difference: there it was a symptom of real corruption, here it was
  a benign firmware stall.
- Knowing whether a VM is mid-write is what determines whether a force stop is safe.
  A firmware picker screen is idle; an install copying files is not. That judgment,
  not the symptom, decides the action.
- Clean history is itself diagnostic evidence. Being able to say "this VM has never
  been force-stopped or had hardware changed" eliminated an entire class of cause
  immediately — one practical payoff of having rebuilt rather than patched.

---

### Issue 24 — Network adapter fully resolved on the rebuilt VM ✅

**What happened:**
After completing OOBE and reaching the desktop, running the UTM Guest Tools installer
(`utm-guest-tools-latest.iso`) **automatically installed and bound the "Red Hat VirtIO
Ethernet Adapter" driver** under Device Manager's Network adapters category — with no
manual "Update driver → browse to NetKVM folder" steps needed this time.

**Root cause (of the success):**
Because the VM had `virtio-net-pci` configured from the very first boot, the driver
bundled on the Guest Tools ISO matched the hardware's vendor/device ID correctly out
of the box. This is precisely the mismatch that Issue 20 identified and that Issues
21–23 were spent correcting.

**Resolution / verification:**
Confirmed via `ipconfig /all` that the adapter obtained a real DHCP IPv4 address:

| Setting | Value |
|---|---|
| IPv4 address | 192.168.64.4 (DHCP) |
| Default gateway | Present |
| DNS servers | Present (DHCP-issued) |

**Status: RESOLVED.** The adapter is fully working.

**Next step — why DHCP-issued DNS is not sufficient:**
The client's DNS must be pointed specifically at **DC01 (192.168.64.10)** before
attempting the domain join. Generic DHCP-issued DNS from UTM's NAT will not resolve
the AD-specific **SRV records** (`_ldap._tcp.dc._msdcs.corp.local` and similar) that a
client uses to locate a domain controller — so the join would fail even though general
internet connectivity works fine.

**What I learned:**
- The whole arc from Issue 19 to here resolved to a **single configuration choice**
  made at VM creation time. Setting the NIC correctly up front cost nothing; getting
  it wrong cost a driver hunt, a corrupted VM, and a full rebuild.
- "It works automatically now" is the signature of correctly matched hardware and
  drivers. Fighting a driver into place is usually a signal that something upstream
  is wrong — as it was in Issue 20.
- Working internet connectivity does **not** imply a client can join a domain. Domain
  location depends on DNS SRV records that only the DC serves, which is why this step
  has its own prerequisite rather than being covered by "the network works."

---

### Issue 25 — DNS query hijacked by an auto-discovered IPv6 DNS server, despite correct IPv4 configuration

**What happened:**
After pointing the client at DC01 with

```powershell
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.64.10
```

`nslookup corp.local` still failed with **"Non-existent domain."**

**How it was caught:**
The `Server:` / `Address:` lines in the `nslookup` output. Instead of reporting
`192.168.64.10`, they showed a **link-local IPv6 address** (`fe80::...`) — the query
had never gone to DC01 at all.

**Root cause:**
`Set-DnsClientServerAddress` manages only the **IPv4** DNS server list for an adapter.
Meanwhile UTM's virtual network sends IPv6 **Router Advertisements** carrying an
**RDNSS** (Recursive DNS Server) option, which Windows learns automatically and uses
alongside the manually configured IPv4 server. That auto-discovered IPv6 resolver is
UTM's virtual router, which has no knowledge of `corp.local` — so it answered the
query authoritatively wrong.

The IPv4 configuration was correct the entire time. It simply was not the
configuration being consulted.

**Resolution:**
Disabled IPv6 on the adapter entirely, removing the competing resolver:

```powershell
Disable-NetAdapterBinding -InterfaceAlias "Ethernet" -ComponentID ms_tcpip6
```

Re-running `nslookup corp.local` then resolved correctly against `192.168.64.10`.

**What I learned:**
- **Windows prefers IPv6 over IPv4 by default.** Configuring IPv4 DNS correctly does
  not guarantee it will be used if an IPv6 resolver is also present.
- Always read `nslookup`'s `Server:` line before interpreting its answer. "Non-existent
  domain" from the *wrong* server is a completely different problem from the same
  answer from the *right* one — and only that line distinguishes them.
- RDNSS means a network can hand a host a DNS server via IPv6 Router Advertisements
  without any DHCP involvement, which is why this resolver never appeared in the IPv4
  configuration being inspected.
- Disabling IPv6 is acceptable in this lab. In production it is a blunt instrument —
  the better fix is usually configuring the IPv6 DNS server correctly, or stopping the
  RA from advertising one, rather than turning off the protocol.

---

### Issue 26 — `Get-Credential` failed to prompt in the VM console, blocking the domain join

**What happened:**
Running the domain join failed immediately:

```powershell
Add-Computer -DomainName "corp.local" -Credential (Get-Credential) -Restart
```

```
Get-Credential : Cannot process command because of one or more missing mandatory
parameters: Credential.
```

Passing a plain username string instead (`-Credential CORP\Administrator`) also
failed, with `Add-Computer` reporting the Credential argument was null or empty.

**Root cause:**
`Get-Credential` depends on Windows' **CredUI** subsystem to render its
username/password dialog, and that dialog failed to render in this VM's console
session. The second approach hit the *same* underlying failure rather than a
different one: `Add-Computer`'s automatic conversion of a username string into a
`PSCredential` calls `Get-Credential` internally.

**Resolution:**
Bypassed CredUI entirely by constructing the `PSCredential` object manually —
`Read-Host -AsSecureString` gives a pure console password prompt with no GUI
dependency:

```powershell
$username = "CORP\Administrator"
$password = Read-Host -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential($username, $password)

Add-Computer -DomainName "corp.local" -Credential $cred -Restart
```

The manually built credential object worked correctly.

One detour on the way: the first attempt threw a "Cannot find type" error from a
typo — `System.Managment` instead of `System.Management`.

**What I learned:**
- **Two different commands failing identically is a clue, not a coincidence.** Both
  paths routed through `Get-Credential`, so the second attempt was never an
  independent test of the problem.
- `Read-Host -AsSecureString` is the reliable console fallback whenever a GUI
  credential prompt is unavailable — Server Core, SSH sessions, and constrained VM
  consoles all hit this.
- `PSCredential` needs a plain-text username and a `SecureString` password, in that
  order. Knowing how to build one by hand means never being blocked by a
  non-rendering prompt.
- "Cannot find type" is a .NET type-name error, distinct from a PowerShell cmdlet
  error — it points at spelling in the fully-qualified type name rather than at
  syntax.

---

### Issue 27 — Domain join succeeded: verified end-to-end, not assumed from a lack of errors ✅

**What happened:**
With DNS resolving correctly (Issue 25) and a working credential object (Issue 26),
the join completed and the client rebooted:

```powershell
Add-Computer -DomainName "corp.local" -Credential $cred -Restart
```

The post-reboot lock screen still defaulted to the local `localadmin` account. This
is **expected and not a failure signal**: Windows shows the last interactive user
regardless of join outcome, and the PowerShell method does not display the GUI
"Welcome to the domain" confirmation that `sysdm.cpl` shows.

**Resolution / verification:**
Because the absence of an error is not evidence of success, membership was verified
explicitly. Logged in as `CORP\Administrator` — a **distinct account** from
`localadmin`, so a successful login is itself meaningful — then confirmed:

| Check | Result | What it proves |
|---|---|---|
| `whoami` | `corp\administrator` | The session is authenticated as a **domain** account, not a local one |
| `(Get-WmiObject Win32_ComputerSystem).Domain` | `corp.local` | The machine's domain membership as the OS itself reports it |
| `(Get-WmiObject Win32_ComputerSystem).PartOfDomain` | `True` | Explicit boolean: joined to a domain, not merely in a workgroup with a matching name |

Together these confirm the whole chain is working: **DNS resolution** located the
domain controller, the **machine's secure-channel trust** with the domain is
established, and **Kerberos user authentication** succeeds.

**Status: RESOLVED. Step 5 is complete.**

**What I learned:**
- **"No error" is not verification.** `Add-Computer` completing silently and the
  machine rebooting proves the command ran, not that the join took effect. The three
  checks above test the actual end state.
- Each check covers a different layer, which is why all three matter: `whoami` proves
  *user* authentication, `.Domain` and `.PartOfDomain` prove *machine* membership. A
  machine can be joined while a user login still fails, and vice versa.
- `.Domain` alone is insufficient — a workgroup can be named `corp.local`. `.PartOfDomain`
  is what distinguishes real membership from a coincidentally matching name.
- Logging in with an account that exists **only** in the domain is itself a test. Had
  the join silently failed, `CORP\Administrator` would not have authenticated at all.

---

### Issue 28 — Client rename attempt left behind an orphaned domain-controller-flagged AD object

**What happened:**
The client was still running its Windows-assigned hostname, `WIN-NSHG0FCOL9Q`, while
this documentation referred to it throughout as `WIN11-CLIENT01`. Renaming the machine
to close that gap failed repeatedly:

```powershell
Rename-Computer -NewName "WIN11-CLIENT01" -Restart
```

The first attempt ran without an explicit `-DomainCredential` and got partway through.
A rename on a **domain-joined** machine is a two-phase operation: first a new computer
account is created in AD under the target name, then the local machine identity is
updated and the machine reboots into it. The run was interrupted before the second
phase completed, so the local hostname never changed — but the new AD object had
already been created.

Every subsequent attempt then failed with:

```
The account already exists.
```

Investigating that leftover object turned up something unexpected. The orphaned
`WIN11-CLIENT01` account was flagged internally as a **domain controller account**
rather than a normal workstation, it was sitting in the **Domain Controllers** OU, and
its creation timestamp dated back to the *original, pre-rebuild* client VM — the build
that was scrapped after the network driver and boot corruption problems documented in
Issues 19–23. That earlier abandoned VM had evidently been promoted, or partially
promoted, as a second domain controller under the same intended name before it was
discarded.

Because the object was typed as a DC account with no real server behind it, the normal
cleanup paths both refused:

- `Remove-ADComputer` threw a generic internal error regardless of the object's
  location or whether accidental-deletion protection was cleared.
- Active Directory Users and Computers declined to force-delete it through its live
  snap-in connection, because the object was never a properly promoted, demotable
  domain controller.

**Root cause:**
An interrupted domain-join/rename operation on an earlier, already-abandoned VM build
left dead directory metadata behind, flagged with the wrong account type for the object
it actually represented. The blocking error (`The account already exists`) was accurate;
what made it stubborn was that the pre-existing account was the wrong *kind* of object,
which put it outside the reach of the standard workstation-cleanup tooling.

**Resolution:**
The remaining routes forward were `ntdsutil` metadata cleanup or a direct
`userAccountControl` edit on the object. Both are legitimate fixes, but both operate
directly on forest metadata — disproportionate risk for what is ultimately a cosmetic
hostname mismatch. **The rename was abandoned instead.**

The working client keeps its Windows-assigned hostname, `WIN-NSHG0FCOL9Q`, and
[`../README.md`](../README.md) has been updated to use that name throughout so the
documentation matches reality rather than intent. The orphaned `WIN11-CLIENT01` object
remains in AD, undisturbed: it holds no privileges, takes no part in replication, and
has no effect on DC01's FSMO roles. It is recorded here as a **known artifact**, not as
outstanding work.

**Status: ACCEPTED, not resolved — by design.**

**What I learned:**
- **A domain-joined rename is two operations, not one.** Creating the AD account and
  switching the local machine identity are separate phases, and an interruption between
  them leaves the directory ahead of the machine — with the half-finished state blocking
  every retry.
- **"The account already exists" is a starting point, not a conclusion.** Reading the
  blocking object's actual attributes is what turned a naming collision into the real
  finding: stale DC metadata from a VM that no longer exists.
- **Abandoned lab builds leave residue in the directory.** Deleting a VM does not delete
  what it registered in AD. A build scrapped weeks earlier was still shaping what was
  possible today.
- **Knowing when to stop is part of the skill.** `ntdsutil` metadata cleanup was
  available and would probably have worked. Choosing not to run it against a healthy
  single-DC forest to fix a naming inconsistency — and documenting that choice — is a
  sounder call than proving the tool can be driven.

---

### Issue 29 — RSAT reported a successful install on the client, but the tools were never present

**What happened:**
The plan was to test `jsmith`'s delegated permissions from the Windows 11 client rather
than from the domain controller, which meant installing the AD RSAT tools there first:

```powershell
Add-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"
```

The command returned `Online: True`, `RestartNeeded: False` — every sign of a clean
success. Nothing it should have installed actually worked:

- `Get-Module -ListAvailable ActiveDirectory` returned nothing at all.
- `Import-Module ActiveDirectory` failed with *"no valid module file was found in any
  module directory."*
- `dsa.msc` was not recognised as a command.

**Root cause:**
Querying the capability directly told a different story than the install had:

```powershell
Get-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"
```

Its actual `State` was **`NotPresent`**, with `DownloadSize: 0` and `InstallSize: 0` — the
signature of a Feature-on-Demand package that is simply not published for this client's OS
build through Windows Update. Connectivity was ruled out separately:
`Test-NetConnection -ComputerName download.windowsupdate.com -Port 443` confirmed the
client could reach Windows Update fine. This client runs a **Windows 11 ARM64 Insider
Preview** build, and while the RSAT FOD catalogue is reliably available for mainstream x64
Windows 10/11, it can be incomplete for ARM64 and Insider channels. A zero-byte package
cannot install, and `Add-WindowsCapability` reported success on having nothing to do.

**Resolution:**
Rather than chase a package that may not exist for this build, installing RSAT on the
client was abandoned entirely. All delegation verification was run **directly from DC01**,
which already carries the full AD DS toolset natively as the domain controller — the same
tests, from a host that was never missing the tooling.

**Status: ACCEPTED, not resolved — by design.** Parked the same way the client hostname
rename was in Issue 28 above.

---

### Issue 30 — `runas /netonly` silently failed to apply the alternate identity, invalidating a full round of tests

**What happened:**
Regular domain users are blocked by default from logging on interactively to a domain
controller, so testing `jsmith`'s delegated rights on DC01 called for an alternate
identity rather than a second login:

```powershell
runas /netonly /user:CORP\jsmith powershell
```

`/netonly` is meant to authenticate as the supplied account for any **network** operation
— which is what an AD query is — while leaving the local session's identity in place for
everything else. Inside that window, every AD operation succeeded, **including a password
reset against a user in the deliberately excluded `IT/Admins` OU**. That is the exact
opposite of the expected result: the test that was supposed to be denied passed.

Two plausible causes were checked before doubting the shell itself:

- **An unintended inherited ACE** — whether `IT-Admins` had picked up rights on the
  excluded OU by inheritance from the parent `IT` OU:
  `dsacls "OU=IT,DC=corp,DC=local" | Select-String "IT-Admins"` returned **no matches**.
- **Unintended privileged group membership** — whether `jsmith` or `mgarcia` had landed in
  something like `Account Operators`: `Get-ADPrincipalGroupMembership` came back clean for
  both, showing only `Domain Users`, `IT-Admins`, and `VPN-Users`.

Both were ruled out. A decisive test settled it — creating an OU at the domain root from
inside the `/netonly` window:

```powershell
New-ADOrganizationalUnit -Name "TEST-DELEGATION-CHECK" -Path "DC=corp,DC=local"
```

It **succeeded** — an operation a plain domain user should never be able to perform under
any circumstance.

**Root cause:**
That success proved the window had been running as **Administrator** the entire time.
`/netonly`'s credential substitution never took effect for the ActiveDirectory PowerShell
module's connection — a known rough edge when that module is run directly on a domain
controller, where it defaults to the session's integrated Windows token instead of the
alternate network credentials. Every "pass" from that round of testing was the local
administrator's rights, not `jsmith`'s.

**Resolution:**
Abandoned `/netonly` and switched to passing an explicit `-Credential` object on each
individual AD cmdlet call, built by hand:

```powershell
$pw   = Read-Host "Password" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential("CORP\jsmith", $pw)
```

Supplying the credential per-operation forces the identity unambiguously and sidesteps the
issue entirely. The test OU was removed once the cause was confirmed — clearing
`-ProtectedFromAccidentalDeletion` first, then `Remove-ADOrganizationalUnit`.

---

### Issue 31 — A self-referential permission test produced a misleading "pass"

**What happened:**
Before switching the target to `mgarcia`, delegation was first tested by having `jsmith`
reset **`jsmith`'s own** password. It succeeded — and that result proved nothing.

**Root cause:**
Every AD user object carries a built-in **`SELF`** security principal with its own default
*Change Password* right, independent of any OU-level delegation. A user resetting their own
password exercises that built-in right, not whatever was explicitly delegated to their
group. The underlying error was conflating *"a permission check passed"* with *"the
delegation being tested is what caused it to pass"* — the test had no way to distinguish
the two, so it could not fail for the right reason either.

**Resolution:**
Re-ran the test against **`mgarcia`** — a different member of `IT-Admins`, sitting in the
same excluded `IT/Admins` OU. One account acting on a *different* account is the only
version of this test that exercises OU-level delegation rather than self-service rights.

---

### Issue 32 — A pasted multi-line script was silently swallowed into a single masked password prompt

**What happened:**
After switching to the explicit `-Credential` approach, a multi-line block of PowerShell —
building the credential object, then two `Set-ADAccountPassword` calls — was pasted into
the console in one go. The first line triggered the `Read-Host -AsSecureString` prompt, and
from that moment the console stopped treating the newlines in the rest of the paste as
separate command submissions. Every remaining character, including entire subsequent lines
of code, was absorbed as literal masked input into that one password variable, showing up
as an abnormally long run of asterisks. None of the other pasted lines had executed as
commands at all.

**Root cause:**
Once a masked/secure-string prompt is reading, PowerShell console input does not reliably
treat embedded newlines from a paste as *Enter* the way an unmasked prompt does. The paste
looked like it ran; it was being eaten.

**Resolution:**
Cancelled the pending input with `Ctrl+C` before submitting the corrupted value, then re-ran
the remaining commands **one line at a time**. Adopted as general practice for the rest of
this project: never paste a multi-line block when an interactive prompt like `Read-Host` is
part of it.

**Status: RESOLVED.**

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
| Security groups | `IT-Admins`, `HR-Staff`, `VPN-Users` | Confirmed via `Get-ADGroupMember` |
| User accounts | 10 across the five OUs (`sjohnson`, `kpark` disabled by design) | Confirmed via `Get-ADUser` |
| GPOs | Password Policy (domain root), Screen Lock (IT/HR/Finance/Contractors), USB Block (Contractors) | Linked; confirmed on DC01 via `gpresult /r` |
| Windows 11 ARM client VM | `WIN11-CLIENT01` — UTM Virtualize mode, ARM64, NIC `virtio-net-pci` | Rebuilt from scratch; installed and booting from disk |
| Client network adapter | Red Hat VirtIO Ethernet Adapter | Confirmed working — DHCP IPv4 `192.168.64.4`, gateway and DNS present |
| Client DNS configuration | `192.168.64.10` (DC01); IPv6 disabled on the adapter | Confirmed — `nslookup corp.local` resolves against DC01 |
| Domain join | `WIN11-CLIENT01` joined to `corp.local` | Confirmed — `whoami` = `corp\administrator`, `.Domain` = `corp.local`, `.PartOfDomain` = `True` |
| Client GPO application | Screen Lock and USB Block not yet checked on the client | Pending — `gpresult /r` on `WIN11-CLIENT01` |

---

## Next steps

1. ~~Boot DC01 and confirm hostname shows `DC01`~~ — done
2. ~~Install AD DS role~~ — done
3. ~~Promote to domain controller (create new forest `corp.local`)~~ — done
4. ~~Build OU structure: IT, HR, Finance, Contractors~~ — done (see [`../scripts/new-ou-structure.ps1`](../scripts/new-ou-structure.ps1))
5. ~~Create 10+ user accounts and security groups (`IT-Admins`, `HR-Staff`, `VPN-Users`)~~ — done (see [`../scripts/new-users-and-groups.ps1`](../scripts/new-users-and-groups.ps1))
6. ~~Configure 3 GPOs (password policy, screen lock, USB restriction on Contractors OU)~~ — done, verified on DC01
7. ~~Create Windows 11 ARM client VM~~ — rebuilt from scratch as `WIN11-CLIENT01` with `virtio-net-pci` set before install
8. ~~Install the client's network adapter driver~~ — done, Red Hat VirtIO Ethernet Adapter bound automatically (Issue 24)
9. ~~Configure client DNS to point at DC01 (`192.168.64.10`)~~ — done; required disabling IPv6 on the adapter (Issue 25)
10. ~~Join `WIN11-CLIENT01` to `corp.local` and verify domain login~~ — done and verified end to end (Issue 27)
11. **Verify GPOs applying with `gpresult /r` on the client** — next step; the Screen Lock and USB Block policies target workstations and have only been confirmed on DC01 so far
12. Practice AD user lifecycle operations: password reset, disable/enable, move between OUs

---

## Key commands reference

```powershell
# Check current IP configuration
ipconfig /all

# Set static IP (include -DefaultGateway — omitting it caused Issue 9)
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
