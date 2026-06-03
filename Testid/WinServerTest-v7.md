Nüüd vist juba ok

```powershell
<#
.SYNOPSIS
    Täielik Windows Serveri auditi skript vastavalt hindamiskriteeriumitele.
    Sisaldab osalist hindamist (DHCP, Haldur, Arvutid, CSV) ja XML-põhist GPO kontrolli.
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

# --- FUNKTSIOON TULEMUSTE LISAMISEKS (Toetab osalisi punkte) ---
function Add-Result {
    param(
        [string]$Ylesanne,
        [string]$Oodatud,
        [string]$Leitud,
        [bool]$Staatus,
        [double]$MaxPunktid,
        [double]$OsalisedPunktid = -1
    )
    
    # Arvutame teenitud punktid
    $teenitud = if ($OsalisedPunktid -ge 0) { $OsalisedPunktid } elseif ($Staatus) { $MaxPunktid } else { 0 }
    $Global:TotalPoints += $teenitud
    
    # Määrame värvi ja staatuse teksti
    if ($teenitud -eq $MaxPunktid -and $MaxPunktid -gt 0) {
        $color = "#c6efce" # Roheline
        $staatusTekst = "OK"
    } elseif ($teenitud -gt 0) {
        $color = "#fff2cc" # Kollane (osaline)
        $staatusTekst = "OSALINE"
    } else {
        $color = "#ffc7ce" # Punane
        $staatusTekst = "PUUDU/VIGA"
    }

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


# --- 3. DHCP TEENUS (1.0 punkt) JA FAILOVER (1.0 punkt) ---
$DHCPScope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Select-Object -First 1

$dhcpTasksMet = 0
$dhcpDetails = "<ul style='margin:0; padding-left:20px;'>"

# Osa 1: DHCP Teenuse seadistused (maksimum 1.0p)
if ($DHCPScope) {
    $dhcpTasksMet++
    $dhcpDetails += "<li>Skoop leitud: <b style='color:green'>Jah (+0.25p)</b></li>"

    if ($DHCPScope.LeaseDuration.TotalHours -eq 4) {
        $dhcpTasksMet++
        $dhcpDetails += "<li>Rendiaeg 4h: <b style='color:green'>Täidetud (+0.25p)</b></li>"
    } else {
        $dhcpDetails += "<li>Rendiaeg 4h: <b style='color:red'>Vale ($($DHCPScope.LeaseDuration))</b></li>"
    }
    
    # Parandatud reservatsioonide loogika (force array) ja nimede kuvamine
    $Reservations = @(Get-DhcpServerv4Reservation -ScopeId $DHCPScope.ScopeId -ErrorAction SilentlyContinue)
    if ($Reservations.Count -gt 0) {
        $dhcpTasksMet++
        $resInfo = ($Reservations | ForEach-Object { if($_.Name){$_.Name}else{$_.IPAddress} }) -join ", "
        $dhcpDetails += "<li>Reservatsioonid: <b style='color:green'>Täidetud (+0.25p)</b> [Kliendid: $resInfo]</li>"
    } else {
        $dhcpDetails += "<li>Reservatsioonid: <b style='color:red'>Puudu</b></li>"
    }
    
    $DNSOptions = Get-DhcpServerv4OptionValue -ScopeId $DHCPScope.ScopeId -OptionId 6 -ErrorAction SilentlyContinue
    if ($DNSOptions -and $DNSOptions.Value.Count -ge 2) {
        $dhcpTasksMet++
        $dhcpDetails += "<li>DNS serverid (min 2): <b style='color:green'>Täidetud (+0.25p)</b></li>"
    } else {
        $dhcpDetails += "<li>DNS serverid (min 2): <b style='color:red'>Puudu / Vähem kui 2</b></li>"
    }
} else {
    $dhcpDetails += "<li>Skoop leitud: <b style='color:red'>Puudu</b></li>"
    $dhcpDetails += "<li>Rendiaeg 4h: <b style='color:red'>-</b></li>"
    $dhcpDetails += "<li>Reservatsioonid: <b style='color:red'>-</b></li>"
    $dhcpDetails += "<li>DNS serverid (min 2): <b style='color:red'>-</b></li>"
}
$dhcpDetails += "</ul>"

$dhcpScore = $dhcpTasksMet * 0.25
$dhcpStatus = ($dhcpTasksMet -eq 4)
Add-Result "Seadista DHCP teenus, reservatsioonid, DNS" "Skoop, 4h, reserv, 2xDNS" $dhcpDetails $dhcpStatus 1.0 $dhcpScore

# Osa 2: DHCP Failover (maksimum 1.0p)
$Failover = Get-DhcpServerv4Failover -ErrorAction SilentlyContinue
$foStatus = ($Failover -and (($Failover.PartnerServer -join " ") -match "DC2"))
$foDetails = if ($foStatus) { "Partner DC2 leitud" } else { "Failover puudu või vale partner" }
Add-Result "Seadista DHCP teenusele failover" "Partneriks on DC2" $foDetails $foStatus 1.0


# --- 4. AD STRUKTUUR, HALDUR JA KLIENT (1.5 punkti) ---
$OUUsers = Get-ADOrganizationalUnit -Filter "Name -eq 'Kasutajad'"
$OUComps = Get-ADOrganizationalUnit -Filter "Name -eq 'Arvutid'"
Add-Result "AD-sse on loodud 2 OU-d: Kasutajad ja Arvutid" "Mõlemad loodud" (if($OUUsers -and $OUComps){"Mõlemad leitud"}else{"Puudu/Osaline"}) ($OUUsers -and $OUComps) 0.5

# HALDURI KONTROLL (Osaline hindamine 0.5p)
$Haldur = Get-ADUser -Filter "Name -eq 'Haldur' -or SamAccountName -eq 'haldur'" -Properties MemberOf, DistinguishedName -ErrorAction SilentlyContinue
$haldurTasksMet = 0
$haldurDetails = "<ul style='margin:0; padding-left:20px;'>"

if ($Haldur) {
    if ($Haldur.DistinguishedName -match "OU=Kasutajad") {
        $haldurTasksMet++
        $haldurDetails += "<li>Haldur asub OU-s Kasutajad: <b style='color:green'>Jah (+0.25p)</b></li>"
    } else {
        $haldurDetails += "<li>Haldur asub OU-s Kasutajad: <b style='color:red'>Ei (Asub: $($Haldur.DistinguishedName))</b></li>"
    }
    
    $IsDomainAdmin = ($Haldur.MemberOf -match "Domain Admins|Domeeni administraatorid")
    if ($IsDomainAdmin) {
        $haldurTasksMet++
        $haldurDetails += "<li>Haldur on Domain Admins grupis: <b style='color:green'>Jah (+0.25p)</b></li>"
    } else {
        $haldurDetails += "<li>Haldur on Domain Admins grupis: <b style='color:red'>Ei</b></li>"
    }
} else {
    $haldurDetails += "<li>Kasutaja 'haldur': <b style='color:red'>Ei leitud AD-st</b></li>"
    $haldurDetails += "<li>Domain Admins liikmelisus: <b style='color:red'>-</b></li>"
}
$haldurDetails += "</ul>"

$haldurScore = $haldurTasksMet * 0.25
$haldurStatus = ($haldurTasksMet -eq 2)
Add-Result "Domeeni on lisatud kasutaja haldur (Domain Admins)" "OU=Kasutajad ja Domain Admins" $haldurDetails $haldurStatus 0.5 $haldurScore


# KLIENTMASINA KONTROLL (Osaline hindamine 0.5p)
$AllComps = Get-ADComputer -Filter {Name -notlike "DC1" -and Name -notlike "DC2"} -Properties DistinguishedName -ErrorAction SilentlyContinue
$compTasksMet = 0
$compDetails = "<ul style='margin:0; padding-left:20px;'>"

if ($AllComps) {
    $inArvutidOU = $AllComps | Where-Object { $_.DistinguishedName -match "OU=Arvutid" }
    $inComputersCN = $AllComps | Where-Object { $_.DistinguishedName -match "CN=Computers" }
    
    if ($inArvutidOU) {
        $compTasksMet = 2 # 0.5 punkti
        $compDetails += "<li>Domeenist leitud klientmasin: <b style='color:green'>Jah (+0.25p)</b></li>"
        $compDetails += "<li>Masin asub OU-s Arvutid: <b style='color:green'>Jah (+0.25p) ($($inArvutidOU[0].Name))</b></li>"
    } elseif ($inComputersCN) {
        $compTasksMet = 1 # 0.25 punkti
        $compDetails += "<li>Domeenist leitud klientmasin: <b style='color:green'>Jah (+0.25p)</b></li>"
        $compDetails += "<li>Masin asub OU-s Arvutid: <b style='color:orange'>Ei, asub hoopis CN=Computers all ($($inComputersCN[0].Name))</b></li>"
    } else {
        $compTasksMet = 1 # 0.25 punkti (liidetud domeeni, aga suvalises kohas)
        $compDetails += "<li>Domeenist leitud klientmasin: <b style='color:green'>Jah (+0.25p)</b></li>"
        $compDetails += "<li>Masin asub OU-s Arvutid: <b style='color:orange'>Ei, asub mujal ($($AllComps[0].DistinguishedName))</b></li>"
    }
} else {
    $compDetails += "<li>Domeenist leitud klientmasin: <b style='color:red'>Ei leitud ühtegi (va DCd)</b></li>"
    $compDetails += "<li>Masin asub OU-s Arvutid: <b style='color:red'>-</b></li>"
}
$compDetails += "</ul>"

$compScore = $compTasksMet * 0.25
$compStatus = ($compTasksMet -eq 2)
Add-Result "Windows 11 klientmasin on lisatud domeeni ja OU-sse Arvutid" "Domeenis ja OU-s Arvutid" $compDetails $compStatus 0.5 $compScore


# --- 5. DNS A-KIRJED (1.0 punkt) ---
$DnsRecords = Get-DnsServerResourceRecord -ZoneName $ExpectedDomain -RRType A | Where-Object {$_.HostName -notmatch "@|gc|DomainDnsZones|ForestDnsZones|DC1|DC2"}
Add-Result "DNS serveris on tehtud A-kirjed kõikide Linux serverite jaoks" "Vähemalt 1 manuaalne A-kirje" "$($DnsRecords.Count) tk leitud" ($DnsRecords.Count -gt 0) 1.0


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
$UserCheckDetails = "<ul style='margin:0; padding-left:20px;'>"

foreach ($Dept in $TestUsers.Keys) {
    $ExpectedUser = $TestUsers[$Dept]
    $FoundUser = Get-ADUser -Filter "Name -eq '$ExpectedUser'" -Properties DistinguishedName -ErrorAction SilentlyContinue
    
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

# 1 punkt, kui on leitud kasvõi mõned testitavad kasutajad
$ImportSuccess = ($UsersFoundCount -gt 0)
Add-Result "Loodud skript impordib AD kasutajad (kasutajad.csv)" "Kasutajad ja struktuur leitud" "$UsersFoundCount / 7 testkasutajat leitud õigetest OU-dest" $ImportSuccess 1.0


# --- 7. GRUPIPOLIITIKAD (GPO) (2.0 punkti) ---
# GPO_KontodeLukustamine
$LockGPO = Get-GPO -Name "GPO_KontodeLukustamine" -ErrorAction SilentlyContinue
if ($LockGPO) {
    $GpoXml = [xml](Get-GPOReport -Guid $LockGPO.Id -ReportType Xml)
    $XmlContent = $GpoXml.InnerXml
    
    $ThresholdOK = ($XmlContent -match "LockoutBadCount") -and ($XmlContent -match ">5<")
    $DurationOK = ($XmlContent -match "LockoutDuration") -and ($XmlContent -match ">15<")
    $IsLinked = ($GpoXml.GPO.LinksTo -ne $null)

    $Details = "GPO leitud: Jah. Katseid 5: $ThresholdOK. Aeg 15min: $DurationOK. Lingitud: $IsLinked"
    Add-Result "GPO_KontodeLukustamine (5 katset, 15 min)" "Domeenile rakendatud, 5 katset, 15 min" $Details ($ThresholdOK -and $DurationOK -and $IsLinked) 1.0
} else {
    Add-Result "GPO_KontodeLukustamine (5 katset, 15 min)" "Domeenile rakendatud, 5 katset, 15 min" "GPO-d ei leitud" $false 1.0
}

# Edge_Siseportaal
$EdgeGPO = Get-GPO -Name "Edge_Siseportaal" -ErrorAction SilentlyContinue
if ($EdgeGPO) {
    $GpoXml = [xml](Get-GPOReport -Guid $EdgeGPO.Id -ReportType Xml)
    $XmlContent = $GpoXml.InnerXml
    
    $HasHomepageUrl = ($XmlContent -match "siseportaal")
    $HasNewTabPage = ($XmlContent -match "NewTabPageLocation")
    $GpoLinkedToPersonal = ($GpoXml.GPO.LinksTo.SOMPath -match "OU=Personal")

    Add-Result "GPO Edge_Siseportaal (Personal avaleht)" "Avaleht siseportaal, uue tab'i URL, lukustatud, OU=Personal" "Sisu olemas: $($HasHomepageUrl -and $HasNewTabPage), Lingitud Personal: $($GpoLinkedToPersonal -eq $true)" ($HasHomepageUrl -and $HasNewTabPage -and $GpoLinkedToPersonal) 1.0
} else {
    Add-Result "GPO Edge_Siseportaal (Personal avaleht)" "Olemas ja seadistatud" "GPO-d ei leitud" $false 1.0
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
            <th>Ülesanne (Hindamismudel)</th>
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
