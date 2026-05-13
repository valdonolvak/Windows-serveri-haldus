##**Kopeeri selle faili sisu**

```powershell

# --- 0. ETTEVALMISTUS ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$TempPath = "C:\Temp"
if (!(Test-Path $TempPath)) { New-Item -Path $TempPath -ItemType Directory -Force | Out-Null }

# --- 1. SISENDID ---
$RawName = Read-Host "Sisesta oma nimi (Eesnimi Perekonnanimi)"
$VNET = Read-Host "Sisesta oma vnet number (XXX)"
$ServerIP = "192.168.124.64"

$SafeName = $RawName.ToLower().Replace(" ","").Replace("ä","a").Replace("ö","o").Replace("ü","u").Replace("õ","o").Replace("š","s").Replace("ž","z")
$FileName = "$SafeName.json"
$FullFilePath = Join-Path $TempPath $FileName

$Results = @()
$TotalPoints = 0

# --- 2. ABI-FUNKTSIOONID ---

function Get-SimilarName {
    param([string]$Expected, [array]$ActualList)
    foreach ($item in $ActualList) {
        if ($item.ToLower().Contains($Expected.ToLower()) -or $Expected.ToLower().Contains($item.ToLower())) { return $item }
    }
    return $null
}

function Add-DetailedTask {
    param([string]$Nimi, [float]$MaxP, [scriptblock]$Logic)
    $TaskResult = &$Logic
    $p = [math]::Round([float]$TaskResult.Points, 2)
    $global:TotalPoints += $p
    $global:Results += [PSCustomObject]@{
        Nimi     = $Nimi
        Korras   = $p -ge $MaxP
        Punktid  = $p
        Selgitus = $TaskResult.Feedback
    }
}

Write-Host "`n--- ALUSTAN LÕPUTÖÖ DETAILSET KONTROLLI (vnet $VNET) ---" -ForegroundColor Cyan

# --- 3. DETAILSED KONTROLLID (1-16) ---

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
    } else { $fb += "Ketas F: puudub üldse" }
    return @{Points=$p; Feedback=($fb -join ", ")}
}

# 3. DHCP Skoop (1p)
Add-DetailedTask "3. DHCP Skoop HKHK" 1 {
    $s = Get-DhcpServerv4Scope | Where-Object Name -like "*HKHK*"
    $target = "192.168.$VNET.100"
    if ($s.StartRange -eq $target) { return @{Points=1; Feedback="OK"} }
    return @{Points=0; Feedback="VIGA: Oodatud algus $target, leitud $($s.StartRange)"}
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
    $c1 = Get-ADComputer -Identity "Arvuti1" -Properties DistinguishedName
    $c2 = Get-ADComputer -Identity "Arvuti2" -Properties DistinguishedName
    if ($c1.DistinguishedName -like "*OU=Win10,OU=ARVUTID*") { $p += 0.5 } else { $fb += "Arvuti1 vales OU-s" }
    if ($c2.DistinguishedName -like "*OU=Win11,OU=ARVUTID*") { $p += 0.5 } else { $fb += "Arvuti2 vales OU-s" }
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
    # Lektorid
    $gL = Get-ADGroup -Filter "Name -eq 'Lektorid'" -ErrorAction SilentlyContinue
    $uL = Get-ADGroupMember -Identity "Lektorid" | Where-Object Name -like "*oppejoud*"
    if($gL){$p+=0.25}; if($uL.Count -ge 2){$p+=0.25} else {$fb+="Lektorid puudu"}
    
    # Tudengid + LogonHours
    $gT = Get-ADGroup -Filter "Name -eq 'Tudengid'" -ErrorAction SilentlyContinue
    $uT = Get-ADUser -Filter "Name -like '*tudeng*'" -Properties LogonHours
    if($gT){$p+=0.25}; if($uT.Count -ge 2){$p+=0.25}
    
    # Logon Hours (M-F 08-19) - Kontrollime tudeng1 peal
    $hrs = (Get-ADUser -Identity "tudeng1" -Properties LogonHours).LogonHours
    if($hrs -and $hrs[0] -eq 0){ $p += 1; $fb+="LogonHours OK" } else {$fb+="LogonHours VIGA"}
    
    return @{Points=[math]::Min($p, 2); Feedback=($fb -join ", ")}
}

