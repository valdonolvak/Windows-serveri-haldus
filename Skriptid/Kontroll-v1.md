```powershell
# --- 0. ETTEVALMISTUS ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$TempPath = "C:\Temp"
if (!(Test-Path $TempPath)) { New-Item -Path $TempPath -ItemType Directory -Force | Out-Null }

# --- 1. KASUTAJA SISENDID ---
$RawName = Read-Host "Sisesta oma nimi (Eesnimi Perekonnanimi)"
$VNET = Read-Host "Sisesta oma vnet number (näiteks: 50)"
$ServerIP = "192.168.124.64"

# Failinime puhastamine: jyrijuurikas.json
$SafeName = $RawName.ToLower().Replace(" ","").Replace("ä","a").Replace("ö","o").Replace("ü","u").Replace("õ","o").Replace("š","s").Replace("ž","z")
$FileName = "$SafeName.json"
$FullFilePath = Join-Path $TempPath $FileName

$Results = @()
$TotalPoints = 0

# --- 2. ABI-FUNKTSIOONID ---

# Fuzzy Matching funktsioon
function Get-SimilarName {
    param([string]$Expected, [array]$ActualList)
    foreach ($item in $ActualList) {
        if ($item.ToLower().Contains($Expected.ToLower()) -or $Expected.ToLower().Contains($item.ToLower())) { return $item }
    }
    return $null
}

function Add-Task {
    param([string]$Nimi, [int]$MaxP, [scriptblock]$Test, [string]$Expected)
    $Status = $false
    $Found = ""
    try {
        $Found = &$Test
        if ($Found -eq "OK") {
            $Status = $true
            $global:TotalPoints += $MaxP
            $Expl = "Korrastatud"
        } else {
            $Expl = "VIGA! Oodatud: $Expected | Leiti: $Found"
        }
    } catch { $Expl = "Viga käivitamisel: $($_.Exception.Message)" }

    $global:Results += [PSCustomObject]@{
        Nimi = $Nimi; Korras = $Status; Punktid = if($Status){$MaxP}else{0}; Selgitus = $Expl
    }
}

Write-Host "`n--- ALUSTAN LÕPUTÖÖ KONTROLLI (vnet $VNET) ---" -ForegroundColor Cyan

# --- 3. KONTROLLID (16 ÜLESANNET) ---

# 1. AD ja DNS (1p)
Add-Task "1. AD ja DNS seadistus" 1 {
    $d = (Get-ADDomain).DNSRoot
    if ($d -like "*.local") { "OK" } else { $d }
} "perenimi.local"

# 2. Ketta F: (1p)
Add-Task "2. Ketta F: ja kaustad" 1 {
    if ((Test-Path "F:\STUFF") -and (Test-Path "F:\WWW")) { "OK" } else { "Kaustad puudu" }
} "F: ketas ja struktuur"

# 3. DHCP Skoop (1p)
Add-Task "3. DHCP skoop HKHK" 1 {
    $s = Get-DhcpServerv4Scope | Where-Object Name -like "*HKHK*"
    if ($s.StartRange -eq "192.168.$VNET.100") { "OK" } else { $s.StartRange }
} "Algus 192.168.$VNET.100"

# 4. Domeeniga liitumine (1p)
Add-Task "4. Domeeniga liitumine" 1 {
    $comps = Get-ADComputer -Filter "Name -like 'Arvuti*'"
    if ($comps.Count -ge 2) { "OK" } else { "Leiti $($comps.Count)" }
} "2 arvutit domeenis"

# 5. OU ARVUTID (1p)
Add-Task "5. OU Arvutid struktuur" 1 {
    $ous = Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty Name
    if (Get-SimilarName "Win10" $ous) { "OK" } else { "Win10 OU puudu" }
} "Win10 ja Win11 OU-d"

# 6. OU KASUTAJAD (1p)
Add-Task "6. OU KASUTAJAD struktuur" 1 {
    $ous = Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty Name
    if (Get-SimilarName "LEKTORID" $ous) { "OK" } else { "OU-d puudu" }
} "LEKTORID, TUDENGID, VEEB"

# 7. Kasutajad ja grupid (2p)
Add-Task "7. Kasutajad ja grupid" 2 {
    if (Get-ADGroup -Filter "Name -like '*Tudengid*'" -ErrorAction SilentlyContinue) { "OK" } else { "Gruppi ei leitud" }
} "Grupid ja kasutajad"

