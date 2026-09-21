#Requires -Version 5.1
<#
.SYNOPSIS
    Kontrollib Windows operatsioonisüsteemide halduse kordamistöö ülesandeid
    ja saadab tulemuse hindamisserverisse.

.DESCRIPTION
    Käivita AD1 peal Domain Admini õigustega PowerShellis.

    Uue hindamisserveri aadress:
        http://192.168.124.64:5010/api/submit

    Skript:
      - kontrollib uue töö 17 ülesannet;
      - arvutab punktid maksimaalselt 27 punktist;
      - loob ajutise JSON-faili C:\Temp\Õpilane.json;
      - saadab JSON-i hindamisserverisse;
      - kustutab kohaliku JSON-faili ainult siis, kui upload õnnestus.

    StudentName ja VNET küsitakse käivitamisel, kui neid parameetritena ei anta.

.EXAMPLE
    .\Check-Windows-Management.ps1

.EXAMPLE
    .\Check-Windows-Management.ps1 -StudentName "vnolvak" -VNET "50"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$StudentName,

    [Parameter(Mandatory = $false)]
    [string]$VNET,

    [Parameter(Mandatory = $false)]
    [string]$DashboardUrl = "http://192.168.124.64:5010/api/submit"
)

$ErrorActionPreference = "SilentlyContinue"
$global:Results = @()
$global:TotalPoints = 0

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$TempPath = "C:\Temp"
if (-not (Test-Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
}

function Clean-String {
    param([string]$InputString)

    if ([string]::IsNullOrWhiteSpace($InputString)) {
        return ""
    }

    return $InputString.ToLower().
        Replace("õ","o").
        Replace("ä","a").
        Replace("ö","o").
        Replace("ü","u").
        Replace(" ","").
        Replace(".","")
}

function Get-SimilarName {
    param(
        [string]$Expected,
        [array]$ActualList
    )

    if ($null -eq $ActualList) {
        return $null
    }

    foreach ($item in $ActualList) {
        if ($null -eq $item) { continue }

        $a = $item.ToString().ToLower()
        $e = $Expected.ToLower()

        if ($a -eq $e -or $a.Contains($e) -or $e.Contains($a)) {
            return $item
        }
    }

    return $null
}

function Convert-ToQuarterScore {
    <#
    Teeme iga ülesande punktid neljaks astmeks:
      0%   = 0%
      >0%  = vähemalt 25%
      >=37.5% = 50%
      >=62.5% = 75%
      100% = 100%

    Nii saab õpilane osaliselt tehtud ülesande eest 25%, 50% või 75%
    vastava ülesande maksimaalsest punktisummast.
    Näited:
      0.33 / 1  -> 0.25p
      0.50 / 1  -> 0.50p
      0.75 / 1  -> 0.75p
      1.00 / 1  -> 1.00p
      1.00 / 2  -> 0.50p
      1.50 / 2  -> 1.50p
      2.00 / 2  -> 2.00p
    #>
    param(
        [float]$Points,
        [float]$MaxPoints
    )

    if ($MaxPoints -le 0 -or $Points -le 0) {
        return 0
    }

    if ($Points -ge $MaxPoints) {
        return [math]::Round($MaxPoints, 2)
    }

    $ratio = $Points / $MaxPoints

    # Lävendid on valitud nii, et:
    # umbes 1/3 tehtud -> 25%
    # umbes 1/2 tehtud -> 50%
    # umbes 3/4 tehtud -> 75%
    # ainult 100% -> 100%
    if ($ratio -lt 0.375) {
        $level = 0.25
    }
    elseif ($ratio -lt 0.625) {
        $level = 0.50
    }
    elseif ($ratio -lt 1.0) {
        $level = 0.75
    }
    else {
        $level = 1.00
    }

    return [math]::Round($MaxPoints * $level, 2)
}

function Add-DetailedTask {
    param(
        [string]$Nimi,
        [float]$MaxP,
        [scriptblock]$Logic
    )

    $rawP = 0
    $fb = ""

    try {
        $TaskResult = & $Logic
        $rawP = [float]$TaskResult.Points
        $fb = [string]$TaskResult.Feedback
    }
    catch {
        $rawP = 0
        $fb = "SÜSTEEMNE VIGA: $($_.Exception.Message)"
    }

    if ($rawP -lt 0) { $rawP = 0 }
    if ($rawP -gt $MaxP) { $rawP = $MaxP }

    # Muudame toorpunktid neljaks hindamisastmeks:
    # 0 / 25% / 50% / 75% / 100%.
    $p = Convert-ToQuarterScore -Points $rawP -MaxPoints $MaxP

    $percentage = if ($MaxP -gt 0) {
        [math]::Round(($p / $MaxP) * 100, 0)
    } else {
        0
    }

    $global:TotalPoints += $p

    $global:Results += [PSCustomObject]@{
        Nimi      = $Nimi
        Korras    = ($p -ge $MaxP)
        Punktid   = $p
        Maksimum  = $MaxP
        Protsent  = $percentage
        Selgitus  = $fb
    }
}

function Test-OUPath {
    param(
        [string]$ChildName,
        [string]$ParentDN
    )

    if (-not $ParentDN) {
        return $false
    }

    $ou = Get-ADOrganizationalUnit `
        -Filter "Name -eq '$ChildName'" `
        -SearchBase $ParentDN `
        -ErrorAction SilentlyContinue

    return [bool]$ou
}

# ---------------------------------------------------------------------------
# SISENDID
# ---------------------------------------------------------------------------

if (-not $StudentName) {
    $StudentName = Read-Host "Sisesta õpilase kasutajanimi (NIMI)"
}

if (-not $VNET) {
    $VNET = Read-Host "Sisesta oma vnet number (XXX)"
}

$StudentName = Clean-String $StudentName

if (-not $VNET -or $VNET -notmatch '^\d{1,3}$') {
    Write-Host "HOIATUS: VNET ei ole korrektselt määratud. DHCP IP-vahemiku kontroll võib ebaõnnestuda." -ForegroundColor Yellow
}

$SafeName = if ($StudentName) { $StudentName } else { "opilane" }
$FullFilePath = Join-Path $TempPath "$SafeName.json"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " WINDOWS OPERATSIOONISÜSTEEMIDE HALDUSE KORDAMISTÖÖ" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Õpilane : $StudentName" -ForegroundColor Yellow
Write-Host "VNET    : $VNET" -ForegroundColor Yellow
Write-Host "Server  : $DashboardUrl" -ForegroundColor Yellow
Write-Host ""

# ---------------------------------------------------------------------------
# MOODULID
# ---------------------------------------------------------------------------

foreach ($ModuleName in @(
    "ActiveDirectory",
    "GroupPolicy",
    "DhcpServer",
    "WebAdministration",
    "Storage"
)) {
    if (Get-Module -ListAvailable -Name $ModuleName) {
        Import-Module $ModuleName -ErrorAction SilentlyContinue
    }
}

# ActiveDirectory moodul on selle kontrollskripti jaoks kriitiline.
# Kui moodulit ei ole, anname selge teate; üksik kontroll ei tohi kogu
# skripti lõpetada süsteemse veaga.
if (-not (Get-Command Get-ADOrganizationalUnit -ErrorAction SilentlyContinue)) {
    Write-Host "HOIATUS: ActiveDirectory PowerShelli moodulit / Get-ADOrganizationalUnit cmdletit ei leitud." -ForegroundColor Yellow
    Write-Host "Käivita skript AD1 peal või paigalda RSAT/AD DS haldustööriistad." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# DOMEEINIINFO
# ---------------------------------------------------------------------------

$Domain = $null
$DomainNetBIOS = $null
$DomainInfo = $null

try {
    $DomainInfo = Get-ADDomain -ErrorAction Stop
    $Domain = $DomainInfo.DNSRoot
    $DomainNetBIOS = $DomainInfo.NetBIOSName
}
catch {
    Write-Host "AD domeeni infot ei õnnestunud lugeda." -ForegroundColor Yellow
}

$TargetURL = if ($Domain) {
    "https://veebileht.$Domain"
} else {
    $null
}

# ---------------------------------------------------------------------------
# 1. AD JA DNS - 1p
# ---------------------------------------------------------------------------

Add-DetailedTask "1. AD ja DNS" 1 {
    $domainOk = $false
    $dcOk = $false
    $dnsOk = $false

    try {
        $d = Get-ADDomain -ErrorAction Stop
        $domainOk = $d.DNSRoot -match '\.local$'
    } catch {}

    try {
        $dcOk = ((Get-Service -Name NTDS -ErrorAction SilentlyContinue).Status -eq "Running")
    } catch {}

    try {
        $dnsOk = ((Get-Service -Name DNS -ErrorAction SilentlyContinue).Status -eq "Running")
    } catch {}

    if ($domainOk -and $dcOk -and $dnsOk) {
        return @{
            Points = 1
            Feedback = "Domeen $Domain on .local, AD DS ja DNS töötavad."
        }
    }

    return @{
        Points = 0
        Feedback = "Domeen: $Domain | AD DS: $dcOk | DNS: $dnsOk. Oodatud perenimi.local."
    }
}

# ---------------------------------------------------------------------------
# 2. KETAS F: + KAUSTAD - 1p
# ---------------------------------------------------------------------------

Add-DetailedTask "2. Ketas F: ja kaustad" 1 {
    if (-not (Test-Path "F:\")) {
        return @{
            Points = 0
            Feedback = "Ketas F: puudub."
        }
    }

    $required = @("STUFF", "WWW", "Kasutajad$")
    $found = @()
    $missing = @()

    foreach ($folder in $required) {
        if (Test-Path "F:\$folder") {
            $found += $folder
        } else {
            $missing += $folder
        }
    }

    # F: olemas annab 25% ning iga kolmest nõutud kaustast annab 25%.
    # Seega:
    #   ainult F:                  = 0.25p
    #   F: + 1 kaust              = 0.50p
    #   F: + 2 kausta             = 0.75p
    #   F: + 3 kausta             = 1.00p
    #
    # See vastab soovitud hindamisloogikale: tehtud osa eest saab
    # vastava osa punktidest, mitte ainult 0 või 1 punkti.
    $points = 0.25 + ($found.Count * 0.25)

    return @{
        Points = [math]::Round($points, 2)
        Feedback = "F: olemas. Leitud: $($found -join ', '). Puudu: $(if($missing){$missing -join ', '}else{'puuduvad'}). Punktid: $([math]::Round($points,2)) / 1."
    }
}

# ---------------------------------------------------------------------------
# 3. DHCP HKHK - 1p
# ---------------------------------------------------------------------------

Add-DetailedTask "3. DHCP skoop HKHK" 1 {
    try {
        $scope = Get-DhcpServerv4Scope -ErrorAction Stop |
            Where-Object { $_.Name -eq "HKHK" } |
            Select-Object -First 1

        if (-not $scope) {
            return @{
                Points = 0
                Feedback = "DHCP skoopi HKHK ei leitud."
            }
        }

        if ($VNET -match '^\d{1,3}$') {
            $expectedStart = "192.168.$VNET.100"
            $expectedEnd   = "192.168.$VNET.120"

            if ($scope.StartRange.ToString() -eq $expectedStart -and
                $scope.EndRange.ToString() -eq $expectedEnd) {
                return @{
                    Points = 1
                    Feedback = "HKHK skoop olemas ja vahemik on $expectedStart - $expectedEnd."
                }
            }

            return @{
                Points = 0.5
                Feedback = "HKHK skoop olemas, kuid vahemik on $($scope.StartRange) - $($scope.EndRange). Oodatud $expectedStart - $expectedEnd."
            }
        }

        return @{
            Points = 0.5
            Feedback = "HKHK skoop olemas: $($scope.StartRange) - $($scope.EndRange). VNET-i tõttu ei saanud vahemikku täielikult kontrollida."
        }
    }
    catch {
        return @{
            Points = 0
            Feedback = "DHCP kontroll ebaõnnestus: $($_.Exception.Message)"
        }
    }
}

# ---------------------------------------------------------------------------
# 4. KLIENTIDE DOMEENIGA LIITUMINE - 1p
# Uues juhendis nõutakse Arvuti1 ja Arvuti2.
# Arvuti3 olemasolu ei vähenda tulemust, sest töö juhendi punkt 4 seda ei nõua.
# ---------------------------------------------------------------------------

Add-DetailedTask "4. Arvuti1 ja Arvuti2 domeeniga liitumine" 1 {
    $p = 0
    $fb = @()

    foreach ($computerName in @("Arvuti1", "Arvuti2")) {
        $computer = Get-ADComputer -Filter "Name -eq '$computerName'" `
            -Properties DistinguishedName,Enabled `
            -ErrorAction SilentlyContinue

        if ($computer) {
            $p += 0.5
            $fb += "$computerName OK"
        } else {
            $fb += "$computerName PUUDU"
        }
    }

    return @{
        Points = $p
        Feedback = ($fb -join " | ")
    }
}

# ---------------------------------------------------------------------------
# 5. ARVUTID > STAFF/OFFICE - 1p
# ---------------------------------------------------------------------------

Add-DetailedTask "5. OU ARVUTID > STAFF/OFFICE" 1 {
    $ouArvutid = Get-ADOrganizationalUnit `
        -Filter "Name -eq 'ARVUTID'" `
        -ErrorAction SilentlyContinue

    if (-not $ouArvutid) {
        return @{
            Points = 0
            Feedback = "OU ARVUTID puudub."
        }
    }

    $staff = Get-ADOrganizationalUnit `
        -Filter "Name -eq 'STAFF'" `
        -SearchBase $ouArvutid.DistinguishedName `
        -ErrorAction SilentlyContinue

    $office = Get-ADOrganizationalUnit `
        -Filter "Name -eq 'OFFICE'" `
        -SearchBase $ouArvutid.DistinguishedName `
        -ErrorAction SilentlyContinue

    $c1 = Get-ADComputer -Filter "Name -eq 'Arvuti1'" `
        -Properties DistinguishedName `
        -ErrorAction SilentlyContinue

    $c2 = Get-ADComputer -Filter "Name -eq 'Arvuti2'" `
        -Properties DistinguishedName `
        -ErrorAction SilentlyContinue

    $c1Ok = $false
    $c2Ok = $false

    if ($c1 -and $staff) {
        $c1Ok = $c1.DistinguishedName -like "*$($staff.DistinguishedName)"
    }

    if ($c2 -and $office) {
        $c2Ok = $c2.DistinguishedName -like "*$($office.DistinguishedName)"
    }

    $p = 0
    $fb = @()

    if ($staff) {
        $p += 0.25
        $fb += "STAFF OU OK"
    } else {
        $fb += "STAFF OU PUUDU"
    }

    if ($office) {
        $p += 0.25
        $fb += "OFFICE OU OK"
    } else {
        $fb += "OFFICE OU PUUDU"
    }

    if ($c1Ok) {
        $p += 0.25
        $fb += "Arvuti1 STAFF-is"
    } else {
        $fb += "Arvuti1 ei ole STAFF-is"
    }

    if ($c2Ok) {
        $p += 0.25
        $fb += "Arvuti2 OFFICE-s"
    } else {
        $fb += "Arvuti2 ei ole OFFICE-s"
    }

    return @{
        Points = $p
        Feedback = ($fb -join " | ")
    }
}

# ---------------------------------------------------------------------------
# 6. KASUTAJAD > LEKTORID/TUDENGID/VEEB - 1p
# ---------------------------------------------------------------------------

Add-DetailedTask "6. OU KASUTAJAD" 1 {
    $ouKasutajad = Get-ADOrganizationalUnit `
        -Filter "Name -eq 'KASUTAJAD'" `
        -ErrorAction SilentlyContinue

    if (-not $ouKasutajad) {
        return @{
            Points = 0
            Feedback = "OU KASUTAJAD puudub."
        }
    }

    $subOUs = @("LEKTORID", "TUDENGID", "VEEB")
    $found = @()
    $missing = @()

    foreach ($name in $subOUs) {
        $ou = Get-ADOrganizationalUnit `
            -Filter "Name -eq '$name'" `
            -SearchBase $ouKasutajad.DistinguishedName `
            -ErrorAction SilentlyContinue

        if ($ou) {
            $found += $name
        } else {
            $missing += $name
        }
    }

    $points = $found.Count / 3

    return @{
        Points = $points
        Feedback = "Leitud: $($found -join ', '). Puudu: $(if($missing){$missing -join ', '}else{'puuduvad'})."
    }
}

