#### Kui töö valmis, siis kopeeri see Powershelli skript ja läbi Powershell ISE salvesta see enda arvutisse  kausta **C:\Temp** nimega **Kontroll.ps1 **ja käivita ese Powershell ISE rakenduses ####

----

### Täielik ja detailne kontrollskript: `Kontroll.ps1`

```powershell


# --- 0. PUHASTUS JA ETTEVALMISTUS ---
$global:Results = @()      # Tühjendame tulemuste massiivi
$global:TotalPoints = 0    # Nullime punktid
$ErrorActionPreference = "SilentlyContinue"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
Import-Module ActiveDirectory, GroupPolicy, DhcpServer, WebAdministration -ErrorAction SilentlyContinue

$TempPath = "C:\Temp"
if (!(Test-Path $TempPath)) { New-Item -Path $TempPath -ItemType Directory -Force | Out-Null }

# --- 1. KASUTAJA SISENDID JA NIMELAHELDUS ---
$RawName = Read-Host "Sisesta oma nimi (Eesnimi Perekonnanimi)"
$VNET = Read-Host "Sisesta oma vnet number (XXX)"

# Funktsioon täpitähtede eemaldamiseks
function Clean-String {
    param([string]$InputString)
    return $InputString.ToLower().Replace("õ","o").Replace("ä","a").Replace("ö","o").Replace("ü","u").Replace(" ","")
}

# TUVASTAME JA PUHASTAME PERENIME
try {
    $DomainInfo = Get-ADDomain -ErrorAction Stop
    $RawSurname = $DomainInfo.DNSRoot.Split('.')[0]
    $script:Surname = Clean-String $RawSurname
} catch {
    $NameParts = $RawName.Split(' ')
    $pName = if ($NameParts.Count -gt 1) { $NameParts[1] } else { $NameParts[0] }
    $script:Surname = Clean-String $pName
}

# DEFINEERIME URL-id (Väiketähtedega ja täppideta)
$script:TargetDomain = "veebileht.$($script:Surname).local"
$script:TargetURL = "https://$($script:TargetDomain)"

# Dashboardi seaded
$DashboardIP = "192.168.124.64" 
$script:AD1_IP = "192.168.$VNET.10"

# Failinime loogika (kasutame sama puhastust)
$SafeName = Clean-String $RawName
$FullFilePath = Join-Path $TempPath "$SafeName.json"

Write-Host "`nInfo: Puhastatud perenimi [$($script:Surname)] | URL [$($script:TargetURL)]" -ForegroundColor Yellow


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

# 14. IIS, Wordpress ja MySQL seadistus (TÄIENDATUD)
Add-DetailedTask "14. IIS ja Wordpress" 2 {
    $p = 0; $fb = @()
    $site = Get-Website | Where-Object { $_.Name -match "veebileht" -or $_.Name -match "wordpress" }
    
    if ($site) {
        $p += 1; $fb += "IIS Sait olemas"
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
        } else { $fb += "wp-config.php puudu" }
    } else { $fb += "IIS Sait puudu" }
    
    return @{Points=$p; Feedback=($fb -join " | ")}
}

# 15. HTTPS (KONTROLL AINULT PÄRIS URL-iga)
Add-DetailedTask "15. HTTPS (Port 443)" 2 {
    $p = 0; $fb = @()
    
    $binding = Get-WebBinding | Where-Object { $_.protocol -eq "https" -and $_.bindingInformation -match "443" }
    
    if ($binding) {
        $p += 1; $fb += "Binding 443 olemas"
        
        # Testime päris URL-i, mille me alguses kokku panime
        $test = curl.exe -s -k -I "$TargetURL" --connect-timeout 5 2>&1
        
        if ($test -match "200 OK" -or $test -match "301" -or $test -match "302") {
            $p += 1; $fb += "Veebivastus OK ($TargetURL)"
        } else {
            $fb += "VIGA: Sait ei vasta nimega $TargetURL"
        }
    } else { $fb += "VIGA: HTTPS sidumine puudub" }
    
    return @{Points=$p; Feedback=($fb -join " | ")}
}

