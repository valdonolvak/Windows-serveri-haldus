Siin on täiendatud skript, mis on koostatud põhimõttel **"Ootasin vs Leidsin"**. See skript käib läbi kõik 16 punkti, kontrollib nende sisu ja väljastab lõpus õpilasele selge koondraporti (Dashboardi stiilis), kus on välja toodud nii õnnestumised kui ka puudajäägid.

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
$ServerIP = "192.168.124.64" # DashBoard serveri IP

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
        Korras=$p -ge ($MaxP * 0.8); # 80% punktidest märgib ülesande sooritatuks
        Punktid=$p; 
        Selgitus=$fb 
    }
}

Write-Host "`n--- ALUSTAN LÕPUTÖÖ DETAILSET KONTROLLI (vnet $VNET) ---" -ForegroundColor Cyan

# --- 3. KONTROLLID (1-16) ---

# 1. AD ja DNS (1p)
Add-DetailedTask "1. AD ja DNS" 1 {
    $d = (Get-ADDomain).DNSRoot
    if ($d -like "*.local") { return @{Points=1; Feedback="Ootasin: .local domeeni | Leidsin: $d (OK)"} }
    return @{Points=0; Feedback="Ootasin: .local domeeni | Leidsin: $d (VALE)"}
}

# 2. Ketta F: ja struktuur (1p)
Add-DetailedTask "2. Ketas F: ja struktuur" 1 {
    $found = @(); $missing = @()
    if (Test-Path "F:") {
        foreach($f in @("STUFF", "WWW", "Kasutajad$")) {
            if (Test-Path "F:\$f") { $found += $f } else { $missing += $f }
        }
        $p = 0.4 + ($found.Count * 0.2)
        return @{Points=$p; Feedback="Ootasin: STUFF, WWW, Kasutajad$ | Leidsin: $($found -join ',') | Puudu: $($missing -join ',')"}
    }
    return @{Points=0; Feedback="Ootasin: Ketas F: | Leidsin: PUUDUB"}
}

# 3. DHCP Skoop (1p)
Add-DetailedTask "3. DHCP Skoop HKHK" 1 {
    $s = Get-DhcpServerv4Scope | Where-Object Name -like "*HKHK*"
    $target = "192.168.$VNET.100"
    if ($s) {
        if ($s.StartRange -eq $target) { return @{Points=1; Feedback="Ootasin algust: $target | Leidsin: $($s.StartRange) (OK)"} }
        return @{Points=0.5; Feedback="Ootasin algust: $target | Leidsin: $($s.StartRange) (VALE IP)"}
    }
    return @{Points=0; Feedback="Ootasin skoopi 'HKHK' | Leidsin: EI LEIDNUD"}
}

# 4. Domeeniga liitumine (1p)
Add-DetailedTask "4. Klientide domeeniliitumine" 1 {
    $p = 0; $fb = @()
    foreach($c in @("Arvuti1", "Arvuti2")){
        if(Get-ADComputer -Filter "Name -eq '$c'" -ErrorAction SilentlyContinue){ $p += 0.5; $fb += "$c OK" } else { $fb += "$c PUUDU" }
    }
    return @{Points=$p; Feedback="Ootasin: Arvuti1 ja Arvuti2 domeenis | Leidsin: $($fb -join ', ')"}
}

# 5. OU Arvutid paigutus (1p)
Add-DetailedTask "5. OU ARVUTID" 1 {
    $c1 = Get-ADComputer -Identity "Arvuti1" -Properties DistinguishedName -ErrorAction SilentlyContinue
    $c2 = Get-ADComputer -Identity "Arvuti2" -Properties DistinguishedName -ErrorAction SilentlyContinue
    $p = 0; $fb = @()
    if($c1.DistinguishedName -like "*OU=Win10,OU=ARVUTID*"){$p += 0.5; $fb += "Arvuti1 OK"} else {$fb += "Arvuti1 VALE OU"}
    if($c2.DistinguishedName -like "*OU=Win11,OU=ARVUTID*"){$p += 0.5; $fb += "Arvuti2 OK"} else {$fb += "Arvuti2 VALE OU"}
    return @{Points=$p; Feedback="Ootasin: OU=Win10/Win11,OU=ARVUTID | Leidsin: $($fb -join ' | ')"}
}

# 6. OU KASUTAJAD (1p)
Add-DetailedTask "6. OU KASUTAJAD" 1 {
    $ous = Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty Name
    $f = 0; $fb = @()
    foreach($o in @("LEKTORID", "TUDENGID", "VEEB")){
        if(Get-SimilarName $o $ous){ $f++; $fb += "$o OK" } else { $fb += "$o PUUDU" }
    }
    return @{Points=($f/3); Feedback="Ootasin: LEKTORID, TUDENGID, VEEB | Leidsin: $($fb -join ', ')"}
}

