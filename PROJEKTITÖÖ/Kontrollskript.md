Jah — see on tegelikult kõige parem arhitektuur koolikeskkonnas, sest:

* õpetajal ei ole vaja WinRM-i / remote õigusi;
* tulemused saab koguda USB, Moodle’i või võrgu share’i kaudu;
* töötab ka NAT-võrkudes;
* ei sõltu firewallist;
* õpilane ei pea admin õigusi jagama.

See tähendab:

# Arhitektuur

## Õpilane

Käivitab:

```text id="j01h0m"
StudentCheck.ps1
```

See:

* teeb kõik kontrollid;
* genereerib ühe tulemusefaili:

  * JSON
  * või ZIP

Näiteks:

```text id="qagyu6"
nolvak-result.json
```

või:

```text id="w6pdrw"
nolvak-result.zip
```

---

## Õpetaja

Kogub kõik failid kausta:

```text id="3v8g1s"
C:\AD-RESULTS\
```

ja käivitab:

```text id="9b8c7k"
TeacherDashboard.ps1
```

mis:

* loeb kõik tulemused;
* genereerib:

  * HTML dashboardi
  * Exceli
  * kokkuvõtte statistika.

---

# SOOVITATUD STRUKTUUR

```text id="eh0g6j"
C:\AD-RESULTS\
│
├── nolvak-result.json
├── tamm-result.json
├── kask-result.json
│
├── Dashboard.html
└── Summary.csv
```

---

# 1. ÕPILASE PROFESSIONAALNE SKRIPT

# StudentCheck.ps1

```powershell id="u12k3l"
Import-Module ActiveDirectory

$Result = [ordered]@{}
$Score = 0

# ------------------------------------------------
# META
# ------------------------------------------------

$Result.Timestamp = Get-Date
$Result.Computer = $env:COMPUTERNAME

try {
    $Domain = Get-ADDomain
    $Surname = $Domain.DNSRoot.Split(".")[0]
}
catch {
    $Surname = "UNKNOWN"
}

$Result.Student = $Surname

# ------------------------------------------------
# SERVER NAME
# ------------------------------------------------

if ($env:COMPUTERNAME -eq "AD1") {

    $Result.ServerName = "OK"
    $Score += 2
}
else {
    $Result.ServerName = "FAIL"
}

# ------------------------------------------------
# NETWORK
# ------------------------------------------------

$NIC = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -like "10.0.*"
    } |
    Select-Object -First 1

if ($NIC) {

    $Result.IP = $NIC.IPAddress

    $Gateway = Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
        Select-Object -First 1

    $Result.Gateway = $Gateway.NextHop

    $DNS = Get-DnsClientServerAddress `
        -InterfaceIndex $NIC.InterfaceIndex `
        -AddressFamily IPv4

    $Result.DNS = $DNS.ServerAddresses -join ", "
}
else {

    $Result.IP = "NOT FOUND"
}

# ------------------------------------------------
# DOMAIN
# ------------------------------------------------

try {

    if ($Domain.DNSRoot -like "*.lan") {

        $Result.Domain = $Domain.DNSRoot
        $Score += 2
    }
    else {

        $Result.Domain = "FAIL"
    }

}
catch {

    $Result.Domain = "NOT FOUND"
}

# ------------------------------------------------
# OU CHECK
# ------------------------------------------------

$OU1 = Get-ADOrganizationalUnit `
    -Filter 'Name -eq "KASUTAJAD"' `
    -ErrorAction SilentlyContinue

$OU2 = Get-ADOrganizationalUnit `
    -Filter 'Name -eq "WORDPRESS"' `
    -ErrorAction SilentlyContinue

if ($OU1 -and $OU2) {

    $Result.OU = "OK"
    $Score += 2
}
else {

    $Result.OU = "FAIL"
}

# ------------------------------------------------
# USERS
# ------------------------------------------------

$U1 = Get-ADUser pea.toimetaja `
    -Properties PasswordNeverExpires,Enabled `
    -ErrorAction SilentlyContinue

$U2 = Get-ADUser abi.toimetaja `
    -Properties PasswordNeverExpires,Enabled `
    -ErrorAction SilentlyContinue

$UsersOK = $false

if ($U1 -and $U2) {

    if (
        $U1.Enabled -and
        $U2.Enabled -and
        $U1.PasswordNeverExpires -and
        $U2.PasswordNeverExpires
    ) {

        $UsersOK = $true
    }
}

# ------------------------------------------------
# GROUP
# ------------------------------------------------

$Group = Get-ADGroup `
    "KoduleheToimetajad" `
    -ErrorAction SilentlyContinue

$GroupOK = $false

if ($Group) {

    $Members = Get-ADGroupMember $Group

    $M1 = $Members |
        Where-Object {
            $_.SamAccountName -eq "pea.toimetaja"
        }

    $M2 = $Members |
        Where-Object {
            $_.SamAccountName -eq "abi.toimetaja"
        }

    if ($M1 -and $M2) {

        $GroupOK = $true
    }
}

if ($UsersOK -and $GroupOK) {

    $Result.UsersAndGroups = "OK"
    $Score += 2
}
else {

    $Result.UsersAndGroups = "FAIL"
}

# ------------------------------------------------
# DNS RECORD
# ------------------------------------------------

$ProjectHost = "projekt.$Surname.lan"

try {

    $DNSResult = Resolve-DnsName `
        $ProjectHost `
        -ErrorAction Stop

    $ProjectIP = ($DNSResult |
        Where-Object {
            $_.Type -eq "A"
        }).IPAddress

    $Result.DNSRecord = "$ProjectHost -> $ProjectIP"

    $Score += 1
}
catch {

    $Result.DNSRecord = "FAIL"
}

# ------------------------------------------------
# WORDPRESS CHECK
# ------------------------------------------------

try {

    $Response = Invoke-WebRequest `
        "http://$ProjectHost" `
        -TimeoutSec 10

    if (
        $Response.StatusCode -eq 200 -and
        $Response.Content -match "wordpress"
    ) {

        $Result.WordPress = "OK"
        $Score += 1
    }
    else {

        $Result.WordPress = "FAIL"
    }

}
catch {

    $Result.WordPress = "UNREACHABLE"
}

# ------------------------------------------------
# SCORE
# ------------------------------------------------

$Result.Score = $Score

switch ($Score) {

    {$_ -ge 9} { $Grade = 5 }
    {$_ -ge 7} { $Grade = 4 }
    {$_ -ge 5} { $Grade = 3 }
    default { $Grade = "MA" }
}

$Result.Grade = $Grade

# ------------------------------------------------
# SAVE
# ------------------------------------------------

$Folder = "C:\StudentResults"

if (!(Test-Path $Folder)) {

    New-Item -ItemType Directory `
        -Path $Folder
}

