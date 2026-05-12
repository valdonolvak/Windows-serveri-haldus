ÕPILASE SKRIPT

```powershell
# ========================================================
# ACTIVE DIRECTORY + WORDPRESS AUTO GRADER
# FINAL ULTIMATE VERSION - JSON STRUCTURE FIXED
# ========================================================

$ErrorActionPreference = "Continue"

# 1. TURVASEADED (TLS 1.3 ja sertifikaatide ignoreerimine)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor 12288 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

Import-Module ActiveDirectory

# ========================================================
# RESULT OBJECT & HELPER
# ========================================================

$Checks = @()
$TotalPoints = 0

function Add-Check {
    param(
        [string]$Category,
        [string]$Expected,
        [string]$Actual,
        [bool]$Success,
        [double]$Points,
        [double]$MaxPoints
    )

    if ($Success) {
        $Status = "PASS"
        $Awarded = $Points
    }
    else {
        $Status = "FAIL"
        $Awarded = 0
    }

    $global:TotalPoints += $Awarded
    $global:Checks += [PSCustomObject]@{
        Category = $Category
        Expected = $Expected
        Actual   = $Actual
        Status   = $Status
        Points   = $Awarded
        MaxPoints = $MaxPoints
    }
}

# ========================================================
# DOMAIN / STUDENT (Tuvastame nime domeenist)
# ========================================================

try {
    $Domain = Get-ADDomain
    $DomainName = $Domain.DNSRoot
    $Surname = $DomainName.Split(".")[0]
}
catch {
    $Surname = "UNKNOWN"
}

# ========================================================
# 1. SERVERI PÕHISEADISTUS (Hostname & Network)
# ========================================================

# Hostname
$Hostname = $env:COMPUTERNAME
Add-Check "Server Name" "AD1" $Hostname ($Hostname -eq "AD1") 0.5 0.5

# Võrk
$NIC = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "10.0.*" } | Select-Object -First 1

if ($NIC) {
    $IP = $NIC.IPAddress
    Add-Check "IP Address" "10.0.xxx.10" $IP ($IP -match "^10\.0\.\d+\.10$") 0.5 0.5

    $Gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object -First 1).NextHop
    Add-Check "Gateway" "10.0.xxx.1" $Gateway ($Gateway -match "^10\.0\.\d+\.1$") 0.5 0.5

    $DNS = (Get-DnsClientServerAddress -InterfaceIndex $NIC.InterfaceIndex -AddressFamily IPv4).ServerAddresses
    $DNSOK = ($DNS.Count -ge 2 -and $DNS[0] -eq "127.0.0.1" -and $DNS[1] -eq "1.1.1.1")
    Add-Check "DNS Servers" "127.0.0.1, 1.1.1.1" ($DNS -join ", ") $DNSOK 0.5 0.5
}

# Rollid
$ADDS = Get-WindowsFeature AD-Domain-Services
$DNSRole = Get-WindowsFeature DNS
Add-Check "AD DS Role" "Installed" $ADDS.InstallState $ADDS.Installed 0.5 0.5
Add-Check "DNS Role" "Installed" $DNSRole.InstallState $DNSRole.Installed 0.5 0.5

# ========================================================
# 2. ACTIVE DIRECTORY STRUKTUUR (Domain, OUs, Users)
# ========================================================

# Domeeni nimi
Add-Check "Domain" "*.lan" $DomainName ($DomainName -like "*.lan") 1 1

# OUs (Toetab pesastatud struktuuri)
$OU1 = Get-ADOrganizationalUnit -Filter 'Name -eq "KASUTAJAD"'
$OU2 = Get-ADOrganizationalUnit -Filter 'Name -eq "WORDPRESS"'
Add-Check "OU KASUTAJAD" "Exists" $(if($OU1){"Exists"}else{"Missing"}) ($OU1 -ne $null) 1 1
Add-Check "OU WORDPRESS" "Exists" $(if($OU2){"Exists"}else{"Missing"}) ($OU2 -ne $null) 1 1

# Kasutajad (Globaalne otsing üle domeeni)
$User1 = Get-ADUser -Filter 'SamAccountName -eq "pea.toimetaja" -or Name -like "*Pea Toimetaja*"' -Properties PasswordNeverExpires,Enabled | Select-Object -First 1
$User2 = Get-ADUser -Filter 'SamAccountName -eq "abi.toimetaja" -or Name -like "*Abi Toimetaja*"' -Properties PasswordNeverExpires,Enabled | Select-Object -First 1

function Get-UserLocation {
    param($User)
    if ($User) { return ($User.DistinguishedName -split ',', 2)[1] }
    return "Not Found"
}

$User1Location = Get-UserLocation $User1
$User2Location = Get-UserLocation $User2

Add-Check "User pea.toimetaja" "Exists" "Found in: $User1Location" ($User1 -ne $null -and $User1.Enabled -eq $true) 0.5 0.5
Add-Check "User abi.toimetaja" "Exists" "Found in: $User2Location" ($User2 -ne $null -and $User2.Enabled -eq $true) 0.5 0.5

$PWNever = ($User1.PasswordNeverExpires -and $User2.PasswordNeverExpires)
Add-Check "Password Never Expires" "True" "Status: $PWNever" $PWNever 0.5 0.5

# ========================================================
# 3. GRUPI KONTROLL (Fuzzy Matching "KoduleheToimetaja")
# ========================================================

$MatchedGroup = $null
$ActualGroupName = "Missing"
$GroupExists = $false

try {
    $AllGroups = Get-ADGroup -Filter * -Properties Member
    foreach ($g in $AllGroups) {
        $CleanName = ($g.Name -replace '\s','').ToLower()
        if ($CleanName -match "kodulehe" -and $CleanName -match "toim") {
            $MatchedGroup = $g
            $ActualGroupName = $g.Name
            $GroupExists = $true
            break 
        }
    }
    Add-Check "Group KoduleheToimetajad" "Exists" $(if($GroupExists){"Exists ($ActualGroupName)"}else{"Missing"}) $GroupExists 0.5 0.5
} catch {
    Add-Check "Group KoduleheToimetajad" "Exists" "ERROR" $false 0.5 0.5
}

# Grupi liikmed (Kasutades leitud gruppi)
try {
    if ($GroupExists -and $MatchedGroup) {
        $GroupMemberDNs = $MatchedGroup.Member
        $HasPea = ($User1 -ne $null -and $GroupMemberDNs -contains $User1.DistinguishedName)
        $HasAbi = ($User2 -ne $null -and $GroupMemberDNs -contains $User2.DistinguishedName)

        if (-not $HasPea -or -not $HasAbi) {
            $MembersObj = Get-ADGroupMember -Identity $MatchedGroup.DistinguishedName
            $MemberNames = $MembersObj.SamAccountName + $MembersObj.Name
            if (-not $HasPea) { $HasPea = ($MemberNames -match "pea.toimetaja" -or $MemberNames -match "Pea Toimetaja") }
            if (-not $HasAbi) { $HasAbi = ($MemberNames -match "abi.toimetaja" -or $MemberNames -match "Abi Toimetaja") }
        }
        Add-Check "Group Member pea.toimetaja" "Added" $(if($HasPea){"YES"}else{"NO"}) $HasPea 0.5 0.5
        Add-Check "Group Member abi.toimetaja" "Added" $(if($HasAbi){"YES"}else{"NO"}) $HasAbi 0.5 0.5
    } else {
        Add-Check "Group Member pea.toimetaja" "Added" "No Group" $false 0.5 0.5
        Add-Check "Group Member abi.toimetaja" "Added" "No Group" $false 0.5 0.5
    }
} catch {
    Add-Check "Group Members" "Check failed" "ERROR" $false 1 1
}

# ========================================================
# 4. DNS JA VEEBI KONTROLL
# ========================================================

# DNS Kirje
$ProjectHost = "projekt.$Surname.lan"
try {
    $DNSResult = Resolve-DnsName $ProjectHost -ErrorAction Stop
    Add-Check "DNS Record" $ProjectHost ($DNSResult | Where-Object {$_.Type -eq "A"}).IPAddress $true 0.5 0.5
} catch {
    Add-Check "DNS Record" $ProjectHost "NOT FOUND" $false 0.5 0.5
}

# Veebi kättesaadavus
$SiteReachable = $false
foreach ($Proto in @("https", "http")) {
    if ($SiteReachable) { break }
    try {
        $test = curl.exe -s -k -I "$($Proto)://$($ProjectHost)" --connect-timeout 5
        if ($test -match "200 OK") { $SiteReachable = $true; $UsedProto = $Proto }
    } catch { }
}
Add-Check "WordPress Website" "Reachable" $(if($SiteReachable){"YES ($UsedProto)"}else{"UNREACHABLE"}) $SiteReachable 0.5 0.5

# WordPressi autentimine (Sisu-põhine tõekontroll)
$TestPassword = "Passw0rd!"
$LoginSuccess = $false
$LoginMsg = "Sisselogimine ebaõnnestus"
$CookieFile = "$env:TEMP\wp_final_cookies.txt"
if (Test-Path $CookieFile) { Remove-Item $CookieFile }

foreach ($Proto in @("https", "http")) {
    if ($LoginSuccess) { break }
    $LoginUrl = "$($Proto)://$($ProjectHost)/wp-login.php"
    $AdminUrl = "$($Proto)://$($ProjectHost)/wp-admin/index.php"
    try {
        curl.exe -s -k -c $CookieFile "$LoginUrl" --connect-timeout 10 | Out-Null
        $PostData = "log=pea.toimetaja&pwd=$($TestPassword)&wp-submit=Log+In&testcookie=1"
        curl.exe -s -k -b $CookieFile -c $CookieFile -X POST -d "$PostData" "$LoginUrl" --connect-timeout 10 | Out-Null
        $AdminContent = curl.exe -s -k -b $CookieFile -L "$AdminUrl" --connect-timeout 10
        if ($AdminContent -match "wpadminbar" -or $AdminContent -match "Dashboard" -or $AdminContent -match "Töölaud") {
            if ($AdminContent -notmatch "user_login" -and $AdminContent -notmatch "loginform") {
                $LoginSuccess = $true; $LoginMsg = "OK ($($Proto.ToUpper()))"
            }
        }
    } catch { $LoginMsg = "Viga: $($_.Exception.Message)" }
}
Add-Check "WordPress LDAP Login" "pea.toimetaja authenticates" $LoginMsg $LoginSuccess 1 1

# ========================================================
# KOKKUVÕTE JA JSON EKSPORT (image_e0f837.png järgi)
# ========================================================

$TotalPoints = [math]::Round($TotalPoints, 2)
$MaxTotalPoints = [math]::Round(($Checks | Measure-Object -Property MaxPoints -Sum).Sum, 2)

if ($TotalPoints -ge 9) { $Grade = 5 }
elseif ($TotalPoints -ge 7) { $Grade = 4 }
elseif ($TotalPoints -ge 5) { $Grade = 3 }
else { $Grade = "MA" }

# Objekti loomine täpselt soovitud väljadega
$Result = [PSCustomObject]@{
    Student        = $Surname
    Timestamp      = Get-Date
    TotalPoints    = $TotalPoints
    MaxTotalPoints = $MaxTotalPoints
    Grade          = $Grade
    Checks         = $Checks
}

# Salvestamine
$Folder = "$PSScriptRoot\Results"; if (!(Test-Path $Folder)) { New-Item -ItemType Directory -Path $Folder -Force | Out-Null }
$File = Join-Path $Folder "$Surname-result.json"
$Result | ConvertTo-Json -Depth 10 | Out-File $File -Encoding UTF8

Write-Host "`n=================================="
Write-Host "Õpilane: $Surname | Punktid: $TotalPoints / $MaxTotalPoints | Hinne: $Grade"
Write-Host "==================================`n"

```
