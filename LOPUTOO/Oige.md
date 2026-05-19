#### Kui töö valmis, siis kopeeri see Powershelli skript ja läbi Powershell ISE salvesta see enda arvutisse  kausta **C:\Temp** nimega **Kontroll.ps1 **ja käivita ese Powershell ISE rakenduses ####

----

### Täielik ja detailne kontrollskript: `Kontroll.ps1`

```powershell
# --- 0. ETTEVALMISTUS JA MOODULID ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Import-Module ActiveDirectory, GroupPolicy, DhcpServer, WebAdministration -ErrorAction SilentlyContinue

$TempPath = "C:\Temp"
if (!(Test-Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
}

# --- 1. SISEND ---
$RawName = Read-Host "Sisesta oma nimi (Eesnimi Perekonnanimi)"
$VNET = Read-Host "Sisesta oma vnet number (XXX)"
$ServerIP = "192.168.124.64"

$SafeName = $RawName.ToLower().Replace(" ","").Replace("ä","a").Replace("ö","o").Replace("ü","u").Replace("õ","o")
$FileName = "$SafeName.json"
$FullFilePath = Join-Path $TempPath $FileName

$Results = @()
$TotalPoints = 0

# --- 2. ABI FUNKTSIOONID ---
function Get-SimilarName {
    param([string]$Expected, [array]$ActualList)
    if ($null -eq $ActualList) { return $null }

    foreach ($item in $ActualList) {
        if ($item.ToLower().Contains($Expected.ToLower()) -or $Expected.ToLower().Contains($item.ToLower())) {
            return $item
        }
    }
    return $null
}

function Add-DetailedTask {
    param([string]$Nimi, [float]$MaxP, [scriptblock]$Logic)

    $p = 0
    $fb = ""

    try {
        $r = &$Logic
        $p = [math]::Round([float]$r.Points, 2)
        $fb = $r.Feedback
    }
    catch {
        $p = 0
        $fb = "❌ VIGA: $($_.Exception.Message)"
    }

    $global:TotalPoints += $p

    $global:Results += [PSCustomObject]@{
        Nimi=$Nimi
        Korras=$p -ge $MaxP
        Punktid=$p
        Selgitus=$fb
    }
}

Write-Host "`n--- ANALÜÜS ALGAB (vnet $VNET) ---" -ForegroundColor Cyan

# --- 1. AD ---
Add-DetailedTask "AD ja DNS" 1 {
    $d = (Get-ADDomain).DNSRoot
    if ($d -like "*.local") {
        return @{Points=1; Feedback="✅ $d OK"}
    }
    return @{Points=0; Feedback="❌ vale domeen: $d"}
}

# --- 2. DISK ---
Add-DetailedTask "F: struktuur" 1 {
    $p = 0
    $fb = @()

    if (Test-Path "F:") {
        $p += 0.4; $fb += "F olemas"

        foreach ($x in @("STUFF","WWW","Kasutajad$")) {
            if (Test-Path "F:\$x") {
                $p += 0.2; $fb += "$x OK"
            } else {
                $fb += "$x puudu"
            }
        }
    } else {
        $fb += "F puudub"
    }

    return @{Points=$p; Feedback=($fb -join ", ")}
}

# --- 3. DHCP ---
Add-DetailedTask "DHCP HKHK" 1 {
    $s = Get-DhcpServerv4Scope | Where-Object Name -like "*HKHK*"
    $target = "192.168.$VNET.100"

    if ($s) {
        if ($s.StartRange -eq $target) {
            return @{Points=1; Feedback="✅ $target OK"}
        }
        return @{Points=0.5; Feedback="⚠️ vale algus $($s.StartRange)"}
    }

    return @{Points=0; Feedback="❌ puudub"}
}

# --- 4. DOMAIN JOIN ---
Add-DetailedTask "Domain Join" 1 {
    $p = 0
    $fb = @()

    foreach ($c in @("Arvuti1","Arvuti2")) {
        if (Get-ADComputer -Filter "Name -eq '$c'" -ErrorAction SilentlyContinue) {
            $p += 0.5; $fb += "$c OK"
        } else {
            $fb += "$c puudu"
        }
    }

    return @{Points=$p; Feedback=($fb -join ", ")}
}

