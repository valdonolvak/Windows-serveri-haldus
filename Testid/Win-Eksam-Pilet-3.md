## Windows Pilet 3 ##


```powershell
<#
.SYNOPSIS
    Täielik Windows Serveri auditi skript vastavalt 20-punktisele hindamiskriteeriumile.
    Sisaldab nutikat Folder Redirection (Pilvekaustad) hindamist ja fuzzy otsingut.
    Käivitada DC1 serveris Domain Admin õigustes.
#>

$ErrorActionPreference = "SilentlyContinue"

# Moodulite laadimine
Import-Module ActiveDirectory
Import-Module GroupPolicy
Import-Module DhcpServer
Import-Module DnsServer
Import-Module SmbShare

# --- SEADISTUSED JA SISEND ---
$ExpectedDomain = Read-Host "Sisesta oodatud domeeninimi (nt oige.ee või sinunimi.local)"
$OpilaseNimi = Read-Host "Sisesta õpilase ees- ja perekonnanimi (dashboardile saatmiseks ja failinimeks)"

Write-Host "Vali pileti liik:" -ForegroundColor Cyan
Write-Host "1 - Linux"
Write-Host "2 - Windows"
Write-Host "3 - Võrk"
$PiletLiikValik = Read-Host "Sisesta number (1-3)"
$PiletLiik = switch ($PiletLiikValik) {
    '1' { 'Linux' }
    '2' { 'Windows' }
    '3' { 'Võrk' }
    Default { 'Määramata' }
}

$PiletNumber = Read-Host "Sisesta pileti number (1-6)"
$TaisPilet = "$PiletLiik $PiletNumber"

# --- FAILINIMEDE GENEREERIMINE ---
$SafeName = $OpilaseNimi -replace '\s+', '_'
$SafePilet = $TaisPilet -replace '\s+', '_'

$ReportPath = "$PSScriptRoot\HindamisRaport_${SafeName}_${SafePilet}.html"
$JsonPath = "$PSScriptRoot\HindamisRaport_${SafeName}_${SafePilet}.json"

$TotalPoints = 0
$Results = @()

# --- FUNKTSIOON TULEMUSTE LISAMISEKS ---
function Add-Result {
    param(
        [string]$Ylesanne,
        [string]$Oodatud,
        [string]$Leitud,
        [bool]$Staatus,
        [double]$MaxPunktid,
        [double]$OsalisedPunktid = -1
    )
    
    $teenitud = if ($OsalisedPunktid -ge 0) { $OsalisedPunktid } elseif ($Staatus) { $MaxPunktid } else { 0 }
    $Global:TotalPoints += $teenitud
    
    if ($teenitud -eq $MaxPunktid -and $MaxPunktid -gt 0) {
        $color = "#c6efce"; $staatusTekst = "OK"
    } elseif ($teenitud -gt 0) {
        $color = "#fff2cc"; $staatusTekst = "OSALINE"
    } else {
        $color = "#ffc7ce"; $staatusTekst = "PUUDU/VIGA"
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

# --- FUNKTSIOON: GPO 25% / 75% / 100% HINDAMINE ---
function Check-GPOSettings {
    param($GpoName, $ExpectedOUs, $Regexes, $MaxP)
    $Gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
    if (!$Gpo) { return @{ Pts = 0; Status = $false; Det = "GPO puudub" } }

    $Xml = [xml](Get-GPOReport -Guid $Gpo.Id -ReportType Xml)
    $txt = $Xml.InnerXml

    $linkText = if ($Xml.GPO.LinksTo) { $Xml.GPO.LinksTo.SOMPath -join " " } else { "" }
    $linksOk = $true
    foreach ($ou in $ExpectedOUs) {
        if ($ou -and $linkText -notmatch $ou) { $linksOk = $false }
    }

    $setMet = 0
    foreach ($r in $Regexes) { if ($txt -match $r) { $setMet++ } }

    if ($linksOk) {
        if ($setMet -eq $Regexes.Count) {
            return @{ Pts = $MaxP; Status = $true; Det = "Nimi ja OU õige (+25%), kõik seaded korras (+75%)" }
        } elseif ($setMet -gt 0) {
            return @{ Pts = ($MaxP * 0.75); Status = $false; Det = "Nimi/OU õige (+25%), osad seaded olemas (+50%)" }
        } else {
            return @{ Pts = ($MaxP * 0.25); Status = $false; Det = "Nimi/OU õige (+25%), aga seaded seest puudu!" }
        }
    } else {
        if ($setMet -eq $Regexes.Count) {
            return @{ Pts = ($MaxP * 0.75); Status = $false; Det = "Seaded korras, aga OU link puudu/vale (+75%)" }
        } elseif ($setMet -gt 0) {
            return @{ Pts = ($MaxP * 0.5); Status = $false; Det = "Osad seaded olemas, OU link vale (+50%)" }
        } else {
            return @{ Pts = 0; Status = $false; Det = "Seaded puudu ja OU link vale" }
        }
    }
}


# ====================================================================
# 1. SERVERITE NIMED JA IP-D (2.0 punkti)
# ====================================================================
$ComputerName = $env:COMPUTERNAME
$dc1NameStatus = ($ComputerName -eq "DC1")
Add-Result "Muuta WinServer2025 masin nimi DC1" "Masina nimi on DC1" $ComputerName $dc1NameStatus 0.5

$DC1IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq "Manual" -and $_.InterfaceAlias -notmatch "Loopback" }).IPAddress
$dc1IpStatus = ($DC1IP.Count -gt 0)
Add-Result "Anna DC1 serverile staatiline IP-aadress" "Manuaalne IPv4 seadistus" ($DC1IP -join ", ") $dc1IpStatus 0.5

$DC2 = Get-ADComputer -Filter "Name -eq 'DC2'" -ErrorAction SilentlyContinue
$dc2Status = [bool]($DC2)
$dc2LeitudText = if($DC2){"Leitud DC2"}else{"Ei leitud"}
Add-Result "WinCore2025 masinal muuta nimi DC2-ks" "AD-s eksisteerib arvuti DC2" $dc2LeitudText $dc2Status 0.5

$DC2DNS = Resolve-DnsName -Name "DC2" -Type A -ErrorAction SilentlyContinue
$dc2IpDet = "Ei tuvastatud IP-d"
$dc2IpStatus = $false
if ($DC2DNS) {
    $ip = $DC2DNS.IPAddress[0]
    $dc2IpDet = "IP: $ip"
    $dc2IpStatus = $true
}
Add-Result "WinCore2025 serverile anda staatiline IP-aadress" "DNS kirje viitab DC2 IP-le" $dc2IpDet $dc2IpStatus 0.5


# ====================================================================
# 2. AD DS JA DNS TEENUSED (2.5 punkti)
# ====================================================================
$Domain = Get-ADDomain
$adStatus = ($Domain.DNSRoot -eq $ExpectedDomain)
Add-Result "Seadista DC1 serverile Acitve Directory domeeni teenused domeeni $ExpectedDomain tarvis" "Domeen $ExpectedDomain" $($Domain.DNSRoot) $adStatus 1.0

$DNSRole = Get-WindowsFeature DNS -ErrorAction SilentlyContinue
$dnsStatus = [bool]($DNSRole.Installed)
Add-Result "Seadista DC1 serverile DNS teenus" "DNS roll paigaldatud" $($DNSRole.InstallState) $dnsStatus 0.5

$DomainControllers = Get-ADDomainController -Filter * -ErrorAction SilentlyContinue
$HasTwoDCs = ($DomainControllers.Count -ge 2) -and ($DomainControllers.Name -contains "DC2")
$hasTwoDCsStatus = [bool]($HasTwoDCs)
Add-Result "Lisada WinCore2025 server teiseks domeenikontrolleriks domeeni $ExpectedDomain jaoks" "Vähemalt 2 DC-d (sh DC2)" ($DomainControllers.Name -join ", ") $hasTwoDCsStatus 1.0


# ====================================================================
# 3. DHCP TEENUS JA FAILOVER (2.0 punkti)
# ====================================================================
$DHCPScope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Select-Object -First 1
$dhcpTasksMet = 0
$dhcpDetails = "<ul style='margin:0; padding-left:20px;'>"

if ($DHCPScope) {
    $dhcpTasksMet++
    $dhcpDetails += "<li>Skoop leitud: <b style='color:green'>Jah (+0.25p)</b></li>"

    if ($DHCPScope.LeaseDuration.TotalHours -eq 4) {
        $dhcpTasksMet++
        $dhcpDetails += "<li>Rendiaeg 4h: <b style='color:green'>Täidetud (+0.25p)</b></li>"
    } else {
        $dhcpDetails += "<li>Rendiaeg 4h: <b style='color:red'>Vale ($($DHCPScope.LeaseDuration))</b></li>"
    }
    
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
        $dhcpDetails += "<li>DNS serverid (min 2 tk): <b style='color:green'>Täidetud (+0.25p)</b> [Leitud: $($DNSOptions.Value -join ', ')]</li>"
    } else {
        $dnsFound = if ($DNSOptions -and $DNSOptions.Value) { $DNSOptions.Value -join ", " } else { "Puudub" }
        $dhcpDetails += "<li>DNS serverid (min 2 tk): <b style='color:red'>Viga! (Leiti: $dnsFound)</b></li>"
    }
} else {
    $dhcpDetails += "<li>Skoop leitud: <b style='color:red'>Puudu</b></li>"
    $dhcpDetails += "<li>Rendiaeg 4h: <b style='color:red'>-</b></li>"
    $dhcpDetails += "<li>Reservatsioonid: <b style='color:red'>-</b></li>"
    $dhcpDetails += "<li>DNS serverid (min 2 tk): <b style='color:red'>-</b></li>"
}
$dhcpDetails += "</ul>"

$dhcpScore = $dhcpTasksMet * 0.25
$dhcpStatus = ($dhcpTasksMet -eq 4)
Add-Result "Seadista WinServer2025 peal DHCP teenus, kus klientidele antakse reservereritud IP-aadressid. DHCP server jagab DNS serveritena välja mõlemad AD serverid" "Skoop, 4h, reserv, 2xDNS" $dhcpDetails $dhcpStatus 1.0 $dhcpScore

$Failover = Get-DhcpServerv4Failover -ErrorAction SilentlyContinue
$foStatus = ($Failover -and (($Failover.PartnerServer -join " ") -match "DC2"))
$foDetails = if ($foStatus) { "Partner DC2 leitud" } else { "Failover puudu või vale partner" }
Add-Result "Seadista DHCP teenusele failover, kus failover partneriks on DC2 server" "Partneriks on DC2" $foDetails $foStatus 1.0


# ====================================================================
# 4. AD STRUKTUUR, HALDUR JA KLIENT (1.5 punkti)
# ====================================================================
$OUUsers = Get-ADOrganizationalUnit -Filter "Name -eq 'Kasutajad'" -ErrorAction SilentlyContinue
$OUComps = Get-ADOrganizationalUnit -Filter "Name -eq 'Arvutid'" -ErrorAction SilentlyContinue
$ouStatus = ([bool]($OUUsers) -and [bool]($OUComps))
$ouLeitudText = if ($ouStatus) { "Mõlemad leitud" } else { "Puudu/Osaline" }
Add-Result "AD-sse on loodud 2 OU-d: Kasutajad ja Arvutid." "Mõlemad loodud" $ouLeitudText $ouStatus 0.5

# HALDUR 
$Haldur = Get-ADUser -Filter "Name -eq 'Haldur' -or SamAccountName -eq 'haldur'" -Properties DistinguishedName -ErrorAction SilentlyContinue
$haldurTasksMet = 0
$haldurDetails = "<ul style='margin:0; padding-left:20px;'>"

if ($Haldur) {
    $haldurTasksMet++
    $haldurDetails += "<li>Kasutaja asukoht: <b style='color:green'>Jah ($($Haldur.DistinguishedName)) (+0.25p)</b></li>"
    
    $HaldurGroups = Get-ADPrincipalGroupMembership -Identity $Haldur -ErrorAction SilentlyContinue
    $IsDomainAdmin = ($HaldurGroups.Name -match "Domain Admins|Domeeni administraatorid")
    
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
Add-Result "Domeeni on lisatud kasutaja haldur, kes on lisatud Domain Admins gruppi" "Eksisteerib AD-s ja Domain Admins" $haldurDetails $haldurStatus 0.5 $haldurScore


# KLIENTMASIN
$AllComps = Get-ADComputer -Filter {Name -notlike "DC1" -and Name -notlike "DC2"} -Properties DistinguishedName -ErrorAction SilentlyContinue
$compTasksMet = 0
$compDetails = "<ul style='margin:0; padding-left:20px;'>"

if ($AllComps) {
    $inArvutidOU = $AllComps | Where-Object { $_.DistinguishedName -match "OU=Arvutid" }
    $inComputersCN = $AllComps | Where-Object { $_.DistinguishedName -match "CN=Computers" }
    
    if ($inArvutidOU) {
        $compTasksMet = 2 
        $compDetails += "<li>Domeenist leitud klientmasin: <b style='color:green'>Jah (+0.25p)</b></li>"
        $compDetails += "<li>Masin asub OU-s Arvutid: <b style='color:green'>Jah (+0.25p) ($($inArvutidOU[0].Name))</b></li>"
    } elseif ($inComputersCN) {
        $compTasksMet = 1
        $compDetails += "<li>Domeenist leitud klientmasin: <b style='color:green'>Jah (+0.25p)</b></li>"
        $compDetails += "<li>Masin asub OU-s Arvutid: <b style='color:orange'>Ei, asub CN=Computers all ($($inComputersCN[0].Name))</b></li>"
    } else {
        $compTasksMet = 1 
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
Add-Result "Windows 11 klientmasin on lisatud domeeni ja pandud OU-sse Arvutid" "Domeenis ja OU-s Arvutid" $compDetails $compStatus 0.5 $compScore


# ====================================================================
# 5. DNS A-KIRJED JA CSV IMPORT (2.0 punkti)
# ====================================================================
$DnsRecords = Get-DnsServerResourceRecord -ZoneName $ExpectedDomain -RRType A | Where-Object {$_.HostName -notmatch "@|gc|DomainDnsZones|ForestDnsZones|DC1|DC2"}
$dnsRecordsStatus = ($DnsRecords.Count -gt 0)
Add-Result "DNS serveris on tehtud A-kirjed kõikide Linux serverite jaoks" "Vähemalt 1 manuaalne A-kirje" "$($DnsRecords.Count) tk leitud" $dnsRecordsStatus 1.0

$TestUsers = @{"Müük"="Aivo Teder"; "Personal"="Andres Karl Kukk"; "Raamatupidamine"="Anette Kuusk"; "Toimetajad"="Anneli Koppel"; "IT"="Anneli Roos"; "Juhtkond"="Annika Rand"; "Haldus"="Erki Niit"}
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

$importStatus = ($UsersFoundCount -gt 0)
Add-Result "Loodud on Powershelli skript, mis impordib AD kasutajad koos OU struktuuriga failist kasutajad.csv" "Kasutajad ja struktuur leitud" "$UsersFoundCount / 7 testkasutajat leitud õigetest OU-dest" $importStatus 1.0


# ====================================================================
# 6. GPO: ALGSED KONTROLLID (2.0 punkti)
# ====================================================================
$resLock = Check-GPOSettings "GPO_KontodeLukustamine" @() @("LockoutBadCount", ">5<", "LockoutDuration", ">15<") 1.0
Add-Result "Grupipoliitika (GPO): Loo GPO nimega GPO_KontodeLukustamine, mis lukustab kasutajakonto 15 minutiks, kui parooli on 5 korda järjest valesti sisestatud. Poliitika peab rakenduma kogu domeenile." "Domeenile rakendatud, 5 katset, 15 min" $resLock.Det $resLock.Status 1.0 $resLock.Pts

$resEdge = Check-GPOSettings "Edge_Siseportaal" @("OU=Personal") @("siseportaal", "NewTabPageLocation") 1.0
Add-Result "Grupipoliitika (GPO): Loo GPO nimega Edge_Siseportaal, mis määrab OU-sse Personal kuuluvate kasutajate Microsoft Edge brauseri vaikimisi avaleheks (Homepage) ja uue vahekaardi leheks (New Tab Page) siseportaali aadressi [https://siseportaal.$ExpectedDomain](https://siseportaal.$ExpectedDomain). Kasutajatel peab olema avalehe muutmine veebilehitseja seadetest blokeeritud." "Avaleht siseportaal, uue tab'i URL, lukustatud" $resEdge.Det $resEdge.Status 1.0 $resEdge.Pts


# ====================================================================
# 7. FOLDER REDIRECTION (PILVEKAUSTAD) JA GPO (Kokku: 8.0 punkti)
# ====================================================================

# 7.1 Turvagrupi loomine (0.5p)
$PilveGroup = Get-ADGroup -Filter "Name -eq 'PilveKasutajad'" -Properties Member, DistinguishedName -ErrorAction SilentlyContinue
$GrpDet = "<ul style='margin:0; padding-left:20px;'>"
$GrpPts = 0.0

if ($PilveGroup) {
    $GrpPts = 0.5
    $GrpDet += "<li>Grupp 'PilveKasutajad': <b style='color:green'>Leitud (+0.5p)</b></li>"
    
    if ($PilveGroup.DistinguishedName -match "OU=Kasutajad") {
        $GrpDet += "<li>Asukoht: <b style='color:green'>OU=Kasutajad</b></li>"
    } else {
        $GrpDet += "<li>Asukoht: <b style='color:orange'>$($PilveGroup.DistinguishedName)</b></li>"
    }
    
    if ($PilveGroup.Member -and $PilveGroup.Member.Count -gt 0) {
        $Members = ($PilveGroup.Member | ForEach-Object { ($_ -split ',')[0].Substring(3) }) -join ", "
        $GrpDet += "<li>Liikmed: <b style='color:blue'>$Members</b></li>"
    } else {
        $GrpDet += "<li>Liikmed: <b style='color:red'>Grupp on tühi</b></li>"
    }
} else {
    $GrpDet += "<li>Grupp 'PilveKasutajad': <b style='color:red'>Puudu</b></li>"
}
$GrpDet += "</ul>"
$grpStatus = ($GrpPts -eq 0.5)
Add-Result "Turvagrupi loomine. Active Directory's on loodud uus Security Group nimega PilveKasutajad." "AD-s eksisteerib grupp 'PilveKasutajad'" $GrpDet $grpStatus 0.5 $GrpPts


# 7.2 Kausta loomine ja varjatud jagamine nutika otsinguga (1.0p)
$SDet = "<ul style='margin:0; padding-left:20px;'>"
$SPts = 0.0

# Otsime kausta kettalt fuzzy logicuga, juhuks kui nimel on tühik
$FolderFuzzy = Get-ChildItem -Path "F:\" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "KasutajateFailid" }
$ShareFuzzy = Get-SmbShare -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "KasutajateFailid" }

if ($FolderFuzzy) {
    $ActualDir = $FolderFuzzy[0].FullName
    $SDet += "<li>Kaust F: kettal leitud ($ActualDir): <b style='color:green'>Jah (+0.5p)</b></li>"
    $SPts += 0.5
} elseif (Test-Path "F:\KasutajateFailid") {
    $SDet += "<li>Kaust F:\KasutajateFailid: <b style='color:green'>Jah (+0.5p)</b></li>"
    $SPts += 0.5
} else {
    $SDet += "<li>Kaust F:\KasutajateFailid: <b style='color:red'>Puudu (või puudub ligipääs F: kettale)</b></li>"
}

if ($ShareFuzzy) {
    $ShareName = $ShareFuzzy[0].Name
    if ($ShareName -match "\`$$") {
        $SDet += "<li>Varjatud share ($ShareName): <b style='color:green'>Jah (+0.5p)</b></li>"
        $SPts += 0.5
    } else {
        $SDet += "<li>Varjatud share: <b style='color:red'>Ei (Nimi on $ShareName, puudub $)</b></li>"
    }
} else {
    $SDet += "<li>Varjatud share: <b style='color:red'>Puudu või ei jookse Admin õigustes</b></li>"
}
$SDet += "</ul>"
$sPtsStatus = ($SPts -eq 1.0)
Add-Result "Serveri F: kettale on füüsiliselt loodud kaust KasutajateFailid. See on jagatud võrku varjatult, mis tähendab, et jagamisnime (Share Name) lõpus on dollarimärk (nt KasutajateFailid`$)" "Serveri F: kettal kaust KasutajateFailid`$" $SDet $sPtsStatus 1.0 $SPts


# 7.3 Kausta turvaõigused (1.0p)
$PermDet = "<ul style='margin:0; padding-left:20px;'>"
$PermPts = 0.0
if ($ShareFuzzy) {
    $ShareAccess = Get-SmbShareAccess -Name $ShareFuzzy[0].Name -ErrorAction SilentlyContinue
    if ($ShareAccess.AccountName -match "PilveKasutajad|Everyone|Kõik|Users") {
        $PermPts += 1.0
        $PermDet += "<li>Share õigused lubavad ligipääsu: <b style='color:green'>Jah (+1.0p)</b></li>"
    } else {
        $PermDet += "<li>Share õigused: <b style='color:red'>Puudulikud ($($ShareAccess.AccountName -join ', '))</b></li>"
    }
} else {
    $PermDet += "<li>Share õigused: <b style='color:red'>Share puudub, ei saa õigusi testida</b></li>"
}
$PermDet += "</ul>"
$permPtsStatus = ($PermPts -eq 1.0)
Add-Result "Kausta turvaõigused (NTFS ja Share). Varjatud võrgukaustal on korrektsed õigused. Kogu rühmal PilveKasutajad (või Everyone) peab olema piisav õigus (Share: Change/Full, NTFS: Modify või spetsiifilised loovõigused), et süsteem saaks sinna kasutajate alamkaustu tekitada." "Grupil on Change/Full õigused" $PermDet $permPtsStatus 1.0 $PermPts


# 7.4 GPO loomine ja linkimine (1.0p)
$GpoP = Get-GPO -Name "GPO_Pilvekaustad" -ErrorAction SilentlyContinue
$GpoXml = if ($GpoP) { [xml](Get-GPOReport -Guid $GpoP.Id -ReportType Xml) } else { $null }
$GpoDet = "<ul style='margin:0; padding-left:20px;'>"
$GpoPts = 0.0
if ($GpoP) {
    $GpoDet += "<li>GPO loodud: <b style='color:green'>Jah (+0.5p)</b></li>"
    $GpoPts += 0.5
    if ($GpoXml.GPO.LinksTo) {
        $GpoDet += "<li>GPO lingitud: <b style='color:green'>Jah (+0.5p)</b></li>"
        $GpoPts += 0.5
    } else {
        $GpoDet += "<li>GPO lingitud: <b style='color:red'>Ei (Link puudub)</b></li>"
    }
    
    if ($GpoXml.InnerXml -match "ExtensionData|FolderRedirection") {
        $GpoDet += "<li>GPO sisu: <b style='color:green'>Seadistused leitud</b></li>"
    } else {
        $GpoDet += "<li>GPO sisu: <b style='color:orange'>HOIATUS: GPO on tühi (seadistusi pole sees)!</b></li>"
    }
} else {
    $GpoDet += "<li>GPO 'GPO_Pilvekaustad': <b style='color:red'>Puudu</b></li>"
}
$GpoDet += "</ul>"
$gpoPtsStatus = ($GpoPts -eq 1.0)
Add-Result "GPO loomine ja linkimine. Loodud on uus Group Policy nimega GPO_Pilvekaustad ning see on korrektselt lingitud (domeeni juurde või spetsiifilisse kasutajate OU-sse, kus sihtgrupi kasutajad asuvad)." "GPO_Pilvekaustad olemas ja lingitud" $GpoDet $gpoPtsStatus 1.0 $GpoPts


# 7.5 GPO turvafilter (Security Filtering) (1.5p)
$SecDet = "<ul style='margin:0; padding-left:20px;'>"
$SecPts = 0.0
if ($GpoP) {
    $PilvePerm = Get-GPPermission -Guid $GpoP.Id -TargetName "PilveKasutajad" -TargetType Group -ErrorAction SilentlyContinue | Where-Object Permission -match "GpoApply"
    $AuthPerm = Get-GPPermission -Guid $GpoP.Id -TargetName "Authenticated Users" -TargetType Group -ErrorAction SilentlyContinue | Where-Object Permission -match "GpoApply"
    
    if ($PilvePerm) {
        $SecPts += 0.75
        $SecDet += "<li>PilveKasutajad 'Apply' õigus: <b style='color:green'>Jah (+0.75p)</b></li>"
    } else {
        $SecDet += "<li>PilveKasutajad 'Apply' õigus: <b style='color:red'>Puudu</b></li>"
    }
    
    if (!$AuthPerm) {
        $SecPts += 0.75
        $SecDet += "<li>Auth. Users 'Apply' eemaldatud: <b style='color:green'>Jah (+0.75p)</b></li>"
    } else {
        $SecDet += "<li>Auth. Users 'Apply' eemaldatud: <b style='color:red'>Ei (Vaikimisi filter eemaldamata)</b></li>"
    }
} else {
    $SecDet += "<li>Turvafilter: <b style='color:red'>GPO puudub</b></li>"
}
$SecDet += "</ul>"
$secPtsStatus = ($SecPts -eq 1.5)
Add-Result "GPO turvafilter (Security Filtering). GPO Scope saki all on Security Filtering alt eemaldatud vaikimisi Authenticated Users ja lisatud loodud grupp PilveKasutajad. (See tagab, et poliitika rakendub AINULT õigetele inimestele)." "PilveKasutajad lubatud, Auth Users eemaldatud" $SecDet $secPtsStatus 1.5 $SecPts


# --- Loeme GPO XML sisu, et kontrollida 7.6, 7.7 ja 7.8 seadistusi ---
$InnerXml = if ($GpoXml) { $GpoXml.InnerXml } else { "" }

# 7.6 Dokumendid (Documents) ümbersuunamine (1.0p)
$DocsRedir = ($InnerXml -match "Documents|Personal") -and ($InnerXml -match "FolderRedirection")
$DocDet = "<ul style='margin:0; padding-left:20px;'>"
$DocPts = 0.0
if ($DocsRedir) {
    $DocDet += "<li>Documents ümbersuunamine: <b style='color:green'>Leitud XML-ist (+1.0p)</b></li>"
    $DocPts = 1.0
} else {
    $DocDet += "<li>Documents ümbersuunamine: <b style='color:red'>Seadistus puudub</b></li>"
}
$DocDet += "</ul>"
$docPtsStatus = ($DocPts -eq 1.0)
Add-Result "Dokumendid (Documents) ümbersuunamine. GPO sätetes on Folder Redirection all Documents seadistatud režiimile Basic - Redirect everyone's folder to the same location." "Documents suunatakse ümber" $DocDet $docPtsStatus 1.0 $DocPts


# 7.7 Töölaud (Desktop) ümbersuunamine (1.0p)
$DeskRedir = ($InnerXml -match "Desktop") -and ($InnerXml -match "FolderRedirection")
$DeskDet = "<ul style='margin:0; padding-left:20px;'>"
$DeskPts = 0.0
if ($DeskRedir) {
    $DeskDet += "<li>Desktop ümbersuunamine: <b style='color:green'>Leitud XML-ist (+1.0p)</b></li>"
    $DeskPts = 1.0
} else {
    $DeskDet += "<li>Desktop ümbersuunamine: <b style='color:red'>Seadistus puudub</b></li>"
}
$DeskDet += "</ul>"
$deskPtsStatus = ($DeskPts -eq 1.0)
Add-Result "Töölaud (Desktop) ümbersuunamine. GPO sätetes on Folder Redirection all Desktop seadistatud režiimile Basic - Redirect everyone's folder to the same location." "Desktop suunatakse ümber" $DeskDet $deskPtsStatus 1.0 $DeskPts


# 7.8 Korrektne juurteekond (Root Path) (1.0p)
$PathMatch = ($InnerXml -match "KasutajateFailid")
$PathDet = "<ul style='margin:0; padding-left:20px;'>"
$PathPts = 0.0
if ($PathMatch) {
    $PathDet += "<li>Root Path ('KasutajateFailid'): <b style='color:green'>Leitud (+1.0p)</b></li>"
    $PathPts = 1.0
} else {
    $PathDet += "<li>Root Path ('KasutajateFailid'): <b style='color:red'>Root Path vale või puudu</b></li>"
}
$PathDet += "</ul>"
$pathPtsStatus = ($PathPts -eq 1.0)
Add-Result "Korrektne juurteekond (Root Path). Mõlema ümbersuunatud kausta seadetes on Root Path lahtrisse sisestatud eelnevalt loodud varjatud kausta UNC võrgutee (kujul \\<ServeriNimi>\KasutajateFailid`$). Süsteem peab moodustama teekonna \\...\`%USERNAME%\Documents" "Kujul \\ServerNimi\KasutajateFailid`$" $PathDet $pathPtsStatus 1.0 $PathPts


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
        <span class='total-points'>KOKKU PUNKTE: $TotalPoints / 20.0</span>
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
        <p>Kontrolliti igast osakonnast ühte kindlat töötajat, et kinnitada andmete importi ja OU-struktuuri:</p>
        $UserCheckDetails
    </div>
