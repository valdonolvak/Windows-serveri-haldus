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

# --- 1. KASUTAJA SISENDID ---
$RawName = Read-Host "Sisesta oma nimi (Eesnimi Perekonnanimi)"
$VNET = Read-Host "Sisesta oma vnet number (XXX)"
$ServerIP = "192.168.124.64" # Linux serveri IP

$SafeName = $RawName.ToLower().Replace(" ","").Replace("ä","a").Replace("ö","o").Replace("ü","u").Replace("õ","o")
$FileName = "$SafeName.json"
$FullFilePath = Join-Path $TempPath $FileName

$script:Results = @()
$script:TotalPoints = 0

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
        $fb = "❌ VIGA: $($_.Exception.Message)"
    }
    $script:TotalPoints += $p
    $script:Results += [PSCustomObject]@{ Nimi=$Nimi; Korras=$p -ge ($MaxP * 0.7); Punktid=$p; Selgitus=$fb }
}

Write-Host "`n--- ALUSTAN LÕPUTÖÖ DETAILSET KONTROLLI (vnet $VNET) ---" -ForegroundColor Cyan

# --- 3. DETAILSED KONTROLLID (1-16) ---

# 1-7: Kasutame sinu esimest toimivat loogikat
Add-DetailedTask "1. AD ja DNS seadistus" 1 {
    $d = (Get-ADDomain).DNSRoot
    if ($d -like "*.local") { return @{Points=1; Feedback="✅ Domeen: $d"} }
    return @{Points=0; Feedback="❌ VIGA: Domeen peab olema .local"}
}

Add-DetailedTask "2. Ketas F: ja struktuur" 1 {
    $p = 0; $fb = @()
    if (Test-Path "F:") { 
        $p += 0.4; $fb += "✅ Ketas F:"
        foreach($f in @("STUFF", "WWW", "Kasutajad$")) {
            if (Test-Path "F:\$f") { $p += 0.2; $fb += "✅ $f" } else { $fb += "❌ $f" }
        }
    } else { $fb += "❌ Ketas F: puudu" }
    return @{Points=$p; Feedback=($fb -join " | ")}
}

Add-DetailedTask "3. DHCP Skoop HKHK" 1 {
    $s = Get-DhcpServerv4Scope | Where-Object Name -like "*HKHK*"
    $target = "192.168.$VNET.100"
    if ($s) {
        if ($s.StartRange -eq $target) { return @{Points=1; Feedback="✅ Skoop OK ($target)"} }
        return @{Points=0.5; Feedback="⚠️ Algus IP vale: $($s.StartRange)"}
    }
    return @{Points=0; Feedback="❌ Skoop puudu"}
}

Add-DetailedTask "4. Klientide domeeniga liitumine" 1 {
    $p = 0; $fb = @()
    foreach($c in @("Arvuti1", "Arvuti2")){
        if(Get-ADComputer -Filter "Name -eq '$c'" -ErrorAction SilentlyContinue){ $p += 0.5; $fb += "✅ $c" } else { $fb += "❌ $c" }
    }
    return @{Points=$p; Feedback=($fb -join ", ")}
}

Add-DetailedTask "5. OU ARVUTID ja masinate asukoht" 1 {
    $p = 0; $fb = @()
    $c1 = Get-ADComputer -Identity "Arvuti1" -Properties DistinguishedName -ErrorAction SilentlyContinue
    $c2 = Get-ADComputer -Identity "Arvuti2" -Properties DistinguishedName -ErrorAction SilentlyContinue
    if($c1.DistinguishedName -like "*OU=Win10,OU=ARVUTID*"){$p += 0.5; $fb += "✅ Arvuti1 OK"}
    if($c2.DistinguishedName -like "*OU=Win11,OU=ARVUTID*"){$p += 0.5; $fb += "✅ Arvuti2 OK"}
    return @{Points=$p; Feedback=($fb -join " | ")}
}

Add-DetailedTask "6. OU KASUTAJAD struktuur" 1 {
    $ous = Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty Name
    $f = 0
    foreach($o in @("LEKTORID", "TUDENGID", "VEEB")){ if(Get-SimilarName $o $ous){ $f++ } }
    return @{Points=($f/3); Feedback="Leitud $f/3 vajalikku OU-d"}
}

Add-DetailedTask "7. Kasutajad ja grupid" 2 {
    $p = 0
    if(Get-ADGroup -Filter "Name -eq 'Lektorid'" -ErrorAction SilentlyContinue){ $p += 0.25 }
    if(Get-ADGroup -Filter "Name -eq 'Tudengid'" -ErrorAction SilentlyContinue){ $p += 0.25 }
    $uCount = (Get-ADUser -Filter "Name -like '*tudeng*' -or Name -like '*oppejoud*'" -ErrorAction SilentlyContinue).Count
    if($uCount -ge 4){ $p += 0.5 }
    $t1 = Get-ADUser -Filter "Name -like '*tudeng1*'" -Properties LogonHours -ErrorAction SilentlyContinue
    if($t1.LogonHours -and $t1.LogonHours[0] -ne 255){ $p += 1 }
    return @{Points=$p; Feedback="Kasutajad, grupid ja Logon Hours kontrollitud"}
}

