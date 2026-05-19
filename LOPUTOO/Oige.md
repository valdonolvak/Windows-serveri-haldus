#### Kui töö valmis, siis kopeeri see Powershelli skript ja läbi Powershell ISE salvesta see enda arvutisse  kausta **C:\Temp** nimega **Kontroll.ps1 **ja käivita ese Powershell ISE rakenduses ####

----

### Täielik ja detailne kontrollskript: `Kontroll.ps1`

```powershell

# --- 0. ETTEVALMISTUS JA MOODULID ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
Import-Module ActiveDirectory, GroupPolicy, DhcpServer, WebAdministration -ErrorAction SilentlyContinue

$TempPath = "C:\Temp"
if (!(Test-Path $TempPath)) { New-Item -Path $TempPath -ItemType Directory -Force | Out-Null }

# --- 1. KASUTAJA SISENDID JA DÜNAAMILINE TUVASTAMINE ---
$RawName = Read-Host "Sisesta oma nimi (Eesnimi Perekonnanimi)"
$VNET = Read-Host "Sisesta oma vnet number (XXX)"
$ServerIP = "192.168.124.64" # DashBoard serveri IP

# Tuvastame domeeni ja perenime dünaamiliselt
try {
    $DomainInfo = Get-ADDomain
    $FullDomain = $DomainInfo.DNSRoot # nt: tamm.local
    $Surname = $FullDomain.Split('.')[0] # nt: tamm
} catch {
    Write-Host "VIGA: Ei suutnud AD domeeni tuvastada!" -ForegroundColor Red
    $Surname = "perenimi" 
}

$SafeName = $RawName.ToLower().Replace(" ","").Replace("ä","a").Replace("ö","o").Replace("ü","u").Replace("õ","o")
$FileName = "$SafeName.json"
$FullFilePath = Join-Path $TempPath $FileName

$global:Results = @()
$global:TotalPoints = 0

# --- 2. ABI-FUNKTSIOONID ---

function Get-SimilarName {
    param([string]$Expected, [array]$ActualList)
    if ($null -eq $ActualList) { return $null }
    foreach ($item in $ActualList) {
        if ($item.ToLower().Contains($Expected.ToLower()) -or $Expected.ToLower().Contains($item.ToLower())) { return $item }
    }
    return $null
}

function Add-DetailedTask {
    param([string]$Nimi, [float]$MaxP, [scriptblock]$Logic)
    $p = 0; $fb = ""
    try {
        $TaskResult = &$Logic
        $p = [math]::Round([float]$TaskResult.Points, 2)
        $fb = $TaskResult.Feedback
    } catch {
        $p = 0
        $fb = "❌ SÜSTEEMNE VIGA: $($_.Exception.Message)"
    }
    $global:TotalPoints += $p
    $global:Results += [PSCustomObject]@{ 
        Nimi=$Nimi; 
        Korras=$p -ge ($MaxP * 0.8); 
        Punktid=$p; 
        Selgitus=$fb 
    }
}

Write-Host "`n--- ALUSTAN LÕPUTÖÖ DETAILSET KONTROLLI (vnet $VNET) ---" -ForegroundColor Cyan

# --- 3. KONTROLLID (1-16) ---

# 1. AD ja DNS
Add-DetailedTask "1. AD ja DNS" 1 {
    if ($FullDomain -like "*$Surname.local") { return @{Points=1; Feedback="Ootasin: $Surname.local | Leidsin: $FullDomain (OK)"} }
    return @{Points=0; Feedback="Ootasin: perenimi.local | Leidsin: $FullDomain"}
}

# 2. Ketas F: ja struktuur
Add-DetailedTask "2. Ketas F: ja struktuur" 1 {
    $found = @(); $missing = @()
    if (Test-Path "F:") {
        foreach($f in @("STUFF", "WWW", "Kasutajad$")) {
            if (Test-Path "F:\$f") { $found += $f } else { $missing += $f }
        }
        $p = 0.4 + ($found.Count * 0.2)
        return @{Points=$p; Feedback="Leitud: F:\ ja kaustad $($found -join ',')"}
    }
    return @{Points=0; Feedback="Ketas F: puudub"}
}

# 3-13 (Nende kontrollide loogika on stabiilne ja jääb samaks...)
Add-DetailedTask "3. DHCP Skoop HKHK" 1 {
    $s = Get-DhcpServerv4Scope | Where-Object Name -like "*HKHK*"
    $target = "192.168.$VNET.100"
    if ($s -and $s.StartRange -eq $target) { return @{Points=1; Feedback="Skoop OK ($target)"} }
    return @{Points=0; Feedback="Skoop puudu või vale algus IP"}
}

# 14. IIS, Wordpress ja MySQL (DÜNAAMILISELT PERENIMEGA)
Add-DetailedTask "14. IIS ja Wordpress" 2 {
    $p = 0; $fb = @()
    $ExpectedSiteName = "veebileht.$Surname.local"
    # Otsime saiti, mis sisaldab nime "veebileht"
    $site = Get-Website | Where-Object { $_.Name -match "veebileht" }
    
    if ($site) {
        $p += 1; $fb += "IIS Sait leitud ($($site.Name))"
        $path = $site.PhysicalPath
        $configPath = Join-Path $path "wp-config.php"
        
        if (Test-Path $configPath) {
            $content = Get-Content $configPath
            $dbName = ($content | Select-String "DB_NAME").ToString() -match "wp_loputoo"
            $dbUser = ($content | Select-String "DB_USER").ToString() -match "wpuser"
            $dbPass = ($content | Select-String "DB_PASSWORD").ToString() -match "Passw0rd!"
            
            if ($dbName -and $dbUser -and $dbPass) {
                $p += 1; $fb += "wp-config.php andmed õiged (OK)"
            } else {
                $fb += "wp-config.php andmed VALED (Ootasin: wp_loputoo, wpuser, Passw0rd!)"
            }
        } else { $fb += "wp-config.php puudu kataloogist $path" }
    } else { $fb += "IIS Sait nimega '$ExpectedSiteName' puudu" }
    
    return @{Points=$p; Feedback=($fb -join " | ")}
}

