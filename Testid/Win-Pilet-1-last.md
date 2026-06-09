## Windows Piket 1 veel parem ##


```powershell

<#
.SYNOPSIS
    Täielik Windows Serveri auditi skript koos detailse asukohatuvastusega.
    Käivitada DC1 serveris Domain Admin õigustes.
#>

$ErrorActionPreference = "SilentlyContinue"

# Moodulite laadimine
Import-Module ActiveDirectory
Import-Module GroupPolicy
Import-Module DhcpServer
Import-Module DnsServer
Import-Module WebAdministration

# --- SEADISTUSED JA SISEND ---
$ExpectedDomain = Read-Host "Sisesta oodatud domeeninimi (nt oige.ee või sinunimi.local)"
$OpilaseNimi = Read-Host "Sisesta õpilase ees- ja perekonnanimi"

Write-Host "Vali pileti liik (1 - Linux, 2 - Windows, 3 - Võrk):" -ForegroundColor Cyan
$PiletLiikValik = Read-Host "Sisesta number"
$PiletLiik = switch ($PiletLiikValik) { '1' {'Linux'} '2' {'Windows'} '3' {'Võrk'} Default {'Määramata'} }
$PiletNumber = Read-Host "Sisesta pileti number (1-6)"
$TaisPilet = "$PiletLiik $PiletNumber"

$SafeName = $OpilaseNimi -replace '\s+', '_'
$SafePilet = $TaisPilet -replace '\s+', '_'
$ReportPath = "$PSScriptRoot\HindamisRaport_${SafeName}_${SafePilet}.html"
$JsonPath = "$PSScriptRoot\HindamisRaport_${SafeName}_${SafePilet}.json"

$TotalPoints = 0
$Results = @()

function Add-Result {
    param([string]$Ylesanne, [string]$Oodatud, [string]$Leitud, [bool]$Staatus, [double]$MaxPunktid, [double]$OsalisedPunktid = -1)
    $teenitud = if ($OsalisedPunktid -ge 0) { $OsalisedPunktid } elseif ($Staatus) { $MaxPunktid } else { 0 }
    $Global:TotalPoints += $teenitud
    
    if ($teenitud -eq $MaxPunktid -and $MaxPunktid -gt 0) { $color = "#c6efce"; $staatusTekst = "OK" }
    elseif ($teenitud -gt 0) { $color = "#fff2cc"; $staatusTekst = "OSALINE" }
    else { $color = "#ffc7ce"; $staatusTekst = "PUUDU/VIGA" }

    $Global:Results += [PSCustomObject]@{
        Ylesanne = $Ylesanne; Oodatud = $Oodatud; Leitud = $Leitud; Staatus = $staatusTekst; Punktid = $teenitud; Color = $color
    }
}

# --- ABIFUNKTSIOON: DN muutmine loetavaks domeenirajaks ---
function Convert-DNToReadable {
    param([string]$dn)
    if (!$dn) { return "Puudub" }
    $parts = $dn -split ','
    $ouPath = @()
    $domainParts = @()
    foreach ($p in $parts) {
        if ($p -match "^OU=(.+)$") { $ouPath += $Matches[1] }
        if ($p -match "^CN=(.+)$" -and $ouPath.Count -eq 0) { $ouPath += $Matches[1] }
        if ($p -match "^DC=(.+)$") { $domainParts += $Matches[1] }
    }
    [array]::Reverse($ouPath)
    $domainStr = $domainParts -join '.'
    return "$domainStr/" + ($ouPath -join '/')
}

# --- DETAILEERITUD GPO HINDAMISE FUNKTSIOON ---
function Check-GPOSettings {
    param($GpoName, $ExpectedOUs, $Regexes, $MaxP)
    $Gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
    if (!$Gpo) { return @{ Pts = 0; Status = $false; Det = "GPO nimega '$GpoName' ei eksisteeri üldse." } }

    $Xml = [xml](Get-GPOReport -Guid $Gpo.Id -ReportType Xml)
    $txt = $Xml.InnerXml

    # Tuvastame kõik reaalsed kohad, kuhu see GPO on lingitud
    $actualLinks = @()
    if ($Xml.GPO.LinksTo) {
        $links = $Xml.GPO.LinksTo
        if ($links -is [array]) {
            foreach ($l in $links) { $actualLinks += $l.SOMName }
        } else {
            $actualLinks += $links.SOMName
        }
    }
    $linksStr = if ($actualLinks.Count -gt 0) { $actualLinks -join ", " } else { "Kuhu tegemata (lingid puuduvad)" }

    # Kontrollime, kas oodatud link on olemas
    $linksOk = $true
    foreach ($ou in $ExpectedOUs) {
        if ($ou -and $actualLinks -notcontains $ou -and ($Xml.GPO.LinksTo.SOMPath -join " ") -notmatch $ou) { $linksOk = $false }
    }

    # Sisemiste seadete kontroll regexiga
    $setMet = 0
    foreach ($r in $Regexes) { if ($txt -match $r) { $setMet++ } }

    if ($linksOk) {
        if ($setMet -eq $Regexes.Count) {
            return @{ Pts = $MaxP; Status = $true; Det = "Seaded korras ja õigesti lingitud ($linksStr)." }
        } elseif ($setMet -gt 0) {
            return @{ Pts = ($MaxP * 0.75); Status = $false; Det = "Link õige ($linksStr), kuid seadistus on poolik." }
        } else {
            return @{ Pts = ($MaxP * 0.25); Status = $false; Det = "Link õige ($linksStr), aga seaded seest puudu!" }
        }
    } else {
        # VALE ASUKOHT, kuid seaded võivad olla õiged
        if ($setMet -eq $Regexes.Count) {
            return @{ Pts = ($MaxP * 0.75); Status = $false; Det = "Seaded sisse ehitatud 100% ÕIGESTI, kuid VALE LINK! GPO on lingitud hoopis: [$linksStr]" }
        } elseif ($setMet -gt 0) {
            return @{ Pts = ($MaxP * 0.5); Status = $false; Det = "Seaded osaliselt olemas, kuid asukoht täiesti vale (Lingitud: [$linksStr])" }
        } else {
            return @{ Pts = 0; Status = $false; Det = "Seaded puudu ja asukoht vale (Lingitud: [$linksStr])" }
        }
    }
}

# ====================================================================
# 1. SERVERITE NIMED JA IP-D (2.0 punkti)
# ====================================================================
$ComputerName = $env:COMPUTERNAME
Add-Result "Muuta masina nimi DC1" "Masina nimi on DC1" "Leitud arvuti nimi: $ComputerName" ($ComputerName -eq "DC1") 0.5

$DC1IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq "Manual" -and $_.InterfaceAlias -notmatch "Loopback" }).IPAddress
Add-Result "DC1 staatiline IP" "Manuaalne IPv4 seadistus" ("IP-aadressid: " + ($DC1IP -join ", ")) ($DC1IP.Count -gt 0) 0.5

$DC2 = Get-ADComputer -Filter "Name -eq 'DC2'"
Add-Result "WinCore2025 masina nimi DC2" "AD-s eksisteerib arvuti DC2" (if($DC2){"Leitud DC2 konto Active Directoryst"}else{"Ei leitud arvutit nimega DC2"}) ($DC2 -ne $null) 0.5

$DC2DNS = Resolve-DnsName -Name "DC2" -Type A -ErrorAction SilentlyContinue
Add-Result "DC2 staatiline IP" "DNS kirje viitab DC2 IP-le" (if($DC2DNS){"DNS-is suunab IP-le: " + $DC2DNS.IPAddress}else{"DNS-is puudub kirje 'DC2'"}) ($DC2DNS -ne $null) 0.5

# ====================================================================
# 2. AD DS JA DNS TEENUSED (2.5 punkti)
# ====================================================================
$Domain = Get-ADDomain
Add-Result "Seadista DC1 AD DS domeen" "Domeen $ExpectedDomain" "Tuvastatud domeen: $($Domain.DNSRoot)" ($Domain.DNSRoot -eq $ExpectedDomain) 1.0

$DNSRole = Get-WindowsFeature DNS
Add-Result "Seadista DC1 DNS teenus" "DNS roll paigaldatud" "Roll on: $($DNSRole.InstallState)" ($DNSRole.Installed) 0.5

$DomainControllers = Get-ADDomainController -Filter *
$HasTwoDCs = ($DomainControllers.Count -ge 2) -and ($DomainControllers.Name -contains "DC2")
Add-Result "Lisada DC2 teiseks domeenikontrolleriks" "Vähemalt 2 DC-d (sh DC2)" ("Domeenikontrollerid: " + ($DomainControllers.Name -join ", ")) $HasTwoDCs 1.0

# ====================================================================
# 3. DHCP TEENUS JA FAILOVER (2.0 punkti)
# ====================================================================
$DHCPScope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Select-Object -First 1
$dhcpTasksMet = 0
$dhcpDetails = "<ul style='margin:0; padding-left:20px;'>"

if ($DHCPScope) {
    $dhcpTasksMet++
    $dhcpDetails += "<li>Skoop leitud: <b style='color:green'>Jah (+0.25p) [$($DHCPScope.ScopeId)]</b></li>"
    if ($DHCPScope.LeaseDuration.TotalHours -eq 4) {
        $dhcpTasksMet++; $dhcpDetails += "<li>Rendiaeg 4h: <b style='color:green'>Täidetud (+0.25p)</b></li>"
    } else {
        $dhcpDetails += "<li>Rendiaeg: <b style='color:red'>Vale ($($DHCPScope.LeaseDuration))</b></li>"
    }
    $Reservations = @(Get-DhcpServerv4Reservation -ScopeId $DHCPScope.ScopeId -ErrorAction SilentlyContinue)
    if ($Reservations.Count -gt 0) {
        $dhcpTasksMet++
        $resInfo = ($Reservations | ForEach-Object { if($_.Name){$_.Name}else{$_.IPAddress} }) -join ", "
        $dhcpDetails += "<li>Reservatsioonid: <b style='color:green'>Täidetud (+0.25p)</b> [$resInfo]</li>"
    } else { $dhcpDetails += "<li>Reservatsioonid: <b style='color:red'>Puudu</b></li>" }
    
    $DNSOptions = Get-DhcpServerv4OptionValue -ScopeId $DHCPScope.ScopeId -OptionId 6 -ErrorAction SilentlyContinue
    if ($DNSOptions -and $DNSOptions.Value.Count -ge 2) {
        $dhcpTasksMet++; $dhcpDetails += "<li>DNS serverid (min 2): <b style='color:green'>Täidetud (+0.25p)</b></li>"
    } else { $dhcpDetails += "<li>DNS serverid: <b style='color:red'>Vähem kui 2 seadistatud</b></li>" }
} else { $dhcpDetails += "<li>Skoop: <b style='color:red'>DHCP Skoop puudub täielikult</b></li>" }
$dhcpDetails += "</ul>"

Add-Result "Seadista DHCP teenus, reservatsioonid, DNS" "Skoop, 4h, reserv, 2xDNS" $dhcpDetails ($dhcpTasksMet -eq 4) 1.0 ($dhcpTasksMet * 0.25)

$Failover = Get-DhcpServerv4Failover -ErrorAction SilentlyContinue
$foStatus = ($Failover -and (($Failover.PartnerServer -join " ") -match "DC2"))
$foDetails = if ($foStatus) { "Failover korras. Partner: DC2" } else { "Failover puudub või partner pole DC2. Tuvastatud partner: $($Failover.PartnerServer)" }
Add-Result "Seadista DHCP teenusele failover" "Partneriks on DC2" $foDetails $foStatus 1.0

# ====================================================================
# 4. AD STRUKTUUR, HALDUR JA KLIENT (1.5 punkti)
# ====================================================================
$OUUsers = Get-ADOrganizationalUnit -Filter "Name -eq 'Kasutajad'"
$OUComps = Get-ADOrganizationalUnit -Filter "Name -eq 'Arvutid'"
Add-Result "AD-sse on loodud 2 OU-d: Kasutajad ja Arvutid" "Mõlemad loodud" (if($OUUsers -and $OUComps){"Mõlemad leitud juurkaustast"}else{"Puudu või valesti loetud"}) ($OUUsers -and $OUComps) 0.5

# HALDUR ASUKOHATUVASTUSEGA
$Haldur = Get-ADUser -Filter "Name -eq 'Haldur' -or SamAccountName -eq 'haldur'" -Properties DistinguishedName -ErrorAction SilentlyContinue
$haldurTasksMet = 0
$haldurDetails = "<ul style='margin:0; padding-left:20px;'>"

if ($Haldur) {
    $realHaldurLocation = Convert-DNToReadable $Haldur.DistinguishedName
    if ($Haldur.DistinguishedName -match "OU=Kasutajad") {
        $haldurTasksMet++
        $haldurDetails += "<li>Asukoht: <b style='color:green'>Õige (Kasutajad all)</b></li>"
    } else {
        $haldurDetails += "<li>Asukoht: <b style='color:red'>VALE! Kasutaja asub hoopis: $realHaldurLocation</b></li>"
    }
    
    $HaldurGroups = Get-ADPrincipalGroupMembership -Identity $Haldur -ErrorAction SilentlyContinue
    $IsDomainAdmin = ($HaldurGroups.Name -match "Domain Admins|Domeeni administraatorid")
    if ($IsDomainAdmin) {
        $haldurTasksMet++
        $haldurDetails += "<li>Grupp: <b style='color:green'>Domain Admins olemas (+0.25p)</b></li>"
    } else {
        $haldurDetails += "<li>Grupp: <b style='color:red'>Ei kuulu Domain Admins gruppi!</b></li>"
    }
} else { $haldurDetails += "<li><b style='color:red'>Kasutajat 'haldur' ei leitud AD-st üldse!</b></li>" }
$haldurDetails += "</ul>"
Add-Result "Domeeni on lisatud kasutaja haldur (Domain Admins)" "OU=Kasutajad ja Domain Admins" $haldurDetails ($haldurTasksMet -eq 2) 0.5 ($haldurTasksMet * 0.25)

# KLIENTMASIN ASUKOHATUVASTUSEGA
$AllComps = Get-ADComputer -Filter {Name -notlike "DC1" -and Name -notlike "DC2"} -Properties DistinguishedName -ErrorAction SilentlyContinue
$compTasksMet = 0
$compDetails = "<ul style='margin:0; padding-left:20px;'>"

if ($AllComps) {
    $compTasksMet = 1 # Leitud domeenist
    $realCompLoc = Convert-DNToReadable $AllComps[0].DistinguishedName
    $compDetails += "<li>Klientmasin '$($AllComps[0].Name)': <b style='color:green'>Liidetud domeeni (+0.25p)</b></li>"
    
    if ($AllComps.DistinguishedName -match "OU=Arvutid") {
        $compTasksMet = 2
        $compDetails += "<li>Asukoht: <b style='color:green'>Õige (OU=Arvutid) (+0.25p)</b></li>"
    } else {
        $compDetails += "<li>Asukoht: <b style='color:red'>VALE OU! Masin unustati asukohta: $realCompLoc</b></li>"
    }
} else { $compDetails += "<li>Klientmasin: <b style='color:red'>Ühtegi klientmasinat (peale DC-de) ei leitud domeenist!</b></li>" }
$compDetails += "</ul>"
Add-Result "Windows 11 klientmasin on lisatud domeeni ja OU-sse Arvutid" "Domeenis ja OU-s Arvutid" $compDetails ($compTasksMet -eq 2) 0.5 ($compTasksMet * 0.25)

# ====================================================================
# 5. DNS A-KIRJED JA CSV IMPORT (2.0 punkti)
# ====================================================================
$DnsRecords = Get-DnsServerResourceRecord -ZoneName $ExpectedDomain -RRType A | Where-Object {$_.HostName -notmatch "@|gc|DomainDnsZones|ForestDnsZones|DC1|DC2"}
Add-Result "DNS serveris on tehtud A-kirjed kõikide Linux serverite jaoks" "Vähemalt 1 manuaalne A-kirje" ("Tuvastati " + $DnsRecords.Count + " manuaalset A-kirjet.") ($DnsRecords.Count -gt 0) 1.0

$TestUsers = @{"Müük"="Aivo Teder"; "Personal"="Andres Karl Kukk"; "Raamatupidamine"="Anette Kuusk"; "Toimetajad"="Anneli Koppel"; "IT"="Anneli Roos"; "Juhtkond"="Annika Rand"; "Haldus"="Erki Niit"}
$UsersFoundCount = 0
$UserCheckDetails = "<ul style='margin:0; padding-left:20px;'>"
foreach ($Dept in $TestUsers.Keys) {
    $ExpectedUser = $TestUsers[$Dept]; $FoundUser = Get-ADUser -Filter "Name -eq '$ExpectedUser'" -Properties DistinguishedName -ErrorAction SilentlyContinue
    if ($FoundUser) {
        $realLoc = Convert-DNToReadable $FoundUser.DistinguishedName
        if ($FoundUser.DistinguishedName -match "OU=$Dept") {
            $UsersFoundCount++; $UserCheckDetails += "<li><b>$ExpectedUser</b> (OU=$Dept) - <span style='color:green'>ÕIGES KOHAS</span></li>"
        } else { $UserCheckDetails += "<li><b>$ExpectedUser</b> (Oodati: OU=$Dept) - <span style='color:orange'>VALES OU-S! Leiti hoopis: $realLoc</span></li>" }
    } else { $UserCheckDetails += "<li><b>$ExpectedUser</b> (OU=$Dept) - <span style='color:red'>PUUDU (Import ebaõnnestus)</span></li>" }
}
$UserCheckDetails += "</ul>"
Add-Result "Loodud skript impordib AD kasutajad (kasutajad.csv)" "Kasutajad ja struktuur leitud" "$UsersFoundCount / 7 testkasutajast asub täpselt õiges OU-s." ($UsersFoundCount -gt 0) 1.0

# ====================================================================
# 6. GPO: DETAILNE KONTROLL (2.0 punkti)
# ====================================================================
$resLock = Check-GPOSettings "GPO_KontodeLukustamine" @() @("LockoutBadCount", ">5<", "LockoutDuration", ">15<") 1.0
Add-Result "GPO_KontodeLukustamine (5 katset, 15 min)" "Domeenile rakendatud, 5 katset, 15 min" $resLock.Det $resLock.Status 1.0 $resLock.Pts

$resEdge = Check-GPOSettings "Edge_Siseportaal" @("Personal") @("siseportaal", "NewTabPageLocation") 1.0
Add-Result "GPO Edge_Siseportaal (Personal avaleht)" "Avaleht siseportaal, uue tab'i URL, lukustatud" $resEdge.Det $resEdge.Status 1.0 $resEdge.Pts

# ====================================================================
# 7. IIS, CMS, AD CS, SSL JA DNS CNAME (Kokku: 8.0 punkti)
# ====================================================================

# 7.1 Lisa IIS serveriteenus
$iisFeature = Get-WindowsFeature Web-Server -ErrorAction SilentlyContinue
$iisSvc = Get-Service W3SVC -ErrorAction SilentlyContinue
$iisPts = 0.0; $iisDet = "<ul style='margin:0; padding-left:20px;'>"
if ($iisFeature.Installed) { $iisPts += 0.5; $iisDet += "<li>IIS Roll: <b style='color:green'>Paigaldatud (+0.5p)</b></li>" }
else { $iisDet += "<li>IIS Roll: <b style='color:red'>Puudu</b></li>" }
if ($iisSvc.Status -eq 'Running') { $iisPts += 0.5; $iisDet += "<li>W3SVC teenus: <b style='color:green'>Töötab (+0.5p)</b></li>" }
else { $iisDet += "<li>W3SVC teenus: <b style='color:red'>Seisab või puudub</b></li>" }
$iisDet += "</ul>"
Add-Result "Lisa IIS serveriteenus Windows DC1 serverile" "IIS roll paigaldatud ja töötab" $iisDet ($iisPts -eq 1.0) 1.0 $iisPts

# 7.2 Saidi siseportaal tegemine
$siteNameMatch = "siseportaal"
$IISSite = Get-Website | Where-Object { $_.Name -match $siteNameMatch -or $_.bindings.Collection.bindingInformation -match $siteNameMatch }
$sitePts = 0.0; $siteDet = "<ul style='margin:0; padding-left:20px;'>"
if ($IISSite) { $sitePts = 1.0; $siteDet += "<li>Sait leitud: <b style='color:green'>Jah (+1.0p) [Nimi IIS-is: '$($IISSite[0].Name)']</b></li>" }
else { $siteDet += "<li>Sait: <b style='color:red'>Ei leitud ühtegi 'siseportaal' nime või bindinguga veebisaiti.</b></li>" }
$siteDet += "</ul>"
Add-Result "Saidi siseportaal.$ExpectedDomain tegemine IIS serverile" "Sait 'siseportaal' eksisteerib" $siteDet ($sitePts -eq 1.0) 1.0 $sitePts

# 7.3 Sisuhaldussüsteemi paigaldus (REALSES KAUSTAS - NÄITAB ASUKOHTA)
$cmsPts = 0.0; $cmsDet = "<ul style='margin:0; padding-left:20px;'>"
if ($IISSite) {
    $rawPath = $IISSite[0].PhysicalPath
    $physPath = [Environment]::ExpandEnvironmentVariables($rawPath)
    
    if ($physPath -and (Test-Path $physPath)) {
        $cmsPts += 1.0
        $cmsDet += "<li>Füüsiline kaust: <b style='color:green'>Tuvastatud asukohast: $physPath (+1.0p)</b></li>"
        $phpFiles = Get-ChildItem -Path $physPath -Filter "*.php" -Recurse -Depth 2 -ErrorAction SilentlyContinue
        if ($phpFiles.Count -gt 0) {
            $cmsPts += 1.0; $cmsDet += "<li>CMS PHP failid: <b style='color:green'>Leitud ($($phpFiles.Count) tk) (+1.0p)</b></li>"
        } else { $cmsDet += "<li>CMS failid: <b style='color:red'>Kaust on tühi või puuduvad .php laiendiga failid.</b></li>" }
    } else { $cmsDet += "<li>Füüsiline kaust: <b style='color:red'>IIS viitab kaustale '$physPath', kuid seda pole kettal olemas!</b></li>" }
} else { $cmsDet += "<li>CMS kontroll: <b style='color:red'>Saiti pole, ei saa kausta kontrollida.</b></li>" }
$cmsDet += "</ul>"
Add-Result "Sisuhaldussüsteemi paigaldus ja seadistamine" "Füüsiline kaust ja CMS (.php) failid olemas" $cmsDet ($cmsPts -eq 2.0) 2.0 $cmsPts

# 7.4 SSL sertifikaadi loomine
$sslPts = 0.0; $sslDet = "<ul style='margin:0; padding-left:20px;'>"
$caFeature = Get-WindowsFeature AD-Certificate -ErrorAction SilentlyContinue
if ($caFeature.Installed) { $sslPts += 0.5; $sslDet += "<li>AD CS roll: <b style='color:green'>Paigaldatud (+0.5p)</b></li>" }
else { $sslDet += "<li>AD CS roll: <b style='color:red'>Puudu</b></li>" }

if ($IISSite) {
    $httpsBinding = $IISSite[0].bindings.Collection | Where-Object { $_.protocol -eq "https" }
    if ($httpsBinding) {
        $sslPts += 0.5; $sslDet += "<li>HTTPS binding: <b style='color:green'>Olemas portidel/andmetel: $($httpsBinding.bindingInformation) (+0.5p)</b></li>"
        $cert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object { $_.Subject -match "siseportaal" -or $_.Extensions.Format(0) -match "siseportaal" }
        if ($cert) {
            $sslPts += 0.5; $sslDet += "<li>Sertifikaat: <b style='color:green'>Leitud nimega '$($cert.Subject)' (+0.5p)</b></li>"
            if ($cert.Extensions.Format(0) -match "siseveeb") {
                $sslPts += 0.5; $sslDet += "<li>SAN laiend 'siseveeb': <b style='color:green'>Olemas sertifikaadil (+0.5p)</b></li>"
            } else { $sslDet += "<li>SAN laiend 'siseveeb': <b style='color:red'>Puudub (Sertifikaadi info: $($cert.Extensions.Format(0)))</b></li>" }
        } else { $sslDet += "<li>Sertifikaat: <b style='color:red'>Sertifikaadihoidlast (My) ei leitud ühtegi 'siseportaal' nimega serti!</b></li>" }
    } else { $sslDet += "<li>HTTPS binding: <b style='color:red'>Sait on ainult HTTP peal, HTTPS puudub.</b></li>" }
} else { $sslDet += "<li>SSL seadistus: <b style='color:red'>Saiti pole leitud.</b></li>" }
$sslDet += "</ul>"
Add-Result "SSL sertifikaadi loomine saidi siseportaal.$ExpectedDomain jaoks" "AD CS olemas, HTTPS binding ja SAN sertifikaat" $sslDet ($sslPts -eq 2.0) 2.0 $sslPts

# 7.5 Seadista sisuhaldussüsteemis AD autentimine
$adPts = 0.0; $adDet = "<ul style='margin:0; padding-left:20px;'>"
$ouVeeb = Get-ADOrganizationalUnit -Filter "Name -eq 'Veebihaldurid'" -ErrorAction SilentlyContinue
if ($ouVeeb) { $adPts += 0.25; $adDet += "<li>OU Veebihaldurid: <b style='color:green'>Leitud asukohast: $(Convert-DNToReadable $ouVeeb.DistinguishedName) (+0.25p)</b></li>" }
else { $adDet += "<li>OU Veebihaldurid: <b style='color:red'>Puudu Active Directoryst!</b></li>" }

$grpToim = Get-ADGroup -Filter "Name -eq 'Toimetajad'" -ErrorAction SilentlyContinue
if ($grpToim) { $adPts += 0.25; $adDet += "<li>Turvagrupp Toimetajad: <b style='color:green'>Leitud kaustast: $(Convert-DNToReadable $grpToim.DistinguishedName) (+0.25p)</b></li>" }
else { $adDet += "<li>Turvagrupp Toimetajad: <b style='color:red'>Puudu!</b></li>" }

$u1 = Get-ADUser -Filter "Name -eq 'Toimetaja1' -or SamAccountName -eq 'Toimetaja1'" -ErrorAction SilentlyContinue
$u2 = Get-ADUser -Filter "Name -eq 'Toimetaja2' -or SamAccountName -eq 'Toimetaja2'" -ErrorAction SilentlyContinue
if ($u1 -and $u2) {
    $adPts += 0.25; $adDet += "<li>Kasutajad: <b style='color:green'>Toimetaja1 ja Toimetaja2 on AD-s loodud (+0.25p)</b></li>"
    $grpMembers = Get-ADGroupMember -Identity "Toimetajad" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SamAccountName
    if ($grpMembers -contains $u1.SamAccountName -and $grpMembers -contains $u2.SamAccountName) {
        $adPts += 0.25; $adDet += "<li>Liikmelisus: <b style='color:green'>Mõlemad kuuluvad gruppi 'Toimetajad' (+0.25p)</b></li>"
    } else { $adDet += "<li>Liikmelisus: <b style='color:red'>Kasutajad unustati gruppi 'Toimetajad' lisamata!</b></li>" }
} else { $adDet += "<li>Kasutajad: <b style='color:red'>Toimetaja1 või Toimetaja2 puudub AD-st!</b></li>" }
$adDet += "</ul>"
Add-Result "Seadista sisuhaldussüsteemis AD autentimine Toimetajad OU-s olevatele kasutajatele" "AD struktuur (OU, Grupp, Kasutajad) loodud" $adDet ($adPts -eq 1.0) 1.0 $adPts

# 7.6 Lisa DNS serverisse CNAME kirjed
$dnsPts = 0.0; $dnsDet = "<ul style='margin:0; padding-left:20px;'>"
$cnamePortaal = Get-DnsServerResourceRecord -ZoneName $ExpectedDomain -Name "siseportaal" -ErrorAction SilentlyContinue
$cnameVeeb = Get-DnsServerResourceRecord -ZoneName $ExpectedDomain -Name "siseveeb" -ErrorAction SilentlyContinue

if ($cnamePortaal) {
    if ($cnamePortaal.RecordType -eq "CNAME") { $dnsPts += 0.5; $dnsDet += "<li>siseportaal: <b style='color:green'>Korrektne CNAME kirje (Viitab -> $($cnamePortaal.RecordData.HostNameAlias)) (+0.5p)</b></li>" }
    else { $dnsDet += "<li>siseportaal: <b style='color:orange'>Leiti VALE tüüpi kirje! On hoopis '$($cnamePortaal.RecordType)' kirje (+0.25p)</b>"; $dnsPts += 0.25 }
} else { $dnsDet += "<li>siseportaal: <b style='color:red'>DNS kirje täiesti puudu!</b></li>" }

if ($cnameVeeb) {
    if ($cnameVeeb.RecordType -eq "CNAME") { $dnsPts += 0.5; $dnsDet += "<li>siseveeb: <b style='color:green'>Korrektne CNAME kirje (Viitab -> $($cnameVeeb.RecordData.HostNameAlias)) (+0.5p)</b></li>" }
    else { $dnsDet += "<li>siseveeb: <b style='color:orange'>Leiti VALE tüüpi kirje! On hoopis '$($cnameVeeb.RecordType)' kirje (+0.25p)</b>"; $dnsPts += 0.25 }
} else { $dnsDet += "<li>siseveeb: <b style='color:red'>DNS kirje täiesti puudu!</b></li>" }
$dnsDet += "</ul>"
Add-Result "Lisa oma DNS serverisse CNAME kirjed, et aadressid siseportaal ja siseveeb lahenduksid" "CNAME kirjed olemas" $dnsDet ($dnsPts -eq 1.0) 1.0 $dnsPts

# --- HTML RAPORTI GENEREERIMINE ---
$Html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'><title>Windows Server Auditi Raport</title>
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
        <strong>Kontrollitud domeen:</strong> $ExpectedDomain<br><strong>Käivitatud masinast:</strong> $ComputerName<br>
        <strong>Õpilane:</strong> $OpilaseNimi - $TaisPilet<br><strong>Aeg:</strong> $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')<br><br>
        <span class='total-points'>KOKKU PUNKTE: $TotalPoints / 20.0</span>
    </div>
    <table>
        <tr><th>Ülesanne (Hindamismudel)</th><th>Oodatud olukord</th><th>Leitud reaalsus (Asukoht / Detailid)</th><th>Staatus</th><th>Punktid</th></tr>
"@

foreach ($row in $Results) {
    $Html += "<tr style='background-color:$($row.Color)'><td>$($row.Ylesanne)</td><td>$($row.Oodatud)</td><td>$($row.Leitud)</td><td><strong>$($row.Staatus)</strong></td><td><strong>$($row.Punktid)</strong></td></tr>"
}
$Html += "</table><div class='details-box'><h3>AD Kasutajate pistelise otsingu detailid (Import CSV)</h3>$UserCheckDetails</div></body></html>"

$Html | Out-File $ReportPath -Encoding UTF8
Write-Host "Kontroll on lõpetatud! Punktid: $TotalPoints / 20.0" -ForegroundColor Yellow

# --- JSON RAPORTI SAATMINE ---
$JsonPayload = @{
    Nimi = "$OpilaseNimi - $TaisPilet"; Pilet = $TaisPilet; Aeg = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); KokkuPunkte = $TotalPoints
    Masin = $ComputerName; Domeen = $ExpectedDomain; Tulemused = $Results; UserCheckDetails = $UserCheckDetails; FailiNimi = "HindamisRaport_${SafeName}_${SafePilet}"
}
$JsonString = $JsonPayload | ConvertTo-Json -Depth 5 -Compress
$JsonString | Out-File $JsonPath -Encoding UTF8

$ServeriURL = "http://192.168.124.64:5001/api/upload"
Write-Host "Saadan andmed dashboardile..." -ForegroundColor Cyan
try {
    $Response = Invoke-RestMethod -Uri $ServeriURL -Method Post -Body $JsonString -ContentType "application/json; charset=utf-8"
    Write-Host "Edukalt üles laetud: $($Response.message)" -ForegroundColor Green
} catch { Write-Host "Viga dashboardile saatmisel: $($_.Exception.Message)" -ForegroundColor Red }

# --- PUHASTUS ---
if (Test-Path $ReportPath) { Remove-Item -Path $ReportPath -Force }
if (Test-Path $JsonPath) { Remove-Item -Path $JsonPath -Force }
Write-Host "Kohalikud failid puhastatud ja hindamine lõpetatud!" -ForegroundColor Green


```