# 8-11: GPO-de kontroll
Add-DetailedTask "8. GPO Taustapildid" 2 {
    $found = Get-GPO -All | Where-Object DisplayName -like "*Taustapildid*"
    if($found){ return @{Points=2; Feedback="✅ GPO leitud"} }
    return @{Points=0; Feedback="❌ Puudu"}
}

Add-DetailedTask "9. GPO Folder Redirection" 2 {
    $found = Get-GPO -All | Where-Object DisplayName -like "*Redirection*"
    if($found){ return @{Points=2; Feedback="✅ GPO leitud"} }
    return @{Points=0; Feedback="❌ Puudu"}
}

Add-DetailedTask "10. Tarkvara GPO-d (7zip/Chrome)" 2 {
    $all = Get-GPO -All | Select-Object -ExpandProperty DisplayName
    $p = 0
    if(Get-SimilarName "7zip" $all){$p++}
    if(Get-SimilarName "Chrome" $all){$p++}
    return @{Points=$p; Feedback="Leitud $p/2 GPO-d"}
}

Add-DetailedTask "11. GPO Chrome Settings" 2 {
    if(Get-GPO -Name "GPO_Chrome_Settings" -ErrorAction SilentlyContinue){ return @{Points=2; Feedback="✅ OK"} }
    return @{Points=0; Feedback="❌ Puudu"}
}

Add-DetailedTask "12. Teine DC (AD2) staatus" 2 {
    if(Get-ADDomainController -Identity "AD2" -ErrorAction SilentlyContinue){ return @{Points=2; Feedback="✅ AD2 on DC"} }
    return @{Points=0; Feedback="❌ AD2 puudu"}
}

Add-DetailedTask "13. DHCP Failover" 1 {
    if(Get-DhcpServerv4Failover -ErrorAction SilentlyContinue){ return @{Points=1; Feedback="✅ OK"} }
    return @{Points=0; Feedback="❌ Puudu"}
}

Add-DetailedTask "14. IIS ja Wordpress" 2 {
    $site = Get-Website | Where-Object Name -like "*veebileht*"
    if($site -and (Test-Path "F:\WWW")){ return @{Points=2; Feedback="✅ Sait ja F:\WWW olemas"} }
    return @{Points=0; Feedback="❌ Seadistus puudulik"}
}

# --- 15 JA 16: PARANDATUD HTTPS JA LDAP KONTROLL ---
Add-DetailedTask "15. HTTPS (Port 443)" 2 {
    $p = 0; $fb = @()
    $b = Get-WebBinding | Where-Object { $_.protocol -eq "https" }
    if($b){ 
        $p += 1; $fb += "✅ Binding olemas"
        # Testime reaalset vastust (ignoreerides sertifikaati)
        try {
            $test = curl.exe -s -k -I "https://localhost" --connect-timeout 5
            if($test -match "200 OK"){ $p += 1; $fb += "✅ Sait vastab HTTPS kaudu" }
        } catch {}
    }
    return @{Points=$p; Feedback=($fb -join " | ")}
}

Add-DetailedTask "16. WP AD Kasutajad (VEEB)" 2 {
    $p = 0; $fb = @()
    $u1 = Get-ADUser -Filter "Name -like '*Peatoimetaja*'" -ErrorAction SilentlyContinue
    $u2 = Get-ADUser -Filter "Name -like '*ToimetajaAbi*'" -ErrorAction SilentlyContinue
    if($u1){ $p += 0.5; $fb += "✅ Peatoimetaja" }
    if($u2){ $p += 0.5; $fb += "✅ ToimetajaAbi" }
    
    # Kontrollime, kas keegi on üldse VEEB OU-s
    $veebOU = Get-ADUser -Filter * -SearchBase "OU=VEEB,OU=KASUTAJAD,$( (Get-ADDomain).DistinguishedName )" -ErrorAction SilentlyContinue
    if($veebOU){ $p += 1; $fb += "✅ Kasutajad õiges OU-s" }
    
    return @{Points=$p; Feedback=($fb -join ", ")}
}

# --- 4. HINDE ARVUTAMINE ---
$HinneTekst = switch ($script:TotalPoints) {
    {$_ -ge 22} { "5" }
    {$_ -ge 17} { "4" }
    {$_ -ge 12} { "3" }
    Default     { "2" }
}

# --- 5. SAATMINE ---
$Payload = [PSCustomObject]@{
    Opilane = $RawName; KokkuPunkte = $script:TotalPoints; Hinne = $HinneTekst; Kontrollid = $script:Results
} | ConvertTo-Json -Depth 10

$Payload | Out-File $FullFilePath -Encoding utf8

$FullApiUrl = "http://$($ServerIP):5000/api/upload"
Write-Host "`nSaadan andmeid serverisse $FullApiUrl..." -ForegroundColor Yellow

try {
    $Response = Invoke-RestMethod -Uri $FullApiUrl -Method Post -Body $Payload -ContentType "application/json; charset=utf-8" -Proxy $null -TimeoutSec 15
    Write-Host "✅ EDUKAS! Punktid: $script:TotalPoints / 25 | Hinne: $HinneTekst" -ForegroundColor Green
    if (Test-Path $FullFilePath) { Remove-Item $FullFilePath -Force }
} catch {
    Write-Host "❌ VIGA: Serverile saatmine ebaõnnestus." -ForegroundColor Red
    Write-Host "Fail salvestati manuaalseks üleslaadimiseks: $FullFilePath" -ForegroundColor Yellow
}


```
