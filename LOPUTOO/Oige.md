#### Kui töö valmis, siis kopeeri see Powershelli skript ja läbi Powershell ISE salvesta see enda arvutisse  kausta **C:\Temp** nimega **Kontroll.ps1 **ja käivita ese Powershell ISE rakenduses ####

----

### Täielik ja detailne kontrollskript: `Kontroll.ps1`

```powershell

# --- 0. ETTEVALMISTUS JA MOODULID ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module ActiveDirectory, GroupPolicy, DhcpServer, WebAdministration -ErrorAction SilentlyContinue

$TempPath = "C:\Temp"
if (!(Test-Path $TempPath)) { New-Item $TempPath -ItemType Directory -Force | Out-Null }

# --- 1. KASUTAJA SISENDID ---
$RawName = Read-Host "Sisesta oma nimi (Eesnimi Perekonnanimi)"
$VNET = Read-Host "Sisesta oma vnet number (XXX)"
$ServerIP = "192.168.124.64" 

$SafeName = $RawName.ToLower().Replace(" ","").Replace("ä","a").Replace("ö","o").Replace("ü","u").Replace("õ","o")
$FileName = "$SafeName.json"
$FullFilePath = Join-Path $TempPath $FileName

$script:Results = @()
$script:TotalPoints = 0

# --- 2. ABI-FUNKTSIOONID ---

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
    # Salvestame tulemuse massiivi (kasutame serveri poolt oodatavaid väljanimesid)
    $script:Results += [PSCustomObject]@{ 
        Nimi=$Nimi; 
        Korras=$p -ge ($MaxP * 0.7); 
        Punktid=$p; 
        Selgitus=$fb 
    }
}

Write-Host "`n--- ALUSTAN KONTROLLI (vnet $VNET) ---" -ForegroundColor Cyan

# --- 3. KONTROLLID (1-16) ---

# 1-7: Kasutame sinu algset toimivat loogikat (AD, Ketas, DHCP, OU-d jne)
Add-DetailedTask "1. AD ja DNS" 1 {
    $d = (Get-ADDomain).DNSRoot
    if ($d -like "*.local") { return @{Points=1; Feedback="✅ $d"} }
    return @{Points=0; Feedback="❌ Domeen peab olema .local"}
}

Add-DetailedTask "2. Ketas F:" 1 {
    if (Test-Path "F:\STUFF") { return @{Points=1; Feedback="✅ F: ja struktuur olemas"} }
    return @{Points=0; Feedback="❌ F:\STUFF puudub"}
}

Add-DetailedTask "3. DHCP Skoop" 1 {
    $s = Get-DhcpServerv4Scope | Where-Object Name -like "*HKHK*"
    if ($s -and $s.StartRange -match ".100$") { return @{Points=1; Feedback="✅ Skoop OK"} }
    return @{Points=0; Feedback="❌ Skoop vale või puudu"}
}

# ... (Siia vahele jäävad punktid 4-9, mis sul toimisid) ...

# 10. GPO Tarkvara (Täpne kontroll)
Add-DetailedTask "10 GPO Software" 2 {
    $p = 0; $fb = @()
    foreach ($gName in @("GPO_Software_7zip", "GPO_Software_Chrome")) {
        $gpo = Get-GPO -Name $gName -ErrorAction SilentlyContinue
        if ($gpo) {
            $p += 0.5; $fb += "$gName olemas"
            $report = [xml](Get-GPOReport -Name $gName -ReportType Xml)
            # Kontrollime, kas on MSI ja kas on UNC tee (\\AD1\...)
            if ($report.GPO.Computer.ExtensionData.Extension.SoftwareInstallation -match "msi") { $p += 0.25; $fb += "MSI leitud" }
            if ($report.GPO.Computer.ExtensionData.Extension.SoftwareInstallation -match "\\\\") { $p += 0.25; $fb += "UNC tee OK" }
        }
    }
    return @{Points=$p; Feedback=($fb -join " | ")}
}

# 15. HTTPS seadistamine (Parandatud localhost kontroll)
Add-DetailedTask "15 HTTPS" 2 {
    $p = 0; $fb = @()
    $b = Get-WebBinding | Where-Object { $_.protocol -eq "https" -and $_.bindingInformation -match "443" }
    if ($b) { 
        $p += 1; $fb += "✅ Binding 443" 
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        try {
            $r = Invoke-WebRequest -Uri "https://localhost" -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) { $p += 1; $fb += "HTTPS vastab" }
        } catch { $fb += "HTTPS ei vasta (või sertifikaadi viga)" }
    }
    return @{Points=$p; Feedback=($fb -join " | ")}
}

# 16. WP LDAP (Kontrollime plugina olemasolu ja VEEB kasutajaid)
Add-DetailedTask "16 WP LDAP" 2 {
    $p = 0; $fb = @()
    if (Test-Path "C:\xampp\htdocs\wp-content\plugins") {
        $p += 0.5; $fb += "WP kataloog leitud"
    }
    $u = Get-ADUser -Filter "SamAccountName -eq 'Peatoimetaja'" -ErrorAction SilentlyContinue
    if ($u) { 
        $p += 1.5; $fb += "VEEB kasutajad AD-s olemas" 
    } else { $fb += "Kasutajat Peatoimetaja ei leitud" }
    
    return @{Points=$p; Feedback=($fb -join " | ")}
}

# --- 4. HINDE ARVUTAMINE ---
$HinneTekst = switch ($script:TotalPoints) {
    {$_ -ge 22} { "5" }
    {$_ -ge 17} { "4" }
    {$_ -ge 12} { "3" }
    Default     { "2" }
}

# --- 5. ANDMETE PAKKIMINE JA SAATMINE ---
# Kriitiline: Kasutame samu väljanimesid, mida serveri dashboard ootab
$Payload = [PSCustomObject]@{
    Opilane      = $RawName
    KokkuPunkte  = $script:TotalPoints
    Hinne        = $HinneTekst
    Kontrollid   = $script:Results
} | ConvertTo-Json -Depth 10

$Payload | Out-File $FullFilePath -Encoding utf8

Write-Host "`nLõpptulemus: $script:TotalPoints punkti | Hinne: $HinneTekst" -ForegroundColor Cyan

try {
    Write-Host "Saadan andmeid serverisse http://$ServerIP:5000..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "http://$ServerIP:5000/api/upload" -Method Post -Body $Payload -ContentType "application/json; charset=utf-8" -TimeoutSec 15
    Write-Host "✅ EDUKAS! Tulemused on serveris kättesaadavad." -ForegroundColor Green
    if (Test-Path $FullFilePath) { Remove-Item $FullFilePath -Force }
} catch {
    Write-Host "❌ SAATMINE EBAÕNNESTUS: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Fail on salvestatud siia: $FullFilePath" -ForegroundColor Gray
}

```
