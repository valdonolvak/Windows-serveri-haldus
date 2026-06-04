## Windows Pilet 2 PS skript ##

```powershell
<#
.SYNOPSIS
    Täielik Windows Serveri auditi skript vastavalt 20-punktisele hindamiskriteeriumile.
    Sisaldab detailset osalist hindamist, unikaalseid failinimesid ja lokaalsete failide eemaldamist.
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
Add-Result "Muuta masina nimi DC1" "Masina nimi on DC1" $ComputerName ($ComputerName -eq "DC1") 0.5

$DC1IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq "Manual" -and $_.InterfaceAlias -notmatch "Loopback" }).IPAddress
Add-Result "DC1 staatiline IP" "Manuaalne IPv4 seadistus" ($DC1IP -join ", ") ($DC1IP.Count -gt 0) 0.5

$DC2 = Get-ADComputer -Filter "Name -eq 'DC2'"
Add-Result "WinCore2025 masina nimi DC2" "AD-s eksisteerib arvuti DC2" (if($DC2){"Leitud DC2"}else{"Ei leitud"}) ($DC2 -ne $null) 0.5

$DC2DNS = Resolve-DnsName -Name "DC2" -Type A -ErrorAction SilentlyContinue
Add-Result "DC2 staatiline IP" "DNS kirje viitab DC2 IP-le" (if($DC2DNS){$DC2DNS.IPAddress}else{"Puudub"}) ($DC2DNS -ne $null) 0.5


# ====================================================================
# 2. AD DS JA DNS TEENUSED (2.5 punkti)
# ====================================================================
$Domain = Get-ADDomain
Add-Result "Seadista DC1 AD DS domeen" "Domeen $ExpectedDomain" $Domain.DNSRoot ($Domain.DNSRoot -eq $ExpectedDomain) 1.0

$DNSRole = Get-WindowsFeature DNS
Add-Result "Seadista DC1 DNS teenus" "DNS roll paigaldatud" $DNSRole.InstallState ($DNSRole.Installed) 0.5

$DomainControllers = Get-ADDomainController -Filter *
$HasTwoDCs = ($DomainControllers.Count -ge 2) -and ($DomainControllers.Name -contains "DC2")
Add-Result "Lisada DC2 teiseks domeenikontrolleriks" "Vähemalt 2 DC-d (sh DC2)" ($DomainControllers.Name -join ", ") $HasTwoDCs 1.0


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

$Failover = Get-DhcpServerv4Failover -ErrorAction SilentlyContinue
$foStatus = ($Failover -and (($Failover.PartnerServer -join " ") -match "DC2"))
$foDetails = if ($foStatus) { "Partner DC2 leitud" } else { "Failover puudu või vale partner" }
Add-Result "Seadista DHCP teenusele failover" "Partneriks on DC2" $foDetails $foStatus 1.0


# ====================================================================
# 4. AD STRUKTUUR, HALDUR JA KLIENT (1.5 punkti)
# ====================================================================
$OUUsers = Get-ADOrganizationalUnit -Filter "Name -eq 'Kasutajad'"
$OUComps = Get-ADOrganizationalUnit -Filter "Name -eq 'Arvutid'"
Add-Result "AD-sse on loodud 2 OU-d: Kasutajad ja Arvutid" "Mõlemad loodud" (if($OUUsers -and $OUComps){"Mõlemad leitud"}else{"Puudu/Osaline"}) ($OUUsers -and $OUComps) 0.5

# HALDUR
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
Add-Result "Windows 11 klientmasin on lisatud domeeni ja OU-sse Arvutid" "Domeenis ja OU-s Arvutid" $compDetails $compStatus 0.5 $compScore


# ====================================================================
# 5. DNS A-KIRJED JA CSV IMPORT (2.0 punkti)
# ====================================================================
$DnsRecords = Get-DnsServerResourceRecord -ZoneName $ExpectedDomain -RRType A | Where-Object {$_.HostName -notmatch "@|gc|DomainDnsZones|ForestDnsZones|DC1|DC2"}
Add-Result "DNS serveris on tehtud A-kirjed kõikide Linux serverite jaoks" "Vähemalt 1 manuaalne A-kirje" "$($DnsRecords.Count) tk leitud" ($DnsRecords.Count -gt 0) 1.0

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

$ImportSuccess = ($UsersFoundCount -gt 0)
Add-Result "Loodud skript impordib AD kasutajad (kasutajad.csv)" "Kasutajad ja struktuur leitud" "$UsersFoundCount / 7 testkasutajat leitud õigetest OU-dest" $ImportSuccess 1.0


# ====================================================================
# 6. GPO: ALGSED KONTROLLID (2.0 punkti)
# ====================================================================
$resLock = Check-GPOSettings "GPO_KontodeLukustamine" @() @("LockoutBadCount", ">5<", "LockoutDuration", ">15<") 1.0
Add-Result "GPO_KontodeLukustamine (5 katset, 15 min)" "Domeenile rakendatud, 5 katset, 15 min" $resLock.Det $resLock.Status 1.0 $resLock.Pts

$resEdge = Check-GPOSettings "Edge_Siseportaal" @("OU=Personal") @("siseportaal", "NewTabPageLocation") 1.0
Add-Result "GPO Edge_Siseportaal (Personal avaleht)" "Avaleht siseportaal, uue tab'i URL, lukustatud" $resEdge.Det $resEdge.Status 1.0 $resEdge.Pts


# ====================================================================
# 7. DFS JA FAILISERVERI SEADISTUSED (Kokku: 8.0 punkti / 11 alaülesannet)
# ====================================================================
$DomainFQDN = (Get-ADDomain).DNSRoot

# 7.1 Rollide kontroll (1.5p kokku)
$RolePts = 0
$RoleDetails = "<ul style='margin:0; padding-left:20px;'>"
$Roles = @("FS-DFS-Namespace", "FS-DFS-Replication", "FS-Resource-Manager")
foreach ($Role in $Roles) {
    if ((Get-WindowsFeature $Role -ErrorAction SilentlyContinue).Installed) {
        $RolePts += 0.5
        $RoleDetails += "<li>${Role}: <b style='color:green'>Paigaldatud (+0.5p)</b></li>"
    } else {
        $RoleDetails += "<li>${Role}: <b style='color:red'>Puudu</b></li>"
    }
}
$RoleDetails += "</ul>"
Add-Result "Paigalda Windows Server 2025-le rollid DFS Namespaces, DFS Replication ja File Server Resource Manager" "Kõik 3 rolli paigaldatud" $RoleDetails ($RolePts -eq 1.5) 1.5 $RolePts

# 7.2 DFS nimeruum Jagatud (1p)
$DfsN = Get-DfsnRoot -Path "\\$DomainFQDN\Jagatud" -ErrorAction SilentlyContinue
$DfsnDet = "<ul style='margin:0; padding-left:20px;'>"
$DfsnPts = 0.0
if ($DfsN) {
    $DfsnDet += "<li>Nimeruum leitud: <b style='color:green'>Jah (+1p)</b></li>"
    $DfsnPts = 1.0
} else {
    $DfsnDet += "<li>Nimeruum leitud: <b style='color:red'>Ei leitud</b></li>"
}
$DfsnDet += "</ul>"
Add-Result "Loo DFS nimeruum Jagatud" "Nimeruum \\$DomainFQDN\Jagatud eksisteerib" $DfsnDet ($DfsnPts -eq 1.0) 1.0 $DfsnPts

# 7.3 Nimeruumi kaust Kogukond (0.5p)
$KogukondFolder = Get-DfsnFolder -Path "\\$DomainFQDN\Jagatud\Kogukond" -ErrorAction SilentlyContinue
$KFolderDet = "<ul style='margin:0; padding-left:20px;'>"
$KFolderPts = 0.0
if ($KogukondFolder) {
    $KFolderDet += "<li>Kaust nimeruumis leitud: <b style='color:green'>Jah (+0.5p)</b></li>"
    $KFolderPts = 0.5
} else {
    $KFolderDet += "<li>Kaust nimeruumis leitud: <b style='color:red'>Ei leitud</b></li>"
}
$KFolderDet += "</ul>"
Add-Result "Loo nimeruumi Jagatud kaust Kogukond" "Kaust nimeruumis olemas" $KFolderDet ($KFolderPts -eq 0.5) 0.5 $KFolderPts

# 7.4 Replikatsiooni grupp Kogukond (0.5p)
$RepGroupKogukond = Get-DfsrReplicationGroup -ErrorAction SilentlyContinue | Where-Object Name -match "Kogukond"
$RepKogukondDet = "<ul style='margin:0; padding-left:20px;'>"
$RepKogukondPts = 0.0
if ($RepGroupKogukond) {
    $RepKogukondDet += "<li>Replikatsioonigrupp leitud: <b style='color:green'>Jah (+0.5p)</b></li>"
    $RepKogukondPts = 0.5
} else {
    $RepKogukondDet += "<li>Replikatsioonigrupp leitud: <b style='color:red'>Ei leitud</b></li>"
}
$RepKogukondDet += "</ul>"
Add-Result "Loo kaustale replikatsiooni grupp, et kaustast oleks koopia ka teises (DC2) serveris" "Replikatsioonigrupp Kogukond leitud" $RepKogukondDet ($RepKogukondPts -eq 0.5) 0.5 $RepKogukondPts

# 7.5 GPO Kogukond (1p)
$GpoK = Get-GPO -Name "Kogukond" -ErrorAction SilentlyContinue
$GpoKPts = 0
$GpoKDet = "<ul style='margin:0; padding-left:20px;'>"
if ($GpoK) {
    $GpoKPts += 0.25
    $GpoKDet += "<li>GPO loodud: <b style='color:green'>Jah (+0.25p)</b></li>"

    $GpoKXml = [xml](Get-GPOReport -Name "Kogukond" -ReportType Xml)
    if ($GpoKXml.GPO.LinksTo) {
        $GpoKPts += 0.25
        $GpoKDet += "<li>GPO lingitud: <b style='color:green'>Jah (+0.25p)</b></li>"
    } else {
        $GpoKDet += "<li>GPO lingitud: <b style='color:red'>Ei</b></li>"
    }

    $xmlString = $GpoKXml.InnerXml
    if ($xmlString -match 'letter="Y:"' -or $xmlString -match 'Drive Letter="Y:"') {
        $GpoKPts += 0.5
        $GpoKDet += "<li>Ketas Y: seadistatud: <b style='color:green'>Jah (+0.5p)</b></li>"
    } else {
        $GpoKDet += "<li>Ketas Y: seadistatud: <b style='color:red'>Ei leitud</b></li>"
    }
} else {
    $GpoKDet += "<li>GPO 'Kogukond': <b style='color:red'>Puudu</b></li>"
}
$GpoKDet += "</ul>"
Add-Result "Loo GPO nimega Kogukond, millega kaust jagataks välja kõigile domeeni kasutajatele ligipääsetava võrgukettana Y: kõikidele sinu domeeni kasutajatele" "Ketas Y: jagatud" $GpoKDet ($GpoKPts -eq 1.0) 1.0 $GpoKPts

# 7.6 FSRM Kogukond 10GB (0.5p)
$KogukondQuota = Get-FsrmQuota -ErrorAction SilentlyContinue | Where-Object { $_.Path -match "Kogukond" }
$KQDet = "<ul style='margin:0; padding-left:20px;'>"
$KQPts = 0
if ($KogukondQuota) {
    $KQPts += 0.25
    $KQDet += "<li>Kvoot loodud: <b style='color:green'>Jah (+0.25p)</b></li>"
    if ($KogukondQuota.Size -eq 10GB) {
        $KQPts += 0.25
        $KQDet += "<li>Suurus 10GB: <b style='color:green'>Jah (+0.25p)</b></li>"
    } else {
        $KQDet += "<li>Suurus 10GB: <b style='color:red'>Vale suurus ($($KogukondQuota.Size))</b></li>"
    }
} else {
    $KQDet += "<li>Kvoot: <b style='color:red'>Puudu</b></li>"
}
$KQDet += "</ul>"
Add-Result "Määra kaustale FSRM abil mahupiirang 10 GB" "10GB kvoot rakendatud" $KQDet ($KQPts -eq 0.5) 0.5 $KQPts

# 7.7 FSRM Failipiirang (0.5p)
$FileScreen = Get-FsrmFileScreen -ErrorAction SilentlyContinue | Where-Object { $_.Path -match "Kogukond" }
$FSPts = 0
$FSDet = "<ul style='margin:0; padding-left:20px;'>"
if ($FileScreen) {
    $FSPts += 0.25
    $FSDet += "<li>Failipiirang kaustal: <b style='color:green'>Jah (+0.25p)</b></li>"
    
    $FSGroup = Get-FsrmFileGroup -Name $FileScreen.FileGroup -ErrorAction SilentlyContinue
    if ($FSGroup -and ($FSGroup.IncludePattern -match "\.exe" -or $FSGroup.IncludePattern -match "\.msi" -or $FSGroup.IncludePattern -match "\.bat")) {
        $FSPts += 0.25
        $FSDet += "<li>Keelab .exe/.msi jne: <b style='color:green'>Jah (+0.25p)</b></li>"
    } else {
        $FSDet += "<li>Keelab .exe/.msi jne: <b style='color:red'>Ei tuvastanud sobivaid mustreid</b></li>"
    }
} else {
    $FSDet += "<li>Failipiirang: <b style='color:red'>Puudu</b></li>"
}
$FSDet += "</ul>"
Add-Result "Sellele ressursile luua piirang, mis takistab programmifailide kopeerimist sinna (.msi, .exe, .bat, .ps1)" "Failipiirang aktiivne" $FSDet ($FSPts -eq 0.5) 0.5 $FSPts

# 7.8 Nimeruumi kaust Isiklik (0.5p)
$IsiklikFolder = Get-DfsnFolder -Path "\\$DomainFQDN\Jagatud\Isiklik" -ErrorAction SilentlyContinue
$IFolderDet = "<ul style='margin:0; padding-left:20px;'>"
$IFolderPts = 0.0
if ($IsiklikFolder) {
    $IFolderDet += "<li>Kaust nimeruumis leitud: <b style='color:green'>Jah (+0.5p)</b></li>"
    $IFolderPts = 0.5
} else {
    $IFolderDet += "<li>Kaust nimeruumis leitud: <b style='color:red'>Ei leitud</b></li>"
}
$IFolderDet += "</ul>"
Add-Result "Loo nimeruumi Jagatud kaust Isiklik" "Kaust nimeruumis olemas" $IFolderDet ($IFolderPts -eq 0.5) 0.5 $IFolderPts

# 7.9 Replikatsiooni grupp Isiklik (0.5p)
$RepGroupIsiklik = Get-DfsrReplicationGroup -ErrorAction SilentlyContinue | Where-Object Name -match "Isiklik"
$RepIsiklikDet = "<ul style='margin:0; padding-left:20px;'>"
$RepIsiklikPts = 0.0
if ($RepGroupIsiklik) {
    $RepIsiklikDet += "<li>Replikatsioonigrupp leitud: <b style='color:green'>Jah (+0.5p)</b></li>"
    $RepIsiklikPts = 0.5
} else {
    $RepIsiklikDet += "<li>Replikatsioonigrupp leitud: <b style='color:red'>Ei leitud</b></li>"
}
$RepIsiklikDet += "</ul>"
Add-Result "Loo kaustale replikatsiooni grupp, et kaustast oleks koopia ka teises serveris (DC2)" "Replikatsioonigrupp Isiklik leitud" $RepIsiklikDet ($RepIsiklikPts -eq 0.5) 0.5 $RepIsiklikPts

# 7.10 GPO Isiklik (1p)
$GpoI = Get-GPO -Name "Isiklik" -ErrorAction SilentlyContinue
$GpoIPts = 0
$GpoIDet = "<ul style='margin:0; padding-left:20px;'>"
if ($GpoI) {
    $GpoIPts += 0.25
    $GpoIDet += "<li>GPO loodud: <b style='color:green'>Jah (+0.25p)</b></li>"

    $GpoIXml = [xml](Get-GPOReport -Name "Isiklik" -ReportType Xml)
    if ($GpoIXml.GPO.LinksTo) {
        $GpoIPts += 0.25
        $GpoIDet += "<li>GPO lingitud: <b style='color:green'>Jah (+0.25p)</b></li>"
    } else {
        $GpoIDet += "<li>GPO lingitud: <b style='color:red'>Ei</b></li>"
    }

    $xmlString = $GpoIXml.InnerXml
    if ($xmlString -match 'letter="Z:"' -or $xmlString -match 'Drive Letter="Z:"') {
        $GpoIPts += 0.5
        $GpoIDet += "<li>Ketas Z: seadistatud: <b style='color:green'>Jah (+0.5p)</b></li>"
    } else {
        $GpoIDet += "<li>Ketas Z: seadistatud: <b style='color:red'>Ei leitud</b></li>"
    }
} else {
    $GpoIDet += "<li>GPO 'Isiklik': <b style='color:red'>Puudu</b></li>"
}
$GpoIDet += "</ul>"
Add-Result "Loo GPO nimega Isiklik, millega tehakse kausta sisse domeeni kasutaja nimega kaust ja jagatakse ainult see kaust kasutajale välja võrgukettana Z:" "Ketas Z: seadistatud" $GpoIDet ($GpoIPts -eq 1.0) 1.0 $GpoIPts

# 7.11 FSRM Isiklik 1GB (Auto Quota) (0.5p)
$AutoQuota = Get-FsrmAutoQuota -ErrorAction SilentlyContinue | Where-Object { $_.Path -match "Isiklik" }
$AQPts = 0
$AQDet = "<ul style='margin:0; padding-left:20px;'>"
if ($AutoQuota) {
    $AQPts += 0.25
    $AQDet += "<li>Auto-quota loodud: <b style='color:green'>Jah (+0.25p)</b></li>"
    
    $Template = Get-FsrmQuotaTemplate -Name $AutoQuota.Template -ErrorAction SilentlyContinue
    if ($Template -and $Template.Size -eq 1GB) {
        $AQPts += 0.25
        $AQDet += "<li>Suurus 1GB: <b style='color:green'>Jah (+0.25p)</b></li>"
    } else {
        $AQDet += "<li>Suurus 1GB: <b style='color:red'>Vale või malli suurus tuvastamata</b></li>"
    }
} else {
    $AQDet += "<li>Auto-quota: <b style='color:red'>Puudu</b></li>"
}
$AQDet += "</ul>"
Add-Result "Määra kaustadele FSRM abil mahupiirang 1GB kasutaja kohta" "Auto-quota Isiklik kaustale" $AQDet ($AQPts -eq 0.5) 0.5 $AQPts


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

# Salvestame unikaalse nimega HTML-i lokaalselt (ajutiselt)
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

# Salvestame unikaalse nimega JSON faili lokaalselt (ajutiselt)
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