</body>
</html>
"@

# Salvestame ajutiselt unikaalse nimega HTML-i
$Html | Out-File $ReportPath -Encoding UTF8
Write-Host "Kontroll on lõpetatud!" -ForegroundColor Green
Write-Host "Kogutud punktid: $TotalPoints / 20.0" -ForegroundColor Yellow

# --- JSON GENEREERIMINE JA ÜLESLAADIMINE FLASKI SERVERISSE ---

$JsonPayload = @{
    Nimi = "$OpilaseNimi - $TaisPilet"
    Pilet = $TaisPilet
    Aeg = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    KokkuPunkte = $TotalPoints
    Masin = $ComputerName
    Domeen = $ExpectedDomain
    Tulemused = $Results
    UserCheckDetails = $UserCheckDetails 
    FailiNimi = "HindamisRaport_${SafeName}_${SafePilet}"
}

$JsonString = $JsonPayload | ConvertTo-Json -Depth 5 -Compress

# Salvestame ajutiselt unikaalse nimega JSON faili
$JsonString | Out-File $JsonPath -Encoding UTF8

$ServeriURL = "http://192.168.124.64:5001/api/upload"

Write-Host "Saadan andmed dashboardile ($ServeriURL)..." -ForegroundColor Cyan

try {
    $Response = Invoke-RestMethod -Uri $ServeriURL `
                                  -Method Post `
                                  -Body $JsonString `
                                  -ContentType "application/json; charset=utf-8"
    
    Write-Host "Andmed edukalt üles laetud! Server vastas: $($Response.message)" -ForegroundColor Green
}
catch {
    Write-Host "Viga andmete üleslaadimisel: $($_.Exception.Message)" -ForegroundColor Red
}

# --- LOKAALSETE FAILIDE KUSTUTAMINE ---
Write-Host "Puhastan kohaliku masina testifailidest..." -ForegroundColor Cyan

if (Test-Path $ReportPath) {
    Remove-Item -Path $ReportPath -Force
}

if (Test-Path $JsonPath) {
    Remove-Item -Path $JsonPath -Force
}

Write-Host "Kohalikud .html ja .json failid on edukalt kustutatud!" -ForegroundColor Green


```
