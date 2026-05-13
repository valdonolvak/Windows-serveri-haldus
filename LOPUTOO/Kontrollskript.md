##**Kopeeri selle faili sisu**

```powershell
# --- 0. ETTEVALMISTUS JA TEED ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$TempPath = "C:\Temp"
if (!(Test-Path $TempPath)) { New-Item -Path $TempPath -ItemType Directory -Force | Out-Null }

# --- 1. KASUTAJA SISEND ---
$RawName = Read-Host "Sisesta oma nimi (Eesnimi Perekonnanimi)"
$VNET = Read-Host "Sisesta oma vnet number (XXX)"
$ServerIP = "192.168.124.64"

# Failinime genereerimine: jyrijuurikas.json
$SafeName = $RawName.ToLower().Replace(" ","").Replace("ä","a").Replace("ö","o").Replace("ü","u").Replace("õ","o").Replace("š","s").Replace("ž","z")
$FileName = "$SafeName.json"
$FullFilePath = Join-Path $TempPath $FileName

$Results = @()
$TotalPoints = 0

# --- 2. ABI-FUNKTSIOONID ---

# Funktsioon sarnase nime otsimiseks (GPO-d, OU-d jne)
function Get-SimilarName {
    param([string]$Expected, [array]$ActualList)
    foreach ($item in $ActualList) {
        if ($item -like "*$Expected*" -or $Expected -like "*$item*") { return $item }
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
    } catch { $Expl = "Viga: $($_.Exception.Message)" }

    $global:Results += [PSCustomObject]@{
        Nimi = $Nimi; Korras = $Status; Punktid = if($Status){$MaxP}else{0}; Selgitus = $Expl
    }
}

Write-Host "`n--- ALUSTAN LÕPUTÖÖ KONTROLLI (vnet $VNET) ---" -ForegroundColor Cyan

# --- 3. KONTROLLID (16 PUNKTI) ---

# 1. AD ja DNS (1p)
Add-Task "AD ja DNS seadistus" 1 {
    $d = (Get-ADDomain).DNSRoot
    if ($d -like "*.local") { "OK" } else { $d }
} "perenimi.local"

# 2. Ketta F: initsialiseerimine (1p)
Add-Task "Ketta F: initsialiseerimine" 1 {
    if (Test-Path "F:") { "OK" } else { "F: puudub" }
} "Partitsioon F:"

# 3. DHCP Skoop HKHK (1p)
Add-Task "DHCP skoop HKHK" 1 {
    $s = Get-DhcpServerv4Scope | Where-Object Name -like "*HKHK*"
    if ($s.StartRange -eq "192.168.$VNET.100") { "OK" } else { $s.StartRange }
} "Algus 192.168.$VNET.100"

# 4. Domeeniga liitumine (Arvuti1, Arvuti2) (1p)
Add-Task "Domeeniga liitumine" 1 {
    $comps = Get-ADComputer -Filter "Name -like 'Arvuti*'"
    if ($comps.Count -ge 2) { "OK" } else { "$($comps.Count) arvutit leitud" }
} "Arvuti1 ja Arvuti2 domeenis"

# 5. OU struktuur ARVUTID (Win10, Win11) (1p)
Add-Task "OU Arvutid struktuur" 1 {
    $ous = Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty Name
    if (Get-SimilarName "Win10" $ous) { "OK" } else { "Win10 OU-d ei leitud" }
} "OU Win10 ja Win11"

# 6. OU KASUTAJAD (1p)
Add-Task "OU KASUTAJAD struktuur" 1 {
    $ous = Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty Name
    if (Get-SimilarName "LEKTORID" $ous) { "OK" } else { "LEKTORID OU puudu" }
} "LEKTORID, TUDENGID, VEEB"

# 7. Kasutajad ja grupid (2p)
Add-Task "Kasutajad ja grupid" 2 {
    if (Get-ADGroup -Filter "Name -like '*Tudengid*'" -ErrorAction SilentlyContinue) { "OK" } else { "Gruppi ei leitud" }
} "Grupp Tudengid ja Lektorid"

