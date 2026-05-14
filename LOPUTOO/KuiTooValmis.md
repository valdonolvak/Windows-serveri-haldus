#### Kui töö valmis, siis kopeeri see Powershelli skript ja läbi Powershell ISE salvesta see enda arvutisse  kausta **C:\Temp** nimega **Kontroll.ps1 **ja käivita ese Powershell ISE rakenduses ####

----

### Täielik ja detailne kontrollskript: `Kontroll.ps1`

```powershell
# --- 0. ETTEVALMISTUS JA MOODULID ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module ActiveDirectory, GroupPolicy, DhcpServer, WebAdministration -ErrorAction SilentlyContinue

$TempPath = "C:\Temp"
if (!(Test-Path $TempPath)) { New-Item -Path $TempPath -ItemType Directory -Force | Out-Null }

# --- 1. KASUTAJA SISENDID ---
$RawName = Read-Host "Sisesta oma nimi (Eesnimi Perekonnanimi)"
$VNET = Read-Host "Sisesta oma vnet number (XXX)"
$ServerIP = "192.168.124.64" # Linux serveri IP

$SafeName = $RawName.ToLower().Replace(" ","").Replace("ä","a").Replace("ö","o").Replace("ü","u").Replace("õ","o")
$FileName = "$SafeName.json"
$FullFilePath = Join-Path $TempPath $FileName

$Results = @()
$TotalPoints = 0

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
    $global:Results += [PSCustomObject]@{ Nimi=$Nimi; Korras=$p -ge $MaxP; Punktid=$p; Selgitus=$fb }
}

Write-Host "`n--- ALUSTAN LÕPUTÖÖ DETAILSET SÜVAANALÜÜSI (vnet $VNET) ---" -ForegroundColor Cyan

# --- 3. DETAILSED KONTROLLID (1-16) ---

# 1. AD ja DNS (1p)
Add-DetailedTask "1. AD ja DNS seadistus" 1 {
    $d = (Get-ADDomain).DNSRoot
    if ($d -like "*.local") { return @{Points=1; Feedback="✅ Domeenikonfiguratsioon korras: $d"} }
    return @{Points=0; Feedback="❌ VIGA: Domeen on $d, peab lõppema .local liitega"}
}

# 2. Ketta F: ja struktuur (1p)
Add-DetailedTask "2. Ketas F: ja struktuur" 1 {
    $p = 0; $fb = @()
    if (Test-Path "F:") { 
        $p += 0.4; $fb += "✅ Ketas F: olemas"
        foreach($f in @("STUFF", "WWW", "Kasutajad$")) {
            if (Test-Path "F:\$f") { $p += 0.2; $fb += "✅ $f" } else { $fb += "❌ $f puudu" }
        }
    } else { $fb += "❌ Ketas F: puudub" }
    return @{Points=$p; Feedback=($fb -join " | ")}
}

# 3. DHCP Skoop (1p)
Add-DetailedTask "3. DHCP Skoop HKHK" 1 {
    $s = Get-DhcpServerv4Scope | Where-Object Name -like "*HKHK*"
    $target = "192.168.$VNET.100"
    if ($s) {
        if ($s.StartRange -eq $target) { return @{Points=1; Feedback="✅ Skoop HKHK olemas ($target - $($s.EndRange))"} }
        return @{Points=0.5; Feedback="⚠️ Skoop olemas, aga algusaadress on $($s.StartRange) (oodatud $target)"}
    }
    return @{Points=0; Feedback="❌ Skoop HKHK puudub"}
}

# 4. Domeeniga liitumine (1p)
Add-DetailedTask "4. Klientide domeeniga liitumine" 1 {
    $p = 0; $fb = @()
    foreach($c in @("Arvuti1", "Arvuti2")){
        if(Get-ADComputer -Filter "Name -eq '$c'" -ErrorAction SilentlyContinue){ $p += 0.5; $fb += "✅ $c liidetud" } else { $fb += "❌ $c puudu" }
    }
    return @{Points=$p; Feedback=($fb -join ", ")}
}

