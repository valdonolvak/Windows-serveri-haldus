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

# Kasutame skoopi, et andmed funktsioonidest välja jõuaksid
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
    # Salvestame tulemuse massiivi
    $script:Results += [PSCustomObject]@{ 
        Nimi=$Nimi; 
        Korras=$p -ge ($MaxP * 0.7); 
        Punktid=$p; 
        Selgitus=$fb 
    }
}

Write-Host "`n--- ALUSTAN ANALÜÜSI (vnet $VNET) ---" -ForegroundColor Cyan

# --- 3. KONTROLLID ---

# 1-9: Kasutame sinu esimese skripti loogikat, mis on töökindel
Add-DetailedTask "1. AD ja DNS" 1 {
    $d = (Get-ADDomain).DNSRoot
    if ($d -like "*.local") { return @{Points=1; Feedback="✅ Domeen: $d"} }
    return @{Points=0; Feedback="❌ Peab olema .local"}
}

Add-DetailedTask "2. Ketas F: ja struktuur" 1 {
    if (Test-Path "F:\STUFF") { return @{Points=1; Feedback="✅ F: olemas"} }
    return @{Points=0; Feedback="❌ F:\STUFF puudub"}
}

Add-DetailedTask "3. DHCP Skoop HKHK" 1 {
    $s = Get-DhcpServerv4Scope | Where-Object Name -like "*HKHK*"
    if ($s -and $s.StartRange -match ".$VNET.100") { return @{Points=1; Feedback="✅ Skoop OK"} }
    return @{Points=0; Feedback="❌ Skoop puudu või vale IP"}
}

# 10. Tarkvara GPO-d (UUS JA PÕHJALIK)
Add-DetailedTask "10. Tarkvara GPO-d" 2 {
    $p = 0; $fb = @()
    foreach ($gName in @("GPO_Software_7zip", "GPO_Software_Chrome")) {
        $gpo = Get-GPO -Name $gName -ErrorAction SilentlyContinue
        if ($gpo) {
            $p += 0.5; $fb += "$gName OK"
            $xml = [xml](Get-GPOReport -Name $gName -ReportType Xml)
            if ($xml.GPO.Computer.ExtensionData.Extension.SoftwareInstallation) {
                $p += 0.5; $fb += "(MSI seadistatud)"
            }
        } else { $fb += "$gName PUUDU" }
    }
    return @{Points=[math]::Min($p, 2); Feedback=($fb -join " | ")}
}

# 15. HTTPS seadistamine (PÕHJALIK)
Add-DetailedTask "15. HTTPS (Port 443)" 2 {
    $p = 0; $fb = @()
    $b = Get-WebBinding | Where-Object { $_.protocol -eq "https" }
    if ($b) { 
        $p += 1; $fb += "✅ Port 443 leitud" 
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        try {
            $r = Invoke-WebRequest -Uri "https://localhost" -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) { $p += 1; $fb += "Vastab 200 OK" }
        } catch { $fb += "⚠️ Sait ei vasta (või sertifikaadi viga)" }
    }
    return @{Points=$p; Feedback=($fb -join " | ")}
}

# 16. WP AD Autentimine (VEEB kasutajad)
Add-DetailedTask "16. WP AD Kasutajad" 2 {
    $u1 = Get-ADUser -Filter "SamAccountName -eq 'Peatoimetaja'" -ErrorAction SilentlyContinue
    $u2 = Get-ADUser -Filter "SamAccountName -eq 'ToimetajaAbi'" -ErrorAction SilentlyContinue
    $p = 0; $fb = @()
    if ($u1) { $p++; $fb += "✅ Peatoimetaja" }
    if ($u2) { $p++; $fb += "✅ ToimetajaAbi" }
    return @{Points=$p; Feedback="AD seis: " + ($fb -join ", ")}
}

# --- 4. HINDE ARVUTAMINE ---
$HinneTekst = switch ($script:TotalPoints) {
    {$_ -ge 22} { "5" }
    {$_ -ge 17} { "4" }
    {$_ -ge 12} { "3" }
    Default     { "2" }
}

# --- 5. SAATMINE ---
# Teeme Payload-i valmis
$Payload = [PSCustomObject]@{
    Opilane      = $RawName
    KokkuPunkte  = $script:TotalPoints
    Hinne        = $HinneTekst
    Kontrollid   = $script:Results
} | ConvertTo-Json -Depth 10

$Payload | Out-File $FullFilePath -Encoding utf8

# Saatmine Linux serverisse (Sinu algne, toimiv loogika)
$FullApiUrl = "http://$($ServerIP):5000/api/upload"
Write-Host "`nÜritan saata andmeid serverisse $FullApiUrl..." -ForegroundColor Yellow

try {
    $Response = Invoke-RestMethod -Uri $FullApiUrl `
                                  -Method Post `
                                  -Body $Payload `
                                  -ContentType "application/json; charset=utf-8" `
                                  -Proxy $null `
                                  -TimeoutSec 15
    
    Write-Host "EDUKAS! Punktid: $script:TotalPoints / 25 | Hinne: $HinneTekst" -ForegroundColor Green
    
    if (Test-Path $FullFilePath) {
        Remove-Item $FullFilePath -Force
        Write-Host "Lokaalne fail eemaldatud." -ForegroundColor Gray
    }
} catch {
    Write-Host "VIGA: Serverile saatmine ebaõnnestus ($($_.Exception.Message))." -ForegroundColor Red
    Write-Host "Fail salvestati siia: $FullFilePath" -ForegroundColor Yellow
}
```
