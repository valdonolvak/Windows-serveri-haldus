Siin täiendatud skript:

```powershell
<#
.SYNOPSIS
    Täielik Windows Serveri auditi skript vastavalt hindamiskriteeriumitele.
    Käivitada DC1 serveris Domain Admin õigustes.
#>

$ErrorActionPreference = "SilentlyContinue"

# Moodulite laadimine
Import-Module ActiveDirectory
Import-Module GroupPolicy
Import-Module DhcpServer
Import-Module DnsServer

# --- SEADISTUSED JA SISEND ---
$ExpectedDomain = Read-Host "Sisesta oodatud domeeninimi (nt oige.ee või sinunimi.local)"
$ReportPath = "$PSScriptRoot\HindamisRaport.html"

$TotalPoints = 0
$Results = @()

# --- FUNKTSIOON TULEMUSTE LISAMISEKS ---
function Add-Result {
    param(
        [string]$Ylesanne,
        [string]$Oodatud,
        [string]$Leitud,
        [bool]$Staatus,
        [double]$Punktid
    )
    
    $teenitud = if ($Staatus) { $Punktid } else { 0 }
    $Global:TotalPoints += $teenitud
    $color = if ($Staatus) { "#c6efce" } else { "#ffc7ce" }
    $staatusTekst = if ($Staatus) { "OK" } else { "PUUDU/VIGA" }

    $Global:Results += [PSCustomObject]@{
        Ylesanne = $Ylesanne
        Oodatud = $Oodatud
        Leitud = $Leitud
        Staatus = $staatusTekst
        Punktid = $teenitud
        Color = $color
    }
}

# --- 1. SERVERITE NIMED JA IP-D (2.0 punkti) ---
$ComputerName = $env:COMPUTERNAME
$IsDC1 = ($ComputerName -eq "DC1")
Add-Result "Muuta masina nimi DC1" "Masina nimi on DC1" $ComputerName $IsDC1 0.5

$DC1IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq "Manual" -and $_.InterfaceAlias -notmatch "Loopback" }).IPAddress
Add-Result "DC1 staatiline IP" "Manuaalne IPv4 seadistus" ($DC1IP -join ", ") ($DC1IP.Count -gt 0) 0.5

$DC2 = Get-ADComputer -Filter "Name -eq 'DC2'"
Add-Result "WinCore2025 masina nimi DC2" "AD-s eksisteerib arvuti DC2" (if($DC2){"Leitud DC2"}else{"Ei leitud"}) ($DC2 -ne $null) 0.5

$DC2DNS = Resolve-DnsName -Name "DC2" -Type A -ErrorAction SilentlyContinue
Add-Result "DC2 staatiline IP" "DNS kirje viitab DC2 IP-le" (if($DC2DNS){$DC2DNS.IPAddress}else{"Puudub"}) ($DC2DNS -ne $null) 0.5


# --- 2. AD DS JA DNS TEENUSED (2.5 punkti) ---
$Domain = Get-ADDomain
$IsCorrectDomain = ($Domain.DNSRoot -eq $ExpectedDomain)
Add-Result "Seadista DC1 AD DS domeen" "Domeen $ExpectedDomain" $Domain.DNSRoot $IsCorrectDomain 1.0

$DNSRole = Get-WindowsFeature DNS
Add-Result "Seadista DC1 DNS teenus" "DNS roll paigaldatud" $DNSRole.InstallState ($DNSRole.Installed) 0.5

$DomainControllers = Get-ADDomainController -Filter *
$HasTwoDCs = ($DomainControllers.Count -ge 2) -and ($DomainControllers.Name -contains "DC2")
Add-Result "Lisada DC2 teiseks domeenikontrolleriks" "Vähemalt 2 DC-d (sh DC2)" ($DomainControllers.Name -join ", ") $HasTwoDCs 1.0


# --- 3. DHCP TEENUS JA FAILOVER (2.0 punkti) ---
# Dünaamiline Skoobi tuvastamine
$DHCPScope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Select-Object -First 1

if ($DHCPScope) {
    $ScopeName = $DHCPScope.Name
    $ScopeId = $DHCPScope.ScopeId.IPAddressToString
    $LeaseTime = $DHCPScope.LeaseDuration.ToString()
    
    $Reservations = Get-DhcpServerv4Reservation -ScopeId $DHCPScope.ScopeId -ErrorAction SilentlyContinue
    $ResCount = if ($Reservations) { @($Reservations).Count } else { 0 }
    
    $DNSOptions = Get-DhcpServerv4OptionValue -ScopeId $DHCPScope.ScopeId -OptionId 6 -ErrorAction SilentlyContinue
    $DNSList = if ($DNSOptions) { $DNSOptions.Value -join ", " } else { "Puudub" }
    
    $DhcpDetails = "<b>Skoobi nimi:</b> $ScopeName ($ScopeId)<br><b>Rendiaeg (Lease):</b> $LeaseTime<br><b>Jagatud DNS:</b> $DNSList<br><b>Reservatsioone:</b> $ResCount"
    
    $IsDhcpOk = ($ResCount -gt 0) -and ($DNSOptions.Value.Count -ge 2)
    Add-Result "DHCP teenus, reservatsioonid, DNS" "Skoop olemas, reservatsioonid, jagab 2 AD serverit DNSina" $DhcpDetails $IsDhcpOk 1.0

    $Failover = Get-DhcpServerv4Failover -ErrorAction SilentlyContinue
    Add-Result "DHCP Failover" "Partneriks on DC2" (if($Failover){$Failover.PartnerServer}else{"Puudub"}) ($Failover.PartnerServer -match "DC2") 1.0
} else {
    Add-Result "DHCP teenus, reservatsioonid, DNS" "Skoop olemas, reservatsioonid, jagab 2 AD serverit DNSina" "Skoopi ei leitud" $false 1.0
    Add-Result "DHCP Failover" "Partneriks on DC2" "DHCP Skoop puudub" $false 1.0
}


# --- 4. AD STRUKTUUR JA KLIENT (1.5 punkti) ---
$OUUsers = Get-ADOrganizationalUnit -Filter "Name -eq 'Kasutajad'"
$OUComps = Get-ADOrganizationalUnit -Filter "Name -eq 'Arvutid'"
Add-Result "2 OU-d: Kasutajad ja Arvutid" "Mõlemad loodud" (if($OUUsers -and $OUComps){"Mõlemad leitud"}else{"Puudu/Osaline"}) ($OUUsers -and $OUComps) 0.5

$Haldur = Get-ADUser -Filter "Name -eq 'Haldur'" -Properties MemberOf
$IsDomainAdmin = ($Haldur.MemberOf -match "Domain Admins")
Add-Result "Kasutaja haldur + Domain Admins" "Olemas ja grupis" (if($IsDomainAdmin){"Jah"}else{"Ei"}) ($IsDomainAdmin) 0.5

if ($OUComps) {
    $Win11Client = Get-ADComputer -SearchBase $OUComps.DistinguishedName -Filter {OperatingSystem -like "*Windows 11*"}
    Add-Result "Windows 11 klient OU-s Arvutid" "Win 11 arvuti olemas" (if($Win11Client){$Win11Client.Name}else{"Ei leitud"}) ($Win11Client -ne $null) 0.5
} else {
    Add-Result "Windows 11 klient OU-s Arvutid" "OU Arvutid puudub" "Ei saa kontrollida" $false 0.5
}


# --- 5. DNS A-KIRJED (1.0 punkt) ---
$DnsRecords = Get-DnsServerResourceRecord -ZoneName $ExpectedDomain -RRType A | Where-Object {$_.HostName -notmatch "@|gc|DomainDnsZones|ForestDnsZones|DC1|DC2"}
Add-Result "DNS A-kirjed Linux serveritele" "Vähemalt 1 manuaalne A-kirje" "$($DnsRecords.Count) tk leitud" ($DnsRecords.Count -gt 0) 1.0


# --- 6. KASUTAJATE IMPORT CSV-ST (1.0 punkt) ---
# PISTELINE KONTROLL
$TestUsers = @{
    "Müük" = "Aivo Teder"
    "Personal" = "Andres Karl Kukk"
    "Raamatupidamine" = "Anette Kuusk"
    "Toimetajad" = "Anneli Koppel"
    "IT" = "Anneli Roos"
    "Juhtkond" = "Annika Rand"
    "Haldus" = "Erki Niit"
}

$UsersFoundCount = 0
$UserCheckDetails = "<ul>"

foreach ($Dept in $TestUsers.Keys) {
    $ExpectedUser = $TestUsers[$Dept]
    $FoundUser = Get-ADUser -Filter "Name -eq '$ExpectedUser'" -Properties DistinguishedName
    
    if ($FoundUser) {
        if ($FoundUser.DistinguishedName -match "OU=$Dept") {
            $UsersFoundCount++
            $UserCheckDetails += "<li>Otsiti: <b>$ExpectedUser</b> (OU=$Dept) - <span style='color:green'>LEITUD</span></li>"
        } else {
            $UserCheckDetails += "<li>Otsiti: <b>$ExpectedUser</b> (OU=$Dept) - <span style='color:orange'>LEITUD VALES OU-s</span> ($($FoundUser.DistinguishedName))</li>"
        }
    } else {
        $UserCheckDetails += "<li>Otsiti: <b>$ExpectedUser</b> (OU=$Dept) - <span style='color:red'>PUUDUB</span></li>"
    }
}
$UserCheckDetails += "</ul>"

# Kui leitakse MÕNED kasutajad (vähemalt 1 neist testitavatest), anname 1 punkti
$ImportSuccess = ($UsersFoundCount -gt 0)
Add-Result "Loodud skript impordib AD kasutajad (.csv)" "Kasutajad ja struktuur leitud" "$UsersFoundCount / 7 testkasutajat leitud õigetest OU-dest" $ImportSuccess 1.0


# --- 7. GRUPIPOLIITIKAD (GPO) (2.0 punkti) ---

# GPO_KontodeLukustamine (TÄIELIKULT PARANDATUD - Õiged XML nimed)
$LockGPO = Get-GPO -Name "GPO_KontodeLukustamine" -ErrorAction SilentlyContinue
if ($LockGPO) {
    $GpoXml = [xml](Get-GPOReport -Guid $LockGPO.Id -ReportType Xml)
    $XmlContent = $GpoXml.InnerXml
    
    # GPO kasutab XML-is sisemiselt nimesid "LockoutBadCount" ja "LockoutDuration"
    $ThresholdOK = ($XmlContent -match "LockoutBadCount") -and ($XmlContent -match ">5<")
    $DurationOK = ($XmlContent -match "LockoutDuration") -and ($XmlContent -match ">15<")
    
    $IsLinked = ($GpoXml.GPO.LinksTo -ne $null)

    $Details = "GPO leitud: Jah. Katseid 5: $ThresholdOK. Aeg 15min: $DurationOK. Lingitud: $IsLinked"
    
    Add-Result "GPO_KontodeLukustamine" "Domeenile rakendatud, 5 katset, 15 min" $Details ($ThresholdOK -and $DurationOK -and $IsLinked) 1.0
} else {
    Add-Result "GPO_KontodeLukustamine" "Domeenile rakendatud, 5 katset, 15 min" "GPO-d ei leitud" $false 1.0
}

# Edge_Siseportaal (XML sisu kontroll)
$EdgeGPO = Get-GPO -Name "Edge_Siseportaal"
if ($EdgeGPO) {
    $GpoXml = [xml](Get-GPOReport -Guid $EdgeGPO.Id -ReportType Xml)
    $XmlContent = $GpoXml.InnerXml
    
    $HasHomepageUrl = ($XmlContent -match "siseportaal")
    $HasNewTabPage = ($XmlContent -match "NewTabPageLocation")
    
    $GpoLinkedToPersonal = ($GpoXml.GPO.LinksTo.SOMPath -match "OU=Personal")

    Add-Result "Edge_Siseportaal GPO" "Avaleht siseportaal, uue tab'i URL, lukustatud, OU=Personal" "Sisu olemas: $($HasHomepageUrl -and $HasNewTabPage), Lingitud Personal: $($GpoLinkedToPersonal -eq $true)" ($HasHomepageUrl -and $HasNewTabPage -and $GpoLinkedToPersonal) 1.0
} else {
    Add-Result "Edge_Siseportaal GPO" "Olemas ja seadistatud" "GPO-d ei leitud" $false 1.0
}


# --- HTML RAPORTI GENEREERIMINE ---
$Html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Windows Server Auditi Raport</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f9f9f9; color: #333; }
        h1 { border-bottom: 2px solid #005a9e; padding-bottom: 10px; }
        .summary { background-color: #fff; border-left: 5px solid #005a9e; padding: 15px; margin-bottom: 20px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .total-points { font-size: 24px; font-weight: bold; color: #d83b01; }
        table { border-collapse: collapse; width: 100%; background: white; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        th, td { border: 1px solid #ccc; padding: 10px; text-align: left; vertical-align: top; }
        th { background-color: #005a9e; color: white; }
        .details-box { background: #fff; padding: 15px; margin-top: 20px; border: 1px solid #ccc; }
    </style>
</head>
<body>
    <h1>Windows Server Auditi Raport</h1>
    
    <div class='summary'>
        <strong>Kontrollitud domeen:</strong> $ExpectedDomain<br>
        <strong>Käivitatud masinast:</strong> $ComputerName<br>
        <strong>Aeg:</strong> $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')<br><br>
        <span class='total-points'>KOKKU PUNKTE: $TotalPoints / 12.0</span>
    </div>

    <table>
        <tr>
            <th>Ülesanne</th>
            <th>Oodatud</th>
            <th>Leitud olukord</th>
            <th>Staatus</th>
            <th>Punktid</th>
        </tr>
"@

foreach ($row in $Results) {
    $Html += @"
        <tr style='background-color:$($row.Color)'>
            <td>$($row.Ylesanne)</td>
            <td>$($row.Oodatud)</td>
            <td>$($row.Leitud)</td>
            <td><strong>$($row.Staatus)</strong></td>
            <td><strong>$($row.Punktid)</strong></td>
        </tr>
"@
}

$Html += @"
    </table>

    <div class='details-box'>
        <h3>AD Kasutajate pistelise otsingu detailid (Import CSV)</h3>
        <p>Kontrolliti igast osakonnast ühte kindlat töötajat, et kinnitada andmete importi ja OU-struktuuri (1 punkt antakse juhul, kui leitakse vähemalt mõned kasutajad):</p>
        $UserCheckDetails
    </div>
</body>
</html>
"@

$Html | Out-File $ReportPath -Encoding UTF8
Write-Host "Kontroll on lõpetatud!" -ForegroundColor Green
Write-Host "Kogutud punktid: $TotalPoints / 12.0" -ForegroundColor Yellow
Write-Host "Raport asub failis: $ReportPath" -ForegroundColor Cyan


```
