##**Kopeeri selle faili sisu**

```powershell

# --- 0. ETTEVALMISTUS JA MOODULID ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
Import-Module GroupPolicy -ErrorAction SilentlyContinue
Import-Module DhcpServer -ErrorAction SilentlyContinue
Import-Module WebAdministration -ErrorAction SilentlyContinue

$TempPath = "C:\Temp"
if (!(Test-Path $TempPath)) { New-Item -Path $TempPath -ItemType Directory -Force | Out-Null }

# --- 1. SISENDID ---
$RawName = Read-Host "Sisesta oma nimi (Eesnimi Perekonnanimi)"
$VNET = Read-Host "Sisesta oma vnet number (XXX)"
$ServerIP = "192.168.124.64"

# Failinime loogika: jyrijuurikas.json
$SafeName = $RawName.ToLower().Replace(" ","").Replace("ä","a").Replace("ö","o").Replace("ü","u").Replace("õ","o").Replace("š","s").Replace("ž","z")
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
    $p = 0
    $fb = ""
    try {
        # Käivitame loogika ja püüame vead kinni iga punkti sees eraldi
        $TaskResult = &$Logic
        $p = [math]::Round([float]$TaskResult.Points, 2)
        $fb = $TaskResult.Feedback
    } catch {
        $p = 0
        $fb = "KONTROLLI VIGA: Teenus/objekt puudub või pole kättesaadav."
    }
    
    $global:TotalPoints += $p
    $global:Results += [PSCustomObject]@{
        Nimi     = $Nimi
        Korras   = $p -ge $MaxP
        Punktid  = $p
        Selgitus = $fb
    }
}

Write-Host "`n--- ALUSTAN DETAILSET KONTROLLI (vnet $VNET) ---" -ForegroundColor Cyan

# --- 3. KONTROLLID (1-16) ---

# 1. AD ja DNS (1p)
Add-DetailedTask "1. AD ja DNS seadistus" 1 {
    $d = (Get-ADDomain).DNSRoot
    if ($d -like "*.local") { return @{Points=1; Feedback="OK: $d"} }
    return @{Points=0; Feedback="VIGA: Domeen on $d, aga pidi olema .local"}
}

# 2. Ketta F: ja struktuur (1p)
Add-DetailedTask "2. Ketta F: ja kaustad" 1 {
    $p = 0; $fb = @()
    if (Test-Path "F:") { 
        $p += 0.4
        $folders = @("STUFF", "WWW", "Kasutajad$")
        foreach($f in $folders) {
            if (Test-Path "F:\$f") { $p += 0.2 } else { $fb += "Kaust $f puudu" }
        }
    } else { $fb += "Ketas F: puudub" }
    return @{Points=$p; Feedback=($fb -join ", ")}
}

# 3. DHCP Skoop (1p)
Add-DetailedTask "3. DHCP Skoop HKHK" 1 {
    $s = Get-DhcpServerv4Scope | Where-Object Name -like "*HKHK*"
    $target = "192.168.$VNET.100"
    if ($s -and $s.StartRange -eq $target) { return @{Points=1; Feedback="OK"} }
    return @{Points=0; Feedback="VIGA: Oodatud algus $target"}
}

# 4. Domeeniga liitumine (1p)
Add-DetailedTask "4. Klientide domeeniga liitumine" 1 {
    $c1 = Get-ADComputer -Filter "Name -eq 'Arvuti1'" -ErrorAction SilentlyContinue
    $c2 = Get-ADComputer -Filter "Name -eq 'Arvuti2'" -ErrorAction SilentlyContinue
    $p = 0; if($c1){$p+=0.5}; if($c2){$p+=0.5}
    return @{Points=$p; Feedback="Arvuti1: $(if($c1){'OK'}else{'Puudu'}), Arvuti2: $(if($c2){'OK'}else{'Puudu'})"}
}

# 5. OU Arvutid ja paigutus (1p)
Add-DetailedTask "5. OU ARVUTID ja arvutite asukoht" 1 {
    $p = 0; $fb = @()
    $c1 = Get-ADComputer -Identity "Arvuti1" -Properties DistinguishedName -ErrorAction SilentlyContinue
    $c2 = Get-ADComputer -Identity "Arvuti2" -Properties DistinguishedName -ErrorAction SilentlyContinue
    if ($c1 -and $c1.DistinguishedName -like "*OU=Win10,OU=ARVUTID*") { $p += 0.5 } else { $fb += "Arvuti1 vales OU-s" }
    if ($c2 -and $c2.DistinguishedName -like "*OU=Win11,OU=ARVUTID*") { $p += 0.5 } else { $fb += "Arvuti2 vales OU-s" }
    return @{Points=$p; Feedback=($fb -join "; ")}
}

# 6. OU KASUTAJAD (1p)
Add-DetailedTask "6. OU KASUTAJAD struktuur" 1 {
    $ous = Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty Name
    $req = @("LEKTORID", "TUDENGID", "VEEB")
    $found = 0; foreach($o in $req){ if(Get-SimilarName $o $ous){$found++} }
    return @{Points=($found/3); Feedback="Leitud $found / 3-st (Lektorid, Tudengid, Veeb)"}
}

