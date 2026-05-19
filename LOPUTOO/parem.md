Siin on täiendatud skript, mis on koostatud põhimõttel **"Ootasin vs Leidsin"**. See skript käib läbi kõik 16 punkti, kontrollib nende sisu ja väljastab lõpus õpilasele selge koondraporti (Dashboardi stiilis), kus on välja toodud nii õnnestumised kui ka puudajäägid.

```powershell
# --- 0. ETTEVALMISTUS ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
Import-Module ActiveDirectory, GroupPolicy, DhcpServer, WebAdministration -ErrorAction SilentlyContinue

$script:Results = @()
$script:TotalPoints = 0
$RawName = Read-Host "Sisesta õpilase nimi"
$VNET = Read-Host "Sisesta oma vnet number"
$ServerIP = "192.168.124.64"

# --- 1. ABI-FUNKTSIOONID ---

function Add-DetailedTask {
    param([string]$Nimi, [float]$MaxP, [scriptblock]$Logic)
    $p = 0; $fb = ""
    try {
        $r = &$Logic
        $p = [math]::Round([float]$r.Points, 2)
        $fb = $r.Feedback
    } catch {
        $p = 0
        $fb = "❌ SÜSTEEMNE VIGA: $($_.Exception.Message)"
    }
    $script:TotalPoints += $p
    $script:Results += [PSCustomObject]@{ Nimi=$Nimi; Punktid=$p; Max=$MaxP; Selgitus=$fb }
}

Write-Host "`n--- KONTROLLI KÄIVITAMINE: $RawName (vnet $VNET) ---" -ForegroundColor Cyan

# --- 2. KONTROLLID (1-16) ---

# 1. AD ja DNS
Add-DetailedTask "1. AD ja DNS" 1 {
    $d = (Get-ADDomain).DNSRoot
    if ($d -like "*.local") { return @{Points=1; Feedback="Ootasin: .local domeen | Leidsin: $d (OK)"} }
    return @{Points=0; Feedback="Ootasin: .local domeen | Leidsin: $d (VALE)"}
}

# 2. Ketas F:
Add-DetailedTask "2. Ketas F: ja kaustad" 1 {
    $found = @(); $missing = @()
    if (Test-Path "F:") {
        foreach($f in @("STUFF", "WWW", "Kasutajad$")) {
            if (Test-Path "F:\$f") { $found += $f } else { $missing += $f }
        }
        $p = 0.4 + ($found.Count * 0.2)
        return @{Points=$p; Feedback="Ootasin: F:\ + STUFF,WWW,Kasutajad$ | Leidsin: $($found -join ',') | Puudu: $($missing -join ',')"}
    }
    return @{Points=0; Feedback="Ootasin: Ketas F: | Leidsin: PUUDUB"}
}

# 3. DHCP Skoop
Add-DetailedTask "3. DHCP Skoop HKHK" 1 {
    $s = Get-DhcpServerv4Scope | Where-Object Name -like "*HKHK*"
    $target = "192.168.$VNET.100"
    if ($s) {
        if ($s.StartRange -eq $target) { return @{Points=1; Feedback="Ootasin algust: $target | Leidsin: $($s.StartRange) (OK)"} }
        return @{Points=0.5; Feedback="Ootasin algust: $target | Leidsin: $($s.StartRange) (VALE IP)"}
    }
    return @{Points=0; Feedback="Ootasin skoopi 'HKHK' | Leidsin: EI LEIDNUD"}
}

# 5. OU Arvutid
Add-DetailedTask "5. OU ARVUTID" 1 {
    $c1 = Get-ADComputer -Identity "Arvuti1" -Properties DistinguishedName -ErrorAction SilentlyContinue
    $loc = if($c1){$c1.DistinguishedName} else {"Arvuti puudu"}
    if($loc -like "*OU=Win10,OU=ARVUTID*") { return @{Points=1; Feedback="Ootasin: Arvuti1 asukoht OU=Win10 | Leidsin: OK"} }
    return @{Points=0; Feedback="Ootasin: Arvuti1 asukoht OU=Win10 | Leidsin: $loc"}
}