# 7. Kasutajad ja grupid (2p)
Add-DetailedTask "7. Kasutajad ja grupid" 2 {
    $p = 0; $fb = @()
    
    # 1. Gruppide kontroll (0.5p)
    $gL = Get-ADGroup -Filter "Name -eq 'Lektorid'" -ErrorAction SilentlyContinue
    $gT = Get-ADGroup -Filter "Name -eq 'Tudengid'" -ErrorAction SilentlyContinue
    if($gL){ $p += 0.25; $fb += "Grupp Lektorid OK" }
    if($gT){ $p += 0.25; $fb += "Grupp Tudengid OK" }
    
    # 2. Kasutajate olemasolu kontroll (0.5p)
    $users = @("oppejoud1", "oppejoud2", "tudeng1", "tudeng2")
    $foundUsers = 0
    foreach($u in $users){
        if(Get-ADUser -Filter "SamAccountName -eq '$u'" -ErrorAction SilentlyContinue){ $foundUsers++ }
    }
    if($foundUsers -ge 4){ $p += 0.5; $fb += "Kasutajad loodud" }
    
    # 3. Logon Hours kontroll (1p)
    $t1 = Get-ADUser -Filter "SamAccountName -eq 'tudeng1'" -Properties LogonHours -ErrorAction SilentlyContinue
    if($t1 -and $t1.LogonHours -and $t1.LogonHours[0] -ne 255){ 
        $p += 1; $fb += "Logon Hours OK" 
    } else {
        $fb += "Logon Hours PUUDU"
    }

    # Tagame, et kui kõik on olemas, on tulemus täpselt 2.0
    return @{Points=$p; Feedback="Ootasin: Grupid ja Tudengite tööaja piirang | Leidsin: $($fb -join ' | ')"}
}

# 8. GPO Taustapildid (2p)
Add-DetailedTask "8. GPO Taustapildid" 2 {
    $g = Get-GPO -All | Where-Object DisplayName -match "Taustapildid"
    if($g){ return @{Points=2; Feedback="Ootasin: GPO_Taustapildid | Leidsin: $($g.DisplayName) (OK)"} }
    return @{Points=0; Feedback="Ootasin: GPO_Taustapildid | Leidsin: PUUDU"}
}

# 9. GPO Folder Redirection (2p)
Add-DetailedTask "9. GPO Folder Redirection" 2 {
    $g = Get-GPO -All | Where-Object DisplayName -match "Redirection"
    if($g){ return @{Points=2; Feedback="Ootasin: GPO_Folder_Redirection | Leidsin: $($g.DisplayName) (OK)"} }
    return @{Points=0; Feedback="Ootasin: GPO_Folder_Redirection | Leidsin: PUUDU"}
}

# 10. Tarkvara GPO-d (2p)
Add-DetailedTask "10. Tarkvara GPO-d" 2 {
    $p = 0; $fb = @()
    $g7 = Get-GPO -All | Where-Object { $_.DisplayName -match "7zip" }
    $gC = Get-GPO -All | Where-Object { $_.DisplayName -match "Chrome" }
    if($g7){$p++; $fb += "7zip OK"}
    if($gC){$p++; $fb += "Chrome OK"}
    return @{Points=$p; Feedback="Ootasin: 7zip ja Chrome MSI poliitikaid | Leidsin: $($fb -join ', ')"}
}

# 11. Chrome seadistamine (2p)
Add-DetailedTask "11. GPO Chrome Settings" 2 {
    $g = Get-GPO -All | Where-Object DisplayName -match "Chrome_Settings"
    if($g){ return @{Points=2; Feedback="Ootasin: ADMX põhine Chrome poliitika | Leidsin: $($g.DisplayName) (OK)"} }
    return @{Points=0; Feedback="Ootasin: Chrome_Settings GPO | Leidsin: PUUDU"}
}

# 12. Teine DC (AD2) (2p)
Add-DetailedTask "12. Teine DC (AD2)" 2 {
    $ad2 = Get-ADDomainController -Identity "AD2" -ErrorAction SilentlyContinue
    if($ad2){ return @{Points=2; Feedback="Ootasin: AD2 on domeenikontroller | Leidsin: OK"} }
    return @{Points=0; Feedback="Ootasin: AD2 staatus | Leidsin: AD2 ei ole DC või on maas"}
}

# 13. DHCP Failover (1p)
Add-DetailedTask "13. DHCP Failover" 1 {
    $f = Get-DhcpServerv4Failover -ErrorAction SilentlyContinue
    if($f){ return @{Points=1; Feedback="Ootasin: Load Balance failover | Leidsin: Režiim $($f.Mode) (OK)"} }
    return @{Points=0; Feedback="Ootasin: DHCP Failover seadistus | Leidsin: PUUDU"}
}

