<#
.SYNOPSIS
    Provisions the lab's security groups and 10 user accounts across the existing
    OU structure (IT/Admins, IT/Helpdesk, HR, Finance, Contractors).
.DESCRIPTION
    Run this in an elevated PowerShell window on DC01, AFTER the OU structure
    script (new-ou-structure.ps1) has already been run.

    Design note: instead of writing 10 near-identical New-ADUser calls, this
    script defines the users as a data array and loops over it. In a real
    organization this array would usually be populated from a CSV exported by
    HR (Import-Csv), not hardcoded — this is a small step toward that pattern.
.PARAMETER AccountPassword
    The initial temporary password applied to all ten accounts, as a SecureString.
    Mandatory — if omitted, PowerShell prompts for it with masked input. Combined
    with -ChangePasswordAtLogon below, each user replaces it on first login.
.EXAMPLE
    .\new-users-and-groups.ps1

    Prompts for the temporary password, then provisions the groups and accounts.
.EXAMPLE
    $pw = Read-Host -AsSecureString
    .\new-users-and-groups.ps1 -AccountPassword $pw

    Supplies the password explicitly instead of being prompted.
#>

param(
    [Parameter(Mandatory)]
    [SecureString]$AccountPassword
)

# ---------------------------------------------------------------------------
# 1. Shared lab password
# ---------------------------------------------------------------------------
# The password arrives as a mandatory SecureString parameter rather than being
# hardcoded here. Two reasons:
#
#   1. This repository is public. Anything committed stays in git history
#      permanently, so a password literal in this file would remain exposed
#      even after being removed in a later commit.
#   2. New-ADUser requires a SecureString, not plain text. Taking one directly
#      means the password is never held as a bare, greppable string inside this
#      script at all — which is exactly what ConvertTo-SecureString
#      -AsPlainText -Force would have forced us to do, and why that combination
#      demands the -Force flag to acknowledge the risk.
#
# Because the parameter is Mandatory, running the script with no arguments makes
# PowerShell prompt for the value with masked input.
#
# The original lab run used one shared temporary password across all ten
# accounts, paired with -ChangePasswordAtLogon so each user sets their own on
# first login. A real onboarding script would go further still and generate a
# random password per user, delivered out of band.
$securePassword = $AccountPassword

# ---------------------------------------------------------------------------
# 2. Security groups
# ---------------------------------------------------------------------------
# GroupScope Global is the standard choice for "a group of users who share a
# role," as opposed to DomainLocal (typically used to grant access to a
# specific resource) or Universal (multi-domain forests) — not a concern yet
# in a single-domain lab, but the distinction is worth knowing for Network+/
# interview purposes.
#
# All three groups are placed in OU=IT here, on the convention that IT owns
# and administers security groups even when the group represents another
# department's staff (HR-Staff is an IT-managed group, not an HR-managed
# one). An equally valid alternative — common in larger environments — is a
# dedicated top-level "Groups" OU separate from user OUs entirely; that's a
# reasonable future refactor if you want to practice restructuring later.

New-ADGroup -Name "IT-Admins" -GroupScope Global -GroupCategory Security `
    -Path "OU=IT,DC=corp,DC=local" `
    -Description "Full IT administrative access"

New-ADGroup -Name "HR-Staff" -GroupScope Global -GroupCategory Security `
    -Path "OU=IT,DC=corp,DC=local" `
    -Description "HR department staff"

New-ADGroup -Name "VPN-Users" -GroupScope Global -GroupCategory Security `
    -Path "OU=IT,DC=corp,DC=local" `
    -Description "Users authorized for remote VPN access"

# ---------------------------------------------------------------------------
# 3. User data
# ---------------------------------------------------------------------------
# Two accounts (sjohnson, kpark) are created disabled on purpose — one models
# an offboarded employee, the other an expired contractor. That gives you
# real accounts to practice Enable-ADAccount / Disable-ADAccount against
# instead of only ever disabling accounts you just created yourself.
#
# Note: this does NOT create a "locked out" account — lockout only happens
# after a real string of failed logon attempts against a lockout policy, and
# your domain doesn't have an account lockout threshold configured yet
# (that's part of the Password Policy GPO in Step 4). Once that GPO is
# linked, you can trigger a real lockout on purpose — e.g. attempt to log on
# as dchen with a wrong password enough times — and then practice
# Unlock-ADAccount against a genuine lockout instead of a simulated one.

