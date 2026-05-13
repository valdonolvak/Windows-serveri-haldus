##**Kopeeri selle faili sisu**

```powershell
# --- 0. ETTEVALMISTUS JA VÕRGU PROTOKOLLID ---
# Sunnime TLS 1.2 kasutamise (Windows Serveri puhul sageli vajalik API-dega suhtlemiseks)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- 1. KASUTAJA SISEND ---
$RawName = Read-Host "Sisesta oma nimi (Eesnimi Perekonnanimi)"
$VNET = Read-Host "Sisesta oma vnet number (näiteks: 50)"
$ServerIP = "192.168.124.64" # Sinu Linux serveri IP

# Failinime puhastamine: Jüri Juurikas -> jyrijuurikas.json
$SafeName = $RawName.ToLower().Replace(" ","").Replace("ä","a").Replace("ö","o").Replace("ü","u").Replace("õ","o").Replace("š","s").Replace("ž","z")
$FileName = "$SafeName.json"

$Results = @()
$TotalPoints = 0

# --- 2. ABI-FUNKTSIOON TÄPSEKS KONTROLLIKS ---
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
            $Expl = "VIGA! Oodatud: $Expected | Sina seadistasid: $Found"
        }
    } catch { $Expl = "Viga mooduli või käsu käivitamisel: $($_.Exception.Message)" }

    $global:Results += [PSCustomObject]@{
        Nimi = $Nimi; Korras = $Status; Punktid = if($Status){$MaxP}else{0}; Selgitus = $Expl
    }
}

Write-Host "`n--- ALUSTAN SÜVAANALÜÜSI (vnet $VNET) ---" -ForegroundColor Cyan

# --- 3. KONTROLLID ---

# AD1 Nimi ja IP kontroll
$TargetIP = "192.168.$VNET.10"
Add-Task "AD1 Nimi ja IP" 1 {
    $currentIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object InterfaceAlias -notlike "*Loopback*").IPAddress
    if ($env:COMPUTERNAME -eq "AD1" -and $currentIP -eq $TargetIP) { "OK" } 
    else { "Nimi=$env:COMPUTERNAME, IP=$currentIP" }
} "Nimi=AD1, IP=$TargetIP"

# AD2 olemasolu (Teine DC)
Add-Task "AD2 olemasolu domeenis" 2 {
    if (Get-ADComputer -Filter "Name -eq 'AD2'" -ErrorAction SilentlyContinue) { "OK" } 
    else { "AD2-te ei leitud domeenist" }
} "AD2 peab olema domeeni liige"

# Ketas F: ja vajalikud kaustad
Add-Task "Ketas F: ja struktuur" 1 {
    if ((Test-Path "F:") -and (Test-Path "F:\STUFF") -and (Test-Path "F:\WWW") -and (Test-Path "F:\Kasutajad$")) { "OK" }
    else { "F: ketas või kaustad (STUFF/WWW/Kasutajad$) puudu" }
} "F: ketas + kaustad STUFF, WWW, Kasutajad$"

# DHCP Skoop HKHK
Add-Task "DHCP Skoop" 1 {
    $scope = Get-DhcpServerv4Scope | Where-Object Name -eq "HKHK"
    $expectedStart = "192.168.$VNET.100"
    if ($scope.StartRange -eq $expectedStart) { "OK" } 
    else { "Skoop: $($scope.Name), Algus: $($scope.StartRange)" }
} "Skoop HKHK, algus $expectedStart"

# GPO-de nimede kontroll
$GPO_Nimed = @("GPO_Taustapildid", "GPO_Folder_Redirection", "GPO_Software_7zip", "GPO_Chrome_Settings")
foreach ($g in $GPO_Nimed) {
    Add-Task "$g olemasolu" 2 {
        if (Get-GPO -Name $g -ErrorAction SilentlyContinue) { "OK" } else { "Puudu" }
    } "Täpne nimi: $g"
}

# IIS Veebileht
Add-Task "IIS ja Veebileht" 2 {
    if (Get-Website | Where-Object Name -like "*veebileht*") { "OK" } 
    else { "IIS veebilehte ei leitud" }
} "veebileht.perenimi.local"

# --- 4. HINDE ARVUTAMINE ---
$Hinne = if ($TotalPoints -ge 22) { 5 } elseif ($TotalPoints -ge 17) { 4 } elseif ($TotalPoints -ge 12) { 3 } else { 2 }

# --- 5. ANDMETE PAKENDAMINE ---
$Payload = [PSCustomObject]@{
    Opilane = $RawName
    KokkuPunkte = $TotalPoints
    Hinne = $Hinne
    Kontrollid = $Results
} | ConvertTo-Json -Depth 10

# Salvestame faili lokaalselt (kasutaja nimega)
$Payload | Out-File "$PSScriptRoot\$FileName" -Encoding utf8
Write-Host "`nTulemused salvestatud faili: $FileName" -ForegroundColor Cyan

# --- 6. SAATMINE LINUX SERVERISSE ---
Write-Host "Üritan saata tulemusi aadressile http://$ServerIP:5000..." -ForegroundColor Yellow

try {
    # Kasutame -Proxy $null, et vältida IE seadetest tulenevaid takistusi
    $Response = Invoke-RestMethod -Uri "http://$($ServerIP):5000/api/upload" `
                                  -Method Post `
                                  -Body $Payload `
                                  -ContentType "application/json; charset=utf-8" `
                                  -Proxy $null `
                                  -ErrorAction Stop
    
    Write-Host "EDUKAS! Tulemused saadetud serverisse." -ForegroundColor Green
    Write-Host "Hinne: $Hinne ($TotalPoints punkti)" -ForegroundColor Green
} catch {
    Write-Host "`nHOIATUS: Automaatne saatmine ebaõnnestus." -ForegroundColor Red
    Write-Host "Põhjus: $($_.Exception.Message)" -ForegroundColor Gray
    Write-Host "Palun kasuta veebilehe manuaalset 'Upload' vormi ja laadi üles fail: $FileName" -ForegroundColor Yellow
}

```