$File = Join-Path `
    $Folder `
    "$Surname-result.json"

$Result |
    ConvertTo-Json -Depth 5 |
    Out-File $File -Encoding UTF8

Write-Host ""
Write-Host "================================="
Write-Host "KONTROLL LÕPETATUD"
Write-Host "================================="
Write-Host ""
Write-Host "Õpilane: $Surname"
Write-Host "Punktid: $Score"
Write-Host "Hinne:   $Grade"
Write-Host ""
Write-Host "Tulemusfail:"
Write-Host $File
Write-Host ""
```

---

# 2. ÕPETAJA DASHBOARD

# TeacherDashboard.ps1

```powershell id="d93j4m"
$InputFolder = "C:\AD-RESULTS"
$OutputHTML = Join-Path $InputFolder "Dashboard.html"

$Files = Get-ChildItem "$InputFolder\*.json"

$Rows = foreach ($File in $Files) {

    $Item = Get-Content $File.FullName |
        ConvertFrom-Json

    $Color = switch ($Item.Grade) {

        5 {"#d4edda"}
        4 {"#fff3cd"}
        3 {"#ffe5b4"}
        default {"#f8d7da"}
    }

@"
<tr style='background:$Color'>
<td>$($Item.Student)</td>
<td>$($Item.ServerName)</td>
<td>$($Item.Domain)</td>
<td>$($Item.OU)</td>
<td>$($Item.UsersAndGroups)</td>
<td>$($Item.DNSRecord)</td>
<td>$($Item.WordPress)</td>
<td><b>$($Item.Score)</b></td>
<td><b>$($Item.Grade)</b></td>
</tr>
"@
}

$HTML = @"
<html>

<head>

<title>AD Dashboard</title>

<style>

body {
    font-family: Segoe UI;
    background: #f4f4f4;
    padding: 30px;
}

h1 {
    color: #2b5797;
}

table {
    border-collapse: collapse;
    width: 100%;
    background: white;
}

th {
    background: #2b5797;
    color: white;
    padding: 12px;
}

td {
    border: 1px solid #ddd;
    padding: 10px;
}

tr:hover {
    background: #eeeeee;
}

</style>

</head>

<body>

<h1>Active Directory Hindamisdashboard</h1>

<p>
Genereeritud:
$(Get-Date)
</p>

<table>

<tr>
<th>Õpilane</th>
<th>Server</th>
<th>Domeen</th>
<th>OU</th>
<th>Kasutajad/Grupid</th>
<th>DNS</th>
<th>WordPress</th>
<th>Punktid</th>
<th>Hinne</th>
</tr>

$Rows

</table>

</body>
</html>
"@

$HTML | Out-File $OutputHTML -Encoding UTF8

Write-Host ""
Write-Host "Dashboard valmis:"
Write-Host $OutputHTML
Write-Host ""
```

---

# ÕPETAJA TÖÖVOOG

## 1

Õpilased annavad:

```text id="jpvn1u"
perenimi-result.json
```

---

## 2

Õpetaja paneb need:

```text id="12f47x"
C:\AD-RESULTS\
```

---

## 3

Käivitab:

```powershell id="u7l2xg"
.\TeacherDashboard.ps1
```

---

## 4

Valmib:

```text id="4v1hnw"
Dashboard.html
```

---

# Dashboard näeb välja professionaalne

✅ värvilised read
✅ punktid
✅ hinded
✅ kõik õpilased koos
✅ automaatne HTML
✅ brauseris avatav
✅ lihtne arhiveerida

---

# SUUR EELIS

See süsteem:

✅ ei vaja võrguühendust õpetaja ja VM vahel
✅ ei vaja WinRM-i
✅ ei vaja domeeni trusti
✅ töötab ka laptopites
✅ töötab USB pealt
✅ töötab Moodle uploadiga
✅ töötab Teamsi kaudu
✅ töötab täiesti offline

---

# Väga soovitatud täiustused

Järgmine samm võiks olla:

## 1. ZIP fail

Õpilane annab:

```text id="oqt61j"
nolvak-result.zip
```

kus:

* JSON
* võrguinfo
* screenshot
* wp test

---

## 2. WordPress screenshot

Automaatne screenshot HTML dashboardis.

---

## 3. Automaatne sorting

Parimad eespool.

---

## 4. Kokkuvõtte statistika

Näiteks:

```text id="q18n1t"
Keskmine hinne: 4.1
Parim tulemus: 10p
Nõrgim tulemus: 2p
```

---

## 5. Live dashboard

Auto-refresh.

---

## 6. Dark mode dashboard

---

## 7. CSV + Excel export

---

## 8. Täis enterprise dashboard

Bootstrap + Chart.js + filtrid + otsing + PDF eksport.
