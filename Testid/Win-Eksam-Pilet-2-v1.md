## täiendatud Windows 2 pilet ##

```powershell

<#
.SYNOPSIS
    Täielik Windows Serveri auditi skript vastavalt 20-punktisele hindamiskriteeriumile (PILET 2 - DFS/FSRM).
    Sisaldab täpsustatud pealkirju (dashboardile) ning lollikindlamat DC2 IP tuvastust.
    Käivitada DC1 serveris Domain Admin õigustes.
#>

$ErrorActionPreference = "SilentlyContinue"

# Moodulite laadimine
Import-Module ActiveDirectory
Import-Module GroupPolicy
Import-Module DhcpServer
Import-Module DnsServer
Import-Module DfsN
Import-Module DfsR
Import-Module FileServerResourceManager

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

# --- ABIFUNKTSIOONID ---
function Add-Result {
    param([string]$Ylesanne, [string]$Oodatud, [string]$Leitud, [bool]$Staatus, [double]$MaxPunktid, [double]$OsalisedPunktid = -1)
    $teenitud = if ($OsalisedPunktid -ge 0) { $OsalisedPunktid } elseif ($Staatus) { $MaxPunktid } else { 0 }
    $Global:TotalPoints += $teenitud
    if ($teenitud -eq $MaxPunktid -and $MaxPunktid -gt 0) { $color = "#c6efce"; $staatusTekst = "OK" }
    elseif ($teenitud -gt 0) { $color = "#fff2cc"; $staatusTekst = "OSALINE" }
    else { $color = "#ffc7ce"; $staatusTekst = "PUUDU/VIGA" }
    $Global:Results += [PSCustomObject]@{ Ylesanne = $Ylesanne; Oodatud = $Oodatud; Leitud = $Leitud; Staatus = $staatusTekst; Punktid = $teenitud; Color = $color }
}

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

function Check-GPOSettings {
    param($GpoName, $ExpectedOUs, $Regexes, $MaxP)
    $Gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
    if (!$Gpo) { return @{ Pts = 0; Status = $false; Det = "GPO '$GpoName' puudub." } }
    $Xml = [xml](Get-GPOReport -Guid $Gpo.Id -ReportType Xml)
    $txt = $Xml.InnerXml
    $actualLinks = @()
    if ($Xml.GPO.LinksTo) {
        $links = $Xml.GPO.LinksTo
        if ($links -is [array]) { foreach ($l in $links) { $actualLinks += $l.SOMName } } else { $actualLinks += $links.SOMName }
    }
    $linksStr = if ($actualLinks.Count -gt 0) { $actualLinks -join ", " } else { "Lingid puuduvad" }
    $linksOk = $true
    foreach ($ou in $ExpectedOUs) {
        if ($ou -and $actualLinks -notcontains $ou -and ($Xml.GPO.LinksTo.SOMPath -join " ") -notmatch $ou) { $linksOk = $false }
    }
    $setMet = 0
    foreach ($r in $Regexes) { if ($txt -match $r) { $setMet++ } }
    if ($linksOk) {
        if ($setMet -eq $Regexes.Count) { return @{ Pts = $MaxP; Status = $true; Det = "Kõik seaded korras. Lingitud: $linksStr." } }
        elseif ($setMet -gt 0) { return @{ Pts = ($MaxP * 0.75); Status = $false; Det = "Link õige ($linksStr), osad seaded olemas." } }
        else { return @{ Pts = ($MaxP * 0.25); Status = $false; Det = "Link õige ($linksStr), seaded puudu." } }
    } else {
        if ($setMet -eq $Regexes.Count) { return @{ Pts = ($MaxP * 0.75); Status = $false; Det = "Seaded õiged, aga VALE ASUKOHT! Lingitud: $linksStr" } }
        elseif ($setMet -gt 0) { return @{ Pts = ($MaxP * 0.5); Status = $false; Det = "Osaliselt õige, VALE ASUKOHT: $linksStr" } }
        else { return @{ Pts = 0; Status = $false; Det = "Seaded puudu, vale asukoht." } }
    }
}


# ====================================================================
# PÕHIOSA (12 punkti kokku)
# ====================================================================
$ComputerName = $env:COMPUTERNAME
Add-Result "Muuta WinServer2025 masin nimi DC1" "Masina nimi on DC1" "Tuvastatud: $ComputerName" ($ComputerName -eq "DC1") 0.5

$DC1IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq "Manual" -and $_.InterfaceAlias -notmatch "Loopback" }).IPAddress
Add-Result "Anna DC1 serverile staatiline IP-aadress" "Manuaalne IPv4 seadistus" ("IP: " + ($DC1IP -join ", ")) ($DC1IP.Count -gt 0) 0.5

$Domain = Get-ADDomain
Add-Result "Seadista DC1 serverile Active Directory domeeni teenused domeeni $ExpectedDomain tarvis" "Domeen $ExpectedDomain" "Tuvastatud: $($Domain.DNSRoot)" ($Domain.DNSRoot -eq $ExpectedDomain) 1.0

$DNSRole = Get-WindowsFeature DNS
Add-Result "Seadista DC1 serverile DNS teenus" "DNS roll paigaldatud" "Roll: $($DNSRole.InstallState)" ($DNSRole.Installed) 0.5

# Parem DC2 tuvastus otse AD-st, kaasates ka IP-aadressi
$DC2 = Get-ADComputer -Filter "Name -eq 'DC2'" -Properties IPv4Address -ErrorAction SilentlyContinue
Add-Result "WinCore2025 masinal muuta nimi DC2-ks" "AD-s eksisteerib arvuti DC2" (if($DC2){"Leitud DC2 konto AD-st"}else{"Ei leitud arvutit DC2"}) ($DC2 -ne $null) 0.5

$dc2IpDet = "Ei tuvastatud staatilist IP-d"
$dc2IpStatus = $false
$ip = $null

if ($DC2 -and $DC2.IPv4Address) {
    $ip = $DC2.IPv4Address
} else {
    $DC2DNS = Resolve-DnsName -Name "DC2" -Type A -ErrorAction SilentlyContinue
    if ($DC2DNS) { $ip = $DC2DNS.IPAddress[0] }
}

if ($ip) {
    $lastOctet = [int]($ip -split '\.')[-1]
    if ($lastOctet -lt 100) {
        $dc2IpDet = "Leitud IP: <b>$ip</b> <span style='color:green'>(Tundub staatiline, < .100)</span>"
        $dc2IpStatus = $true
    } else {
        $dc2IpDet = "Leitud IP: <b>$ip</b> <span style='color:orange'>(HOIATUS: Dünaamiline? > .100)</span>"
        $dc2IpStatus = $true 
    }
}
Add-Result "WinCore2025 serverile anda staatiline IP-aadress" "Tuvastatud DC2 IP-aadress" $dc2IpDet $dc2IpStatus 0.5

$DomainDN = $Domain.DistinguishedName
$DCsInOU = Get-ADComputer -Filter * -SearchBase "OU=Domain Controllers,$DomainDN" -ErrorAction SilentlyContinue
$HasTwoDCs = ($DCsInOU.Count -ge 2) -and ($DCsInOU.Name -contains "DC2")
Add-Result "Lisada WinCore2025 server teiseks domeenikontrolleriks domeeni $ExpectedDomain jaoks" "Vähemalt 2 masinat (sh DC2) Domain Controllers OU-s" ("Masinad DC OU-s: " + ($DCsInOU.Name -join ", ")) $HasTwoDCs 1.0


# DHCP
$DHCPScope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Select-Object -First 1
$dhcpTasksMet = 0
$dhcpDetails = "<ul style='margin:0; padding-left:20px;'>"

if ($DHCPScope) {
    $dhcpTasksMet++; $dhcpDetails += "<li>Skoop: <b style='color:green'>Jah (+0.25p) [$($DHCPScope.Name)]</b></li>"
    if ($DHCPScope.LeaseDuration.TotalHours -eq 4) { $dhcpTasksMet++; $dhcpDetails += "<li>Rendiaeg 4h: <b style='color:green'>OK (+0.25p)</b></li>" } 
    else { $dhcpDetails += "<li>Rendiaeg: <b style='color:red'>Vale ($($DHCPScope.LeaseDuration))</b></li>" }
    
    $Reservations = @(Get-DhcpServerv4Reservation -ScopeId $DHCPScope.ScopeId -ErrorAction SilentlyContinue)
    if ($Reservations.Count -gt 0) {
        $dhcpTasksMet++; $dhcpDetails += "<li>Reservatsioonid: <b style='color:green'>OK (+0.25p) [$($Reservations.Count) tk]</b></li>"
    } else { $dhcpDetails += "<li>Reservatsioonid: <b style='color:red'>Puudu</b></li>" }
    
    $DNSOptions = Get-DhcpServerv4OptionValue -ScopeId $DHCPScope.ScopeId -OptionId 6 -ErrorAction SilentlyContinue
    if ($DNSOptions -and $DNSOptions.Value.Count -ge 2) { $dhcpTasksMet++; $dhcpDetails += "<li>DNS serverid (min 2): <b style='color:green'>OK (+0.25p)</b></li>" } 
    else { $dhcpDetails += "<li>DNS serverid: <b style='color:red'>Puudu / < 2</b></li>" }
} else { $dhcpDetails += "<li>Skoop: <b style='color:red'>Puudu</b></li>" }
$dhcpDetails += "</ul>"
Add-Result "Seadista WinServer2025 peal DHCP teenus, kus klientidele antakse reservereritud IP-aadressid. DHCP server jagab DNS serveritena välja mõlemad AD serverid" "Skoop, 4h, reserv, 2xDNS" $dhcpDetails ($dhcpTasksMet -eq 4) 1.0 ($dhcpTasksMet * 0.25)

$Failover = Get-DhcpServerv4Failover -ErrorAction SilentlyContinue
$foStatus = $false; $foDetails = "Failover puudub"
if ($Failover) {
    $partner = $Failover.PartnerServer -join " "
    if ($partner -match "DC2" -or ($ip -ne $null -and $partner -match $ip)) {
        $foStatus = $true; $foDetails = "Failover korras. Partner: <b>$partner</b>"
    } else { $foDetails = "Tuvastatud vale partner: $partner" }
}
Add-Result "Seadista DHCP teenusele failover, kus failover partneriks on DC2 server" "Partneriks on DC2" $foDetails $foStatus 1.0


# AD STRUKTUUR JA HALDUR
$OUUsers = Get-ADOrganizationalUnit -Filter "Name -eq 'Kasutajad'"
$OUComps = Get-ADOrganizationalUnit -Filter "Name -eq 'Arvutid'"
Add-Result "AD-sse on loodud 2 OU-d: Kasutajad ja Arvutid." "Mõlemad loodud" (if($OUUsers -and $OUComps){"Mõlemad leitud"}else{"Puudu/Osaline"}) ($OUUsers -and $OUComps) 0.5

$Haldur = Get-ADUser -Filter "Name -eq 'Haldur' -or SamAccountName -eq 'haldur'" -Properties DistinguishedName -ErrorAction SilentlyContinue
$haldurTasksMet = 0; $haldurDetails = "<ul style='margin:0; padding-left:20px;'>"
if ($Haldur) {
    if ($Haldur.DistinguishedName -match "OU=Kasutajad") { $haldurTasksMet++; $haldurDetails += "<li>Asukoht Kasutajad: <b style='color:green'>OK (+0.25p)</b></li>" } 
    else { $haldurDetails += "<li>Asukoht: <b style='color:red'>VALE! ($(Convert-DNToReadable $Haldur.DistinguishedName))</b></li>" }
    
    $HaldurGroups = Get-ADPrincipalGroupMembership -Identity $Haldur -ErrorAction SilentlyContinue
    if ($HaldurGroups.Name -match "Domain Admins|Domeeni administraatorid") { $haldurTasksMet++; $haldurDetails += "<li>Domain Admins: <b style='color:green'>OK (+0.25p)</b></li>" } 
    else { $haldurDetails += "<li>Domain Admins: <b style='color:red'>Puudu</b></li>" }
} else { $haldurDetails += "<li>Kasutaja 'haldur': <b style='color:red'>Puudu AD-st</b></li>" }
$haldurDetails += "</ul>"
Add-Result "Domeeni on lisatud kasutaja haldur, kes on lisatud Domain Admins gruppi" "OU=Kasutajad ja Domain Admins" $haldurDetails ($haldurTasksMet -eq 2) 0.5 ($haldurTasksMet * 0.25)

# KLIENTMASIN
$AllComps = Get-ADComputer -Filter {Name -notlike "DC1" -and Name -notlike "DC2"} -Properties DistinguishedName -ErrorAction SilentlyContinue
$compTasksMet = 0; $compDetails = "<ul style='margin:0; padding-left:20px;'>"
if ($AllComps) {
    $compTasksMet = 1 
    $inArvutid = $AllComps | Where-Object { $_.DistinguishedName -match "OU=Arvutid" }
    if ($inArvutid) {
        $compTasksMet = 2
        $compDetails += "<li>Klientmasin '$($inArvutid[0].Name)': <b style='color:green'>Leitud domeenist (+0.25p)</b></li>"
        $compDetails += "<li>Asukoht OU=Arvutid: <b style='color:green'>OK (+0.25p)</b></li>"
    } else {
        $compDetails += "<li>Klientmasin '$($AllComps[0].Name)': <b style='color:green'>Leitud domeenist (+0.25p)</b></li>"
        $compDetails += "<li>Asukoht: <b style='color:red'>VALE OU! ($(Convert-DNToReadable $AllComps[0].DistinguishedName))</b></li>"
    }
} else { $compDetails += "<li>Klientmasin: <b style='color:red'>Puudub domeenist</b></li>" }
$compDetails += "</ul>"
Add-Result "Windows 11 klientmasin on lisatud domeeni ja pandud OU-sse Arvutid" "Domeenis ja OU-s Arvutid" $compDetails ($compTasksMet -eq 2) 0.5 ($compTasksMet * 0.25)


# DNS KIRJED JA CSV IMPORT
$DnsRecords = Get-DnsServerResourceRecord -ZoneName $ExpectedDomain -RRType A | Where-Object {$_.HostName -notmatch "@|gc|DomainDnsZones|ForestDnsZones|DC1|DC2"}
Add-Result "DNS serveris on tehtud A-kirjed kõikide Linux serverite jaoks" "Vähemalt 1 manuaalne A-kirje" "$($DnsRecords.Count) tk leitud" ($DnsRecords.Count -gt 0) 1.0

$TestUsers = @{"Müük"="Aivo Teder"; "Personal"="Andres Karl Kukk"; "Raamatupidamine"="Anette Kuusk"; "Toimetajad"="Anneli Koppel"; "IT"="Anneli Roos"; "Juhtkond"="Annika Rand"; "Haldus"="Erki Niit"}
$UsersFoundCount = 0; $UserCheckDetails = "<ul style='margin:0; padding-left:20px;'>"
foreach ($Dept in $TestUsers.Keys) {
    $ExpectedUser = $TestUsers[$Dept]; $FoundUser = Get-ADUser -Filter "Name -eq '$ExpectedUser'" -Properties DistinguishedName -ErrorAction SilentlyContinue
    if ($FoundUser) {
        if ($FoundUser.DistinguishedName -match "OU=$Dept") { $UsersFoundCount++; $UserCheckDetails += "<li><b>$ExpectedUser</b> (OU=$Dept) - <span style='color:green'>OK</span></li>" } 
        else { $UserCheckDetails += "<li><b>$ExpectedUser</b> - <span style='color:orange'>VALE OU! ($(Convert-DNToReadable $FoundUser.DistinguishedName))</span></li>" }
    } else { $UserCheckDetails += "<li><b>$ExpectedUser</b> - <span style='color:red'>PUUDUB</span></li>" }
}
$UserCheckDetails += "</ul>"
Add-Result "Loodud on Powershelli skript, mis impordib AD kasutajad koos OU struktuuriga failist kasutajad.csv" "Kasutajad ja struktuur leitud" "$UsersFoundCount / 7 testkasutajat OK" ($UsersFoundCount -gt 0) 1.0


# GPO ALGSED KONTROLLID
$resLock = Check-GPOSettings "GPO_KontodeLukustamine" @() @("LockoutBadCount", ">5<", "LockoutDuration", ">15<") 1.0
Add-Result "Grupipoliitika (GPO): Loo GPO nimega GPO_KontodeLukustamine, mis lukustab kasutajakonto 15 minutiks, kui parooli on 5 korda järjest valesti sisestatud. Poliitika peab rakenduma kogu domeenile." "Domeenile rakendatud, 5 katset, 15 min" $resLock.Det $resLock.Status 1.0 $resLock.Pts

$resEdge = Check-GPOSettings "Edge_Siseportaal" @("Personal") @("siseportaal", "NewTabPageLocation") 1.0
Add-Result "Grupipoliitika (GPO): Loo GPO nimega Edge_Siseportaal, mis määrab OU-sse Personal kuuluvate kasutajate Microsoft Edge brauseri vaikimisi avaleheks (Homepage) ja uue vahekaardi leheks (New Tab Page) siseportaali aadressi [https://siseportaal.$ExpectedDomain](https://siseportaal.$ExpectedDomain). Kasutajatel peab olema avalehe muutmine veebilehitseja seadetest blokeeritud." "Avaleht siseportaal, uue tab'i URL, lukustatud" $resEdge.Det $resEdge.Status 1.0 $resEdge.Pts


# ====================================================================
# 7. DFS JA FAILISERVERI SEADISTUSED (LISAOSA - Kokku 8.0 punkti)
# ====================================================================
$DomainFQDN = (Get-ADDomain).DNSRoot

# 7.1 Rollide kontroll
$RolePts = 0; $RoleDetails = "<ul style='margin:0; padding-left:20px;'>"
$Roles = @("FS-DFS-Namespace", "FS-DFS-Replication", "FS-Resource-Manager")
foreach ($Role in $Roles) {
    if ((Get-WindowsFeature $Role -ErrorAction SilentlyContinue).Installed) {
        $RolePts += 0.5; $RoleDetails += "<li>${Role}: <b style='color:green'>OK (+0.5p)</b></li>"
    } else { $RoleDetails += "<li>${Role}: <b style='color:red'>Puudu</b></li>" }
}
$RoleDetails += "</ul>"
Add-Result "Paigalda Windows Server 2025-le rollid DFS Namespaces, DFS Replication ja File Server Resource Manager" "Kõik 3 rolli paigaldatud" $RoleDetails ($RolePts -eq 1.5) 1.5 $RolePts

# 7.2 DFS nimeruum Jagatud
$DfsN = Get-DfsnRoot -Path "\\$DomainFQDN\Jagatud" -ErrorAction SilentlyContinue
$DfsnDet = if($DfsN){"Nimeruum leitud: <b style='color:green'>Jah (+1p)</b>"}else{"Nimeruum leitud: <b style='color:red'>Ei leitud</b>"}
Add-Result "Loo DFS nimeruum Jagatud" "Nimeruum \\$DomainFQDN\Jagatud" $DfsnDet ($DfsN -ne $null) 1.0

# 7.3 Nimeruumi kaust Kogukond
$KogukondFolder = Get-DfsnFolder -Path "\\$DomainFQDN\Jagatud\Kogukond" -ErrorAction SilentlyContinue
$KFolderDet = if($KogukondFolder){"Kaust leitud nimeruumis: <b style='color:green'>Jah (+0.5p)</b>"}else{"Kaust leitud: <b style='color:red'>Ei</b>"}
Add-Result "Loo nimeruumi Jagatud kaust Kogukond" "Kaust nimeruumis olemas" $KFolderDet ($KogukondFolder -ne $null) 0.5

# 7.4 Replikatsiooni grupp Kogukond
$RepGroupKogukond = Get-DfsrReplicationGroup -ErrorAction SilentlyContinue | Where-Object Name -match "Kogukond"
$RepKogukondDet = if($RepGroupKogukond){"Grupp leitud: <b style='color:green'>Jah (+0.5p)</b>"}else{"Grupp leitud: <b style='color:red'>Ei</b>"}
Add-Result "Loo kaustale replikatsiooni grupp, et kaustast oleks koopia ka teises (DC2) serveris" "Replikatsioonigrupp Kogukond leitud" $RepKogukondDet ($RepGroupKogukond -ne $null) 0.5

# 7.5 GPO Kogukond (PAINDLIK KETTATÄHE OTSIJA)
$GpoK = Get-GPO -Name "Kogukond" -ErrorAction SilentlyContinue
$GpoKPts = 0; $GpoKDet = "<ul style='margin:0; padding-left:20px;'>"
if ($GpoK) {
    $GpoKPts += 0.25; $GpoKDet += "<li>GPO loodud: <b style='color:green'>Jah (+0.25p)</b></li>"
    $GpoKXml = [xml](Get-GPOReport -Name "Kogukond" -ReportType Xml)
    if ($GpoKXml.GPO.LinksTo) { $GpoKPts += 0.25; $GpoKDet += "<li>GPO lingitud: <b style='color:green'>Jah (+0.25p)</b></li>" } 
    else { $GpoKDet += "<li>GPO lingitud: <b style='color:red'>Ei (Kuhu see rakendub?)</b></li>" }

    $xmlString = $GpoKXml.InnerXml
    if ($xmlString -match 'letter="([A-Za-z]):"' -or $xmlString -match 'Drive Letter="([A-Za-z]):"') {
        $foundLetter = $Matches[1].ToUpper()
        $GpoKPts += 0.5
        if ($foundLetter -eq 'Y') {
            $GpoKDet += "<li>Ketas ühendatud: <b style='color:green'>Täht Y: (+0.5p)</b></li>"
        } else {
            $GpoKDet += "<li>Ketas ühendatud: <b style='color:orange'>Täht $foundLetter: (Oodati Y:) (+0.5p)</b></li>"
        }
    } else {
        $GpoKDet += "<li>Ketas ühendatud: <b style='color:red'>GPO-s pole Drive Map seadistust tehtud!</b></li>"
    }

    if ($xmlString -match 'path="([^"]+)"' -or $xmlString -match 'Path="([^"]+)"') {
        $GpoKDet += "<li><i>Jagatud sihtkoht: <b>$($Matches[1])</b></i></li>"
    }
} else { $GpoKDet += "<li>GPO 'Kogukond': <b style='color:red'>Puudu</b></li>" }
$GpoKDet += "</ul>"
Add-Result "Loo GPO nimega Kogukond, millega kaust jagataks välja kõigile domeeni kasutajatele ligipääsetava võrgukettana Y: kõikidele sinu domeeni kasutajatele" "Ketas jagatud GPO abil" $GpoKDet ($GpoKPts -eq 1.0) 1.0 $GpoKPts

# 7.6 FSRM Kogukond 10GB
$KogukondQuota = Get-FsrmQuota -ErrorAction SilentlyContinue | Where-Object { $_.Path -match "Kogukond" }
$KQPts = 0; $KQDet = "<ul style='margin:0; padding-left:20px;'>"
if ($KogukondQuota) {
    $KQPts += 0.25; $KQDet += "<li>Kvoot loodud: <b style='color:green'>Jah (+0.25p)</b></li>"
    if ($KogukondQuota.Size -eq 10GB) { $KQPts += 0.25; $KQDet += "<li>Suurus 10GB: <b style='color:green'>Jah (+0.25p)</b></li>" } 
    else { $KQDet += "<li>Suurus: <b style='color:red'>Vale ($($KogukondQuota.Size))</b></li>" }
} else { $KQDet += "<li>Kvoot: <b style='color:red'>Puudu</b></li>" }
$KQDet += "</ul>"
Add-Result "Määra kaustale FSRM abil mahupiirang 10 GB" "10GB kvoot rakendatud" $KQDet ($KQPts -eq 0.5) 0.5 $KQPts

# 7.7 FSRM Failipiirang
$FileScreen = Get-FsrmFileScreen -ErrorAction SilentlyContinue | Where-Object { $_.Path -match "Kogukond" }
$FSPts = 0; $FSDet = "<ul style='margin:0; padding-left:20px;'>"
if ($FileScreen) {
    $FSPts += 0.25; $FSDet += "<li>Failipiirang: <b style='color:green'>Olemas (+0.25p)</b></li>"
    $FSGroup = Get-FsrmFileGroup -Name $FileScreen.FileGroup -ErrorAction SilentlyContinue
    if ($FSGroup -and ($FSGroup.IncludePattern -match "\.exe" -or $FSGroup.IncludePattern -match "\.msi" -or $FSGroup.IncludePattern -match "\.bat")) {
        $FSPts += 0.25; $FSDet += "<li>Keelab skriptid/programmid: <b style='color:green'>Jah (+0.25p)</b></li>"
    } else { $FSDet += "<li>Filtrid: <b style='color:red'>Ei tuvastanud exe/msi filtreid</b></li>" }
} else { $FSDet += "<li>Failipiirang: <b style='color:red'>Puudu</b></li>" }
$FSDet += "</ul>"
Add-Result "Sellele ressursile luua piirang, mis takistab programmifailide kopeerimist sinna (.msi, .exe, .bat, .ps1)" "Failipiirang aktiivne" $FSDet ($FSPts -eq 0.5) 0.5 $FSPts

# 7.8 Nimeruumi kaust Isiklik
$IsiklikFolder = Get-DfsnFolder -Path "\\$DomainFQDN\Jagatud\Isiklik" -ErrorAction SilentlyContinue
$IFolderDet = if($IsiklikFolder){"Kaust leitud nimeruumis: <b style='color:green'>Jah (+0.5p)</b>"}else{"Kaust leitud: <b style='color:red'>Ei</b>"}
Add-Result "Loo nimeruumi Jagatud kaust Isiklik" "Kaust nimeruumis olemas" $IFolderDet ($IsiklikFolder -ne $null) 0.5

# 7.9 Replikatsiooni grupp Isiklik
$RepGroupIsiklik = Get-DfsrReplicationGroup -ErrorAction SilentlyContinue | Where-Object Name -match "Isiklik"
$RepIsiklikDet = if($RepGroupIsiklik){"Grupp leitud: <b style='color:green'>Jah (+0.5p)</b>"}else{"Grupp leitud: <b style='color:red'>Ei</b>"}
Add-Result "Loo kaustale replikatsiooni grupp, et kaustast oleks koopia ka teises serveris (DC2)" "Replikatsioonigrupp leitud" $RepIsiklikDet ($RepGroupIsiklik -ne $null) 0.5

# 7.10 GPO Isiklik (PAINDLIK KETTATÄHE OTSIJA)
$GpoI = Get-GPO -Name "Isiklik" -ErrorAction SilentlyContinue
$GpoIPts = 0; $GpoIDet = "<ul style='margin:0; padding-left:20px;'>"
if ($GpoI) {
    $GpoIPts += 0.25; $GpoIDet += "<li>GPO loodud: <b style='color:green'>Jah (+0.25p)</b></li>"
    $GpoIXml = [xml](Get-GPOReport -Name "Isiklik" -ReportType Xml)
    if ($GpoIXml.GPO.LinksTo) { $GpoIPts += 0.25; $GpoIDet += "<li>GPO lingitud: <b style='color:green'>Jah (+0.25p)</b></li>" } 
    else { $GpoIDet += "<li>GPO lingitud: <b style='color:red'>Ei</b></li>" }

    $xmlString = $GpoIXml.InnerXml
    if ($xmlString -match 'letter="([A-Za-z]):"' -or $xmlString -match 'Drive Letter="([A-Za-z]):"') {
        $foundLetter = $Matches[1].ToUpper()
        $GpoIPts += 0.5
        if ($foundLetter -eq 'Z') {
            $GpoIDet += "<li>Ketas ühendatud: <b style='color:green'>Täht Z: (+0.5p)</b></li>"
        } else {
            $GpoIDet += "<li>Ketas ühendatud: <b style='color:orange'>Täht $foundLetter: (Oodati Z:) (+0.5p)</b></li>"
        }
    } else {
        $GpoIDet += "<li>Ketas ühendatud: <b style='color:red'>GPO-s pole Drive Map seadistust!</b></li>"
    }
    
    if ($xmlString -match 'path="([^"]+)"' -or $xmlString -match 'Path="([^"]+)"') {
        $GpoIDet += "<li><i>Jagatud sihtkoht: <b>$($Matches[1])</b></i></li>"
    }
} else { $GpoIDet += "<li>GPO 'Isiklik': <b style='color:red'>Puudu</b></li>" }
$GpoIDet += "</ul>"
Add-Result "Loo GPO nimega Isiklik, millega tehakse kausta sisse domeeni kasutaja nimega kaust ja jagatakse ainult see kaust kasutajale välja võrgukettana Z:" "Ketas seadistatud GPO abil" $GpoIDet ($GpoIPts -eq 1.0) 1.0 $GpoIPts

# 7.11 FSRM Isiklik 1GB (Auto Quota)
$AutoQuota = Get-FsrmAutoQuota -ErrorAction SilentlyContinue | Where-Object { $_.Path -match "Isiklik" }
$AQPts = 0; $AQDet = "<ul style='margin:0; padding-left:20px;'>"
if ($AutoQuota) {
    $AQPts += 0.25; $AQDet += "<li>Auto-quota loodud: <b style='color:green'>Jah (+0.25p)</b></li>"
    $Template = Get-FsrmQuotaTemplate -Name $AutoQuota.Template -ErrorAction SilentlyContinue
    if ($Template -and $Template.Size -eq 1GB) { $AQPts += 0.25; $AQDet += "<li>Suurus 1GB: <b style='color:green'>Jah (+0.25p)</b></li>" } 
    else { $AQDet += "<li>Suurus: <b style='color:red'>Vale või malli ei tuvastatud</b></li>" }
} else { $AQDet += "<li>Auto-quota: <b style='color:red'>Puudu</b></li>" }
$AQDet += "</ul>"
Add-Result "Määra kaustadele FSRM abil mahupiirang 1GB kasutaja kohta" "Auto-quota rakendatud" $AQDet ($AQPts -eq 0.5) 0.5 $AQPts


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
        <strong>Kontrollitud domeen:</strong> $ExpectedDomain<br>
        <strong>Käivitatud masinast:</strong> $ComputerName<br>
        <strong>Õpilane:</strong> $OpilaseNimi - $TaisPilet<br>
        <strong>Aeg:</strong> $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')<br><br>
        <span class='total-points'>KOKKU PUNKTE: $TotalPoints / 20.0</span>
    </div>
    <table>
        <tr><th>Ülesanne (Hindamismudel)</th><th>Oodatud</th><th>Leitud reaalsus</th><th>Staatus</th><th>Punktid</th></tr>
"@

foreach ($row in $Results) {
    $Html += "<tr style='background-color:$($row.Color)'><td>$($row.Ylesanne)</td><td>$($row.Oodatud)</td><td>$($row.Leitud)</td><td><strong>$($row.Staatus)</strong></td><td><strong>$($row.Punktid)</strong></td></tr>"
}
$Html += "</table><div class='details-box'><h3>AD Kasutajate pistelise otsingu detailid</h3>$UserCheckDetails</div></body></html>"

$Html | Out-File $ReportPath -Encoding UTF8
Write-Host "Kontroll on lõpetatud! Kogutud punktid: $TotalPoints / 20.0" -ForegroundColor Yellow


# --- JSON GENEREERIMINE JA ÜLESLAADIMINE ---
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
    Write-Host "Andmed edukalt üles laetud! ($($Response.message))" -ForegroundColor Green
} catch { Write-Host "Viga andmete üleslaadimisel: $($_.Exception.Message)" -ForegroundColor Red }

if (Test-Path $ReportPath) { Remove-Item -Path $ReportPath -Force }
if (Test-Path $JsonPath) { Remove-Item -Path $JsonPath -Force }
Write-Host "Kohalikud failid puhastatud." -ForegroundColor Green
```