# 16. WP AD Autentimine (KÜPSISEPÕHINE KONTROLL)
Add-DetailedTask "16. WP AD Kasutajad" 2 {
    $p = 0; $fb = @()
    $testUser = "Peatoimetaja"
    $testPass = "Toimetaja123!"
    
    $u1 = Get-ADUser -Filter "SamAccountName -eq '$testUser'" -ErrorAction SilentlyContinue
    if ($u1) {
        $p += 0.5; $fb += "Kasutajad AD-s olemas"
        
        # Lisame URL-ile sisselogimise tee
        $LoginURL = "$TargetURL/wp-login.php"
        $cookieFile = "$env:TEMP\wp_ldap_cookie.txt"
        if (Test-Path $cookieFile) { Remove-Item $cookieFile }

        try {
            curl.exe -s -k -c $cookieFile "$LoginURL" --connect-timeout 5 | Out-Null
            $postData = "log=$testUser&pwd=$testPass&wp-submit=Log+In&testcookie=1"
            $result = curl.exe -s -k -L -i -b $cookieFile -c $cookieFile -d "$postData" "$LoginURL" --connect-timeout 10

            $cookieContent = if (Test-Path $cookieFile) { Get-Content $cookieFile } else { "" }

            if ($cookieContent -match "wordpress_logged_in" -or $result -match "location: .*wp-admin") {
                $p += 1.5; $fb += "LDAP autentimine TOIMIB ($TargetURL)"
            } else {
                $fb += "Autentimine ebaõnnestus aadressil $LoginURL"
            }
        } catch { $fb += "Viga ühenduses: $($_.Exception.Message)" }
    } else { $fb += "Kasutajat $testUser ei leitud AD-st" }

    return @{Points=$p; Feedback=($fb -join " | ")}
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

# --- 6. SALVESTAMINE JA SAATMINE SERVERISSE ---

# 1. Koostame andmepaketi
$PayloadObj = [PSCustomObject]@{
    Opilane     = $RawName
    VNET        = $VNET
    Aeg         = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    KokkuPunkte = $global:TotalPoints
    Hinne       = $Hinne
    Kontrollid  = $global:Results
}
$JsonData = $PayloadObj | ConvertTo-Json -Depth 10

try {
    # 2. SALVESTAMINE (Ülekirjutamine)
    $JsonData | Set-Content -Path $FullFilePath -Encoding utf8 -Force
    Write-Host "`n✅ Uus raport loodud: $FullFilePath" -ForegroundColor Cyan

    # 3. SAATMINE SERVERISSE 
    # NB! Kasutame $DashboardIP muutujat (või $ServerIP, olenevalt kumba sa alguses defineerisid)
    # Kui sul on alguses $DashboardIP = "192.168.124.64", siis kasuta seda:
    $TargetIP = if ($DashboardIP) { $DashboardIP } else { "192.168.124.64" }
    
    $FullApiUrl = "http://$($TargetIP):5000/api/upload"
    
    Invoke-RestMethod -Uri $FullApiUrl -Method Post -Body $JsonData -ContentType "application/json; charset=utf-8" -TimeoutSec 15 | Out-Null
    Write-Host "✅ ANDMED SAADETUD DASHBOARD SERVERISSE ($TargetIP)." -ForegroundColor Green

    # 4. EEMALDAMINE
    if (Test-Path $FullFilePath) {
        Remove-Item $FullFilePath -Force
        Write-Host "Sweep: Lokaalne fail eemaldatud." -ForegroundColor Gray
    }

} catch {
    Write-Host "`n❌ VIGA: Saatmine ebaõnnestus ($($_.Exception.Message))" -ForegroundColor Red
    Write-Host "Fail säilitati siin: $FullFilePath" -ForegroundColor Yellow
}



```