# --- 5. OU ---
Add-DetailedTask "OU struktuur" 1 {
    $ous = Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty Name
    $found = 0
    $fb = @()

    foreach ($x in @("LEKTORID","TUDENGID","VEEB")) {
        if (Get-SimilarName $x $ous) {
            $found++
            $fb += "$x OK"
        } else {
            $fb += "$x puudu"
        }
    }

    return @{Points=($found/3); Feedback=($fb -join ", ")}
}

# --- 6. GPO BASIC ---
Add-DetailedTask "GPO basic" 2 {
    $g = Get-GPO -All | Select-Object -ExpandProperty DisplayName

    $z = Get-SimilarName "7zip" $g
    $c = Get-SimilarName "Chrome" $g

    $p = 0
    if ($z) { $p++ }
    if ($c) { $p++ }

    return @{Points=$p; Feedback="7zip: $(if($z){'OK'}else{'PUUDUB'}) | Chrome: $(if($c){'OK'}else{'PUUDUB'})"}
}

# --- 7. HTTPS FIXED ---
Add-DetailedTask "HTTPS" 2 {

    $points = 0
    $fb = @()

    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue

        $https = Get-WebBinding | Where-Object protocol -eq "https"

        if ($https) {
            $points += 1
            $fb += "HTTPS olemas"

            if ($https.bindingInformation -match ":443:") {
                $points += 0.5
                $fb += "443 OK"
            }
        }
        else {
            $fb += "HTTPS puudub"
        }

        try {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

            $r = Invoke-WebRequest -Uri "https://localhost/wp-login.php" -UseBasicParsing -TimeoutSec 10

            if ($r.StatusCode -eq 200) {
                $points += 0.5
                $fb += "WP HTTPS OK"
            }
        }
        catch {
            $fb += "WP HTTPS ei tööta"
        }
    }
    catch {
        $fb += $_.Exception.Message
    }

    return @{Points=$points; Feedback=($fb -join " | ")}
}

# --- 8. WP + LDAP FIXED ---
Add-DetailedTask "WP + LDAP" 2 {

    $points = 0
    $fb = @()

    $wpPath = "F:\WWW"

    try {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

        try {
            $r = Invoke-WebRequest -Uri "https://localhost/wp-login.php" -UseBasicParsing -TimeoutSec 10
            if ($r.StatusCode -eq 200) {
                $points += 0.5
                $fb += "WP OK"
            }
        } catch {
            $fb += "WP fail"
        }

        $plugins = @(
            "simple-ldap-login",
            "ldap-login-for-intranet-sites",
            "miniOrange-login-openid",
            "active-directory-integration"
        )

        $found = $false

        foreach ($p in $plugins) {
            if (Test-Path (Join-Path $wpPath "wp-content\plugins\$p")) {
                $found = $true
            }
        }

        if ($found) {
            $points += 0.5
            $fb += "LDAP plugin OK"
        }
        else {
            $fb += "LDAP plugin puudub"
        }

        $u1 = Get-ADUser -Filter "Name -like '*Peatoimetaja*'" -ErrorAction SilentlyContinue
        $u2 = Get-ADUser -Filter "Name -like '*ToimetajaAbi*'" -ErrorAction SilentlyContinue

        if ($u1 -and $u2) {
            $points += 1
            $fb += "AD users OK"
        }
        else {
            $fb += "AD users puuduvad"
        }
    }
    catch {
        $fb += $_.Exception.Message
    }

    return @{Points=$points; Feedback=($fb -join " | ")}
}

# --- 9. HINNE ---
$Grade = switch ($TotalPoints) {
    {$_ -ge 22} { "5" }
    {$_ -ge 17} { "4" }
    {$_ -ge 12} { "3" }
    default { "2" }
}

# --- 10. JSON ---
$Payload = [PSCustomObject]@{
    Opilane = $RawName
    KokkuPunkte = $TotalPoints
    Hinne = $Grade
    Kontrollid = $Results
} | ConvertTo-Json -Depth 10

$Payload | Out-File $FullFilePath -Encoding UTF8

# --- 11. SEND ---
try {
    Invoke-RestMethod -Uri "http://$ServerIP:5000/api/upload" `
        -Method Post `
        -Body $Payload `
        -ContentType "application/json"
    
    Write-Host "OK $TotalPoints / 25 | Hinne $Grade" -ForegroundColor Green
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
}

```