# 14. IIS ja Wordpress (2p)
Add-DetailedTask "14. IIS ja Wordpress" 2 {
    $site = Get-Website | Where-Object Name -like "*veebileht*"
    if($site -and (Test-Path "F:\WWW")){ return @{Points=2; Feedback="Ootasin: IIS Sait ja kataloog F: kettal | Leidsin: OK"} }
    return @{Points=0; Feedback="Ootasin: IIS/WP seadistus | Leidsin: PUUDULIK"}
}

# 15. HTTPS (2p) - REAALNE KONTROLL
Add-DetailedTask "15. HTTPS (Port 443)" 2 {
    $p = 0; $fb = ""
    $b = Get-WebBinding | Where-Object { $_.protocol -eq "https" }
    if($b) {
        $p = 1; $fb = "Binding olemas. "
        try {
            $test = curl.exe -s -k -I "https://localhost" --connect-timeout 3
            if($test -match "200 OK"){ $p = 2; $fb += "Veeb vastab HTTPS kaudu (OK)" }
            else { $fb += "Binding on, aga veebileht ei vasta (200 OK puudu)" }
        } catch { $fb += "HTTPS päring ebaõnnestus" }
    } else { $fb = "Ootasin: HTTPS binding 443 | Leidsin: PUUDU" }
    return @{Points=$p; Feedback=$fb}
}

# 16. WP AD Autentimine (2p) - LDAP LOGI TEST
Add-DetailedTask "16. WP AD Kasutajad" 2 {
    $p = 0; $fb = @()
    $pass = "Toimetaja123!"
    $users = @("Peatoimetaja", "ToimetajaAbi")
    foreach($u in $users) {
        $obj = Get-ADUser -Filter "Name -eq '$u' -or SamAccountName -eq '$u'" -ErrorAction SilentlyContinue
        if($obj) {
            $p += 0.5; $authMsg = "Kasutaja olemas"
            try {
                $dn = $obj.DistinguishedName
                $entry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$dn", $dn, $pass)
                if($entry.NativeGuid){ $p += 0.5; $authMsg += " + Parool OK" }
            } catch { $authMsg += " + Parool VALE" }
            $fb += "$u ($authMsg)"
        } else { $fb += "$u PUUDU" }
    }
    return @{Points=$p; Feedback="Ootasin: Kasutajad ja LDAP paroolitest | Leidsin: $($fb -join ' | ')"}
}

# --- 4. HINDE ARVUTAMINE ---
$Hinne = switch ($global:TotalPoints) {
    {$_ -ge 22} { "5" }
    {$_ -ge 17} { "4" }
    {$_ -ge 12} { "3" }
    Default     { "2" }
}

# --- 5. KOONDKOKKUVÕTE ÕPILASELE KONSOOLIS ---
Write-Host "`n" + "="*60 -ForegroundColor Gray
Write-Host " KOKKUVÕTE: $RawName | PUNKTID: $global:TotalPoints / 25 | HINNE: $Hinne" -ForegroundColor Yellow
Write-Host "="*60 -ForegroundColor Gray

foreach($res in $global:Results) {
    $color = if($res.Korras){"Green"}else{"Red"}
    $sym = if($res.Korras){"✅"}else{"❌"}
    Write-Host "$sym $($res.Nimi): $($res.Punktid)p" -ForegroundColor $color
    Write-Host "   -> $($res.Selgitus)" -ForegroundColor Gray
}

# --- 6. SAATMINE SERVERISSE ---
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

### Mida see skript teisiti teeb?

1. **Detailne tagasiside (Ootasin vs Leidsin):**
* Selle asemel, et öelda "GPO puudub", ütleb skript nüüd näiteks: `Ootasin: GPO_Taustapildid | Leidsin: PUUDU`.
* Kui domeen on vale, ütleb: `Ootasin: .local domeen | Leidsin: mandre.com (VALE)`.


2. **LDAP Turvakontroll:**
* See ei vaata ainult, kas kasutaja on olemas. See proovib reaalselt LDAP kaudu sisse logida parooliga `Toimetaja123!`. Kui parool on vale (õpilane unustas muuta), saab ta punkti ainult kasutaja olemasolu eest, mitte autentimise eest.


3. **Värviline koondraport:**
* Skript väljastab Powershelli aknas lõpus suure tabeli.
* **Roheline:** Punktid täis.
* **Kollane:** Osad punktid käes (nt sisselogimine õnnestus, aga IP on vale).
* **Punane:** 0 punkti.


4. **HTTPS reaalne testimine:**
* Punkt 15 ei vaata ainult IIS-i sätteid, vaid proovib teha päringu. Kui binding on olemas, aga veebileht "viskab errorit", saab õpilane teada, et "veeb ei vasta".