# 8-11. GPO-d (8p kokku)
$gpoTasks = @(
    @{N="8. GPO_Taustapildid"; S="Taustapildid"; P=2},
    @{N="9. GPO_Folder_Redirection"; S="Redirection"; P=2},
    @{N="10. Tarkvara GPO-d (7zip/Chrome)"; S="Software"; P=2},
    @{N="11. GPO_Chrome_Settings"; S="Chrome_Settings"; P=2}
)

foreach($gt in $gpoTasks){
    Add-DetailedTask $gt.N $gt.P {
        $all = Get-GPO -All | Select-Object -ExpandProperty DisplayName
        if(Get-SimilarName $gt.S $all){ return @{Points=$gt.P; Feedback="OK"} }
        return @{Points=0; Feedback="GPO-d ei leitud"}
    }
}

# 12. Teine DC (AD2) (2p)
Add-DetailedTask "12. Teine DC (AD2) staatus" 2 {
    $ad2 = Get-ADDomainController -Identity "AD2" -ErrorAction SilentlyContinue
    if($ad2){ return @{Points=2; Feedback="OK: AD2 on DC"} }
    return @{Points=0; Feedback="VIGA: AD2 ei ole DC või pole kättesaadav"}
}

# 13. DHCP Failover (1p)
Add-DetailedTask "13. DHCP Failover seadistus" 1 {
    $f = Get-DhcpServerv4Failover -ErrorAction SilentlyContinue
    if($f){ return @{Points=1; Feedback="OK: Mood: $($f.Mode)"} }
    return @{Points=0; Feedback="VIGA: Failover suhet ei leitud"}
}

# 14. IIS ja Wordpress (2p)
Add-DetailedTask "14. IIS ja Wordpress (F: kettal)" 2 {
    $site = Get-Website | Where-Object Name -like "*veebileht*"
    $path = Test-Path "F:\WWW"
    $p = 0; if($site){$p+=1}; if($path){$p+=1}
    return @{Points=$p; Feedback="Sait: $(if($site){'Jah'}else{'Ei'}), Kaust F-il: $(if($path){'Jah'}else{'Ei'})"}
}

# 15. HTTPS (2p)
Add-DetailedTask "15. HTTPS (Sertifikaat)" 2 {
    $b = Get-WebBinding -Name "*veebileht*" | Where-Object protocol -eq "https"
    if($b){ return @{Points=2; Feedback="OK: Port 443 seadistatud"} }
    return @{Points=0; Feedback="VIGA: HTTPS puudub"}
}

# 16. WP AD Autentimine (2p)
Add-DetailedTask "16. WP AD Kasutajad (VEEB)" 2 {
    $u1 = Get-ADUser -Filter "Name -eq 'Peatoimetaja'" -ErrorAction SilentlyContinue
    $u2 = Get-ADUser -Filter "Name -eq 'ToimetajaAbi'" -ErrorAction SilentlyContinue
    $p = 0; if($u1){$p+=1}; if($u2){$p+=1}
    return @{Points=$p; Feedback="Peatoimetaja: $(if($u1){'OK'}else{'Puudu'}), ToimetajaAbi: $(if($u2){'OK'}else{'Puudu'})"}
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
    Invoke-RestMethod -Uri "http://$ServerIP:5000/api/upload" -Method Post -Body $Payload -ContentType "application/json; charset=utf-8" -Proxy $null
    Write-Host "`nKONTROLL LÕPPENUD. Tulemused saadetud serverisse." -ForegroundColor Green
    Write-Host "Sinu punktid: $TotalPoints / 25" -ForegroundColor Yellow
    Write-Host "Hinne: $HinneTekst" -ForegroundColor Yellow
} catch {
    Write-Host "`nAndmete saatmine ebaõnnestus, kuid fail salvestati: $FullFilePath" -ForegroundColor Red
}

```
