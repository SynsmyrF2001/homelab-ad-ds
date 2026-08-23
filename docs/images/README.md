# Screenshots

Evidence captured during the build, referenced from
[`../troubleshooting-log.md`](../troubleshooting-log.md).

Save each screenshot into this folder using the filename below so the links in the
troubleshooting log resolve. Timestamps are taken from the Windows taskbar clock in
each capture.

| Filename | Timestamp | What it shows | Related issue |
|---|---|---|---|
| `01-server-manager-dashboard.png` | 8/19/2026 9:32 PM | Server Manager dashboard on first load — Roles: 1, before AD DS was added | — |
| `02-ipconfig-before-static-ip.png` | 8/19/2026 9:34 PM | `ipconfig` showing the UTM NAT-assigned address `192.168.64.2` before static configuration | — |
| `03-new-netipaddress-static-ip.png` | 8/19/2026 9:49 PM | `New-NetIPAddress` setting `192.168.64.10/24`; note `AddressState: Tentative` (ActiveStore) and `Invalid` (PersistentStore) | Issue 9 |
| `04-set-dns-and-ipconfig-all.png` | 8/19/2026 9:58 PM | `Set-DnsClientServerAddress` pointing DNS at self, then `ipconfig /all` — IPv4 `192.168.64.10(Preferred)`, `DHCP Enabled: No`, and **no IPv4 default gateway listed** | Issue 9 |
| `05-new-netaddress-typo.png` | 8/20/2026 11:36 AM | `New-NetAddress` typo raising `CommandNotFoundException`, corrected to `New-NetIPAddress`; "Activate Windows" watermark visible | Issues 9, 10, 14 |
| `06-install-windowsfeature-progress.png` | 8/20/2026 7:45 PM | AD DS role installation in progress at 60% | — |
| `07-install-windowsfeature-success.png` | 8/20/2026 7:54 PM | `hostname` returning `DC01`, and `Install-WindowsFeature` completing with `Success: True`, `Restart Needed: No` | — |
| `08-install-addsforest-prerequisites.png` | 8/20/2026 8:04 PM | `Install-ADDSForest` running its prerequisite check, with the full command and the `SafeModeAdministratorPassword` (DSRM) prompt visible | Issue 12 |
| `09-azure-arc-0xc0000142.png` | — | `azcmagent.exe - Application Error (0xc0000142)` dialog on boot | Issue 7 |