# 8. GPO Taustapildid (Fuzzy search) (2p)
Add-Task "GPO Taustapildid" 2 {
    $allGPOs = Get-GPO -All | Select-Object -ExpandProperty DisplayName
    $found = Get-SimilarName "Taustapildid" $allGPOs
    if ($found) { "OK" } else { "Sarnast GPO-d ei leitud" }
} "GPO_Taustapildid"

# 9. GPO Folder Redirection (Fuzzy search) (2p)
Add-Task "GPO Folder Redirection" 2 {
    $allGPOs = Get-GPO -All | Select-Object -ExpandProperty DisplayName
    $found = Get-SimilarName "Redirection" $allGPOs
    if ($found) { "OK" } else { "Sarnast GPO-d ei leitud" }
} "GPO_Folder_Redirection"

# 10. Tarkvara GPO-d (7zip/Chrome) (2p)
Add-Task "Tarkvara GPO-d" 2 {
    $allGPOs = Get-GPO -All | Select-Object -ExpandProperty DisplayName
    if ((Get-SimilarName "7zip" $allGPOs) -and (Get-SimilarName "Chrome" $allGPOs)) { "OK" } else { "Mõni GPO puudu" }
} "7zip ja Chrome GPO-d"

# 11. Chrome seadistused (2p)
Add-Task "Chrome seadistused" 2 {
    $allGPOs = Get-GPO -All | Select-Object -ExpandProperty DisplayName
    if (Get-SimilarName "Chrome_Settings" $allGPOs) { "OK" } else { "Ei leitud" }
} "GPO_Chrome_Settings"

# 12. Teine DC (AD2) (2p)
Add-Task "Teine DC (AD2)" 2 {
    if (Get-ADComputer -Filter "Name -eq 'AD2'" -ErrorAction SilentlyContinue) { "OK" } else { "AD2 puudub" }
} "AD2 domeenis"

# 13. DHCP Failover (1p)
Add-Task "DHCP Failover" 1 {
    if (Get-DhcpServerv4Failover -ErrorAction SilentlyContinue) { "OK" } else { "Seadistamata" }
} "Failover suhe AD1 ja AD2 vahel"

# 14. IIS ja Wordpress (2p)
Add-Task "IIS ja Wordpress" 2 {
    if (Get-Website | Where-Object Name -like "*veebileht*") { "OK" } else { "Veebilehte ei leitud" }
} "veebileht.perenimi.local"

# 15. HTTPS seadistus (2p)
Add-Task "HTTPS seadistus" 2 {
    $b = Get-WebBinding -Name "*veebileht*" | Where-Object protocol -eq "https"
    if ($b) { "OK" } else { "443 binding puudu" }
} "HTTPS (port 443)"

# 16. AD Autentimine WP-s (2p)
Add-Task "AD Autentimine WP-s" 2 {
    $u = Get-ADUser -Filter "Name -like '*Peatoimetaja*'" -ErrorAction SilentlyContinue
    if ($u) { "OK" } else { "Kasutaja puudu" }
} "VEEB OU kasutajate olemasolu"

# --- 4. HINDE ARVUTAMINE ---
$Hinne = switch ($TotalPoints) {
    {$_ -ge 22} { "5 (Väga hea)" }
    {$_ -ge 17} { "4 (Hea)" }
    {$_ -ge 12} { "3 (Rahuldav)" }
    Default { "2 (Mittearvestatud)" }
}

# --- 5. SALVESTAMINE JA SAATMINE ---
$Payload = [PSCustomObject]@{
    Opilane = $RawName
    KokkuPunkte = $TotalPoints
    Hinne = $Hinne
    Kontrollid = $Results
} | ConvertTo-Json -Depth 10

$Payload | Out-File $FullFilePath -Encoding utf8
Write-Host "`nTulemused salvestatud: $FullFilePath" -ForegroundColor Cyan

try {
    Invoke-RestMethod -Uri "http://$ServerIP:5000/api/upload" -Method Post -Body $Payload -ContentType "application/json; charset=utf-8" -Proxy $null
    Write-Host "EDUKAS! Punktid: $TotalPoints / 25 | Hinne: $Hinne" -ForegroundColor Green
} catch {
    Write-Host "VIGA: Automaatne saatmine ebaõnnestus. Kasuta veebivormi." -ForegroundColor Red
}


```
