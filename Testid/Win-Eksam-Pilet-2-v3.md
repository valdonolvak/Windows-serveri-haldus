## Winserver Pilet 2 ##


```powershell

<#
.SYNOPSIS
    Täielik Windows Serveri auditi skript vastavalt 20-punktisele hindamiskriteeriumile (PILET 2 - DFS/FSRM).
    Sisaldab täpsustatud pealkirju, üli-otsingut GPO-dele, DC2 IP lollikindlat tuvastust ja sügavaid varuplaane DFS-ile.
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
Import-Module ServerManager

# --- SEADISTUSED JA SISEND ---
$ExpectedDomain = Read-Host "Sisesta oodatud domeeninimi (nt oige.ee või sinunimi.local)"
$OpilaseNimi = Read-Host "Sisesta õpilase ees- ja perekonnanimi"

Write-Host "Vali pileti liik (1 - Linux, 2 - Windows, 3 - Võrk):" -ForegroundColor Cyan
$PiletLiikValik = Read-Host "Sisesta number"
$PiletLiik = switch ($PiletLiikValik) { 
    '1' {'Linux'} 
    '2' {'Windows'} 
    '3' {'Võrk'} 
    Default {'Määramata'} 
}

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
        $color = "#c6efce"
        $staatusTekst = "OK" 
    } elseif ($teenitud -gt 0) { 
        $color = "#fff2cc"
        $staatusTekst = "OSALINE" 
    } else { 
        $color = "#ffc7ce"
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
    
    $Gpos = Get-GPO -All -ErrorAction SilentlyContinue
    if (!$Gpos) { 
        return @{ Pts = 0; Status = $false; Det = "GPO-de lugemine ebaõnnestus." } 
    }
    
    # 1. Täpne otsing
    $Gpo = $Gpos | Where-Object { $_.DisplayName -eq $GpoName } | Select-Object -First 1
    
    # 2. Hägune otsing (asendame alakriipsud ja tühikud)
    if (!$Gpo) {
        $cleanName = $GpoName -replace '_','.*'
        $Gpo = $Gpos | Where-Object { $_.DisplayName -match "(?i)$cleanName" } | Select-Object -First 1
    }
    
    # 3. Väga hägune otsing (eemaldame "GPO_" algusest täielikult, et leida nt "Kontode lukustamine")
    if (!$Gpo) {
        $shortName = $GpoName -replace "(?i)GPO_?", "" -replace '\s','' -replace '_',''
        $Gpo = $Gpos | Where-Object { ($_.DisplayName -replace '\s','' -replace '_','') -match "(?i)$shortName" } | Select-Object -First 1
    }

    if (!$Gpo) { 
        return @{ Pts = 0; Status = $false; Det = "GPO '$GpoName' (või sarnase nimega) puudub." } 
    }
    
    $Xml = [xml](Get-GPOReport -Guid $Gpo.Id -ReportType Xml)
    $txt = $Xml.InnerXml
    $actualLinks = @()
    
    if ($Xml.GPO.LinksTo) {
        $links = $Xml.GPO.LinksTo
        if ($links -is [array]) { 
            foreach ($l in $links) { $actualLinks += $l.SOMName } 
        } else { 
            $actualLinks += $links.SOMName 
        }
    }
    
    $linksStr = if ($actualLinks.Count -gt 0) { $actualLinks -join ", " } else { "Lingid puuduvad" }
    
    $linksOk = $true
    foreach ($ou in $ExpectedOUs) {
        if ($ou -and $actualLinks -notcontains $ou -and ($Xml.GPO.LinksTo.SOMPath -join " ") -notmatch $ou) { 
            $linksOk = $false 
        }
    }
    
    $setMet = 0
    foreach ($r in $Regexes) { 
        if ($txt -match $r) { $setMet++ } 
    }
    
    if ($linksOk) {
        if ($setMet -eq $Regexes.Count) { 
            return @{ Pts = $MaxP; Status = $true; Det = "Kõik seaded korras (Leitud GPO: $($Gpo.DisplayName)). Lingitud: $linksStr." } 
        } elseif ($setMet -gt 0) { 
            return @{ Pts = ($MaxP * 0.75); Status = $false; Det = "Link õige ($linksStr), osad seaded olemas (GPO: $($Gpo.DisplayName))." } 
        } else { 
            return @{ Pts = ($MaxP * 0.25); Status = $false; Det = "Link õige ($linksStr), seaded puudu (GPO: $($Gpo.DisplayName))." } 
        }
    } else {
        if ($setMet -eq $Regexes.Count) { 
            return @{ Pts = ($MaxP * 0.75); Status = $false; Det = "Seaded õiged, aga VALE ASUKOHT! Lingitud: $linksStr (GPO: $($Gpo.DisplayName))" } 
        } elseif ($setMet -gt 0) { 
            return @{ Pts = ($MaxP * 0.5); Status = $false; Det = "Osaliselt õige, VALE ASUKOHT: $linksStr (GPO: $($Gpo.DisplayName))" } 
        } else { 
            return @{ Pts = 0; Status = $false; Det = "Seaded puudu, vale asukoht." } 
        }
    }
}


# ====================================================================
# PÕHIOSA (12 punkti kokku)
# ====================================================================

# 1. DC1 nimi
$ComputerName = $env:COMPUTERNAME
$dc1NameStatus = ($ComputerName -eq "DC1")
Add-Result "Muuta WinServer2025 masin nimi DC1" "Masina nimi on DC1" "Tuvastatud: $ComputerName" $dc1NameStatus 0.5

# 2. DC1 IP
$DC1IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq "Manual" -and $_.InterfaceAlias -notmatch "Loopback" }).IPAddress
$dc1IpStatus = ($DC1IP.Count -gt 0)
Add-Result "Anna DC1 serverile staatiline IP-aadress" "Manuaalne IPv4 seadistus" ("IP: " + ($DC1IP -join ", ")) $dc1IpStatus 0.5

# 3. AD Roll
$Domain = Get-ADDomain
$adStatus = ($Domain.DNSRoot -eq $ExpectedDomain)
Add-Result "Seadista DC1 serverile Acitve Directory domeeni teenused domeeni $ExpectedDomain tarvis" "Domeen $ExpectedDomain" "Tuvastatud: $($Domain.DNSRoot)" $adStatus 1.0

# 4. DNS Roll
$DNSRole = Get-WindowsFeature -Name DNS -ErrorAction SilentlyContinue
$DNSService = Get-Service -Name DNS -ErrorAction SilentlyContinue
$dnsStatus = ($DNSRole.Installed -eq $true -or $DNSService -ne $null)
$dnsLeitudText = if ($DNSRole) { $($DNSRole.InstallState) } elseif ($DNSService) { "Teenus töötab ($($DNSService.Status))" } else { "Puudu" }
Add-Result "Seadista DC1 serverile DNS teenus" "DNS roll paigaldatud" "Roll: $dnsLeitudText" $dnsStatus 0.5

# 5. DC2 nimi
$DC2 = Get-ADComputer -Filter "Name -eq 'DC2'" -Properties IPv4Address -ErrorAction SilentlyContinue
$dc2Status = [bool]($DC2)
$dc2LeitudText = if ($dc2Status) { "Leitud DC2 konto AD-st" } else { "Ei leitud arvutit DC2" }
Add-Result "WinCore2025 masinal muuta nimi DC2-ks" "AD-s eksisteerib arvuti DC2" $dc2LeitudText $dc2Status 0.5

# 6. DC2 IP
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

# 7. DC2 on domeenikontroller
$DomainDN = $Domain.DistinguishedName
$DCsInOU = Get-ADComputer -Filter * -SearchBase "OU=Domain Controllers,$DomainDN" -ErrorAction SilentlyContinue
$HasTwoDCs = ($DCsInOU.Count -ge 2) -and ($DCsInOU.Name -contains "DC2")
$hasTwoDCsStatus = [bool]($HasTwoDCs)
Add-Result "Lisada WinCore2025 server teiseks domeenikontrolleriks domeeni $ExpectedDomain jaoks" "Vähemalt 2 masinat (sh DC2) Domain Controllers OU-s" ("Masinad DC OU-s: " + ($DCsInOU.Name -join ", ")) $hasTwoDCsStatus 1.0


# 8. DHCP
$DHCPScope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Select-Object -First 1
$dhcpTasksMet = 0
$dhcpDetails = "<ul style='margin:0; padding-left:20px;'>"

if ($DHCPScope) {
    $dhcpTasksMet++
    $dhcpDetails += "<li>Skoop: <b style='color:green'>Jah (+0.25p) [$($DHCPScope.Name)]</b></li>"
    
    if ($DHCPScope.LeaseDuration.TotalHours -eq 4) { 
        $dhcpTasksMet++
        $dhcpDetails += "<li>Rendiaeg 4h: <b style='color:green'>OK (+0.25p)</b></li>" 
    } else { 
        $dhcpDetails += "<li>Rendiaeg: <b style='color:red'>Vale ($($DHCPScope.LeaseDuration))</b></li>" 
    }
    
    $Reservations = @(Get-DhcpServerv4Reservation -ScopeId $DHCPScope.ScopeId -ErrorAction SilentlyContinue)
    if ($Reservations.Count -gt 0) {
        $dhcpTasksMet++
        $dhcpDetails += "<li>Reservatsioonid: <b style='color:green'>OK (+0.25p) [$($Reservations.Count) tk]</b></li>"
    } else { 
        $dhcpDetails += "<li>Reservatsioonid: <b style='color:red'>Puudu</b></li>" 
    }
    
    $DNSOptions = Get-DhcpServerv4OptionValue -ScopeId $DHCPScope.ScopeId -OptionId 6 -ErrorAction SilentlyContinue
    if ($DNSOptions -and $DNSOptions.Value.Count -ge 2) { 
        $dhcpTasksMet++
        $dhcpDetails += "<li>DNS serverid (min 2 tk): <b style='color:green'>OK (+0.25p)</b> [Leitud: $($DNSOptions.Value -join ', ')]</li>" 
    } else { 
        $dnsFound = if ($DNSOptions -and $DNSOptions.Value) { $DNSOptions.Value -join ", " } else { "Puudub" }
        $dhcpDetails += "<li>DNS serverid (min 2 tk): <b style='color:red'>Viga! (Leiti: $dnsFound)</b></li>" 
    }
    
    # Visuaalne abistav info Ruuteri kohta
    $RouterOption = Get-DhcpServerv4OptionValue -ScopeId $DHCPScope.ScopeId -OptionId 3 -ErrorAction SilentlyContinue
    if ($RouterOption -and $RouterOption.Value) {
        $dhcpDetails += "<li><i>Ruuter (Gateway): $($RouterOption.Value -join ", ")</i></li>"
    } else {
        $dhcpDetails += "<li><i>Ruuter (Gateway): Puudub</i></li>"
    }
    
} else { 
    $dhcpDetails += "<li>Skoop: <b style='color:red'>Puudu</b></li>" 
}
$dhcpDetails += "</ul>"
$dhcpStatus = ($dhcpTasksMet -eq 4)
Add-Result "Seadista WinServer2025 peal DHCP teenus, kus klientidele antakse reservereritud IP-aadressid. DHCP server jagab DNS serveritena välja mõlemad AD serverid" "Skoop, 4h, reserv, 2xDNS" $dhcpDetails $dhcpStatus 1.0 ($dhcpTasksMet * 0.25)


# 9. DHCP Failover
$Failover = Get-DhcpServerv4Failover -ErrorAction SilentlyContinue
$foStatus = $false
$foDetails = "Failover puudub"

if ($Failover) {
    $partner = $Failover.PartnerServer -join " "
    if ($partner -match "DC2" -or ($ip -ne $null -and $partner -match $ip)) {
        $foStatus = $true
        $foDetails = "Failover korras. Partner: <b>$partner</b>"
    } else { 
        $foDetails = "Tuvastatud vale partner: $partner" 
    }
}
Add-Result "Seadista DHCP teenusele failover, kus failover partneriks on DC2 server" "Partneriks on DC2" $foDetails $foStatus 1.0


# 10. AD OU-d
$OUUsers = Get-ADOrganizationalUnit -Filter "Name -eq 'Kasutajad'"
$OUComps = Get-ADOrganizationalUnit -Filter "Name -eq 'Arvutid'"
$ouStatus = ([bool]($OUUsers) -and [bool]($OUComps))
$ouLeitudText = if ($ouStatus) { "Mõlemad leitud" } else { "Puudu/Osaline" }
Add-Result "AD-sse on loodud 2 OU-d: Kasutajad ja Arvutid." "Mõlemad loodud" $ouLeitudText $ouStatus 0.5


# 11. Haldur
$Haldur = Get-ADUser -Filter "Name -eq 'Haldur' -or SamAccountName -eq 'haldur'" -Properties DistinguishedName -ErrorAction SilentlyContinue
$haldurTasksMet = 0
$haldurDetails = "<ul style='margin:0; padding-left:20px;'>"

if ($Haldur) {
    if ($Haldur.DistinguishedName -match "OU=Kasutajad") { 
        $haldurTasksMet++
        $haldurDetails += "<li>Asukoht Kasutajad: <b style='color:green'>OK (+0.25p)</b></li>" 
    } else { 
        $haldurDetails += "<li>Asukoht: <b style='color:red'>VALE! ($(Convert-DNToReadable $Haldur.DistinguishedName))</b></li>" 
    }
    
    $HaldurGroups = Get-ADPrincipalGroupMembership -Identity $Haldur -ErrorAction SilentlyContinue
    if ($HaldurGroups.Name -match "Domain Admins|Domeeni administraatorid") { 
        $haldurTasksMet++
        $haldurDetails += "<li>Domain Admins: <b style='color:green'>OK (+0.25p)</b></li>" 
    } else { 
        $haldurDetails += "<li>Domain Admins: <b style='color:red'>Puudu</b></li>" 
    }
} else { 
    $haldurDetails += "<li>Kasutaja 'haldur': <b style='color:red'>Puudu AD-st</b></li>" 
}
$haldurDetails += "</ul>"
$haldurStatus = ($haldurTasksMet -eq 2)
Add-Result "Domeeni on lisatud kasutaja haldur, kes on lisatud Domain Admins gruppi" "OU=Kasutajad ja Domain Admins" $haldurDetails $haldurStatus 0.5 ($haldurTasksMet * 0.25)


# 12. Klientmasin
$AllComps = Get-ADComputer -Filter {Name -notlike "DC1" -and Name -notlike "DC2"} -Properties DistinguishedName -ErrorAction SilentlyContinue
$compTasksMet = 0
$compDetails = "<ul style='margin:0; padding-left:20px;'>"

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
} else { 
    $compDetails += "<li>Klientmasin: <b style='color:red'>Puudub domeenist</b></li>" 
}
$compDetails += "</ul>"
$compStatus = ($compTasksMet -eq 2)
Add-Result "Windows 11 klientmasin on lisatud domeeni ja pandud OU-sse Arvutid" "Domeenis ja OU-s Arvutid" $compDetails $compStatus 0.5 ($compTasksMet * 0.25)


# 13. DNS Kirjed
$DnsRecords = Get-DnsServerResourceRecord -ZoneName $ExpectedDomain -RRType A | Where-Object {$_.HostName -notmatch "@|gc|DomainDnsZones|ForestDnsZones|DC1|DC2"}
$dnsRecordsStatus = ($DnsRecords.Count -gt 0)
Add-Result "DNS serveris on tehtud A-kirjed kõikide Linux serverite jaoks" "Vähemalt 1 manuaalne A-kirje" "$($DnsRecords.Count) tk leitud" $dnsRecordsStatus 1.0


# 14. AD Import
$TestUsers = @{"Müük"="Aivo Teder"; "Personal"="Andres Karl Kukk"; "Raamatupidamine"="Anette Kuusk"; "Toimetajad"="Anneli Koppel"; "IT"="Anneli Roos"; "Juhtkond"="Annika Rand"; "Haldus"="Erki Niit"}
$UsersFoundCount = 0
$UserCheckDetails = "<ul style='margin:0; padding-left:20px;'>"

foreach ($Dept in $TestUsers.Keys) {
    $ExpectedUser = $TestUsers[$Dept]
    $FoundUser = Get-ADUser -Filter "Name -eq '$ExpectedUser'" -Properties DistinguishedName -ErrorAction SilentlyContinue
    if ($FoundUser) {
        if ($FoundUser.DistinguishedName -match "OU=$Dept") { 
            $UsersFoundCount++
            $UserCheckDetails += "<li><b>$ExpectedUser</b> (OU=$Dept) - <span style='color:green'>OK</span></li>" 
        } else { 
            $UserCheckDetails += "<li><b>$ExpectedUser</b> - <span style='color:orange'>VALE OU! ($(Convert-DNToReadable $FoundUser.DistinguishedName))</span></li>" 
        }
    } else { 
        $UserCheckDetails += "<li><b>$ExpectedUser</b> - <span style='color:red'>PUUDUB</span></li>" 
    }
}
$UserCheckDetails += "</ul>"
$importStatus = ($UsersFoundCount -gt 0)
Add-Result "Loodud on Powershelli skript, mis impordib AD kasutajad koos OU struktuuriga failist kasutajad.csv" "Kasutajad ja struktuur leitud" "$UsersFoundCount / 7 testkasutajat OK" $importStatus 1.0


# 15. GPO Lukustamine
$resLock = Check-GPOSettings "GPO_KontodeLukustamine" @() @("LockoutBadCount", ">5<", "LockoutDuration", ">15<") 1.0
Add-Result "Grupipoliitika (GPO): Loo GPO nimega GPO_KontodeLukustamine, mis lukustab kasutajakonto 15 minutiks, kui parooli on 5 korda järjest valesti sisestatud. Poliitika peab rakenduma kogu domeenile." "Domeenile rakendatud, 5 katset, 15 min" $resLock.Det $resLock.Status 1.0 $resLock.Pts


# 16. GPO Edge
$resEdge = Check-GPOSettings "Edge_Siseportaal" @("Personal") @("siseportaal", "NewTabPageLocation") 1.0
Add-Result "Grupipoliitika (GPO): Loo GPO nimega Edge_Siseportaal, mis määrab OU-sse Personal kuuluvate kasutajate Microsoft Edge brauseri vaikimisi avaleheks (Homepage) ja uue vahekaardi leheks (New Tab Page) siseportaali aadressi [https://siseportaal.$ExpectedDomain](https://siseportaal.$ExpectedDomain). Kasutajatel peab olema avalehe muutmine veebilehitseja seadetest blokeeritud." "Avaleht siseportaal, uue tab'i URL, lukustatud" $resEdge.Det $resEdge.Status 1.0 $resEdge.Pts


# ====================================================================
# 7. DFS JA FAILISERVERI SEADISTUSED (LISAOSA - Kokku 8.0 punkti)
# ====================================================================
$DomainFQDN = (Get-ADDomain).DNSRoot

# 17. DFS Rollide kontroll (Varuplaaniga, kui Get-WindowsFeature jookseb kokku)
$RolePts = 0
$RoleDetails = "<ul style='margin:0; padding-left:20px;'>"
$Roles = @(
    @{Name="FS-DFS-Namespace"; Svc="Dfs"},
    @{Name="FS-DFS-Replication"; Svc="Dfsr"},
    @{Name="FS-Resource-Manager"; Svc="srmsvc"}
)

foreach ($Role in $Roles) {
    $rName = $Role.Name
    $rSvc = $Role.Svc
    $feat = Get-WindowsFeature $rName -ErrorAction SilentlyContinue
    $svc = Get-Service -Name $rSvc -ErrorAction SilentlyContinue
    
    if (($feat -and $feat.Installed) -or $svc) {
        $RolePts += 0.5
        $RoleDetails += "<li>${rName}: <b style='color:green'>OK (+0.5p)</b></li>"
    } else { 
        $RoleDetails += "<li>${rName}: <b style='color:red'>Puudu</b></li>" 
    }
}
$RoleDetails += "</ul>"
$rolesStatus = ($RolePts -eq 1.5)
Add-Result "Paigalda Windows Server 2025-le rollid DFS Namespaces, DFS Replication ja File Server Resource Manager" "Kõik 3 rolli paigaldatud" $RoleDetails $rolesStatus 1.5 $RolePts


# 18. DFS nimeruum Jagatud
$AllRoots = @(Get-DfsnRoot -Domain $DomainFQDN -ErrorAction SilentlyContinue)
$AllRoots += @(Get-DfsnRoot -ComputerName $ComputerName -ErrorAction SilentlyContinue)

$DfsN = $AllRoots | Where-Object { $_.Path -match "(?i)jaga|jag|share" } | Select-Object -First 1
if (!$DfsN -and $AllRoots.Count -gt 0) { $DfsN = $AllRoots[0] }

# Ülisügav varuplaan: otsime C:\DFSRoots kaustast
if (!$DfsN) {
    $dfsDirs = Get-ChildItem "C:\DFSRoots" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "(?i)jaga|jag|share" }
    if ($dfsDirs) {
        $DfsN = [PSCustomObject]@{ Path = "\\$ExpectedDomain\$($dfsDirs[0].Name)" }
    }
}

$DfsnDet = if ($DfsN) { "Nimeruum leitud: <b style='color:green'>Jah (+1p)</b> [Asukoht: $($DfsN.Path)]" } else { "Nimeruum leitud: <b style='color:red'>Ei leitud</b>" }
$dfsnStatus = [bool]($DfsN)
Add-Result "Loo DFS nimeruum Jagatud" "Nimeruum \\$DomainFQDN\Jagatud (või ligilähedane nimi)" $DfsnDet $dfsnStatus 1.0


# ABIMUUTUJAD ALAMKAUSTADE JAOKS
$KogukondFolder = $null
$IsiklikFolder = $null

if ($DfsN) {
    $AllFolders = Get-DfsnFolder -Path "$($DfsN.Path)\*" -ErrorAction SilentlyContinue
    $KogukondFolder = $AllFolders | Where-Object { $_.Path -match "(?i)kogu|kogukond" } | Select-Object -First 1 
    $IsiklikFolder = $AllFolders | Where-Object { $_.Path -match "(?i)isik|isiklik" } | Select-Object -First 1 
    
    # Sügav varuplaan: Kui Get-DfsnFolder ei tööta, testime UNC radu
    if (!$KogukondFolder -and (Test-Path "$($DfsN.Path)\Kogukond" -ErrorAction SilentlyContinue)) { 
        $KogukondFolder = [PSCustomObject]@{ Path = "$($DfsN.Path)\Kogukond" } 
    }
    if (!$IsiklikFolder -and (Test-Path "$($DfsN.Path)\Isiklik" -ErrorAction SilentlyContinue)) { 
        $IsiklikFolder = [PSCustomObject]@{ Path = "$($DfsN.Path)\Isiklik" } 
    }
}


# 19. Nimeruumi kaust Kogukond
$KFolderDet = if ($KogukondFolder) { "Kaust leitud nimeruumist: <b style='color:green'>Jah (+0.5p)</b> [Asukoht: $($KogukondFolder.Path)]" } else { "Kaust leitud: <b style='color:red'>Ei</b>" }
$kfolderStatus = [bool]($KogukondFolder)
Add-Result "Loo nimeruumi Jagatud kaust Kogukond" "Kaust Kogukond nimeruumis olemas" $KFolderDet $kfolderStatus 0.5


# 20. Replikatsiooni grupp Kogukond
$RepGroupKogukond = Get-DfsrReplicationGroup -ErrorAction SilentlyContinue | Where-Object { "$($_.GroupName) $($_.Name)" -match "(?i)kogu" } | Select-Object -First 1
$RepKogukondPts = 0

if ($RepGroupKogukond) {
    $RepKogukondPts = 0.5
    $RepKogukondDet = "Grupp leitud: <b style='color:green'>Jah (+0.5p)</b> [Nimi: $($RepGroupKogukond.GroupName)]"
} else {
    if ($KogukondFolder) {
        $KTargets = @(Get-DfsnFolderTarget -Path $KogukondFolder.Path -ErrorAction SilentlyContinue)
        if ($KTargets.Count -ge 2) {
            $RepKogukondPts = 0.5
            $RepKogukondDet = "Kaudselt tuvastatud: Kaustal on mitu sihtkohta (DC1, DC2): <b style='color:green'>Jah (+0.5p)</b>"
        } else {
            # Veel sügavam varuplaan: proovime otse serveri pealt kausta kätte saada (nagu õpilase pildil \\DC1 ja \\DC2)
            if ((Test-Path "\\DC1\Kogukond" -ErrorAction SilentlyContinue) -and (Test-Path "\\DC2\Kogukond" -ErrorAction SilentlyContinue)) {
                $RepKogukondPts = 0.5
                $RepKogukondDet = "Kaudselt tuvastatud: Kaustad on jagatud ja kättesaadavad nii DC1 kui DC2 peal: <b style='color:green'>Jah (+0.5p)</b>"
            } else {
                $RepKogukondDet = "Grupp leitud: <b style='color:red'>Ei (Ka sihtkohti on vaid $($KTargets.Count))</b>"
            }
        }
    } else {
        $RepKogukondDet = "Grupp leitud: <b style='color:red'>Ei (Kaust ise puudub)</b>"
    }
}
$repKogukondStatus = ($RepKogukondPts -eq 0.5)
Add-Result "Loo kaustale replikatsiooni grupp, et kaustast oleks koopia ka teises (DC2) serveris" "Replikatsioonigrupp Kogukond leitud" $RepKogukondDet $repKogukondStatus 0.5 $RepKogukondPts


# 21. GPO Kogukond
$GpoK = Get-GPO -All -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "(?i)kogu|kogukond" } | Select-Object -First 1
$GpoKPts = 0
$GpoKDet = "<ul style='margin:0; padding-left:20px;'>"

if ($GpoK) {
    $GpoKPts += 0.25
    $GpoKDet += "<li>GPO loodud: <b style='color:green'>Jah (+0.25p)</b> [Leitud nimi: $($GpoK.DisplayName)]</li>"
    
    $GpoKXml = [xml](Get-GPOReport -Guid $GpoK.Id -ReportType Xml)
    if ($GpoKXml.GPO.LinksTo) { 
        $GpoKPts += 0.25
        $GpoKDet += "<li>GPO lingitud: <b style='color:green'>Jah (+0.25p)</b></li>" 
    } else { 
        $GpoKDet += "<li>GPO lingitud: <b style='color:red'>Ei (Kuhu see rakendub?)</b></li>" 
    }

    $xmlString = $GpoKXml.InnerXml
    if ($xmlString -match '(?i)letter="([A-Z]):?"' -or $xmlString -match '(?i)Drive Letter="([A-Z]):?"') {
        $foundLetter = $Matches[1].ToUpper()
        $GpoKPts += 0.5
        if ($foundLetter -eq 'Y') {
            $GpoKDet += "<li>Ketas ühendatud: <b style='color:green'>Täht Y: (+0.5p)</b></li>"
        } else {
            $GpoKDet += "<li>Ketas ühendatud: <b style='color:orange'>Täht ${foundLetter}: (Oodati Y:) (+0.5p)</b></li>"
        }
    } else {
        $GpoKDet += "<li>Ketas ühendatud: <b style='color:red'>GPO-s pole Drive Map seadistust tehtud!</b></li>"
    }

    if ($xmlString -match '(?i)path="([^"]+)"') {
        $GpoKDet += "<li><i>Jagatud sihtkoht: <b>$($Matches[1])</b></i></li>"
    }
} else { 
    $GpoKDet += "<li>GPO 'Kogukond': <b style='color:red'>Puudu</b></li>" 
}
$GpoKDet += "</ul>"
$gpoKStatus = ($GpoKPts -eq 1.0)
Add-Result "Loo GPO nimega Kogukond, millega kaust jagataks välja kõigile domeeni kasutajatele ligipääsetava võrgukettana Y: kõikidele sinu domeeni kasutajatele" "Ketas jagatud GPO abil" $GpoKDet $gpoKStatus 1.0 $GpoKPts


# 22. FSRM Kogukond 10GB
$KogukondQuota = Get-FsrmQuota -ErrorAction SilentlyContinue | Where-Object { $_.Path -match "(?i)kogu|kogukond" } | Select-Object -First 1
$KQPts = 0
$KQDet = "<ul style='margin:0; padding-left:20px;'>"

if ($KogukondQuota) {
    $KQPts += 0.25
    $KQDet += "<li>Kvoot loodud: <b style='color:green'>Jah (+0.25p)</b></li>"
    
    if ($KogukondQuota.Size -eq 10GB) { 
        $KQPts += 0.25
        $KQDet += "<li>Suurus 10GB: <b style='color:green'>Jah (+0.25p)</b></li>" 
    } else { 
        $KQDet += "<li>Suurus: <b style='color:red'>Vale ($($KogukondQuota.Size))</b></li>" 
    }
} else { 
    $KQDet += "<li>Kvoot: <b style='color:red'>Puudu</b></li>" 
}
$KQDet += "</ul>"
$kqStatus = ($KQPts -eq 0.5)
Add-Result "Määra kaustale FSRM abil mahupiirang 10 GB" "10GB kvoot rakendatud" $KQDet $kqStatus 0.5 $KQPts


# 23. FSRM Failipiirang
$FileScreen = Get-FsrmFileScreen -ErrorAction SilentlyContinue | Where-Object { $_.Path -match "(?i)kogu|kogukond" } | Select-Object -First 1
$FSPts = 0
$FSDet = "<ul style='margin:0; padding-left:20px;'>"

if ($FileScreen) {
    $FSPts += 0.25
    $FSDet += "<li>Failipiirang: <b style='color:green'>Olemas (+0.25p)</b></li>"
    
    $FSPatternFound = $false
    $FSGroupNames = $FileScreen.IncludeGroup
    
    if ($FSGroupNames) {
        foreach ($gName in $FSGroupNames) {
            $FSGroup = Get-FsrmFileGroup -Name $gName -ErrorAction SilentlyContinue
            if ($FSGroup) {
                $joinedPatterns = $FSGroup.IncludePattern -join " "
                if ($joinedPatterns -match "(?i)\.exe|\.msi|\.bat|\.ps1") {
                    $FSPatternFound = $true
                    break
                }
            }
        }
    }
    
    if ($FSPatternFound) {
        $FSPts += 0.25
        $FSDet += "<li>Keelab skriptid/programmid: <b style='color:green'>Jah (+0.25p)</b></li>"
    } else { 
        $FSDet += "<li>Filtrid: <b style='color:red'>Ei tuvastanud exe/msi filtreid rakendatud grupis</b></li>" 
    }
} else { 
    $FSDet += "<li>Failipiirang: <b style='color:red'>Puudu</b></li>" 
}
$FSDet += "</ul>"
$fsStatus = ($FSPts -eq 0.5)
Add-Result "Sellele ressursile luua piirang, mis takistab programmifailide kopeerimist sinna (.msi, .exe, .bat, .ps1)" "Failipiirang aktiivne" $FSDet $fsStatus 0.5 $FSPts


# 24. Nimeruumi kaust Isiklik
$IFolderDet = if ($IsiklikFolder) { "Kaust leitud nimeruumis: <b style='color:green'>Jah (+0.5p)</b> [Asukoht: $($IsiklikFolder.Path)]" } else { "Kaust leitud: <b style='color:red'>Ei</b>" }
$ifolderStatus = [bool]($IsiklikFolder)
Add-Result "Loo nimeruumi Jagatud kaust Isiklik" "Kaust nimeruumis olemas" $IFolderDet $ifolderStatus 0.5


# 25. Replikatsiooni grupp Isiklik
$RepGroupIsiklik = Get-DfsrReplicationGroup -ErrorAction SilentlyContinue | Where-Object { "$($_.GroupName) $($_.Name)" -match "(?i)isik" } | Select-Object -First 1
$RepIsiklikPts = 0

if ($RepGroupIsiklik) {
    $RepIsiklikPts = 0.5
    $RepIsiklikDet = "Grupp leitud: <b style='color:green'>Jah (+0.5p)</b> [Nimi: $($RepGroupIsiklik.GroupName)]"
} else {
    if ($IsiklikFolder) {
        $ITargets = @(Get-DfsnFolderTarget -Path $IsiklikFolder.Path -ErrorAction SilentlyContinue)
        if ($ITargets.Count -ge 2) {
            $RepIsiklikPts = 0.5
            $RepIsiklikDet = "Kaudselt tuvastatud: Kaustal on mitu sihtkohta (DC1, DC2): <b style='color:green'>Jah (+0.5p)</b>"
        } else {
            if ((Test-Path "\\DC1\Isiklik" -ErrorAction SilentlyContinue) -and (Test-Path "\\DC2\Isiklik" -ErrorAction SilentlyContinue)) {
                $RepIsiklikPts = 0.5
                $RepIsiklikDet = "Kaudselt tuvastatud: Kaustad on jagatud ja kättesaadavad nii DC1 kui DC2 peal: <b style='color:green'>Jah (+0.5p)</b>"
            } else {
                $RepIsiklikDet = "Grupp leitud: <b style='color:red'>Ei (Ka sihtkohti on vaid $($ITargets.Count))</b>"
            }
        }
    } else {
        $RepIsiklikDet = "Grupp leitud: <b style='color:red'>Ei (Kaust ise puudub)</b>"
    }
}
$repIsiklikStatus = ($RepIsiklikPts -eq 0.5)
Add-Result "Loo kaustale replikatsiooni grupp, et kaustast oleks koopia ka teises serveris (DC2)" "Replikatsioonigrupp leitud" $RepIsiklikDet $repIsiklikStatus 0.5 $RepIsiklikPts


# 26. GPO Isiklik
$GpoI = Get-GPO -All -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "(?i)isik|isiklik" } | Select-Object -First 1
$GpoIPts = 0
$GpoIDet = "<ul style='margin:0; padding-left:20px;'>"

if ($GpoI) {
    $GpoIPts += 0.25
    $GpoIDet += "<li>GPO loodud: <b style='color:green'>Jah (+0.25p)</b> [Leitud nimi: $($GpoI.DisplayName)]</li>"
    
    $GpoIXml = [xml](Get-GPOReport -Guid $GpoI.Id -ReportType Xml)
    if ($GpoIXml.GPO.LinksTo) { 
        $GpoIPts += 0.25
        $GpoIDet += "<li>GPO lingitud: <b style='color:green'>Jah (+0.25p)</b></li>" 
    } else { 
        $GpoIDet += "<li>GPO lingitud: <b style='color:red'>Ei</b></li>" 
    }

    $xmlString = $GpoIXml.InnerXml
    if ($xmlString -match '(?i)letter="([A-Z]):?"' -or $xmlString -match '(?i)Drive Letter="([A-Z]):?"') {
        $foundLetter = $Matches[1].ToUpper()
        $GpoIPts += 0.5
        if ($foundLetter -eq 'Z') {
            $GpoIDet += "<li>Ketas ühendatud: <b style='color:green'>Täht Z: (+0.5p)</b></li>"
        } else {
            $GpoIDet += "<li>Ketas ühendatud: <b style='color:orange'>Täht ${foundLetter}: (Oodati Z:) (+0.5p)</b></li>"
        }
    } else {
        $GpoIDet += "<li>Ketas ühendatud: <b style='color:red'>GPO-s pole Drive Map seadistust!</b></li>"
    }
    
    if ($xmlString -match '(?i)path="([^"]+)"') {
        $GpoIDet += "<li><i>Jagatud sihtkoht: <b>$($Matches[1])</b></i></li>"
    }
} else { 
    $GpoIDet += "<li>GPO 'Isiklik': <b style='color:red'>Puudu</b></li>" 
}
$GpoIDet += "</ul>"
$gpoIStatus = ($GpoIPts -eq 1.0)
Add-Result "Loo GPO nimega Isiklik, millega tehakse kausta sisse domeeni kasutaja nimega kaust ja jagatakse ainult see kaust kasutajale välja võrgukettana Z:" "Ketas seadistatud GPO abil" $GpoIDet $gpoIStatus 1.0 $GpoIPts


# 27. FSRM Isiklik Auto Quota
$AutoQuota = Get-FsrmAutoQuota -ErrorAction SilentlyContinue | Where-Object { $_.Path -match "(?i)isik|isiklik" } | Select-Object -First 1
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
        $AQDet += "<li>Suurus: <b style='color:red'>Vale või malli ei tuvastatud</b></li>" 
    }
} else { 
    $AQDet += "<li>Auto-quota: <b style='color:red'>Puudu</b></li>" 
}
$AQDet += "</ul>"
$aqStatus = ($AQPts -eq 0.5)
Add-Result "Määra kaustadele FSRM abil mahupiirang 1GB kasutaja kohta" "Auto-quota rakendatud" $AQDet $aqStatus 0.5 $AQPts


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
        <strong>Õpilane:</strong> $OpilaseNimi - $TaisPilet<br>
        <strong>Aeg:</strong> $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')<br><br>
        <span class='total-points'>KOKKU PUNKTE: $TotalPoints / 20.0</span>
    </div>
    <table>
        <tr>
            <th>Ülesanne (Hindamismudel)</th>
            <th>Oodatud</th>
            <th>Leitud reaalsus</th>
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
        <h3>AD Kasutajate pistelise otsingu detailid</h3>
        $UserCheckDetails
    </div>
</body>
</html>
"@

$Html | Out-File $ReportPath -Encoding UTF8
Write-Host "Kontroll on lõpetatud! Kogutud punktid: $TotalPoints / 20.0" -ForegroundColor Yellow


# --- JSON GENEREERIMINE JA ÜLESLAADIMINE ---
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
$JsonString | Out-File $JsonPath -Encoding UTF8

$ServeriURL = "http://192.168.124.64:5001/api/upload"

Write-Host "Saadan andmed dashboardile..." -ForegroundColor Cyan

try {
    $Response = Invoke-RestMethod -Uri $ServeriURL -Method Post -Body $JsonString -ContentType "application/json; charset=utf-8"
    Write-Host "Andmed edukalt üles laetud! ($($Response.message))" -ForegroundColor Green
} catch { 
    Write-Host "Viga andmete üleslaadimisel: $($_.Exception.Message)" -ForegroundColor Red 
}

if (Test-Path $ReportPath) { Remove-Item -Path $ReportPath -Force }
if (Test-Path $JsonPath) { Remove-Item -Path $JsonPath -Force }

Write-Host "Kohalikud failid puhastatud." -ForegroundColor Green


```
