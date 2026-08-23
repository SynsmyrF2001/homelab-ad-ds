<#
.SYNOPSIS
    Creates the standard OU (Organizational Unit) structure for the corp.local domain.
.DESCRIPTION
    Recreates, via PowerShell, the OU hierarchy originally built manually through
    Active Directory Users and Computers (ADUC). Idempotent note: this will error
    on OUs that already exist — intended as documentation of the build, and as a
    starting point for provisioning a fresh domain the same way.
#>

# Top-level OUs — each maps to a simulated department in the lab org structure.
New-ADOrganizationalUnit -Name "IT" -Path "DC=corp,DC=local"
New-ADOrganizationalUnit -Name "HR" -Path "DC=corp,DC=local"
New-ADOrganizationalUnit -Name "Finance" -Path "DC=corp,DC=local"
New-ADOrganizationalUnit -Name "Contractors" -Path "DC=corp,DC=local"

# Sub-OUs under IT — split so GPOs and delegated permissions can differ between
# admins and helpdesk staff without affecting the rest of the IT department.
New-ADOrganizationalUnit -Name "Admins" -Path "OU=IT,DC=corp,DC=local"
New-ADOrganizationalUnit -Name "Helpdesk" -Path "OU=IT,DC=corp,DC=local"
