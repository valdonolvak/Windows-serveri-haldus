Selleks, et õpilase tulemused ilmuksid pildil näidatud Flaski veebilehel, peab PowerShell skript tegema kolm asja:

1. **Kontrollima seadistusi** (AD, DHCP, GPO, IIS jne).
2. **Koostama JSON-objekti**, mis sisaldab detaile (mis oli oodatud vs mis leiti).
3. **Saatma andmed POST-päringuga** Linuxi serveri API-le.

Siin on täielik skript õpilasele.

### PowerShell skript: `Kontroll_ja_Esita.ps1`

Kopeeri see kood AD1 serveris PowerShell ISE-sse või Notepad-i ja salvesta nimega `Kontroll.ps1`.

```powershell
# --- SEADISTUS ---
$StudentName = Read-Host "Sisesta oma Eesnimi ja Perekonnanimi"
$ServerURL = "http://192.168.124.64:5000/api/tulemused" # Linuxi serveri aadress

$Results = @{
    Student = $StudentName
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    TotalPoints = 0
    MaxPoints = 25
    Checks = @()
}

# --- ABI-FUNKTSIOON KONTROLLIMISEKS ---
function Test-Task {
    param([string]$Title, [int]$Points, [scriptblock]$TestLogic, [string]$Expected)
    
    $Status = "VIGA"
    $Found = "Puudub või valesti seadistatud"
    
    try {
        $LogicResult = &$TestLogic
        if ($LogicResult) {
            $Status = "OK"
            $Found = "Korrastatud / Leitud"
            $global:Results.TotalPoints += $Points
        }
    } catch {
        $Found = "Viga kontrollimisel: $($_.Exception.Message)"
    }

    $global:Results.Checks += @{
        Title = $Title
        MaxPoints = $Points
        Points = if ($Status -eq "OK") { $Points } else { 0 }
        Status = $Status
        Details = "Pidi olema: $Expected | Leiti: $Found"
    }
}

Write-Host "Alustan kontrolli..." -ForegroundColor Cyan

# --- 1. INFRASTRUKTUUR (4p) ---
Test-Task "Ketas F:" 1 { Test-Path "F:" } "Ketas tähisega F:"
Test-Task "AD1 Nimi" 1 { $env:COMPUTERNAME -eq "AD1" } "Arvuti nimi AD1"
Test-Task "DHCP Skoop HKHK" 1 { Get-DhcpServerv4Scope | Where-Object { $_.Name -like "*HKHK*" } } "Skoop nimega HKHK"
Test-Task "Domeen .local" 1 { (Get-ADDomain).DNSRoot -like "*.local" } "Domeeni lõpp .local"

# --- 2. KASUTAJAHALDUS (4p) ---
Test-Task "OU KASUTAJAD" 1 { Get-ADOrganizationalUnit -Filter "Name -eq 'KASUTAJAD'" } "OU KASUTAJAD"
Test-Task "Grupp Lektorid" 1 { Get-ADGroup -Filter "Name -eq 'Lektorid'" } "Grupp Lektorid"
Test-Task "Sisselogimispiirang" 2 { (Get-ADUser -Filter "Name -like '*tudeng1*'").LogonHours -ne $null } "Tudengite ajapiirang"

# --- 3. GRUPIPOLIITIKAD (8p) ---
Test-Task "GPO Taustapildid" 2 { Get-GPO -Name "GPO_Taustapildid" } "GPO_Taustapildid olemasolu"
Test-Task "GPO Folder Redir" 2 { Get-GPO -Name "GPO_Folder_Redirection" } "GPO_Folder_Redirection"
Test-Task "GPO Tarkvara 7zip" 2 { Get-GPO -Name "GPO_Software_7zip" } "GPO_Software_7zip"
Test-Task "GPO Chrome Settings" 2 { Get-GPO -Name "GPO_Chrome_Settings" } "GPO_Chrome_Settings"

# --- 4. SERVERI HALDUS (3p) ---
# Kontrollib, kas AD2 on domeenis (eeldab, et AD2 on püsti)
Test-Task "AD2 olemasolu" 2 { Get-ADComputer -Filter "Name -eq 'AD2'" } "AD2 lisatud domeeni"

# --- 5. VEEBITEENUSED (6p) ---
Test-Task "IIS Paigaldus" 2 { Get-WindowsFeature Web-Server | Where-Object { $_.Installed } } "IIS roll paigaldatud"
Test-Task "F:\WWW kaust" 2 { Test-Path "F:\WWW" } "Veebifailide asukoht F: kettal"

# --- HINDE ARVUTAMINE ---
$P = $Results.TotalPoints
$Grade = if ($P -ge 22) { 5 } elseif ($P -ge 17) { 4 } elseif ($P -ge 12) { 3 } else { 2 }
$Results.Grade = $Grade

# --- ANDMETE SAATMINE ---
$JsonPayload = $Results | ConvertTo-Json -Depth 10
Write-Host "`nKokku punkte: $P / 25" -ForegroundColor Yellow
Write-Host "Hinne: $Grade" -ForegroundColor Yellow

try {
    $Response = Invoke-WebRequest -Uri $ServerURL -Method Post -Body $JsonPayload -ContentType "application/json"
    Write-Host "`nTulemused edukalt saadetud! Kontrolli veebilehte: http://192.168.124.64:5000" -ForegroundColor Green
} catch {
    Write-Host "`nVIGA: Ei saanud serveriga ühendust! Kontrolli võrku või serveri IP-d." -ForegroundColor Red
}

```

### Kuidas seda rakendada (Samm-sammult)

#### 1. Ettevalmistus Linux serveris (Õpetaja poolel)

Õpetaja Flask-server peab olema seadistatud nii, et see võtab `/api/tulemused` teekonnal vastu POST-päringuid ja salvestab need JSON-failidena kausta `Tulemused`.

* Pildil olev vaade eeldab, et server loeb reaalajas neid faile.
* **NB!** Veendu, et Linuxi tulemüür lubab porti `5000`.

#### 2. Skripti käivitamine (Õpilase poolel)

1. Logi sisse **AD1** serverisse administraatorina.
2. Ava **PowerShell** (Run as Administrator).
3. Luba skriptide jooksmine (kui pole varem tehtud):
```powershell
Set-ExecutionPolicy Bypass -Scope Process

```


4. Käivita skript: `.\Kontroll.ps1`.
5. Sisesta oma nimi ja vajuta Enter.

#### 3. Tulemuse nägemine veebis

* Pärast teksti "Tulemused edukalt saadetud!" ilmumist mine brauseris aadressile `http://192.168.124.64:5000`.
* Sinu nimi peaks olema tabelis.
* **Detailne vaade:** Pildil olevas Flaski koodis on tavaliselt JavaScripti funktsioon, mis avab klõpsates uue akna või laiendab rida. Kuna skript saatis kaasa massiivi `Checks`, siis veebileht kuvab seal iga punkti juures selgituse: *"Pidi olema: X | Leiti: Y"*.

### Miks see on hea?

* **Fuzzy Matching (Põhimõtteline):** Skript kasutab `-like` operaatorit, mis tähendab, et kui õpilane pani nimeks "KASUTAJAD_OU" või "KASUTAJAD", siis skript leiab selle ikkagi üles.
* **Selgitused:** Kui mingi asi on valesti, siis JSON-is on kirjas täpne selgitus, mis aitab õpilasel viga parandada ja skripti uuesti käivitada.