# 5. OU Arvutid paigutus (1p)
Add-DetailedTask "5. OU ARVUTID ja masinate asukoht" 1 {
    $p = 0; $fb = @()
    $c1 = Get-ADComputer -Identity "Arvuti1" -Properties DistinguishedName -ErrorAction SilentlyContinue
    $c2 = Get-ADComputer -Identity "Arvuti2" -Properties DistinguishedName -ErrorAction SilentlyContinue
    if($c1.DistinguishedName -like "*OU=Win10,OU=ARVUTID*"){$p += 0.5; $fb += "✅ Arvuti1 (Win10) OK"} else {$fb += "❌ Arvuti1 vales OU-s"}
    if($c2.DistinguishedName -like "*OU=Win11,OU=ARVUTID*"){$p += 0.5; $fb += "✅ Arvuti2 (Win11) OK"} else {$fb += "❌ Arvuti2 vales OU-s"}
    return @{Points=$p; Feedback=($fb -join " | ")}
}

# 6. OU KASUTAJAD (1p)
Add-DetailedTask "6. OU KASUTAJAD struktuur" 1 {
    $ous = Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty Name
    $fb = @(); $f = 0
    foreach($o in @("LEKTORID", "TUDENGID", "VEEB")){
        if(Get-SimilarName $o $ous){ $f++; $fb += "✅ $o" } else { $fb += "❌ $o" }
    }
    return @{Points=($f/3); Feedback="Leitud struktuur: " + ($fb -join ", ")}
}

# 7. Kasutajad ja grupid (2p)
Add-DetailedTask "7. Kasutajad, grupid ja piirangud" 2 {
    $p = 0; $fb = @()
    # Grupid (0.5p)
    foreach($g in @("Lektorid", "Tudengid")){
        if(Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue){ $p += 0.25; $fb += "✅ Grupp $g" } else { $fb += "❌ Grupp $g" }
    }
    # Kasutajad (0.5p)
    $users = @("oppejoud1", "oppejoud2", "tudeng1", "tudeng2")
    $foundUsers = @()
    foreach($u in $users){
        $check = Get-ADUser -Filter "Name -like '*$u*' -or SamAccountName -like '*$u*'" -ErrorAction SilentlyContinue
        if($check){ $foundUsers += "✅ $u"; $p += 0.125 } else { $foundUsers += "❌ $u" }
    }
    $fb += ($foundUsers -join ", ")
    # Logon Hours (1p)
    $t1 = Get-ADUser -Filter "Name -like '*tudeng1*'" -Properties LogonHours -ErrorAction SilentlyContinue
    if($t1 -and $t1.LogonHours -and $t1.LogonHours[0] -ne 255){ $p += 1; $fb += " | ✅ Logon Hours seadistatud" } else { $fb += " | ❌ Logon Hours puudu" }
    return @{Points=$p; Feedback=($fb -join " | ")}
}

# 8. GPO Taustapildid (2p)
Add-DetailedTask "8. GPO Taustapildid" 2 {
    $all = Get-GPO -All | Select-Object -ExpandProperty DisplayName
    $found = Get-SimilarName "Taustapildid" $all
    if($found){ return @{Points=2; Feedback="✅ Leitud: $found"} }
    return @{Points=0; Feedback="❌ GPO_Taustapildid puudub"}
}

# 9. GPO Folder Redirection (2p)
Add-DetailedTask "9. GPO Folder Redirection" 2 {
    $all = Get-GPO -All | Select-Object -ExpandProperty DisplayName
    $found = Get-SimilarName "Redirection" $all
    if($found){ return @{Points=2; Feedback="✅ Leitud: $found"} }
    return @{Points=0; Feedback="❌ GPO_Folder_Redirection puudub"}
}

