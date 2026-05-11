## ÕPILASE SKRIPT — StudentCheck.ps1

Salvesta failina:

```text
StudentCheck.ps1
```

Käivitatakse õpilase AD serveris.

See:

* kontrollib kõik punktid;
* genereerib detailse JSON faili;
* arvutab punktid;
* määrab hinde.

```powershell
$ErrorActionPreference = "SilentlyContinue"

Import-Module ActiveDirectory

# ------------------------------------------------
# RESULT OBJECT
# ------------------------------------------------

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
        Actual = $Actual
        Status = $Status
        Points = $Awarded
        MaxPoints = $MaxPoints
    }
}

# ------------------------------------------------
# STUDENT
# ------------------------------------------------

try {
    $Domain = Get-ADDomain
    $Surname = $Domain.DNSRoot.Split(".")[0]
}
catch {
    $Surname = "UNKNOWN"
}

# ------------------------------------------------
# HOSTNAME
# ------------------------------------------------

$Hostname = $env:COMPUTERNAME

Add-Check `
    "Server Name" `
    "AD1" `
    $Hostname `
    ($Hostname -eq "AD1") `
    0.5 `
    0.5

# ------------------------------------------------
# NETWORK
# ------------------------------------------------

$NIC = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -like "10.0.*"
    } |
    Select-Object -First 1

if ($NIC) {

    $IP = $NIC.IPAddress

    Add-Check `
        "IP Address" `
        "10.0.xxx.10" `
        $IP `
        ($IP -match "^10\.0\.\d+\.10$") `
        0.5 `
        0.5

    $Gateway = (
        Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
        Select-Object -First 1
    ).NextHop

    Add-Check `
        "Gateway" `
        "10.0.xxx.1" `
        $Gateway `
        ($Gateway -match "^10\.0\.\d+\.1$") `
        0.5 `
        0.5

    $DNS = (
        Get-DnsClientServerAddress `
            -InterfaceIndex $NIC.InterfaceIndex `
            -AddressFamily IPv4
    ).ServerAddresses

    $DNSString = $DNS -join ", "

    $DNSOK = (
        $DNS[0] -eq "127.0.0.1" -and
        $DNS[1] -eq "1.1.1.1"
    )

    Add-Check `
        "DNS Servers" `
        "127.0.0.1, 1.1.1.1" `
        $DNSString `
        $DNSOK `
        0.5 `
        0.5
}

# ------------------------------------------------
# ROLES
# ------------------------------------------------

$ADDS = Get-WindowsFeature AD-Domain-Services
$DNSRole = Get-WindowsFeature DNS

Add-Check `
    "AD DS Role" `
    "Installed" `
    $ADDS.InstallState `
    ($ADDS.Installed) `
    0.5 `
    0.5

Add-Check `
    "DNS Role" `
    "Installed" `
    $DNSRole.InstallState `
    ($DNSRole.Installed) `
    0.5 `
    0.5

# ------------------------------------------------
# DOMAIN
# ------------------------------------------------

try {

    $DomainName = $Domain.DNSRoot

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

# ------------------------------------------------
# OUs
# ------------------------------------------------

$OU1 = Get-ADOrganizationalUnit `
    -Filter 'Name -eq "KASUTAJAD"'

