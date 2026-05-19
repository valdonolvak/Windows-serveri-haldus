#### Kui töö valmis, siis kopeeri see Powershelli skript ja läbi Powershell ISE salvesta see enda arvutisse  kausta **C:\Temp** nimega **Kontroll.ps1 **ja käivita ese Powershell ISE rakenduses ####

----

### Täielik ja detailne kontrollskript: `Kontroll.ps1`

```powershell
# --- 0. ETTEVALMISTUS ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module ActiveDirectory, GroupPolicy, DhcpServer, WebAdministration -ErrorAction SilentlyContinue

$TempPath = "C:\Temp"
if (!(Test-Path $TempPath)) { New-Item $TempPath -ItemType Directory -Force | Out-Null }

# --- 1. SISEND ---
$RawName = Read-Host "Sisesta nimi"
$VNET = Read-Host "Sisesta vnet (XXX)"
$ServerIP = "192.168.124.64"

if (-not $ServerIP) {
    throw "ServerIP on tühi!"
}

$SafeName = $RawName.ToLower().Replace(" ","").Replace("ä","a").Replace("ö","o").Replace("ü","u").Replace("õ","o")
$FileName = "$SafeName.json"
$FullFilePath = Join-Path $TempPath $FileName

$Results = @()
$TotalPoints = 0

# --- ABI ---
function Get-SimilarName {
    param($Expected, $List)
    foreach ($i in $List) {
        if ($i -and ($i.ToLower().Contains($Expected.ToLower()) -or $Expected.ToLower().Contains($i.ToLower()))) {
            return $i
        }
    }
    return $null
}

function Add-DetailedTask {
    param($Name, $MaxP, $Logic)

    $p = 0
    $fb = ""

    try {
        $r = & $Logic
        $p = [math]::Round([float]$r.Points,2)
        $fb = $r.Feedback
    } catch {
        $p = 0
        $fb = "ERROR: $($_.Exception.Message)"
    }

    $script:TotalPoints += $p
    $script:Results += [PSCustomObject]@{
        Nimi=$Name
        Punktid=$p
        Feedback=$fb
    }
}

Write-Host "ALUSTAN ANALÜÜSI vnet $VNET"

# --- 10 GPO (FIXED, sinu loogika alles) ---
Add-DetailedTask "10 GPO Software" 2 {

    $points = 0
    $fb = @()

    $domainDN = (Get-ADDomain).DistinguishedName

    function Find-Link($gpoName) {
        $found = @()

        try {
            Get-ADOrganizationalUnit -Filter * | ForEach-Object {
                try {
                    $links = (Get-GPInheritance -Target $_.DistinguishedName).GpoLinks
                    foreach ($l in $links) {
                        if ($l.DisplayName -eq $gpoName) {
                            $found += $_.DistinguishedName
                        }
                    }
                } catch {}
            }
        } catch {}

        return $found
    }

    function Check-GPO($name) {
        $gpo = Get-GPO -Name $name -ErrorAction SilentlyContinue
        if (-not $gpo) { return $null }

        $rep = Get-GPOReport -Guid $gpo.Id -ReportType Xml

        return @{
            GPO=$gpo
            Software = $rep -match "Software Installation"
            UNC = $rep -match "\\\\AD1\\"
            MSI = $rep -match "\.msi"
        }
    }

    foreach ($app in @("GPO_Software_7zip","GPO_Software_Chrome")) {

        $c = Check-GPO $app

        if ($c) {
            $points += 0.5
            $fb += "$app olemas"

            if ($c.Software) { $points += 0.2; $fb += "$app Software OK" }
            if ($c.UNC) { $points += 0.2; $fb += "$app UNC OK" }
            if ($c.MSI) { $points += 0.2; $fb += "$app MSI OK" }

            $loc = Find-Link $app
            if ($loc.Count -gt 0) {
                if ($loc -match "ARVUTID") {
                    $points += 0.1
                    $fb += "$app OU ARVUTID OK"
                } else {
                    $fb += "$app olemas aga vale OU: $($loc -join ',')"
                }
            } else {
                $fb += "$app ei ole lingitud"
            }

        } else {
            $fb += "$app PUUDUB"
        }
    }

    return @{
        Points = [math]::Min($points,2)
        Feedback = ($fb -join " | ")
    }
}

# --- 15 HTTPS (FIXED - NO "\" ERRORS) ---
Add-DetailedTask "15 HTTPS" 2 {

    $points = 0
    $fb = @()

    try {
        $b = Get-WebBinding | Where-Object { $_.protocol -eq "https" }

        if ($b) {
            $points += 1
            $fb += "HTTPS olemas"

            if ($b.bindingInformation -match ":443:") {
                $points += 0.5
                $fb += "Port 443 OK"
            }
        } else {
            $fb += "HTTPS puudub"
        }

        # FIX: NO "\" line continuation anymore
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

        try {
            $r = Invoke-WebRequest -Uri "https://localhost" -UseBasicParsing -TimeoutSec 5
            if ($r.StatusCode -eq 200) {
                $points += 0.5
                $fb += "HTTPS vastab"
            }
        } catch {
            $fb += "HTTPS ei vasta"
        }

    } catch {
        $fb += "HTTPS error: $($_.Exception.Message)"
    }

    return @{Points=$points; Feedback=($fb -join " | ")}
}

# --- 16 WP + LDAP (FIXED BLOCK) ---
Add-DetailedTask "16 WP LDAP" 2 {

    $points = 0
    $fb = @()

    try {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

        $wp = Invoke-WebRequest -Uri "https://localhost/wp-login.php" -UseBasicParsing -TimeoutSec 5

        if ($wp.StatusCode -eq 200) {
            $points += 0.5
            $fb += "WP login OK"
        }

    } catch {
        $fb += "WP ei vasta"
    }

    $plugins = @(
        "simple-ldap-login",
        "ldap-login-for-intranet-sites",
        "miniOrange-login-openid",
        "active-directory-integration"
    )

    $wpPath = "C:\xampp\htdocs"

    foreach ($p in $plugins) {
        if (Test-Path (Join-Path $wpPath "wp-content\plugins\$p")) {
            $points += 0.25
            $fb += "Plugin: $p OK"
        }
    }

    try {
        $u1 = Get-ADUser -Filter "Name -like '*Peatoimetaja*'"
        $u2 = Get-ADUser -Filter "Name -like '*ToimetajaAbi*'"

        if ($u1 -and $u2) {
            $points += 0.5
            $fb += "AD users OK"
        }

    } catch {
        $fb += "AD error"
    }

    return @{Points=$points; Feedback=($fb -join " | ")}
}

# --- 5. SAATMINE ---
$Payload = [PSCustomObject]@{
    Opilane = $RawName; KokkuPunkte = $TotalPoints; Hinne = $HinneTekst; Kontrollid = $Results
} | ConvertTo-Json -Depth 10

$Payload | Out-File $FullFilePath -Encoding utf8

try {
    Write-Host "`nÜritan saata andmeid serverisse http://$ServerIP:5000..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "http://$($ServerIP):5000/api/upload" -Method Post -Body $Payload -ContentType "application/json; charset=utf-8" -Proxy $null -TimeoutSec 15
    Write-Host "EDUKAS! Punktid: $TotalPoints / 25 | Hinne: $HinneTekst" -ForegroundColor Green
} catch {
    Write-Host "`nSAATMINE EBAÕNNESTUS: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Fail salvestati: $FullFilePath" -ForegroundColor Cyan
}

# --- 6. SAATMINE LINUX SERVERISSE ---
$FullApiUrl = "http://$($ServerIP):5000/api/upload"
Write-Host "Saadan andmeid serverisse..." -ForegroundColor Yellow

try {
    $Response = Invoke-RestMethod -Uri $FullApiUrl `
                                  -Method Post `
                                  -Body $Payload `
                                  -ContentType "application/json; charset=utf-8" `
                                  -Proxy $null `
                                  -TimeoutSec 15
    
    Write-Host "EDUKAS! Punktid: $TotalPoints / 25 | Hinne: $HinneTekst" -ForegroundColor Green
    
    # --- UUS: FAILINIME EEMALDAMINE PÄRAST ÕNNESTUMIST ---
    if (Test-Path $FullFilePath) {
        Remove-Item $FullFilePath -Force
        Write-Host "Lokaalne fail $FileName eemaldatud." -ForegroundColor Gray
    }
} catch {
    Write-Host "VIGA: Serverile saatmine ebaõnnestus ($($_.Exception.Message))." -ForegroundColor Red
    Write-Host "Fail salvestati manuaalseks üleslaadimiseks: $FullFilePath" -ForegroundColor Yellow
}
```