# 10. Tarkvara GPO-d (2p)
Add-DetailedTask "10. Tarkvara GPO-d (7zip/Chrome)" 2 {
    $all = Get-GPO -All | Select-Object -ExpandProperty DisplayName
    $z = Get-SimilarName "7zip" $all; $c = Get-SimilarName "Chrome" $all
    $p = 0; if($z){$p++}; if($c){$p++}
    return @{Points=$p; Feedback="Staatus: $(if($z){'✅ 7zip'}else{'❌ 7zip'}), $(if($c){'✅ Chrome'}else{'❌ Chrome'})"}
}

# 11. Chrome seadistamine (2p)
Add-DetailedTask "11. GPO Chrome Settings" 2 {
    $all = Get-GPO -All | Select-Object -ExpandProperty DisplayName
    $found = Get-SimilarName "Chrome_Settings" $all
    if($found){ return @{Points=2; Feedback="✅ Leitud: $found"} }
    return @{Points=0; Feedback="❌ GPO_Chrome_Settings puudub"}
}

# 12. Teine DC (AD2) (2p)
Add-DetailedTask "12. Teine DC (AD2) staatus" 2 {
    $ad2 = Get-ADDomainController -Identity "AD2" -ErrorAction SilentlyContinue
    if($ad2){ return @{Points=2; Feedback="✅ AD2 on domeenikontroller"} }
    return @{Points=0; Feedback="❌ AD2 ei ole DC või pole kättesaadav"}
}

# 13. DHCP Failover (1p)
Add-DetailedTask "13. DHCP Failover" 1 {
    $f = Get-DhcpServerv4Failover -ErrorAction SilentlyContinue
    if($f){ return @{Points=1; Feedback="✅ Failover seadistatud (Režiim: $($f.Mode))"} }
    return @{Points=0; Feedback="❌ Failover seadistamata"}
}

# 14. IIS ja Wordpress (2p)
Add-DetailedTask "14. IIS ja Wordpress" 2 {
    $site = Get-Website | Where-Object Name -like "*veebileht*"
    $p = 0; $fb = @()
    if($site){ $p += 1; $fb += "✅ IIS Sait olemas" } else { $fb += "❌ IIS Sait puudu" }
    if(Test-Path "F:\WWW") { $p += 1; $fb += "✅ Kaust F: kettal" } else { $fb += "❌ Kaust F:\WWW puudu" }
    return @{Points=$p; Feedback=($fb -join ", ")}
}

# 15. HTTPS seadistamine (2p)
Add-DetailedTask "15. HTTPS (Port 443)" 2 {
    $b = Get-WebBinding -Name "*veebileht*" | Where-Object protocol -eq "https"
    if($b){ return @{Points=2; Feedback="✅ HTTPS sidumine leitud (443)"} }
    return @{Points=0; Feedback="❌ HTTPS (Port 443) puudub"}
}

# 16. WP AD Autentimine (2p)
Add-DetailedTask "16. WP AD Kasutajad (VEEB)" 2 {
    $u1 = Get-ADUser -Filter "Name -like '*Peatoimetaja*'" -ErrorAction SilentlyContinue
    $u2 = Get-ADUser -Filter "Name -like '*ToimetajaAbi*'" -ErrorAction SilentlyContinue
    $p = 0; $fb = @()
    if($u1){ $p++; $fb += "✅ Peatoimetaja" } else { $fb += "❌ Peatoimetaja" }
    if($u2){ $p++; $fb += "✅ ToimetajaAbi" } else { $fb += "❌ ToimetajaAbi" }
    return @{Points=$p; Feedback="Leitud: " + ($fb -join ", ")}
}

# --- 4. HINDE ARVUTAMINE ---
$HinneTekst = switch ($TotalPoints) {
    {$_ -ge 22} { "5" }
    {$_ -ge 17} { "4" }
    {$_ -ge 12} { "3" }
    Default     { "2" }
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