# ---------------------------------------------------------------------------
# 7. KASUTAJAD JA GRUPID - 2p
# ---------------------------------------------------------------------------

Add-DetailedTask "7. Kasutajad ja grupid" 2 {
    $p = 0
    $fb = @()

    $lektoridGroup = Get-ADGroup `
        -Filter "Name -eq 'Lektorid'" `
        -ErrorAction SilentlyContinue

    $tudengidGroup = Get-ADGroup `
        -Filter "Name -eq 'Tudengid'" `
        -ErrorAction SilentlyContinue

    $oj1 = Get-ADUser `
        -Filter "SamAccountName -eq 'oppejoud1'" `
        -Properties DistinguishedName `
        -ErrorAction SilentlyContinue

    $oj2 = Get-ADUser `
        -Filter "SamAccountName -eq 'oppejoud2'" `
        -Properties DistinguishedName `
        -ErrorAction SilentlyContinue

    $t1 = Get-ADUser `
        -Filter "SamAccountName -eq 'tudeng1'" `
        -Properties LogonHours,DistinguishedName `
        -ErrorAction SilentlyContinue

    $t2 = Get-ADUser `
        -Filter "SamAccountName -eq 'tudeng2'" `
        -Properties LogonHours,DistinguishedName `
        -ErrorAction SilentlyContinue

    # 0.5p grupid
    if ($lektoridGroup) {
        $p += 0.25
        $fb += "Lektorid grupp OK"
    } else {
        $fb += "Lektorid grupp PUUDU"
    }

    if ($tudengidGroup) {
        $p += 0.25
        $fb += "Tudengid grupp OK"
    } else {
        $fb += "Tudengid grupp PUUDU"
    }

    # 0.5p lektorite kasutajad + grupiliikmelisus
    if ($lektoridGroup -and $oj1 -and $oj2) {
        try {
            $members = Get-ADGroupMember -Identity $lektoridGroup |
                Select-Object -ExpandProperty SamAccountName

            if ($members -contains "oppejoud1" -and $members -contains "oppejoud2") {
                $p += 0.5
                $fb += "oppejoud1/oppejoud2 Lektorid grupis"
            } else {
                $fb += "oppejoud1/oppejoud2 grupis puudulik"
            }
        } catch {
            $fb += "Lektorid grupiliikmelisust ei saanud kontrollida"
        }
    } else {
        $fb += "Lektorite kasutajad puuduvad"
    }

    # 1p tudengid + grupiliikmelisus + logonHours
    if ($tudengidGroup -and $t1 -and $t2) {
        try {
            $members = Get-ADGroupMember -Identity $tudengidGroup |
                Select-Object -ExpandProperty SamAccountName

            $groupOk = ($members -contains "tudeng1" -and $members -contains "tudeng2")

            if ($groupOk) {
                $p += 0.5
                $fb += "tudeng1/tudeng2 Tudengid grupis"
            } else {
                $fb += "tudeng1/tudeng2 grupis puudulik"
            }

            # logonHours on AD-s 21-baidine bitimask.
            # Täpset ajakava tõlgendatakse allpool; kontrollime, et piirang
            # ei oleks lihtsalt "kõik tunnid lubatud".
            $restricted1 = $false
            $restricted2 = $false

            if ($t1.LogonHours) {
                $restricted1 = ($t1.LogonHours | Where-Object { $_ -ne 255 }).Count -gt 0
            }

            if ($t2.LogonHours) {
                $restricted2 = ($t2.LogonHours | Where-Object { $_ -ne 255 }).Count -gt 0
            }

            if ($restricted1 -and $restricted2) {
                $p += 0.5
                $fb += "Mõlemal tudengil on logonHours piirang"
            } else {
                $fb += "Tudengite E-R 08:00-19:00 piirang ei ole automaatselt kinnitatud"
            }
        } catch {
            $fb += "Tudengite grupi/logonHours kontroll ebaõnnestus"
        }
    } else {
        $fb += "Tudengite kasutajad või grupp puuduvad"
    }

    return @{
        Points = $p
        Feedback = ($fb -join " | ")
    }
}