# 7. Kasutajad ja grupid (2p)
Add-DetailedTask "7. Kasutajad, grupid ja piirangud" 2 {
    $p = 0; $fb = @()
    # Lektorid ja Tudengid grupid
    $gL = Get-ADGroup -Filter "Name -eq 'Lektorid'" -ErrorAction SilentlyContinue
    $gT = Get-ADGroup -Filter "Name -eq 'Tudengid'" -ErrorAction SilentlyContinue
    if($gL){ $p += 0.25; $m = Get-ADGroupMember -Identity "Lektorid" -ErrorAction SilentlyContinue; if($m.Count -ge 2){$p+=0.25} }
    if($gT){ $p += 0.25; $uT = Get-ADUser -Filter "Name -like '*tudeng*'" -ErrorAction SilentlyContinue; if($uT.Count -ge 2){$p+=0.25} }
    
    # Logon Hours kontroll
    $t1 = Get-ADUser -Filter "SamAccountName -eq 'tudeng1'" -Properties LogonHours -ErrorAction SilentlyContinue
    if($t1 -and $t1.LogonHours -and $t1.LogonHours[0] -eq 0){ $p += 1; $fb+="LogonHours OK" } else {$fb+="LogonHours puudu/vale"}
    
    return @{Points=[math]::Min($p, 2); Feedback=($fb -join ", ")}
}

# 8-11. GPO-d (8p)
$gpoTasks = @(
    @{N="8. GPO_Taustapildid"; S="Taustapildid"; P=2},
    @{N="9. GPO_Folder_Redirection"; S="Redirection"; P=2},
    @{N="10. Tarkvara GPO-d (7zip/Chrome)"; S="Software"; P=2},
    @{N="11. GPO_Chrome_Settings"; S="Chrome_Settings"; P=2}
)
foreach($gt in $gpoTasks){
    Add-DetailedTask $gt.N $gt.P {
        $all = Get-GPO -All -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DisplayName
        if(Get-SimilarName $gt.S $all){ return @{Points=$gt.P; Feedback="OK"} }
        return @{Points=0; Feedback="GPO-d ei leitud"}
    }
}

# 12. Teine DC (AD2) (2p)
Add-DetailedTask "12. Teine DC (AD2) staatus" 2 {
    $ad2 = Get-ADDomainController -Identity "AD2" -ErrorAction SilentlyContinue
    if($ad2){ return @{Points=2; Feedback="OK: AD2 on DC"} }
    return @{Points=0; Feedback="VIGA: AD2 ei ole DC"}
}

# 13. DHCP Failover (1p)
Add-DetailedTask "13. DHCP Failover seadistus" 1 {
    $f = Get-DhcpServerv4Failover -ErrorAction SilentlyContinue
    if($f){ return @{Points=1; Feedback="OK"} }
    return @{Points=0; Feedback="VIGA: Failover puudub"}
}

# 14. IIS ja Wordpress (2p)
Add-DetailedTask "14. IIS ja Wordpress" 2 {
    $site = Get-Website -ErrorAction SilentlyContinue | Where-Object Name -like "*veebileht*"
    $p = 0; if($site){$p+=1}; if(Test-Path "F:\WWW"){$p+=1}
    return @{Points=$p; Feedback="Sait: $(if($site){'OK'}else{'Ei'}), Kaust F: $(if(Test-Path 'F:\WWW'){'OK'}else{'Ei'})"}
}

# 15. HTTPS (2p)
Add-DetailedTask "15. HTTPS seadistus" 2 {
    $b = Get-WebBinding -Name "*veebileht*" -ErrorAction SilentlyContinue | Where-Object protocol -eq "https"
    if($b){ return @{Points=2; Feedback="OK"} }
    return @{Points=0; Feedback="VIGA: Port 443 puudu"}
}

# 16. WP AD Autentimine (2p)
Add-DetailedTask "16. WP AD Kasutajad (VEEB)" 2 {
    $u1 = Get-ADUser -Filter "Name -eq 'Peatoimetaja'" -ErrorAction SilentlyContinue
    $u2 = Get-ADUser -Filter "Name -eq 'ToimetajaAbi'" -ErrorAction SilentlyContinue
    $p = 0; if($u1){$p+=1}; if($u2){$p+=1}
    return @{Points=$p; Feedback="Kasutajad: $p / 2"}
}

# --- 4. HINDAMINE ---
$HinneTekst = switch ($TotalPoints) {
    {$_ -ge 22} { "5 (Väga hea)" }
    {$_ -ge 17} { "4 (Hea)" }
    {$_ -ge 12} { "3 (Rahuldav)" }
    Default     { "2 (Mittearvestatud)" }
}

# --- 5. SAATMINE ---
$Payload = [PSCustomObject]@{
    Opilane = $RawName
    KokkuPunkte = $TotalPoints
    Hinne = $HinneTekst
    Kontrollid = $Results
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

```
