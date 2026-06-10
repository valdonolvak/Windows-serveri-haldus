## Windows Pilet 4 ##

```powershell
<#
.SYNOPSIS
    Täielik Windows Serveri auditi skript vastavalt 20-punktisele hindamiskriteeriumile (PILET 4 - GPO SPETSIIFILISED PIIRANGUD).
    Sisaldab täpsustatud pealkirju, üli-otsingut GPO-dele (sh taustapildi trükivigadele), DC2 IP lollikindlat tuvastust ja laiendatud rakenduste piirangute otsingut.
    Käivitada DC1 serveris Domain Admin õigustes.
#>

$ErrorActionPreference = "SilentlyContinue"

# Moodulite laadimine
Import-Module ActiveDirectory
Import-Module GroupPolicy
Import-Module DhcpServer
Import-Module DnsServer
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
    
    # 3. Väga hägune otsing (eemaldame "GPO_" algusest täielikult)
    if (!$Gpo) {
        $shortName = $GpoName -replace "(?i)GPO_?", "" -replace '\s','' -replace '_',''
        $Gpo = $Gpos | Where-Object { ($_.DisplayName -replace '\s','' -replace '_','') -match "(?i)$shortName" } | Select-Object -First 1
    }

    # 4. ÜLI-HÄGUNE OTSING SPETSIAALSELT TAUSTAPILDILE
    if (!$Gpo -and $GpoName -match "(?i)Taustapilt") {
        $Gpo = $Gpos | Where-Object { $_.DisplayName -match "(?i)töölau|tausta|tasuta|wallpaper" } | Select-Object -First 1
        if ($Gpo) {
            $testXml = [xml](Get-GPOReport -Guid $Gpo.Id -ReportType Xml -ErrorAction SilentlyContinue)
            if ($testXml.InnerXml -notmatch "(?i)Wallpaper|Taustapilt") {
                $Gpo = $null 
            }
        }
    }

    if (!$Gpo) { 
        return @{ Pts = 0; Status = $false; Det = "GPO '$GpoName' (või sarnase nimega) puudub." } 
    }
    
    $Xml = [xml](Get-GPOReport -Guid $Gpo.Id -ReportType Xml -ErrorAction SilentlyContinue)
    $txt = if ($Xml) { $Xml.InnerXml } else { "" }
    $actualLinks = @()
    
    if ($Xml -and $Xml.GPO.LinksTo) {
        $links = $Xml.GPO.LinksTo
        if ($links -is [array]) { 
            foreach ($l in $links) { $actualLinks += $l.SOMName } 
        } else { 
            $actualLinks += $links.SOMName 
        }
    }
    
    $linksStr = if ($actualLinks.Count -gt 0) { $actualLinks -join ", " } else { "Lingid puuduvad" }
    
    $linksOk = $true
    if ($ExpectedOUs.Count -gt 0) {
        foreach ($ou in $ExpectedOUs) {
            if ($ou -and $actualLinks -notcontains $ou -and ($Xml.GPO.LinksTo.SOMPath -join " ") -notmatch $ou) { 
                $linksOk = $false 
            }
        }
    }
    
    $setMet = 0
    foreach ($r in $Regexes) { 
        if ($txt -match $r) { $setMet++ } 
    }
    
    if ($linksOk) {
        if ($setMet -eq $Regexes.Count) { 
            return @{ Pts = $MaxP; Status = $true; Det = "Kõik seaded korras (Leiti GPO: <b>$($Gpo.DisplayName)</b>). Lingitud: $linksStr." } 
        } elseif ($setMet -gt 0) { 
            return @{ Pts = ($MaxP * 0.75); Status = $false; Det = "Link õige ($linksStr), osad seaded olemas (Leiti GPO: <b>$($Gpo.DisplayName)</b>)." } 
        } else { 
            return @{ Pts = ($MaxP * 0.25); Status = $false; Det = "Link õige ($linksStr), seaded puudu (Leiti GPO: <b>$($Gpo.DisplayName)</b>)." } 
        }
    } else {
        if ($setMet -eq $Regexes.Count) { 
            return @{ Pts = ($MaxP * 0.75); Status = $false; Det = "Seaded õiged, aga VALE ASUKOHT! Lingitud: $linksStr (Leiti GPO: <b>$($Gpo.DisplayName)</b>)" } 
        } elseif ($setMet -gt 0) { 
            return @{ Pts = ($MaxP * 0.5); Status = $false; Det = "Osaliselt õige, VALE ASUKOHT: $linksStr (Leiti GPO: <b>$($Gpo.DisplayName)</b>)" } 
        } else { 
            return @{ Pts = 0; Status = $false; Det = "Seaded puudu, vale asukoht (Leiti GPO: <b>$($Gpo.DisplayName)</b>)." } 
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
Add-Result "Seadista WinServer2025 peal DHCP teenus, kus klientidele antakse reservereritud IP-aadressid. DHCP server jagab DNS serveritena välja mõlemad DC serverid" "Skoop, 4h, reserv, 2xDNS" $dhcpDetails $dhcpStatus 1.0 ($dhcpTasksMet * 0.25)


# 9. DHCP Failover
$Failover = Get-DhcpServerv4Failover -ErrorAction SilentlyContinue
$foStatus = $false
$foDetails = "Failover puudub"

if ($Failover) {
    $partner = $Failover.PartnerServer -join " "
    if ($partner -match "DC2" -or ($ip -ne $null -and $partner -match [regex]::Escape($ip))) {
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
Add-Result "DC-sse on loodud 2 OU-d: Kasutajad ja Arvutid." "Mõlemad loodud" $ouLeitudText $ouStatus 0.5


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
Add-Result "Domeeni on lisatud kasutaja haldur, kes on lisatud Domain DC admins gruppi" "OU=Kasutajad ja Domain Admins" $haldurDetails $haldurStatus 0.5 ($haldurTasksMet * 0.25)


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


# 15. GPO Lukustamine (Parandatud: Otsib laiemalt LockoutBadCount ja LockoutDuration väärtusi)
$resLock = Check-GPOSettings "GPO_KontodeLukustamine" @() @("(?i)LockoutBadCount.*5", "(?i)LockoutDuration.*15") 1.0
Add-Result "Grupipoliitika (GPO): Loo GPO nimega GPO_KontodeLukustamine, mis lukustab kasutajakonto 15 minutiks, kui parooli on 5 korda järjest valesti sisestatud. Poliitika peab rakenduma kogu domeenile." "Domeenile rakendatud, 5 katset, 15 min" $resLock.Det $resLock.Status 1.0 $resLock.Pts


# 16. GPO Edge (Parandatud: Otsib nii 'NewTabPageLocation' kui ka 'Homepage' / 'New tab' seadistusi)
$resEdge = Check-GPOSettings "Edge_Siseportaal" @("Personal") @("(?i)siseportaal", "(?i)NewTabPage|New tab|Homepage|Home page") 1.0
Add-Result "Grupipoliitika (GPO): Loo GPO nimega Edge_Siseportaal, mis määrab OU-sse Personal kuuluvate kasutajate Microsoft Edge brauseri vaikimisi avaleheks (Homepage) ja uue vahekaardi leheks (New Tab Page) siseportaali aadressi [https://siseportaal.$ExpectedDomain](https://siseportaal.$ExpectedDomain). Kasutajatel peab olema avalehe muutmine veebilehitseja seadetest blokeeritud." "Avaleht siseportaal, uue tab'i URL, lukustatud" $resEdge.Det $resEdge.Status 1.0 $resEdge.Pts


# ====================================================================
# PILET 4 SPETSIIFILINE OSA (8 PUNKTI) - KÕIKIDELE GPO-dele HÄGUNE OTSING JA LAIENDATUD PIIRANGUD
# ====================================================================

# 17. Turvaline Sisselogimine (Parandatud: Laiendatud keele- ja seadistusefiltrid)
$resTurv = Check-GPOSettings "TurvalineSisselogimine" @() @("(?i)DontDisplayLastUserName|HideFastUserSwitching", "(?i)Guest|Külaline|SeDenyInteractiveLogonRight|SeInteractiveLogonRight|Local account|Kohalik") 1.0
Add-Result "Loo arvutitele poliitika GPO_TurvalineSisselogimine, mis eemaldab sisselogimisekraanilt viimase sisseloginud kasutaja nime ja keelab külaliskontode (Guest) ning lokaalsete tavakasutajate sisselogimise." "DontDisplayLastUserName ja Guest keelatud" $resTurv.Det $resTurv.Status 1.0 $resTurv.Pts

# 18. KeelaUSB (Parandatud: Toetab ka "Deny read access" variatsioone XML-ist)
$resUsb = Check-GPOSettings "KeelaUSB" @("Arvutid") @("(?i)Removable.*Read|Deny_Read|Deny read", "(?i)Removable.*Write|Deny_Write|Deny write") 1.0
Add-Result "Loo arvutitele poliitika GPO_KeelaUSB ja lingi see OU-ga Arvutid, keelates kõigil sealsetel masinatel väliste USB-andmekandjate lugemis- ja kirjutamisõigused." "Removable Storage Access (Deny Read/Write)" $resUsb.Det $resUsb.Status 1.0 $resUsb.Pts

# 19. TöölauaTaustapilt
$resWp = Check-GPOSettings "TöölauaTaustapilt" @() @("(?i)Wallpaper|Taustapilt") 1.0
Add-Result "Loo poliitika GPO_TöölauaTaustapilt, mis määrab kõigile kasutajatele kohustusliku taustapildi viisil, et see salvestatakse klientmasina vahemällu ja toimib ka ilma AD võrguühenduseta." "Wallpaper seadistus leitud" $resWp.Det $resWp.Status 1.0 $resWp.Pts

# 20. TurvapoliitikaTeade
$resMsg = Check-GPOSettings "TurvapoliitikaTeade" @("Personal") @("(?i)LegalNotice") 1.5
Add-Result "Loo poliitika GPO_TurvapoliitikaTeade ja lingi see OU-ga Personal, kuvamaks kasutajale sisselogimisel interaktiivset hoiatust ettevõtte turvapoliitika ja arvuti kasutamise eeskirjade kohta." "LegalNoticeCaption/Text seadistus" $resMsg.Det $resMsg.Status 1.5 $resMsg.Pts

# 21. ParooliKehtivus
$resPwd = Check-GPOSettings "ParooliKehtivus" @() @("(?i)MaximumPasswordAge.*30") 1.0
if ($resPwd.Status -eq $false -and $resPwd.Pts -eq 0) {
    $resPwd = Check-GPOSettings "Default Domain Policy" @() @("(?i)MaximumPasswordAge.*30") 1.0
}
Add-Result "Loo uus domeenitaseme grupipoliitika nimega GPO_ParooliKehtivus (või seadista Default Domain Policy), mis määrab kasutajate paroolide maksimaalseks elueaks (Maximum password age) 30 päeva." "MaxPasswordAge = 30" $resPwd.Det $resPwd.Status 1.0 $resPwd.Pts


# 22. KÄIVITAMISE KEELUD (Laiendatud otsingusõnad vastavalt kasutajaliidesele)
$AllGPOsXml = ""
$AllGposList = Get-GPO -All -ErrorAction SilentlyContinue
if ($AllGposList) {
    foreach ($g in $AllGposList) {
        $xmlRep = [xml](Get-GPOReport -Guid $g.Id -ReportType Xml -ErrorAction SilentlyContinue)
        if ($xmlRep) { 
            $AllGPOsXml += $xmlRep.InnerXml 
        }
    }
}

$headerRestr = "Keela kõigil kasutajatel, kes on OU-s Personal, Myyk, Juhtkond, Haldus või Toimetajad:"

# cmd
$chkCmd = ($AllGPOsXml -match "(?i)DisableCMD|Prevent access to the command prompt")
$cmdStatus = [bool]($chkCmd)
$cmdDet = if ($cmdStatus) { "Leitud GPO-st: <b style='color:green'>Jah (+0.5p)</b>" } else { "Seadistus: <b style='color:red'>Puudu (Ei leitud DisableCMD/Prevent access...)</b>" }
Add-Result "$headerRestr - cmd käivitamine" "DisableCMD leitud" $cmdDet $cmdStatus 0.5

# powershell
$chkPs = ($AllGPOsXml -match "(?i)powershell\.exe|powershell_ise\.exe|RestrictRun|DisallowRun|Don't run specified Windows applications|Run only specified Windows applications")
$psStatus = [bool]($chkPs)
$psDet = if ($psStatus) { "Leitud GPO-st: <b style='color:green'>Jah (+0.5p)</b>" } else { "Seadistus: <b style='color:red'>Puudu (Ei leitud DisallowRun/RestrictRun...)</b>" }
Add-Result "$headerRestr - PowerShelli käivitamine" "RestrictRun / DisallowRun powershell" $psDet $psStatus 0.5

# juhtpaneel
$chkCp = ($AllGPOsXml -match "(?i)NoControlPanel|RestrictCpl|Show only specified Control Panel items|Prohibit access to Control Panel|Prohibit access to the Control Panel")
$cpStatus = [bool]($chkCp)
$cpDet = if ($cpStatus) { "Leitud GPO-st: <b style='color:green'>Jah (+0.5p)</b>" } else { "Seadistus: <b style='color:red'>Puudu (Ei leitud RestrictCpl/NoControlPanel...)</b>" }
Add-Result "$headerRestr - juhtpaneeli avamine" "NoControlPanel / RestrictCpl leitud" $cpDet $cpStatus 0.5

# tegumihaldur
$chkTm = ($AllGPOsXml -match "(?i)DisableTaskMgr|Remove Task Manager")
$tmStatus = [bool]($chkTm)
$tmDet = if ($tmStatus) { "Leitud GPO-st: <b style='color:green'>Jah (+0.5p)</b>" } else { "Seadistus: <b style='color:red'>Puudu (Ei leitud DisableTaskMgr/Remove Task Manager...)</b>" }
Add-Result "$headerRestr - tegumihalduri käivitamine" "DisableTaskMgr leitud" $tmDet $tmStatus 0.5

# regedit
$chkReg = ($AllGPOsXml -match "(?i)DisableRegistryTools|Prevent access to registry editing tools")
$regStatus = [bool]($chkReg)
$regDet = if ($regStatus) { "Leitud GPO-st: <b style='color:green'>Jah (+0.5p)</b>" } else { "Seadistus: <b style='color:red'>Puudu (Ei leitud DisableRegistryTools/Prevent access...)</b>" }
Add-Result "$headerRestr - regedit.exe käivitamine" "DisableRegistryTools leitud" $regDet $regStatus 0.5


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