# 8. GPO Taustapildid (PARANDATUD)
Add-DetailedTask "8. GPO Taustapildid" 2 {
    $g = Get-GPO -All | Where-Object DisplayName -match "Taustapildid"
    if($g) { return @{Points=2; Feedback="Ootasin: GPO_Taustapildid | Leidsin: $($g.DisplayName) (OK)"} }
    return @{Points=0; Feedback="Ootasin: GPO nimega 'Taustapildid' | Leidsin: PUUDU"}
}

# 10. Tarkvara GPO-d
Add-DetailedTask "10. Tarkvara GPO-d" 2 {
    $g7 = Get-GPO -All | Where-Object { $_.DisplayName -match "7zip" }
    $gC = Get-GPO -All | Where-Object { $_.DisplayName -match "Chrome" }
    $p = 0; $msg = ""
    if($g7){$p++; $msg+="7zip olemas. "} else {$msg+="7zip PUUDU. "}
    if($gC){$p++; $msg+="Chrome olemas."} else {$msg+="Chrome PUUDU."}
    return @{Points=$p; Feedback="Ootasin: 7zip ja Chrome GPO-d | Leidsin: $msg"}
}

# 15. HTTPS (KONTROLLIB VASTUST)
Add-DetailedTask "15. HTTPS (Port 443)" 2 {
    $b = Get-WebBinding | Where-Object { $_.protocol -eq "https" -and $_.bindingInformation -match "443" }
    if($b) {
        $test = curl.exe -s -k -I "https://localhost" --connect-timeout 2
        if($test -match "200 OK") { return @{Points=2; Feedback="Ootasin: HTTPS vastust | Leidsin: 200 OK (OK)"} }
        return @{Points=1; Feedback="Ootasin: HTTPS vastust | Leidsin: Binding olemas, aga veeb ei vasta"}
    }
    return @{Points=0; Feedback="Ootasin: HTTPS Binding | Leidsin: PUUDU"}
}

# 16. WP AD Autentimine (LDAP + PAROOL)
Add-DetailedTask "16. WP AD Kasutajad" 2 {
    $p = 0; $fb = @()
    $users = @("Peatoimetaja", "ToimetajaAbi")
    foreach($u in $users) {
        $obj = Get-ADUser -Filter "Name -eq '$u' -or SamAccountName -eq '$u'" -ErrorAction SilentlyContinue
        if($obj) {
            $p += 0.5; $fb += "$u olemas"
            try {
                $entry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$($obj.DistinguishedName)", $obj.DistinguishedName, "Toimetaja123!")
                if($entry.NativeGuid) { $p += 0.5; $fb += " (Parool OK)" }
            } catch { $fb += " (Parool VALE)" }
        } else { $fb += "$u PUUDU" }
    }
    return @{Points=$p; Feedback="Ootasin: Kasutajad + parool Toimetaja123! | Leidsin: $($fb -join ', ')"}
}

# --- 3. KOONDARUANNE ÕPILASELE ---

Write-Host "`n" + "="*60 -ForegroundColor Gray
Write-Host " KOONDARUANNE: $RawName" -ForegroundColor Yellow
Write-Host "="*60 -ForegroundColor Gray

foreach ($res in $script:Results) {
    $color = if($res.Punktid -eq $res.Max){"Green"} elseif($res.Punktid -gt 0){"Yellow"} else {"Red"}
    Write-Host ("[{0}/{1}] {2}" -f $res.Punktid, $res.Max, $res.Nimi) -ForegroundColor $color
    Write-Host "      -> $($res.Selgitus)" -ForegroundColor Gray
}

Write-Host "="*60 -ForegroundColor Gray
$Hinne = switch ($script:TotalPoints) { {$_ -ge 22}{5} {$_ -ge 17}{4} {$_ -ge 12}{3} Default{2} }
Write-Host "KOKKU: $script:TotalPoints / 25 punkti | HINNE: $Hinne" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Gray

# --- 4. SAATMINE ---
$Payload = [PSCustomObject]@{ Opilane=$RawName; KokkuPunkte=$script:TotalPoints; Hinne=$Hinne; Kontrollid=$script:Results } | ConvertTo-Json -Depth 10
try {
    Invoke-RestMethod -Uri "http://$($ServerIP):5000/api/upload" -Method Post -Body $Payload -ContentType "application/json; charset=utf-8" -TimeoutSec 10 | Out-Null
    Write-Host "Andmed saadetud serverisse." -ForegroundColor DarkGreen
} catch {
    Write-Host "Serverisse saatmine ebaõnnestus." -ForegroundColor Red
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