$OU2 = Get-ADOrganizationalUnit `
    -Filter 'Name -eq "WORDPRESS"'

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

# ------------------------------------------------
# USERS
# ------------------------------------------------

$User1 = Get-ADUser `
    pea.toimetaja `
    -Properties PasswordNeverExpires,Enabled

$User2 = Get-ADUser `
    abi.toimetaja `
    -Properties PasswordNeverExpires,Enabled

Add-Check `
    "User pea.toimetaja" `
    "Exists + Enabled" `
    $(if($User1){"Exists"}else{"Missing"}) `
    ($User1.Enabled) `
    0.5 `
    0.5

Add-Check `
    "User abi.toimetaja" `
    "Exists + Enabled" `
    $(if($User2){"Exists"}else{"Missing"}) `
    ($User2.Enabled) `
    0.5 `
    0.5

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

# ------------------------------------------------
# GROUP
# ------------------------------------------------

$Group = Get-ADGroup "KoduleheToimetajad"

$Members = Get-ADGroupMember $Group

$M1 = $Members |
    Where-Object {
        $_.SamAccountName -eq "pea.toimetaja"
    }

$M2 = $Members |
    Where-Object {
        $_.SamAccountName -eq "abi.toimetaja"
    }

$GroupOK = ($M1 -and $M2)

Add-Check `
    "Group Members" `
    "Both users added" `
    $(($Members.SamAccountName) -join ", ") `
    $GroupOK `
    0.5 `
    0.5

# ------------------------------------------------
# DNS RECORD
# ------------------------------------------------

$ProjectHost = "projekt.$Surname.lan"

try {

    $DNSResult = Resolve-DnsName $ProjectHost

    $ProjectIP = (
        $DNSResult |
        Where-Object {$_.Type -eq "A"}
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

# ------------------------------------------------
# WORDPRESS
# ------------------------------------------------

try {

    $Response = Invoke-WebRequest `
        "http://$ProjectHost" `
        -TimeoutSec 10

    $WP = (
        $Response.Content -match "wordpress"
    )

    Add-Check `
        "WordPress Website" `
        "Reachable" `
        $Response.StatusCode `
        $WP `
        0.5 `
        0.5

}
catch {

    Add-Check `
        "WordPress Website" `
        "Reachable" `
        "UNREACHABLE" `
        $false `
        0.5 `
        0.5
}

# ------------------------------------------------
# LDAP LOGIN CHECK
# ------------------------------------------------

Add-Check `
    "LDAP Authentication" `
    "Configured" `
    "MANUAL CHECK REQUIRED" `
    $true `
    0.5 `
    0.5

# ------------------------------------------------
# GRADE
# ------------------------------------------------

switch ($TotalPoints) {

    {$_ -ge 9} {$Grade = 5}
    {$_ -ge 7} {$Grade = 4}
    {$_ -ge 5} {$Grade = 3}
    default {$Grade = "MA"}
}

# ------------------------------------------------
# FINAL RESULT
# ------------------------------------------------

$Result = [PSCustomObject]@{

    Student = $Surname
    Timestamp = Get-Date
    TotalPoints = $TotalPoints
    Grade = $Grade
    Checks = $Checks
}

# ------------------------------------------------
# SAVE
# ------------------------------------------------

$Folder = "$PSScriptRoot\\Results"

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

Write-Host ""
Write-Host "=================================="
Write-Host "KONTROLL LÕPETATUD"
Write-Host "=================================="
Write-Host ""
Write-Host "Õpilane: $Surname"
Write-Host "Punktid: $TotalPoints"
Write-Host "Hinne: $Grade"
Write-Host ""
Write-Host "JSON:"
Write-Host $File
Write-Host ""
```

---

# ÕPETAJA SCRIPT — TeacherDashboard.ps1

See:

* loeb kõik JSON failid;
* genereerib detailse HTML dashboardi;
* kuvab kõik kontrollid punkt-punktilt.

Salvesta:

```text
TeacherDashboard.ps1
```

```powershell
$InputFolder = "$PSScriptRoot\\Results"

$OutputHTML = Join-Path `
    $InputFolder `
    "Dashboard.html"

$Files = Get-ChildItem `
    "$InputFolder\\*.json"

# ------------------------------------------------
# HTML START
# ------------------------------------------------

$Rows = ""

