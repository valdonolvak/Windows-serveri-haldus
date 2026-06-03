Siin Gemini test

```powershell

# Sinu ülesande kohane täielik kontrollskript
# Käivita administraatorina DC1/AD1 masinas

$ErrorActionPreference = "SilentlyContinue"
Import-Module ActiveDirectory, GroupPolicy, DhcpServer, Storage

# --- KASUTAJA SISEND ---
$CustomDomain = Read-Host "Sisesta kontrollitav domeeninimi (nt sinunimi.local või oige.ee)"
$CSVPath = "C:\Scripts\kasutajad.csv" # Muuda vajadusel faili asukohta
$ReportPath = "C:\Audit\HindamisRaport.html"

if (!(Test-Path "C:\Audit")) { New-Item -ItemType Directory -Path "C:\Audit" -Force | Out-Null }

$totalPoints = 0
$Results = @()

# --- ABIFUNKTSIOON TULEMUSTE JA PUNKTIDE JAOKS ---
function Add-Result {
    param([string]$Kontroll, [string]$Ootus, [string]$Leiti, [bool]$Staatus, [double]$Punktid)
    $earned = if($Staatus){$Punktid} else {0}
    $color = if($Staatus){"#c6efce"} else {"#ffc7ce"} # Roheline vs Punane
    $script:totalPoints += $earned
    $script:Results += [PSCustomObject]@{
        Kontroll = $Kontroll; Ootus = $Ootus; Leiti = $Leiti; Staatus = if($Staatus){"OK"}else{"FAIL"}; Punktid = $earned; Color = $color
    }
}

# --- 1. DOMEEN JA SERVERI NIMED (1.5p) ---
$domain = Get-ADDomain
$dcName = $env:COMPUTERNAME
Add-Result "Serveri nimi" "DC1 või AD1" $dcName ($dcName -match "DC1|AD1") 0.5
Add-Result "AD Domeeni nimi" $CustomDomain $domain.DNSRoot ($domain.DNSRoot -eq $CustomDomain) 1.0

# --- 2. VÕRK JA ROLLID (1.5p) ---
$staticIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.PrefixOrigin -eq "Manual" -and $_.IPAddress -notlike "169.254*"}).IPAddress
Add-Result "Staatiline IP" "Seadistatud" ($staticIP -join "; ") ($staticIP.Count -gt 0) 0.5

$dnsRole = Get-WindowsFeature DNS
Add-Result "DNS Teenus" "Installed" $dnsRole.InstallState ($dnsRole.Installed) 0.5

$dcs = Get-ADDomainController -Filter *
Add-Result "DC-de arv" "Vähemalt 2 (DC1 ja DC2)" $dcs.Count ($dcs.Count -ge 2) 0.5

# --- 3. DHCP JA FAILOVER (4.0p) ---
$scope = Get-DhcpServerv4Scope
if($scope) {
    Add-Result "DHCP Teenus" "Scope olemas" $scope.ScopeId ($scope -ne $null) 1.0
    Add-Result "DHCP Lease aeg" "04:00:00" $scope.LeaseDuration.ToString() ($scope.LeaseDuration.TotalHours -eq 4) 1.0
    
    $dnsOpt = Get-DhcpServerv4OptionValue -OptionId 6
    Add-Result "DHCP DNS Serverid" "2 serverit" ($dnsOpt.Value -join ", ") ($dnsOpt.Value.Count -ge 2) 0.5
    
    $reservations = Get-DhcpServerv4Reservation -ScopeId $scope.ScopeId
    Add-Result "DHCP Staatilised rendid" "Olemas" $reservations.Count ($reservations.Count -gt 0) 0.5

    $failover = Get-DhcpServerv4Failover
    Add-Result "DHCP Failover" "DC2 partnerina" ($failover.PartnerServer) ($failover.PartnerServer -match "DC2|AD2") 1.0
} else {
    Add-Result "DHCP" "Seadistamata" "Scope puudu" $false 4.0
}

# --- 4. OU-D, KASUTAJAD JA GRUPID (2.0p) ---
$ouUsers = Get-ADOrganizationalUnit -Filter "Name -eq 'Kasutajad'"
$ouComps = Get-ADOrganizationalUnit -Filter "Name -eq 'Arvutid'"
Add-Result "OU Kasutajad ja Arvutid" "Loodud" (if($ouUsers -and $ouComps){"Jah"}else{"Ei"}) ($ouUsers -and $ouComps) 0.5

$haldur = Get-ADUser -Filter "SamAccountName -eq 'haldur'" -Properties MemberOf
$isAdmin = $haldur.MemberOf -like "*Domain Admins*"
Add-Result "Kasutaja Haldur Admin" "Domain Admins liige" (if($isAdmin){"Jah"}else{"Ei"}) ($isAdmin) 0.5

if($ouComps) {
    $comps = Get-ADComputer -SearchBase $ouComps.DistinguishedName -Filter *
    Add-Result "Klientmasin domeenis" "OU-s Arvutid" $comps.Count ($comps.Count -gt 0) 0.5
}

$records = Get-DnsServerResourceRecord -ZoneName $CustomDomain -RRType A | Where-Object { $_.HostName -notmatch "@|gc|DomainDnsZones" }
Add-Result "DNS A-kirjed (Linux)" "Loodud" $records.Count ($records.Count -gt 0) 0.5

# --- 5. CSV IMPORT JA OSAKONNAD (1.0p) ---
if (Test-Path $CSVPath) {
    $osakonnad = @("Müük", "Personal", "Raamatupidamine", "Toimetajad", "IT", "Juhtkond", "Haldus")
    $allFound = $true
    foreach($os in $osakonnad) {
        $checkOU = Get-ADOrganizationalUnit -Filter "Name -eq '$os'"
        if(!$checkOU) { $allFound = $false }
    }
    Add-Result "CSV Import/OU struktuur" "Osakonnad loodud" (if($allFound){"Kõik olemas"}else{"Mõni puudu"}) ($allFound) 1.0
} else {
    Add-Result "CSV Fail" "C:\Scripts\kasutajad.csv" "Puudub" $false 1.0
}

# --- 6. KETAS F: (1.0p) ---
$diskF = Get-Volume -DriveLetter F
Add-Result "Ketas F:" "Vormindatud ja ühendatud" (if($diskF){"Leitud"}else{"Puudub"}) ($diskF -ne $null) 1.0

# --- 7. GRUPIPÖHIMÕTTED (GPO) SISU KONTROLL (2.0p) ---

# GPO 1: Kontode lukustamine
$lockGPO = Get-GPO -Name "GPO_KontodeLukustamine"
if($lockGPO) {
    $defPwd = Get-ADDefaultDomainPasswordPolicy
    $lockOK = ($defPwd.LockoutThreshold -eq 5 -and $defPwd.LockoutDuration.TotalMinutes -eq 15)
    Add-Result "GPO KontodeLukustamine" "5 katset / 15 min" "Threshold: $($defPwd.LockoutThreshold)" $lockOK 1.0
} else {
    Add-Result "GPO KontodeLukustamine" "Puudub" "Ei leitud" $false 1.0
}

# GPO 2: Edge Siseportaal (Sisu kontroll XML-ist)
$edgeGPO = Get-GPO -Name "Edge_Siseportaal"
if($edgeGPO) {
    $xml = [xml](Get-GPOReport -Guid $edgeGPO.Id -ReportType Xml)
    $xmlText = $xml.InnerXml
    $contentOK = ($xmlText -match "siseportaal.$CustomDomain") -and ($xmlText -match "NewTabPageLocation")
    Add-Result "GPO Edge Siseportaal" "Sisu: URL ja lukustus" (if($contentOK){"Õige URL leitud"}else{"URL vale või puudu"}) $contentOK 1.0
} else {
    Add-Result "GPO Edge Siseportaal" "Puudub" "Ei leitud" $false 1.0
}

# --- HTML RAPORTI GENEREERIMINE ---
$html = @"
<html>
<head>
    <meta charset='UTF-8'>
    <title>Serveri Audit - $CustomDomain</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f4f4f4; }
        table { border-collapse: collapse; width: 100%; background: white; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #333; color: white; }
        h1, h2 { color: #333; }
        .summary { font-size: 1.2em; font-weight: bold; margin-bottom: 20px; padding: 15px; background: #fff; border-left: 5px solid #333; }
    </style>
</head>
<body>
    <h1>Windows Serveri Auditi Raport</h1>
    <div class='summary'>
        Domeen: $CustomDomain <br>
        Kontrolli teostas: $env:USERNAME <br>
        KOONDPUNKTID: $totalPoints / 13.0
    </div>
    <table>
        <tr>
            <th>Kontrollitav tegevus</th>
            <th>Oodatud tulemus</th>
            <th>Leitud olukord</th>
            <th>Staatus</th>
            <th>Punktid</th>
        </tr>
"@

foreach($row in $Results) {
    $html += "<tr style='background-color:$($row.Color)'>
        <td>$($row.Kontroll)</td>
        <td>$($row.Ootus)</td>
        <td>$($row.Leiti)</td>
        <td>$($row.Staatus)</td>
        <td>$($row.Punktid)</td>
    </tr>"
}

$html += "</table></body></html>"
$html | Out-File $ReportPath -Encoding UTF8

Write-Host "Kontroll lõpetatud!" -ForegroundColor Green
Write-Host "Raport asub: $ReportPath" -ForegroundColor Cyan
Write-Host "Kokku punkte: $totalPoints" -ForegroundColor Yellow

```
