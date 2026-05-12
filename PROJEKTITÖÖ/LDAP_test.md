

```powershell
# ========================================================
# ACTIVE DIRECTORY + WORDPRESS AUTO GRADER
# FULLY FIXED VERSION - NESTED OU & TLS 1.3 SUPPORT
# ========================================================

$ErrorActionPreference = "Continue"

# Lubame ebausaldusväärsed sertifikaadid ja kõik TLS protokollid (vajalik HTTPS jaoks)
# Kasutame numbrilisi väärtusi, et tagada ühilduvus (Tls12 = 3072, Tls13 = 12288)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor 12288 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

Import-Module ActiveDirectory

# ========================================================
# RESULT OBJECT
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
# DOMAIN / STUDENT
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
# HOSTNAME
# ========================================================

$Hostname = $env:COMPUTERNAME

Add-Check `
    "Server Name" `
    "AD1" `
    $Hostname `
    ($Hostname -eq "AD1") `
    0.5 `
    0.5

# ========================================================
# NETWORK
# ========================================================

$NIC = Get-NetIPAddress `
    -AddressFamily IPv4 |

    Where-Object {
        $_.IPAddress -like "10.0.*"
    } |

    Select-Object -First 1

if ($NIC) {

    # -----------------------------
    # IP
    # -----------------------------

    $IP = $NIC.IPAddress

    Add-Check `
        "IP Address" `
        "10.0.xxx.10" `
        $IP `
        ($IP -match "^10\.0\.\d+\.10$") `
        0.5 `
        0.5

    # -----------------------------
    # GATEWAY
    # -----------------------------

    $Gateway = (
        Get-NetRoute `
            -DestinationPrefix "0.0.0.0/0" |

        Select-Object -First 1
    ).NextHop

    Add-Check `
        "Gateway" `
        "10.0.xxx.1" `
        $Gateway `
        ($Gateway -match "^10\.0\.\d+\.1$") `
        0.5 `
        0.5

    # -----------------------------
    # DNS
    # -----------------------------

    $DNS = (
        Get-DnsClientServerAddress `
            -InterfaceIndex $NIC.InterfaceIndex `
            -AddressFamily IPv4
    ).ServerAddresses

    $DNSOK = (
        $DNS.Count -ge 2 -and
        $DNS[0] -eq "127.0.0.1" -and
        $DNS[1] -eq "1.1.1.1"
    )

    Add-Check `
        "DNS Servers" `
        "127.0.0.1, 1.1.1.1" `
        ($DNS -join ", ") `
        $DNSOK `
        0.5 `
        0.5
}

# ========================================================
# WINDOWS ROLES
# ========================================================

$ADDS = Get-WindowsFeature AD-Domain-Services
$DNSRole = Get-WindowsFeature DNS

Add-Check `
    "AD DS Role" `
    "Installed" `
    $ADDS.InstallState `
    $ADDS.Installed `
    0.5 `
    0.5

Add-Check `
    "DNS Role" `
    "Installed" `
    $DNSRole.InstallState `
    $DNSRole.Installed `
    0.5 `
    0.5

# ========================================================
# DOMAIN
# ========================================================

try {

    Add-Check `
        "Domain" `
        "*.lan" `
        $DomainName `
        ($DomainName -like "*.lan") `
        1 `
        1
}
catch {

    Add-Check `
        "Domain" `
        "*.lan" `
        "NOT FOUND" `
        $false `
        1 `
        1
}

# ========================================================
# OUs
# ========================================================

$OU1 = Get-ADOrganizationalUnit -Filter 'Name -eq "KASUTAJAD"'
$OU2 = Get-ADOrganizationalUnit -Filter 'Name -eq "WORDPRESS"'

Add-Check `
    "OU KASUTAJAD" `
    "Exists" `
    $(if($OU1){"Exists"}else{"Missing"}) `
    ($OU1 -ne $null) `
    1 `
    1

Add-Check `
    "OU WORDPRESS" `
    "Exists" `
    $(if($OU2){"Exists"}else{"Missing"}) `
    ($OU2 -ne $null) `
    1 `
    1

# ========================================================
# USERS
# ========================================================

$User1 = Get-ADUser -Filter 'SamAccountName -eq "pea.toimetaja"' -Properties PasswordNeverExpires,Enabled
$User2 = Get-ADUser -Filter 'SamAccountName -eq "abi.toimetaja"' -Properties PasswordNeverExpires,Enabled

Add-Check `
    "User pea.toimetaja" `
    "Exists + Enabled" `
    $(if($User1){"Exists"}else{"Missing"}) `
    ($User1.Enabled -eq $true) `
    0.5 `
    0.5

Add-Check `
    "User abi.toimetaja" `
    "Exists + Enabled" `
    $(if($User2){"Exists"}else{"Missing"}) `
    ($User2.Enabled -eq $true) `
    0.5 `
    0.5

# ========================================================
# PASSWORD NEVER EXPIRES
# ========================================================

$PWNever = (
    $User1.PasswordNeverExpires -and
    $User2.PasswordNeverExpires
)

Add-Check `
    "Password Never Expires" `
    "True" `
    "$($User1.PasswordNeverExpires), $($User2.PasswordNeverExpires)" `
    $PWNever `
    0.5 `
    0.5

# ========================================================
# WORDPRESS GROUP
# ========================================================

try {
    $WPGroup = Get-ADGroup -Filter 'Name -eq "KoduleheToimetajad"'
    $GroupExists = ($WPGroup -ne $null)

    Add-Check `
        "Group KoduleheToimetajad" `
        "Exists" `
        $(if($GroupExists){"Exists"}else{"Missing"}) `
        $GroupExists `
        0.5 `
        0.5
}
catch {

    Add-Check `
        "Group KoduleheToimetajad" `
        "Exists" `
        "NOT FOUND" `
        $false `
        0.5 `
        0.5
}

# ========================================================
# GROUP MEMBERS
# ========================================================

try {

    $Members = Get-ADGroupMember "KoduleheToimetajad"

    $HasPea = (
        $Members.SamAccountName `
            -contains "pea.toimetaja"
    )

    $HasAbi = (
        $Members.SamAccountName `
            -contains "abi.toimetaja"
    )

    Add-Check `
        "Group Member pea.toimetaja" `
        "Added to group" `
        $(if($HasPea){"YES"}else{"NO"}) `
        $HasPea `
        0.5 `
        0.5

    Add-Check `
        "Group Member abi.toimetaja" `
        "Added to group" `
        $(if($HasAbi){"YES"}else{"NO"}) `
        $HasAbi `
        0.5 `
        0.5
}
catch {

    Add-Check `
        "Group Members" `
        "Users added" `
        "ERROR" `
        $false `
        1 `
        1
}

# ========================================================
# DNS RECORD
# ========================================================

$ProjectHost = "projekt.$Surname.lan"

try {

    $DNSResult = Resolve-DnsName `
        $ProjectHost -ErrorAction Stop

    $ProjectIP = (
        $DNSResult |

        Where-Object {
            $_.Type -eq "A"
        }
    ).IPAddress

    Add-Check `
        "DNS Record" `
        $ProjectHost `
        $ProjectIP `
        $true `
        0.5 `
        0.5
}
catch {

    Add-Check `
        "DNS Record" `
        $ProjectHost `
        "NOT FOUND" `
        $false `
        0.5 `
        0.5
}

# ========================================================
# WORDPRESS WEBSITE
# ========================================================

$SiteReachable = $false
$UsedProto = ""

foreach ($Proto in @("https", "http")) {
    if ($SiteReachable) { break }
    try {
        $Response = Invoke-WebRequest -Uri "$($Proto)://$($ProjectHost)" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        if ($Response.StatusCode -eq 200) {
            $SiteReachable = $true
            $UsedProto = $Proto
        }
    } catch { }
}

Add-Check `
    "WordPress Website" `
    "Reachable" `
    $(if($SiteReachable){"YES ($UsedProto)"}else{"UNREACHABLE"}) `
    $SiteReachable `
    0.5 `
    0.5

# ========================================================
# WORDPRESS LDAP LOGIN TEST
# ========================================================

$TestPassword = "Passw0rd!"
$LoginSuccess = $false
$LoginError = "No connection successful"
$UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

foreach ($Proto in @("https", "http")) {
    if ($LoginSuccess) { break }
    
    try {
        $LoginUrl = "$($Proto)://$($ProjectHost)/wp-login.php"
        $Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $Session.UserAgent = $UserAgent

        # 1. AVA LOGIN LEHT (Testcookie saamiseks)
        $InitialPage = Invoke-WebRequest -Uri $LoginUrl -WebSession $Session -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop

        # 2. LOGIN ANDMED
        $Body = @{
            log           = "pea.toimetaja@$DomainName"
            pwd           = $TestPassword
            "wp-submit"   = "Log In"
            testcookie    = "1"
        }

        # 3. SAADA POST PÄRING
        $Response = Invoke-WebRequest `
            -Uri $LoginUrl `
            -Method POST `
            -Body $Body `
            -WebSession $Session `
            -UseBasicParsing `
            -TimeoutSec 15 `
            -ErrorAction Stop

        # 4. KONTROLLI KÜPSIST VÕI SISU
        $LoggedInCookie = $Session.Cookies.GetCookies($LoginUrl) | Where-Object { $_.Name -like "*wordpress_logged_in*" }
        
        if ($LoggedInCookie.Count -gt 0 -or $Response.Content -match "wp-admin") {
            $LoginSuccess = $true
            $LoginError = "OK ($($Proto.ToUpper()))"
        }
        else {
            $LoginError = "Login failed: Invalid credentials or plugin not configured ($($Proto.ToUpper()))"
        }
    } 
    catch {
        # Salvestame vea, et näha miks konkreetne protokoll ebaõnnestus
        $LoginError = "Error on $($Proto.ToUpper()): $($_.Exception.Message)"
    }
}

Add-Check `
    "WordPress LDAP Login" `
    "pea.toimetaja authenticates" `
    $LoginError `
    $LoginSuccess `
    1 `
    1

# ========================================================
# FINAL SCORE
# ========================================================

$TotalPoints = [math]::Round(
    $TotalPoints,
    2
)

$MaxTotalPoints = [math]::Round(
    (
        $Checks |

        Measure-Object `
            -Property MaxPoints `
            -Sum
    ).Sum,
    2
)

# ========================================================
# GRADE
# ========================================================

if ($TotalPoints -ge 9) {

    $Grade = 5
}
elseif ($TotalPoints -ge 7) {

    $Grade = 4
}
elseif ($TotalPoints -ge 5) {

    $Grade = 3
}
else {

    $Grade = "MA"
}

# ========================================================
# RESULT OBJECT
# ========================================================

$Result = [PSCustomObject]@{

    Student = $Surname
    Timestamp = Get-Date
    TotalPoints = $TotalPoints
    MaxTotalPoints = $MaxTotalPoints
    Grade = $Grade
    Checks = $Checks
}

# ========================================================
# SAVE JSON
# ========================================================

$Folder = "$PSScriptRoot\Results"

if (!(Test-Path $Folder)) {

    New-Item `
        -ItemType Directory `
        -Path $Folder `
        -Force | Out-Null
}

$File = Join-Path `
    $Folder `
    "$Surname-result.json"

$Result |

    ConvertTo-Json -Depth 10 |

    Out-File `
        $File `
        -Encoding UTF8

# ========================================================
# OUTPUT
# ========================================================

Write-Host ""
Write-Host "=================================="
Write-Host "KONTROLL LÕPETATUD"
Write-Host "=================================="
Write-Host ""

Write-Host "Õpilane: $Surname"
Write-Host "Punktid: $TotalPoints / $MaxTotalPoints"
Write-Host "Hinne: $Grade"

Write-Host ""
Write-Host "JSON:"
Write-Host $File
Write-Host ""

```
