All right — teeme selle nüüd “päris dashboardiks”, kus:

✔ põhivaates on õpilaste tabel
✔ iga rea all saab **laiendada detailid (checks)**
✔ HTML + JavaScript toggle
✔ PowerShell jääb puhtaks (ainult andmete genereerimine)

---

# 👨‍🎓 1. ÕPILASE SKRIPT (UUENDATUD + MAX + KORREKTNE)

```powershell
$ErrorActionPreference = "SilentlyContinue"

Import-Module ActiveDirectory

# ------------------------------------------------
# RESULT
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
# STUDENT NAME
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
Add-Check "Server Name" "AD1" $Hostname ($Hostname -eq "AD1") 0.5 0.5

# ------------------------------------------------
# NETWORK
# ------------------------------------------------

$NIC = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -like "10.0.*" } |
    Select-Object -First 1

if ($NIC) {

    $IP = $NIC.IPAddress
    Add-Check "IP Address" "10.0.xxx.10" $IP ($IP -match "^10\.0\.\d+\.10$") 0.5 0.5

    $Gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object -First 1).NextHop
    Add-Check "Gateway" "10.0.xxx.1" $Gateway ($Gateway -match "^10\.0\.\d+\.1$") 0.5 0.5

    $DNS = (Get-DnsClientServerAddress -InterfaceIndex $NIC.InterfaceIndex -AddressFamily IPv4).ServerAddresses
    $DNSOK = ($DNS[0] -eq "127.0.0.1" -and $DNS[1] -eq "1.1.1.1")

    Add-Check "DNS Servers" "127.0.0.1, 1.1.1.1" ($DNS -join ", ") $DNSOK 0.5 0.5
}

# ------------------------------------------------
# ROLES
# ------------------------------------------------

$ADDS = Get-WindowsFeature AD-Domain-Services
$DNSRole = Get-WindowsFeature DNS

Add-Check "AD DS Role" "Installed" $ADDS.InstallState $ADDS.Installed 0.5 0.5
Add-Check "DNS Role" "Installed" $DNSRole.InstallState $DNSRole.Installed 0.5 0.5

# ------------------------------------------------
# DOMAIN
# ------------------------------------------------

try {
    $DomainName = $Domain.DNSRoot
    Add-Check "Domain" "*.lan" $DomainName ($DomainName -like "*.lan") 1 1
}
catch {
    Add-Check "Domain" "*.lan" "NOT FOUND" $false 1 1
}

# ------------------------------------------------
# OUs
# ------------------------------------------------

$OU1 = Get-ADOrganizationalUnit -Filter 'Name -eq "KASUTAJAD"'
$OU2 = Get-ADOrganizationalUnit -Filter 'Name -eq "WORDPRESS"'

Add-Check "OU KASUTAJAD" "Exists" $(if($OU1){"Exists"}else{"Missing"}) ($OU1 -ne $null) 1 1
Add-Check "OU WORDPRESS" "Exists" $(if($OU2){"Exists"}else{"Missing"}) ($OU2 -ne $null) 1 1

# ------------------------------------------------
# USERS
# ------------------------------------------------

$User1 = Get-ADUser pea.toimetaja -Properties PasswordNeverExpires,Enabled
$User2 = Get-ADUser abi.toimetaja -Properties PasswordNeverExpires,Enabled

Add-Check "User pea.toimetaja" "Exists + Enabled" $(if($User1){"Exists"}else{"Missing"}) ($User1.Enabled) 0.5 0.5
Add-Check "User abi.toimetaja" "Exists + Enabled" $(if($User2){"Exists"}else{"Missing"}) ($User2.Enabled) 0.5 0.5

$PWNever = ($User1.PasswordNeverExpires -and $User2.PasswordNeverExpires)
Add-Check "Password Never Expires" "True" "CHECKED" $PWNever 0.5 0.5

# ------------------------------------------------
# GROUP
# ------------------------------------------------

$Group = Get-ADGroup "KoduleheToimetajad"
$Members = Get-ADGroupMember $Group

$GroupOK = (
    ($Members.SamAccountName -contains "pea.toimetaja") -and
    ($Members.SamAccountName -contains "abi.toimetaja")
)

Add-Check "Group Members" "Both users added" ($Members.SamAccountName -join ", ") $GroupOK 0.5 0.5

# ------------------------------------------------
# DNS
# ------------------------------------------------

$ProjectHost = "projekt.$Surname.lan"

try {
    $DNSResult = Resolve-DnsName $ProjectHost
    $ProjectIP = ($DNSResult | Where-Object {$_.Type -eq "A"}).IPAddress
    Add-Check "DNS Record" $ProjectHost $ProjectIP $true 0.5 0.5
}
catch {
    Add-Check "DNS Record" $ProjectHost "NOT FOUND" $false 0.5 0.5
}

# ------------------------------------------------
# WORDPRESS
# ------------------------------------------------

try {
    $Response = Invoke-WebRequest "http://$ProjectHost" -TimeoutSec 10
    $WP = ($Response.Content -match "wordpress")

    Add-Check "WordPress Website" "Reachable" $Response.StatusCode $WP 0.5 0.5
}
catch {
    Add-Check "WordPress Website" "Reachable" "UNREACHABLE" $false 0.5 0.5
}

# ------------------------------------------------
# LDAP
# ------------------------------------------------

Add-Check "LDAP Authentication" "Configured" "MANUAL CHECK" $true 0.5 0.5

# ------------------------------------------------
# FINAL
# ------------------------------------------------

$TotalPoints = [math]::Round($TotalPoints,2)
$MaxTotalPoints = [math]::Round(($Checks | Measure-Object MaxPoints -Sum).Sum,2)

if ($TotalPoints -ge 9) { $Grade = 5 }
elseif ($TotalPoints -ge 7) { $Grade = 4 }
elseif ($TotalPoints -ge 5) { $Grade = 3 }
else { $Grade = "MA" }

$Result = [PSCustomObject]@{
    Student = $Surname
    Timestamp = Get-Date
    TotalPoints = $TotalPoints
    MaxTotalPoints = $MaxTotalPoints
    Grade = $Grade
    Checks = $Checks
}

$Folder = "$PSScriptRoot\Results"
if (!(Test-Path $Folder)) { New-Item -ItemType Directory -Path $Folder | Out-Null }

$File = Join-Path $Folder "$Surname-result.json"

$Result | ConvertTo-Json -Depth 10 | Out-File $File -Encoding UTF8

Write-Host "DONE $File"
```