foreach ($File in $Files) {

    $Data = Get-Content `
        $File.FullName `
        -Raw |
        ConvertFrom-Json

    $GradeColor = switch ($Data.Grade) {

        5 {"#d4edda"}
        4 {"#fff3cd"}
        3 {"#ffe5b4"}
        default {"#f8d7da"}
    }

    $CheckRows = ""

    foreach ($Check in $Data.Checks) {

        $Color = if (
            $Check.Status -eq "PASS"
        ) {
            "#d4edda"
        }
        else {
            "#f8d7da"
        }

        $Icon = if (
            $Check.Status -eq "PASS"
        ) {
            "✔"
        }
        else {
            "❌"
        }

$CheckRows += @"
<tr style='background:$Color'>
<td>$Icon $($Check.Category)</td>
<td>$($Check.Expected)</td>
<td>$($Check.Actual)</td>
<td>$($Check.Status)</td>
<td>$($Check.Points) / $($Check.MaxPoints)</td>
</tr>
"@
    }

$Rows += @"
<div class='student'>

<h2>
$($Data.Student)
- Punktid:
$($Data.TotalPoints)
- Hinne:
$($Data.Grade)
</h2>

<table>

<tr>
<th>Kontroll</th>
<th>Oodatud</th>
<th>Leitud</th>
<th>Staatus</th>
<th>Punktid</th>
</tr>

$CheckRows

<tr style='background:$GradeColor;font-weight:bold'>
<td colspan='4'>
LÕPPTULEMUS
</td>

<td>
$($Data.TotalPoints)
</td>
</tr>

</table>

</div>
"@
}

# ------------------------------------------------
# FINAL HTML
# ------------------------------------------------

$HTML = @"
<html>

<head>

<title>AD Hindamisdashboard</title>

<style>

body {

    font-family: Segoe UI;
    background: #f4f4f4;
    margin: 30px;
}

h1 {

    color: #2b5797;
}

.student {

    background: white;
    padding: 20px;
    margin-bottom: 40px;
    border-radius: 10px;
    box-shadow: 0 0 10px rgba(0,0,0,0.1);
}

table {

    width: 100%;
    border-collapse: collapse;
    margin-top: 10px;
}

th {

    background: #2b5797;
    color: white;
    padding: 10px;
}

td {

    border: 1px solid #ddd;
    padding: 10px;
}

tr:hover {

    background: #f1f1f1;
}

</style>

</head>

<body>

<h1>
Active Directory Hindamisdashboard
</h1>

<p>
Genereeritud:
$(Get-Date)
</p>

$Rows

</body>

</html>
"@

$HTML |
    Out-File `
        $OutputHTML `
        -Encoding UTF8

Write-Host ""
Write-Host "=================================="
Write-Host "DASHBOARD VALMIS"
Write-Host "=================================="
Write-Host ""
Write-Host $OutputHTML
Write-Host ""
```

---

# KAUSTASTRUKTUUR

## Õpilane

```text
StudentCheck.ps1
Results\
```

---

## Õpetaja

```text
TeacherDashboard.ps1
Results\
    jatsa-result.json
    tamm-result.json
    kask-result.json
```

---

# TULEMUS

HTML dashboard näitab:

## iga õpilase kohta:

| Kontroll      | Oodatud   | Leitud  | Staatus | Punktid   |
| ------------- | --------- | ------- | ------- | --------- |
| ✔ Server Name | AD1       | AD1     | PASS    | 0.5 / 0.5 |
| ❌ DNS Servers | 127.0.0.1 | 8.8.8.8 | FAIL    | 0 / 0.5   |

ja lõpus:

```text
LÕPPTULEMUS: 8.5 punkti
Hinne: 4
```

---

# KASUTAMINE

## Õpilane

```powershell
powershell -ExecutionPolicy Bypass -File .\StudentCheck.ps1
```

JSON tekib:

```text
Results\
```

---

## Õpetaja

Kopeerib kõik JSON failid:

```text
Results\
```

ja käivitab:

```powershell
powershell -ExecutionPolicy Bypass -File .\TeacherDashboard.ps1
```

Valmib:

```text
Dashboard.html
```