$Users = @(
    [PSCustomObject]@{ First='John';    Last='Smith';   Sam='jsmith';   OU='OU=Admins,OU=IT,DC=corp,DC=local';   Title='IT Administrator';      Dept='IT';          Enabled=$true;  Groups=@('IT-Admins','VPN-Users') }
    [PSCustomObject]@{ First='Maria';   Last='Garcia';  Sam='mgarcia';  OU='OU=Admins,OU=IT,DC=corp,DC=local';   Title='IT Administrator';      Dept='IT';          Enabled=$true;  Groups=@('IT-Admins','VPN-Users') }
    [PSCustomObject]@{ First='David';   Last='Chen';    Sam='dchen';    OU='OU=Helpdesk,OU=IT,DC=corp,DC=local'; Title='Helpdesk Technician';   Dept='IT';          Enabled=$true;  Groups=@('VPN-Users') }
    [PSCustomObject]@{ First='Sarah';   Last='Johnson'; Sam='sjohnson'; OU='OU=Helpdesk,OU=IT,DC=corp,DC=local'; Title='Helpdesk Technician';   Dept='IT';          Enabled=$false; Groups=@() }
    [PSCustomObject]@{ First='Emily';   Last='Davis';   Sam='edavis';   OU='OU=HR,DC=corp,DC=local';             Title='HR Generalist';         Dept='HR';          Enabled=$true;  Groups=@('HR-Staff') }
    [PSCustomObject]@{ First='Michael'; Last='Brown';   Sam='mbrown';   OU='OU=HR,DC=corp,DC=local';             Title='HR Manager';            Dept='HR';          Enabled=$true;  Groups=@('HR-Staff','VPN-Users') }
    [PSCustomObject]@{ First='Jessica'; Last='Wilson';  Sam='jwilson';  OU='OU=Finance,DC=corp,DC=local';        Title='Financial Analyst';     Dept='Finance';     Enabled=$true;  Groups=@() }
    [PSCustomObject]@{ First='Robert';  Last='Taylor';  Sam='rtaylor';  OU='OU=Finance,DC=corp,DC=local';        Title='Finance Manager';       Dept='Finance';     Enabled=$true;  Groups=@('VPN-Users') }
    [PSCustomObject]@{ First='Alex';    Last='Nguyen';  Sam='anguyen';  OU='OU=Contractors,DC=corp,DC=local';    Title='Contractor - Web Dev';  Dept='Contractors'; Enabled=$true;  Groups=@('VPN-Users') }
    [PSCustomObject]@{ First='Kevin';   Last='Park';    Sam='kpark';    OU='OU=Contractors,DC=corp,DC=local';    Title='Contractor - Data Entry'; Dept='Contractors'; Enabled=$false; Groups=@() }
)

# ---------------------------------------------------------------------------
# 4. Create the users
# ---------------------------------------------------------------------------
# ChangePasswordAtLogon is set to $true for every account, mirroring real
# onboarding practice: IT issues a known temporary password, and the user is
# forced to set their own on first login so IT never actually knows their
# real password going forward. Note you CANNOT combine
# -ChangePasswordAtLogon $true with -PasswordNeverExpires $true — AD will
# reject that combination, since "must change at next logon" and "never
# expires" are contradictory states.

foreach ($u in $Users) {
    $fullName = "$($u.First) $($u.Last)"
    $upn = "$($u.Sam)@corp.local"

    New-ADUser `
        -Name $fullName `
        -GivenName $u.First `
        -Surname $u.Last `
        -SamAccountName $u.Sam `
        -UserPrincipalName $upn `
        -Path $u.OU `
        -Title $u.Title `
        -Department $u.Dept `
        -Description $u.Title `
        -AccountPassword $securePassword `
        -Enabled $u.Enabled `
        -ChangePasswordAtLogon $true

    Write-Host "Created $fullName ($($u.Sam)) in $($u.OU) [Enabled: $($u.Enabled)]"
}

# ---------------------------------------------------------------------------
# 5. Add users to their groups
# ---------------------------------------------------------------------------
# This runs as a separate pass AFTER all users exist, not inline with user
# creation above. Add-ADGroupMember needs both the group and the user to
# already exist — since the groups were created in step 2 and all users in
# step 4, every membership below is guaranteed to resolve correctly
# regardless of array order.

foreach ($u in $Users) {
    foreach ($groupName in $u.Groups) {
        Add-ADGroupMember -Identity $groupName -Members $u.Sam
        Write-Host "Added $($u.Sam) to $groupName"
    }
}

Write-Host "`nDone. Verify with:"
Write-Host "  Get-ADUser -Filter * -Properties Enabled,Title | Select-Object Name,SamAccountName,Enabled,Title,DistinguishedName | Format-Table -AutoSize"
Write-Host "  Get-ADGroupMember -Identity IT-Admins"
Write-Host "  Get-ADGroupMember -Identity HR-Staff"
Write-Host "  Get-ADGroupMember -Identity VPN-Users"
