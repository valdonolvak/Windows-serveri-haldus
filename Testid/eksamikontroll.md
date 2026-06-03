Siin testiks vajalik ps1 skript

```powershell

# AD-Lab-Audit.ps1
# Käivita Domain Admin õigustes DC1 peal

$ErrorActionPreference = "SilentlyContinue"

Import-Module ActiveDirectory
Import-Module GroupPolicy
Import-Module DhcpServer

$AuditFolder = "C:\Audit"
$ReportFile = Join-Path $AuditFolder "HindamisRaport.html"

if (!(Test-Path $AuditFolder)) {
    New-Item -ItemType Directory -Path $AuditFolder -Force | Out-Null
}

$totalPoints = 0
$Results = @()

function Add-Result {
    param(
        [string]$Kontroll,
        [string]$Oodati,
        [string]$Leiti,
        [bool]$Staatus,
        [double]$Punktid
    )

    $earned = 0
    if($Staatus){
        $earned = $Punktid
        $color = "#c6efce"
        $statusText = "OK"
    } else {
        $color = "#ffc7ce"
        $statusText = "FAIL"
    }

    $script:totalPoints += $earned

    $script:Results += [PSCustomObject]@{
        Kontroll = $Kontroll
        Oodati = $Oodati
        Leiti = $Leiti
        Staatus = $statusText
        Punktid = $earned
        Color = $color
    }
}

$ExpectedUsers = @{
    "IT"="Anneli Roos"
    "Müük"="Aivo Teder"
    "Personal"="Andres Karl Kukk"
    "Raamatupidamine"="Anette Kuusk"
    "Juhtkond"="Annika Rand"
    "Haldus"="Heidi Katrin Pärn"
    "Toimetajad"="Anneli Koppel"
}

$domain = Get-ADDomain
$domainName = $domain.DNSRoot

Add-Result "AD Domeen" "Mingi .local domeen" $domainName ($domainName -like "*.local") 1

# DC1
$dc1 = Get-ADComputer -Filter "Name -eq 'DC1'"
Add-Result "DC1 olemas" "DC1" ($(if($dc1){"Leitud"}else{"Puudub"})) ($dc1 -ne $null) 0.5

# DC2
$dc2 = Get-ADComputer -Filter "Name -eq 'DC2'"
Add-Result "DC2 olemas" "DC2" ($(if($dc2){"Leitud"}else{"Puudub"})) ($dc2 -ne $null) 0.5

# Staatiline IP
$ipcfg = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.IPAddress -notlike "169.254*" -and
    $_.IPAddress -ne "127.0.0.1"
}

$staticFound = $ipcfg | Where-Object {$_.PrefixOrigin -eq "Manual"}
Add-Result "DC1 staatiline IP" "Manual" ($staticFound.IPAddress -join ", ") ($staticFound.Count -gt 0) 0.5

# DNS roll
$dnsRole = Get-WindowsFeature DNS
Add-Result "DNS roll" "Installed" ($dnsRole.InstallState) ($dnsRole.Installed) 0.5

# Teine DC
$dcs = Get-ADDomainController -Filter *
Add-Result "2 domeenikontrollerit" "2 või rohkem" ($dcs.Count) ($dcs.Count -ge 2) 1

# DHCP
$dhcpRole = Get-WindowsFeature DHCP
Add-Result "DHCP roll" "Installed" ($dhcpRole.InstallState) ($dhcpRole.Installed) 1

$scope = Get-DhcpServerv4Scope

if($scope){
    Add-Result "DHCP Lease" "4 tundi" ($scope.LeaseDuration.ToString()) ($scope.LeaseDuration.TotalHours -eq 4) 1
}

# DHCP DNS
try{
    $dnsOption = Get-DhcpServerv4OptionValue -OptionId 6
    $dnsCount = $dnsOption.Value.Count
    Add-Result "DHCP DNS serverid" "2 DNS serverit" ($dnsOption.Value -join ", ") ($dnsCount -ge 2) 1
}catch{
    Add-Result "DHCP DNS serverid" "2 DNS serverit" "Ei leitud" $false 1
}

# DHCP reservatsioonid
$reservations = Get-DhcpServerv4Reservation
Add-Result "DHCP reservatsioonid" "Olemas" ($reservations.Count) ($reservations.Count -gt 0) 1

# Failover
$failover = Get-DhcpServerv4Failover
if($failover){
    Add-Result "DHCP Failover" "DC2 partner" ($failover.PartnerServer) ($failover.PartnerServer -match "DC2") 1
}else{
    Add-Result "DHCP Failover" "DC2 partner" "Puudub" $false 1
}

# OU-d
$ouUsers = Get-ADOrganizationalUnit -Filter "Name -eq 'Kasutajad'"
$ouComputers = Get-ADOrganizationalUnit -Filter "Name -eq 'Arvutid'"

Add-Result "OU Kasutajad" "Olemas" ($(if($ouUsers){"Leitud"}else{"Puudub"})) ($ouUsers -ne $null) 0.25
Add-Result "OU Arvutid" "Olemas" ($(if($ouComputers){"Leitud"}else{"Puudub"})) ($ouComputers -ne $null) 0.25

# Osakonnad
foreach($dep in $ExpectedUsers.Keys){
    $ou = Get-ADOrganizationalUnit -Filter "Name -eq '$dep'"
    Add-Result "Osakonna OU" $dep ($(if($ou){"Leitud"}else{"Puudub"})) ($ou -ne $null) 0.1
}

# Haldur
$haldur = Get-ADUser -Filter "SamAccountName -eq 'Haldur'"
Add-Result "Kasutaja Haldur" "Olemas" ($(if($haldur){"Leitud"}else{"Puudub"})) ($haldur -ne $null) 0.25

if($haldur){
    $groups = Get-ADPrincipalGroupMembership $haldur
    Add-Result "Domain Admins liikmelisus" "Domain Admins" (($groups.Name) -join ",") (($groups.Name -contains "Domain Admins")) 0.25
}

# Testkasutajad
foreach($dep in $ExpectedUsers.Keys){
    $name = $ExpectedUsers[$dep]
    $u = Get-ADUser -Filter "Name -eq '$name'" -Properties DistinguishedName

    if($u){
        $ok = $u.DistinguishedName -match $dep
        Add-Result "Testkasutaja" "$name OU=$dep" $u.DistinguishedName $ok 0.15
    } else {
        Add-Result "Testkasutaja" "$name OU=$dep" "Puudub" $false 0.15
    }
}

# Arvutid OU-s
if($ouComputers){
    $computers = Get-ADComputer -SearchBase $ouComputers.DistinguishedName -Filter *
    Add-Result "Klient OU-s Arvutid" "Vähemalt 1" $computers.Count ($computers.Count -gt 0) 0.5
}

# DNS A kirjed
$records = Get-DnsServerResourceRecord -ZoneName $domainName -RRType A
Add-Result "DNS A kirjed" "Vähemalt 1" $records.Count ($records.Count -gt 0) 1

# CSV
$csvExists = Test-Path "C:\Scripts\kasutajad.csv"
Add-Result "kasutajad.csv" "Olemas" $csvExists $csvExists 0.5

# Import skript
$importExists = Get-ChildItem C:\Scripts\*.ps1 -ErrorAction SilentlyContinue | Where-Object {$_.Name -match "Import|Kasut"}
Add-Result "Import skript" "Olemas" ($(if($importExists){$importExists.Name}else{"Puudub"})) ($importExists -ne $null) 0.5

# F ketas
$f = Get-Volume -DriveLetter F
Add-Result "F ketas" "Olemas" ($(if($f){"Leitud"}else{"Puudub"})) ($f -ne $null) 1

# Konto lukustus
$pwd = Get-ADDefaultDomainPasswordPolicy
Add-Result "Lockout Threshold" "5" $pwd.LockoutThreshold ($pwd.LockoutThreshold -eq 5) 0.5
Add-Result "Lockout Duration" "15" $pwd.LockoutDuration.TotalMinutes ($pwd.LockoutDuration.TotalMinutes -eq 15) 0.5

# Edge GPO
$edge = Get-GPO -Name "Edge_Siseportaal"
if($edge){
    $xml = Get-GPOReport -Guid $edge.Id -ReportType Xml

    Add-Result "Edge GPO olemas" "Edge_Siseportaal" $edge.DisplayName $true 0.25
    Add-Result "Homepage URL" "siseportaal.<domeen>" "Kontrollitud XML-ist" ($xml -match "siseportaal") 0.25
    Add-Result "New Tab URL" "siseportaal.<domeen>" "Kontrollitud XML-ist" ($xml -match "NewTab") 0.25
    Add-Result "Homepage lukustatud" "Jah" "Kontrollitud XML-ist" ($xml -match "Homepage") 0.25
}else{
    Add-Result "Edge GPO" "Olemas" "Puudub" $false 1
}

# HTML
$dnsComment = ""
foreach($r in $records){
    $dnsComment += "<li>$($r.HostName)</li>"
}

$html = @"
<html>
<head>
<meta charset='utf-8'>
<title>AD Audit</title>
<style>
body{font-family:Segoe UI;}
table{border-collapse:collapse;width:100%;}
th,td{border:1px solid black;padding:6px;}
th{background:#dddddd;}
</style>
</head>
<body>
<h1>Windows Server Audit</h1>
<h2>Domeen: $domainName</h2>
<h2>Punktid: $totalPoints</h2>

<h3>DNS A kirjed</h3>
<ul>
$dnsComment
</ul>

<table>
<tr>
<th>Kontroll</th>
<th>Oodati</th>
<th>Leiti</th>
<th>Staatus</th>
<th>Punktid</th>
</tr>
"@

foreach($row in $Results){
$html += @"
<tr bgcolor='$($row.Color)'>
<td>$($row.Kontroll)</td>
<td>$($row.Oodati)</td>
<td>$($row.Leiti)</td>
<td>$($row.Staatus)</td>
<td>$($row.Punktid)</td>
</tr>
"@
}

$html += "</table></body></html>"

$html | Out-File $ReportFile -Encoding UTF8

Write-Host "Raport loodud: $ReportFile"
Write-Host "Punkte kokku: $totalPoints"

```