# 8. GPO Taustapildid (Fuzzy) (2p)
Add-Task "8. GPO Taustapildid" 2 {
    $all = Get-GPO -All | Select-Object -ExpandProperty DisplayName
    if (Get-SimilarName "Taustapildid" $all) { "OK" } else { "Ei leitud" }
} "GPO_Taustapildid"

# 9. GPO Folder Redirection (Fuzzy) (2p)
Add-Task "9. GPO Folder Redirection" 2 {
    $all = Get-GPO -All | Select-Object -ExpandProperty DisplayName
    if (Get-SimilarName "Redirection" $all) { "OK" } else { "Ei leitud" }
} "GPO_Folder_Redirection"

# 10. Tarkvara GPO-d (2p)
Add-Task "10. Tarkvara GPO-d" 2 {
    $all = Get-GPO -All | Select-Object -ExpandProperty DisplayName
    if ((Get-SimilarName "7zip" $all) -and (Get-SimilarName "Chrome" $all)) { "OK" } else { "Puudu" }
} "7zip ja Chrome GPO-d"

# 11. Chrome seadistused (2p)
Add-Task "11. GPO Chrome Settings" 2 {
    $all = Get-GPO -All | Select-Object -ExpandProperty DisplayName
    if (Get-SimilarName "Chrome_Settings" $all) { "OK" } else { "Ei leitud" }
} "GPO_Chrome_Settings"

# 12. Teine DC (AD2) (2p)
Add-Task "12. Teine DC (AD2)" 2 {
    if (Get-ADComputer -Filter "Name -eq 'AD2'" -ErrorAction SilentlyContinue) { "OK" } else { "AD2 puudu" }
} "AD2 domeenis"

# 13. DHCP Failover (1p)
Add-Task "13. DHCP Failover" 1 {
    if (Get-DhcpServerv4Failover -ErrorAction SilentlyContinue) { "OK" } else { "Puudub" }
} "Load balance suhe"

# 14. IIS ja Wordpress (2p)
Add-Task "14. IIS ja Wordpress" 2 {
    if (Get-Website | Where-Object Name -like "*veebileht*") { "OK" } else { "Puudu" }
} "veebileht.perenimi.local"

# 15. HTTPS (2p)
Add-Task "15. HTTPS seadistus" 2 {
    $b = Get-WebBinding -Name "*veebileht*" | Where-Object protocol -eq "https"
    if ($b) { "OK" } else { "Puudu" }
} "Port 443 binding"

# 16. AD Autentimine WP-s (2p)
Add-Task "16. AD Autentimine WP-s" 2 {
    if (Get-ADUser -Filter "Name -like '*Peatoimetaja*'" -ErrorAction SilentlyContinue) { "OK" } else { "Kasutaja puudu" }
} "VEEB kasutajate olemasolu"

# --- 4. HINDE ARVUTAMINE ---
$HinneTekst = switch ($TotalPoints) {
    {$_ -ge 22} { "5 (Väga hea)" }
    {$_ -ge 17} { "4 (Hea)" }
    {$_ -ge 12} { "3 (Rahuldav)" }
    Default { "2 (Mittearvestatud)" }
}

# --- 5. ANDMETE PAKENDAMINE ---
$Payload = [PSCustomObject]@{
    Opilane = $RawName
    KokkuPunkte = $TotalPoints
    Hinne = $HinneTekst
    Kontrollid = $Results
} | ConvertTo-Json -Depth 10

# Lokaalne salvestamine C:\Temp
$Payload | Out-File $FullFilePath -Encoding utf8
Write-Host "`nTulemused salvestatud: $FullFilePath" -ForegroundColor Cyan

# --- 6. SAATMINE LINUX SERVERISSE (Kasutame täpset töötavat koodi) ---
Write-Host "Üritan saata tulemusi aadressile http://$ServerIP:5000..." -ForegroundColor Yellow

try {
    $Response = Invoke-RestMethod -Uri "http://$($ServerIP):5000/api/upload" `
                                  -Method Post `
                                  -Body $Payload `
                                  -ContentType "application/json; charset=utf-8" `
                                  -Proxy $null `
                                  -ErrorAction Stop
    
    Write-Host "EDUKAS! Tulemused saadetud serverisse." -ForegroundColor Green
    Write-Host "Punktid: $TotalPoints / 25 | Hinne: $HinneTekst" -ForegroundColor Green
} catch {
    Write-Host "`nHOIATUS: Automaatne saatmine ebaõnnestus ($($_.Exception.Message))." -ForegroundColor Red
    Write-Host "Kasuta veebivormi ja laadi üles fail: $FullFilePath" -ForegroundColor Yellow
}

```