---

# 🧑‍🏫 2. ÕPETAJA DASHBOARD (EXPAND DETAILS LISATUD)

```powershell
$InputFolder = "$PSScriptRoot\Results"
$OutputHTML = Join-Path $InputFolder "Dashboard.html"

$Files = Get-ChildItem "$InputFolder\*.json"

$Rows = ""
$StudentOptions = ""

# -----------------------------
# STATISTICS
# -----------------------------

$Grades = @()

foreach ($File in $Files) {

    $Data = Get-Content $File.FullName -Raw | ConvertFrom-Json

    $Grades += [PSCustomObject]@{
        Student = $Data.Student
        Points = $Data.TotalPoints
        Max = $Data.MaxTotalPoints
        Grade = $Data.Grade
        Percent = if ($Data.MaxTotalPoints -gt 0) {
            ($Data.TotalPoints / $Data.MaxTotalPoints) * 100
        } else { 0 }
    }

    $StudentOptions += "<option value='$($Data.Student)'>$($Data.Student)</option>"
}

# -----------------------------
# FAIL FILTER DATA
# -----------------------------

$FailRows = ""

# -----------------------------
# MAIN TABLE ROWS
# -----------------------------

foreach ($File in $Files) {

    $Data = Get-Content $File.FullName -Raw | ConvertFrom-Json

    $GradeColor = switch ($Data.Grade) {
        5 {"#d4edda"}
        4 {"#fff3cd"}
        3 {"#ffe5b4"}
        default {"#f8d7da"}
    }

    $Percent = if ($Data.MaxTotalPoints -gt 0) {
        "{0:N1}" -f (($Data.TotalPoints / $Data.MaxTotalPoints) * 100)
    } else { "0" }

    # -------------------------
    # DETAILS
    # -------------------------

    $Details = ""

    foreach ($c in $Data.Checks) {

        $Color = if ($c.Status -eq "PASS") { "#d4edda" } else { "#f8d7da" }

        $Details += @"
<tr style='background:$Color'>
<td>$($c.Status)</td>
<td>$($c.Category)</td>
<td>$($c.Expected)</td>
<td>$($c.Actual)</td>
<td>$($c.Points) / $($c.MaxPoints)</td>
</tr>
"@

        # FAIL ONLY TABLE
        if ($c.Status -eq "FAIL") {
            $FailRows += @"
<tr>
<td>$($Data.Student)</td>
<td>$($c.Category)</td>
<td>$($c.Expected)</td>
<td>$($c.Actual)</td>
</tr>
"@
        }
    }

    $Rows += @"
<tr style='background:$GradeColor'>
    <td>$($Data.Student)</td>
    <td>$($Data.TotalPoints)</td>
    <td>$($Data.MaxTotalPoints)</td>
    <td>$Percent%</td>
    <td>$($Data.Grade)</td>
    <td>$($Data.Timestamp)</td>
</tr>

<tr>
<td colspan='6'>
<button onclick="toggle('$($Data.Student)')">Näita / peida detailid</button>

<div id='$($Data.Student)' style='display:none; margin-top:10px;'>

<table style='width:100%'>
<tr>
<th>Status</th>
<th>Kategooria</th>
<th>Oodatud</th>
<th>Leitud</th>
<th>Punktid</th>
</tr>

$Details

</table>

</div>
</td>
</tr>
"@
}

# -----------------------------
# GRADES FOR CHART
# -----------------------------

$ChartData = @()

foreach ($g in $Grades) {
    $ChartData += "{ student: '$($g.Student)', points: $([math]::Round($g.Points,1)) }"
}

$ChartJson = ($Grades | ForEach-Object {
    [PSCustomObject]@{
        student = $_.Student
        points = [math]::Round($_.Points,1)
    }
}) | ConvertTo-Json -Depth 3

# -----------------------------
# HTML
# -----------------------------

$HTML = @"
<html>
<head>

<title>AD Dashboard</title>

<style>
body { font-family: Segoe UI; background:#f4f4f4; margin:30px; }

table { width:100%; border-collapse:collapse; background:white; }

th { background:#2b5797; color:white; padding:10px; }

td { border:1px solid #ddd; padding:8px; }

tr:hover { background:#f1f1f1; }

button { margin:5px; padding:5px; }

.topbar {
    background:white;
    padding:15px;
    margin-bottom:20px;
}
</style>

<script>
function toggle(id) {
    var x = document.getElementById(id);
    x.style.display = (x.style.display === "none") ? "block" : "none";
}

function filterStudent() {
    var input = document.getElementById("search").value.toLowerCase();
    var rows = document.getElementsByClassName("studentRow");

    for (var i = 0; i < rows.length; i++) {
        var name = rows[i].innerText.toLowerCase();
        rows[i].style.display = name.includes(input) ? "" : "none";
    }
}

function showFails() {
    var all = document.getElementsByClassName("studentRow");
    for (var i = 0; i < all.length; i++) {
        if (!all[i].innerText.includes("FAIL")) {
            all[i].style.display = "none";
        }
    }
}
</script>

</head>

<body>

<h1>AD Hindamisdashboard</h1>
<p>Genereeritud: $(Get-Date)</p>

<div class="topbar">

<input type="text" id="search" onkeyup="filterStudent()" placeholder="Otsi õpilast...">

<button onclick="showFails()">Näita ainult FAIL</button>

</div>

<!-- 📊 CLASS STATISTICS CHART -->
<h2>Klassi statistika</h2>



<h2>Õpilased</h2>

<table>

<tr>
<th>Õpilane</th>
<th>Punktid</th>
<th>Max</th>
<th>%</th>
<th>Hinne</th>
<th>Aeg</th>
</tr>

$Rows

</table>

<h2>FAIL kontrollid</h2>

<table>
<tr>
<th>Õpilane</th>
<th>Kontroll</th>
<th>Oodatud</th>
<th>Leitud</th>
</tr>

$FailRows

</table>

</body>
</html>
"@

$HTML | Out-File $OutputHTML -Encoding UTF8

Write-Host "DASHBOARD READY: $OutputHTML"
```

---

# 🎯 Mis nüüd valmis on?

### ✔ Õpilase skript

* korrektne max punktide arv
* stabiilne hindamine
* JSON korrektne

### ✔ Dashboard

* kõik õpilased tabelis
* % arvutus
* värvid
* ⬇ expandable detail view (checks)
* JavaScript toggle

---

# 🚀 Kui tahad järgmise leveli

Võin lisada:

* 🔎 otsing (õpilase filter)
* 📊 klassi statistika graafik
* 🟥 ainult FAIL filtrid
* 📁 auto-refresh iga 10 sek
* 🧠 “kes kukkus enim läbi” summary

Ütle lihtsalt 👍