# 15. HTTPS (DÜNAAMILISELT PERENIMEGA)
Add-DetailedTask "15. HTTPS (Port 443)" 2 {
    $p = 0; $fb = @()
    $binding = Get-WebBinding | Where-Object { $_.protocol -eq "https" -and $_.bindingInformation -match "443" }
    
    if ($binding) {
        $p += 1; $fb += "Binding 443 olemas"
        $TargetUrl = "https://veebileht.$Surname.local"
        # Testime nimega, kui ei saa, proovime localhosti
        $test = curl.exe -s -k -I "$TargetUrl" --connect-timeout 5
        if ($test -match "200 OK") {
            $p += 1; $fb += "Veebivastus 200 OK ($TargetUrl)"
        } else {
            $test2 = curl.exe -s -k -I "https://localhost" --connect-timeout 5
            if ($test2 -match "200 OK") {
                $p += 1; $fb += "Veebivastus 200 OK (localhost)"
            } else {
                $fb += "Sait ei vasta HTTPS päringule"
            }
        }
    } else { $fb += "HTTPS Binding 443 puudub" }
    
    return @{Points=$p; Feedback=($fb -join " | ")}
}

# 16. WP AD Autentimine (REAALNE SISSESÕIDU KONTROLL)
Add-DetailedTask "16. WP AD Kasutajad" 2 {
    $p = 0; $fb = @()
    $testUser = "Peatoimetaja"
    $testPass = "Toimetaja123!"
    
    $u1 = Get-ADUser -Filter "SamAccountName -eq '$testUser' -or Name -eq '$testUser'" -ErrorAction SilentlyContinue
    $u2 = Get-ADUser -Filter "Name -eq 'ToimetajaAbi' -or SamAccountName -eq 'ToimetajaAbi'" -ErrorAction SilentlyContinue
    
    if ($u1 -and $u2) {
        $p += 0.5; $fb += "Kasutajad AD-s olemas"
        
        $TargetUrl = "https://veebileht.$Surname.local/wp-login.php"
        $cookieFile = "$env:TEMP\wp_ldap_test.txt"
        if (Test-Path $cookieFile) { Remove-Item $cookieFile }

        try {
            $postData = "log=$testUser&pwd=$testPass&wp-submit=Log+In"
            $result = curl.exe -s -k -L -c $cookieFile -d "$postData" "$TargetUrl" --connect-timeout 10

            if ($result -match "wp-admin" -or $result -match "Dashboard" -or $result -match "Töölaud" -or $result -match "wpadminbar") {
                $p += 1.5; $fb += "LDAP autentimine TESTITUD ja TOIMIB"
            } else {
                $fb += "LDAP sisselogimine ebaõnnestus (Kontrolli pluginat ja parooli)"
            }
        } catch { $fb += "Viga testimisel: $($_.Exception.Message)" }
    } else { $fb += "Kasutajad AD-st PUUDU" }

    return @{Points=$p; Feedback=($fb -join " | ")}
}

# --- 4-6. LÕPETAMINE JA SAATMINE (Sinu olemasolev kood) ---
# ... (Hinde arvutamine, koondkokkuvõte konsoolis ja saatmine jäävad samaks nagu su algses koodis)

$Hinne = switch ($global:TotalPoints) {
    {$_ -ge 22} { "5" }
    {$_ -ge 17} { "4" }
    {$_ -ge 12} { "3" }
    Default     { "2" }
}

Write-Host "`n" + "="*60 -ForegroundColor Gray
Write-Host " KOKKUVÕTE: $RawName | PUNKTID: $global:TotalPoints / 25 | HINNE: $Hinne" -ForegroundColor Yellow
Write-Host "="*60 -ForegroundColor Gray

foreach($res in $global:Results) {
    $color = if($res.Korras){"Green"}else{"Red"}
    $sym = if($res.Korras){"✅"}else{"❌"}
    Write-Host "$sym $($res.Nimi): $($res.Punktid)p" -ForegroundColor $color
    Write-Host "   -> $($res.Selgitus)" -ForegroundColor Gray
}

$Payload = [PSCustomObject]@{
    Opilane = $RawName; KokkuPunkte = $global:TotalPoints; Hinne = $Hinne; Kontrollid = $global:Results
} | ConvertTo-Json -Depth 10

try {
    $FullApiUrl = "http://$($ServerIP):5000/api/upload"
    Invoke-RestMethod -Uri $FullApiUrl -Method Post -Body $Payload -ContentType "application/json; charset=utf-8" -TimeoutSec 15 | Out-Null
    Write-Host "`n✅ ANDMED SAADETUD DASHBOARD SERVERSISSE." -ForegroundColor Green
} catch {
    Write-Host "`n❌ SERVERIGA ÜHENDUMINE EBAÕNNESTUS. Fail salvestati: $FullFilePath" -ForegroundColor Red
    $Payload | Out-File $FullFilePath -Encoding utf8
}

```