# ---------------------------------------------------------------------------
# GPO ABI
# ---------------------------------------------------------------------------

function Test-GpoExistsAndLinked {
    param(
        [string]$GpoName,
        [string]$ExpectedLinkOuNameContains = $null
    )

    $gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue

    if (-not $gpo) {
        return @{
            Exists = $false
            Linked = $false
            Report = $null
        }
    }

    $report = $null
    try {
        [xml]$report = Get-GPOReport `
            -Guid $gpo.Id `
            -ReportType Xml `
            -ErrorAction Stop
    } catch {}

    $linked = $false

    if ($report -and $report.GPO.LinksTo) {
        $links = @($report.GPO.LinksTo)

        if ($ExpectedLinkOuNameContains) {
            foreach ($link in $links) {
                if ($link.SOMPath -match [regex]::Escape($ExpectedLinkOuNameContains)) {
                    $linked = $true
                }
            }
        } else {
            $linked = $true
        }
    }

    return @{
        Exists = $true
        Linked = [bool]$linked
        Report = $report
    }
}

# ---------------------------------------------------------------------------
# 8. TAUSTAPILDI GPO - 2p
# ---------------------------------------------------------------------------

Add-DetailedTask "8. GPO_Taustapildid" 2 {
    $r = Test-GpoExistsAndLinked -GpoName "GPO_Taustapildid"

    if (-not $r.Exists) {
        return @{
            Points = 0
            Feedback = "GPO_Taustapildid puudub."
        }
    }

    $p = 1
    $fb = @("GPO_Taustapildid olemas.")

    if ($r.Linked) {
        $p += 0.5
        $fb += "GPO on lingitud."
    } else {
        $fb += "GPO lingi ei tuvastatud."
    }

    # Kontrollime, et STUFF eksisteerib ning selle ACL on loetav.
    # Erinevate lektor/tudeng piltide tegelik GPO seadistus vajab osaliselt käsitsi kontrolli.
    if (Test-Path "F:\STUFF") {
        try {
            $acl = Get-Acl "F:\STUFF"
            if ($acl) {
                $p += 0.5
                $fb += "F:\STUFF ACL loetav."
            }
        } catch {
            $fb += "F:\STUFF ACL-i ei saanud lugeda."
        }
    } else {
        $fb += "F:\STUFF puudub."
    }

    return @{
        Points = $p
        Feedback = ($fb -join " | ") + " Eraldi lektor/tudeng taustapiltide ning tudengite juurdepääsu lõplik kontroll vajab vajadusel käsitsi ülevaatust."
    }
}

# ---------------------------------------------------------------------------
# 9. FOLDER REDIRECTION - 2p
# ---------------------------------------------------------------------------

Add-DetailedTask "9. GPO_Folder_Redirection" 2 {
    $r = Test-GpoExistsAndLinked -GpoName "GPO_Folder_Redirection"

    $shareOk = $false
    try {
        $shareOk = [bool](Get-SmbShare -Name "Kasutajad$" -ErrorAction SilentlyContinue)
    } catch {}

    $sharePathOk = $false
    if ($shareOk) {
        try {
            $share = Get-SmbShare -Name "Kasutajad$" -ErrorAction SilentlyContinue
            if ($share.Path -eq "F:\Kasutajad$") {
                $sharePathOk = $true
            }
        } catch {}
    }

    if (-not $r.Exists) {
        return @{
            Points = 0
            Feedback = "GPO_Folder_Redirection puudub. Kasutajad$ share: $shareOk."
        }
    }

    $p = 0
    $fb = @()

    if ($r.Linked) {
        $p += 1
        $fb += "GPO olemas ja lingitud."
    } else {
        $fb += "GPO olemas, kuid linki ei tuvastatud."
    }

    if ($sharePathOk) {
        $p += 1
        $fb += "Kasutajad$ jagatud F:\Kasutajad$."
    } elseif ($shareOk) {
        $p += 0.5
        $fb += "Kasutajad$ share olemas, kuid sihtteed ei saanud kinnitada."
    } else {
        $fb += "Kasutajad$ share puudub."
    }

    return @{
        Points = $p
        Feedback = ($fb -join " | ") + " Desktop/Documents Folder Redirection tegelikud GPO sätted vajavad vajadusel käsitsi kontrolli."
    }
}

# ---------------------------------------------------------------------------
# 10. SOFTWARE GPO-d - 2p
# ---------------------------------------------------------------------------

Add-DetailedTask "10. GPO Software 7zip ja Chrome" 2 {
    $r7 = Test-GpoExistsAndLinked -GpoName "GPO_Software_7zip"
    $rc = Test-GpoExistsAndLinked -GpoName "GPO_Software_Chrome"

    $p = 0
    $fb = @()

    if ($r7.Exists) {
        $p += 0.5
        $fb += "GPO_Software_7zip olemas"
        if ($r7.Linked) {
            $p += 0.5
            $fb += "7zip GPO lingitud"
        } else {
            $fb += "7zip GPO link puudub"
        }
    } else {
        $fb += "GPO_Software_7zip puudub"
    }

    if ($rc.Exists) {
        $p += 0.5
        $fb += "GPO_Software_Chrome olemas"
        if ($rc.Linked) {
            $p += 0.5
            $fb += "Chrome GPO lingitud"
        } else {
            $fb += "Chrome GPO link puudub"
        }
    } else {
        $fb += "GPO_Software_Chrome puudub"
    }

    return @{
        Points = $p
        Feedback = ($fb -join " | ") + " MSI pakettide tegelik seadistus vajab vajadusel käsitsi kontrolli."
    }
}

# ---------------------------------------------------------------------------
# 11. CHROME ADMX + KODULEHT - 2p
# ---------------------------------------------------------------------------
 
Add-DetailedTask "11. GPO_Chrome_Settings" 2 {
    $r = Test-GpoExistsAndLinked -GpoName "GPO_Chrome_Settings"
 
    # Kontrollime chrome.admx olemasolu ainult kohalikus PolicyDefinitions
    # kaustas (C:\Windows\PolicyDefinitions) - domeeni Central Store'i
    # (SYSVOL) EI kontrollita.
    $admxPath = "$env:SystemRoot\PolicyDefinitions\chrome.admx"
    $admxOk = Test-Path $admxPath
 
    $homepageOk = $false
 
    try {
        $val = Get-GPRegistryValue `
            -Name "GPO_Chrome_Settings" `
            -Key "HKLM\Software\Policies\Google\Chrome" `
            -ValueName "HomepageLocation" `
            -ErrorAction SilentlyContinue
 
        if ($val -and $val.Value -eq "https://www.hkhk.edu.ee") {
            $homepageOk = $true
        }
    } catch {}
 
    $p = 0
    $fb = @()
 
    if ($r.Exists -and $r.Linked) {
        $p += 0.5
        $fb += "GPO olemas ja lingitud"
    } elseif ($r.Exists) {
        $p += 0.25
        $fb += "GPO olemas, kuid linki ei tuvastatud"
    } else {
        $fb += "GPO puudub"
    }
 
    if ($admxOk) {
        $p += 0.75
        $fb += "chrome.admx leitud kaustast $admxPath"
    } else {
        $fb += "chrome.admx ei leitud kaustast $admxPath"
    }
 
    if ($homepageOk) {
        $p += 0.75
        $fb += "Koduleht on https://www.hkhk.edu.ee"
    } else {
        $fb += "Kodulehe registriväärtust ei õnnestunud kinnitada"
    }
 
    return @{
        Points = $p
        Feedback = ($fb -join " | ")
    }
}
# ---------------------------------------------------------------------------
# 12. GPO_autentimine - 1p
# ---------------------------------------------------------------------------

Add-DetailedTask "12. GPO_autentimine" 1 {
    $r = Test-GpoExistsAndLinked `
        -GpoName "GPO_autentimine" `
        -ExpectedLinkOuNameContains "OFFICE"

    $captionOk = $false
    $textOk = $false

    try {
        $caption = Get-GPRegistryValue `
            -Name "GPO_autentimine" `
            -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
            -ValueName "LegalNoticeCaption" `
            -ErrorAction SilentlyContinue

        $text = Get-GPRegistryValue `
            -Name "GPO_autentimine" `
            -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
            -ValueName "LegalNoticeText" `
            -ErrorAction SilentlyContinue

        if ($caption -and $caption.Value -eq "Hoiatus!") {
            $captionOk = $true
        }

        if ($text -and $text.Value -eq "Ainult lubatud kasutajatele!") {
            $textOk = $true
        }
    } catch {}

    if ($r.Exists -and $r.Linked -and $captionOk -and $textOk) {
        return @{
            Points = 1
            Feedback = "GPO_autentimine on olemas, lingitud OFFICE OU-ga ning teavituse tekst/pealkiri on õiged."
        }
    }

    $fb = @(
        "GPO olemas: $($r.Exists)"
        "OFFICE link: $($r.Linked)"
        "Pealkiri Hoiatus!: $captionOk"
        "Tekst Ainult lubatud kasutajatele!: $textOk"
    )

    return @{
        Points = 0
        Feedback = ($fb -join " | ")
    }
}

# ---------------------------------------------------------------------------
# 13. AD2 TEINE DC - 2p
# ---------------------------------------------------------------------------

Add-DetailedTask "13. Teine DC AD2" 2 {
    try {
        $dcs = @(Get-ADDomainController -Filter * -ErrorAction Stop)
        $ad2 = $dcs | Where-Object { $_.Name -eq "AD2" }

        if ($dcs.Count -ge 2 -and $ad2) {
            return @{
                Points = 2
                Feedback = "Domeenist leiti $($dcs.Count) domeenikontrollerit, sh AD2."
            }
        }

        if ($dcs.Count -ge 2) {
            return @{
                Points = 1
                Feedback = "Leiti $($dcs.Count) DC-d, kuid nimega AD2 DC-d ei leitud."
            }
        }

        return @{
            Points = 0
            Feedback = "AD2 ei ole tuvastatav teise domeenikontrollerina. DC-de arv: $($dcs.Count)."
        }
    }
    catch {
        return @{
            Points = 0
            Feedback = "AD2 kontroll ebaõnnestus: $($_.Exception.Message)"
        }
    }
}

# ---------------------------------------------------------------------------
# 14. DHCP FAILOVER - 1p
# ---------------------------------------------------------------------------

Add-DetailedTask "14. DHCP Failover" 1 {
    try {
        $failovers = @(Get-DhcpServerv4Failover -ErrorAction Stop)

        $relevant = $failovers | Where-Object {
            $_.PartnerServer -match "(?i)AD2" -and
            $_.Mode.ToString() -match "(?i)LoadBalance"
        }

        if ($relevant) {
            $scopeInfo = $relevant | ForEach-Object {
                "Partner=$($_.PartnerServer), Mode=$($_.Mode), Scope=$($_.ScopeId)"
            }

            return @{
                Points = 1
                Feedback = "DHCP Failover AD2-ga režiimis LoadBalance leitud. $($scopeInfo -join ' | ')"
            }
        }

        return @{
            Points = 0
            Feedback = "AD2-ga LoadBalance DHCP Failover suhet ei leitud."
        }
    }
    catch {
        return @{
            Points = 0
            Feedback = "DHCP Failover kontroll ebaõnnestus: $($_.Exception.Message)"
        }
    }
}

# ---------------------------------------------------------------------------
# 15. IIS + WORDPRESS - 2p
# ---------------------------------------------------------------------------

Add-DetailedTask "15. IIS ja WordPress" 2 {
    $domain = $Domain

    if (-not $domain) {
        return @{
            Points = 0
            Feedback = "Domeeni ei õnnestunud tuvastada."
        }
    }

    $expectedName = "veebileht.$domain"
    $expectedPath = "F:\WWW\veebileht.$domain"

    $site = $null

    try {
        $site = Get-Website -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq $expectedName -or
                $_.PhysicalPath -eq $expectedPath
            } |
            Select-Object -First 1
    } catch {}

    $sitePath = $null
    if ($site) {
        $sitePath = $site.PhysicalPath
    } elseif (Test-Path $expectedPath) {
        $sitePath = $expectedPath
    }

    $wpConfigPath = $null
    $wpConfigOk = $false
    $dbNameOk = $false
    $dbUserOk = $false
    $dbPassOk = $false

    if ($sitePath) {
        $wpConfigPath = Join-Path $sitePath "wp-config.php"

        if (Test-Path $wpConfigPath) {
            $wpConfigOk = $true

            try {
                $content = Get-Content $wpConfigPath -Raw -ErrorAction Stop

                $dbNameOk = $content -match "DB_NAME\s*,\s*['""]wp_kordamine['""]"
                $dbUserOk = $content -match "DB_USER\s*,\s*['""]wpuser['""]"
                $dbPassOk = $content -match "DB_PASSWORD\s*,\s*['""]Passw0rd!['""]"
            } catch {}
        }
    }

    $p = 0
    $fb = @()

    if ($site) {
        $p += 1
        $fb += "IIS sait leitud: $($site.Name), path: $($site.PhysicalPath)"
    } else {
        $fb += "IIS saiti $expectedName / F:\WWW\ alt ei leitud"
    }

    if ($wpConfigOk) {
        if ($dbNameOk -and $dbUserOk -and $dbPassOk) {
            $p += 1
            $fb += "wp-config.php leitud ja AB/wpuser/parool vastavad"
        } else {
            $p += 0.5
            $fb += "wp-config.php leitud, kuid AB/wpuser/parooli väärtused ei vasta täielikult"
        }
    } else {
        $fb += "wp-config.php puudub"
    }

    return @{
        Points = $p
        Feedback = ($fb -join " | ")
    }
}

# ---------------------------------------------------------------------------
# 16. HTTPS + AD CS - 2p
# ---------------------------------------------------------------------------

Add-DetailedTask "16. HTTPS ja AD CS" 2 {
    $adcsInstalled = $false
    $httpsBinding = $false
    $certInfo = @()

    try {
        $feature = Get-WindowsFeature -Name AD-Certificate -ErrorAction SilentlyContinue
        $adcsInstalled = [bool]($feature -and $feature.Installed)
    } catch {}

    try {
        $bindings = Get-Website -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Bindings.Collection } |
            Where-Object { $_.protocol -eq "https" }

        $httpsBinding = [bool]$bindings
    } catch {}

    # Proovime lisaks kontrollida, kas LocalMachine My poes leidub veebiserveri
    # sertifikaat, millel on sobiv subjekt/SAN. Seda ei loeta eraldi punktiks,
    # vaid kasutatakse tagasisides.
    try {
        $certs = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue

        foreach ($cert in $certs) {
            if ($cert.Subject -match [regex]::Escape("veebileht.$Domain") -or
                $cert.DnsNameList.Unicode -contains "veebileht.$Domain") {
                $certInfo += $cert.Subject
            }
        }
    } catch {}

    $p = 0
    $fb = @()

    if ($adcsInstalled) {
        $p += 1
        $fb += "AD CS Certification Authority roll on paigaldatud"
    } else {
        $fb += "AD CS Certification Authority roll puudub"
    }

    if ($httpsBinding) {
        $p += 1
        $fb += "IIS HTTPS binding olemas"
    } else {
        $fb += "IIS HTTPS binding puudub"
    }

    if ($certInfo.Count -gt 0) {
        $fb += "Sobiva veebisertifikaadi subjekt leitud"
    } else {
        $fb += "Sobivat sertifikaati LocalMachine\My poest ei tuvastatud"
    }

    return @{
        Points = $p
        Feedback = ($fb -join " | ") + " AD CS usaldusahelat kliendis tuleb vajadusel käsitsi kontrollida."
    }
}

# ---------------------------------------------------------------------------
# 17. WORDPRESS AD AUTENTIMINE - 2p
# ---------------------------------------------------------------------------

Add-DetailedTask "17. WordPress AD autentimine" 2 {
    $expectedPath = $null

    if ($Domain) {
        $expectedPath = "F:\WWW\veebileht.$Domain\wp-content\plugins"
    }

    $pluginNames = @()
    $foundPlugin = $false

    if ($expectedPath -and (Test-Path $expectedPath)) {
        try {
            $pluginNames = @(
                Get-ChildItem $expectedPath -Directory -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.Name -match "(?i)ldap|active.?directory|ad.?auth|wordpress.?ldap"
                    } |
                    Select-Object -ExpandProperty Name
            )

            $foundPlugin = $pluginNames.Count -gt 0
        } catch {}
    }

    $veebUsers = @()
    try {
        $veebUsers = @(
            Get-ADUser -Filter {
                SamAccountName -eq "Peatoimetaja" -or
                SamAccountName -eq "ToimetajaAbi"
            } -Properties DistinguishedName -ErrorAction SilentlyContinue
        )
    } catch {}

    $veebUsersOk = ($veebUsers.Count -ge 2)

    # Kontrollime, kas mõlemad kasutajad on tegelikult VEEB OU all.
    $veebOu = $null
    $veebOuUsersOk = $false

    if (Get-Command Get-ADOrganizationalUnit -ErrorAction SilentlyContinue) {
        $veebOu = Get-ADOrganizationalUnit `
            -Filter "Name -eq 'VEEB'" `
            -ErrorAction SilentlyContinue

        if ($veebOu -and $veebUsers.Count -ge 2) {
            $veebOuUsersOk = $true

            foreach ($u in $veebUsers) {
                if ($u.DistinguishedName -notlike "*$($veebOu.DistinguishedName)") {
                    $veebOuUsersOk = $false
                }
            }
        }
    }

    $p = 0
    $fb = @()

    if ($foundPlugin) {
        $p += 1
        $fb += "AD/LDAP suunaline WordPressi plugin leitud: $($pluginNames -join ', ')"
    } else {
        $fb += "AD/LDAP WordPressi pluginat ei tuvastatud"
    }

    if ($veebOuUsersOk) {
        $p += 1
        $fb += "Peatoimetaja ja ToimetajaAbi on VEEB OU-s"
    } elseif ($veebUsersOk) {
        $p += 0.5
        $fb += "Peatoimetaja ja ToimetajaAbi on AD-s, kuid VEEB OU paiknemist ei saanud kinnitada"
    } else {
        $fb += "Peatoimetaja/ToimetajaAbi puuduvad või mõlemat ei leitud"
    }

    return @{
        Points = $p
        Feedback = ($fb -join " | ") + " Tegelik WordPressi sisselogimine domeenikasutajaga vajab lõplikuks kinnitamiseks käsitsi testimist."
    }
}

# ---------------------------------------------------------------------------
# HINDE ARVUTAMINE
# Uue töö maksimaalne punktisumma on 27.
# Iga ülesande tulemus on enne kogusumma arvutamist normaliseeritud
# astmetele 0%, 25%, 50%, 75% või 100%.
# Juhendis antud hindelävendid:
#   23-27 = 5
#   18-22 = 4
#   13-17 = 3
#   <13   = 2
# ---------------------------------------------------------------------------

$global:TotalPoints = [math]::Round([float]$global:TotalPoints, 2)

$Hinne = if ($global:TotalPoints -ge 23) {
    "5"
}
elseif ($global:TotalPoints -ge 18) {
    "4"
}
elseif ($global:TotalPoints -ge 13) {
    "3"
}
else {
    "2"
}

# ---------------------------------------------------------------------------
# KOKKUVÕTE KONSOOLIS
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Gray
Write-Host " KOKKUVÕTE: $StudentName" -ForegroundColor Yellow
Write-Host " PUNKTID: $global:TotalPoints / 27" -ForegroundColor Yellow
Write-Host " HINNE:   $Hinne" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Gray

foreach ($res in $global:Results) {
    $color = if ($res.Korras) { "Green" } else { "Red" }
    $sym = if ($res.Korras) { "OK" } else { "FAIL" }

    Write-Host ""
    Write-Host "[$sym] $($res.Nimi): $($res.Punktid) / $($res.Maksimum)p ($($res.Protsent)%)" -ForegroundColor $color
    Write-Host "      $($res.Selgitus)" -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# JSON PAYLOAD
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# JSON PAYLOAD
#
# NB! Uus Flaski dashboard /api/submit kasutab kontrolltulemuste puhul
# struktuuri:
#   student, hostname, generated_at, checks
# ning iga check kasutab välju:
#   id, category, name, max_points, points, status, message
#
# Seetõttu EI saadeta siin enam vana skripti välju Opilane/Kontrollid.
# ---------------------------------------------------------------------------

$ApiChecks = @()

foreach ($r in $global:Results) {
    $ApiChecks += [PSCustomObject]@{
        id         = (Clean-String $r.Nimi)
        category   = ""
        name       = [string]$r.Nimi
        max_points = [float]$r.Maksimum
        points     = [float]$r.Punktid
        percentage = [int]$r.Protsent
        # Osaliselt tehtud töö on samuti automaatselt hinnatud.
        # Dashboard ei tohi käsitleda warning-staatust kui "kontrolli käsitsi".
        # Seetõttu:
        #   0%        -> fail
        #   25/50/75% -> pass
        #   100%      -> pass
        status     = if ($r.Punktid -gt 0) {
            "pass"
        }
        else {
            "fail"
        }
        message    = [string]$r.Selgitus
    }
}

$PayloadObj = [PSCustomObject]@{
    student      = $StudentName
    hostname     = $env:COMPUTERNAME
    generated_at = (Get-Date).ToString("o")
    checks       = $ApiChecks
}

$JsonData = $PayloadObj | ConvertTo-Json -Depth 10

# ---------------------------------------------------------------------------
# SALVESTA AJUTINE JSON
# ---------------------------------------------------------------------------

try {
    $JsonData | Set-Content -Path $FullFilePath -Encoding UTF8 -Force

    Write-Host ""
    Write-Host "JSON loodud: $FullFilePath" -ForegroundColor Cyan
}
catch {
    Write-Host ""
    Write-Host "JSON faili loomine ebaõnnestus: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# ÜLESLAADIMINE SERVERISSE
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "Laen tulemuse serverisse: $DashboardUrl" -ForegroundColor Cyan

$UploadSucceeded = $false
$response = $null

try {
    Write-Host "POST $DashboardUrl" -ForegroundColor Gray

    $response = Invoke-RestMethod `
        -Uri $DashboardUrl `
        -Method Post `
        -Body $JsonData `
        -ContentType "application/json; charset=utf-8" `
        -TimeoutSec 20 `
        -ErrorAction Stop

    $UploadSucceeded = $true

    Write-Host "ANDMED SAADETUD HINDAMISSERVERISSE." -ForegroundColor Green

    if ($response) {
        try {
            Write-Host "Serveri vastus: $($response | ConvertTo-Json -Compress -Depth 5)" -ForegroundColor Gray
        } catch {}
    }
}
catch {
    Write-Host ""
    Write-Host "VIGA: saatmine ebaõnnestus." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "JSON-fail jäetakse alles: $FullFilePath" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# JSON KUSTUTAMINE AINULT EDUKA UPLOAD-I KORRAL
# ---------------------------------------------------------------------------

if ($UploadSucceeded) {
    try {
        if (Test-Path $FullFilePath) {
            Remove-Item $FullFilePath -Force -ErrorAction Stop
            Write-Host "Kohalik JSON-fail kustutatud: $FullFilePath" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Hoiatus: JSON saadeti edukalt, kuid lokaalset faili ei õnnestunud kustutada: $FullFilePath" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Kontroll lõpetatud. Osalised tulemused hinnatakse automaatselt 25% / 50% / 75% / 100% astmetena." -ForegroundColor Cyan
