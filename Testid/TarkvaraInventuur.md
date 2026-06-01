### Powershelli skript ###

```powershell

# Määrame arvuti nime (vaikimisi on '.' ehk kohalik masin, kuid siia saab panna ka klientmasina nime, nt 'Arvuti1')
$ComputerName = "localhost"

# Registri teekonnad, kus Windows hoiab paigaldatud tarkvara infot
$RegPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

Write-Host "Kogutakse paigaldatud tarkvara infot arvutist: $ComputerName..." -ForegroundColor Cyan

# Loeme registrist andmed sisse
$InstalledApps = Get-ItemProperty -Path $RegPaths -ErrorAction SilentlyContinue | 
    Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 } | 
    Select-Object DisplayName, DisplayVersion, InstallDate

# Teeme andmed ilusaks ja käitleme tühje kuupäevi
$ReportData = foreach ($App in $InstalledApps) {
    # Kuna Windows salvestab registris kuupäevi sageli formaadis YYYYMMDD, teeme selle loetavamaks
    $FormattedDate = $App.InstallDate
    if ($App.InstallDate -match '^\d{8}$') {
        $FormattedDate = [datetime]::ParseExact($App.InstallDate, 'yyyyMMdd', $null).ToString('yyyy-MM-dd')
    }

    [PSCustomObject]@{
        "Tarkvara nimi"       = $App.DisplayName
        "Versioon"            = $App.DisplayVersion
        "Paigalduse kuupäev"  = if ($FormattedDate) { $FormattedDate } else { "Teadmata" }
    }
}

# Sorteerime nime järgi ja kuvame tulemuse tabelina ekraanile
$ReportData | Sort-Object "Tarkvara nimi" | Out-Gridview -Title "Tarkvara inventuur - $ComputerName"

# Kui soovid tulemust pigem CSV faili, võid kasutada alumist rida:
# $ReportData | Sort-Object "Tarkvara nimi" | Export-Csv -Path "C:\Temp\Tarkvara_$ComputerName.csv" -NoTypeInformation -Encoding UTF8

```


### Võrgus olevate domeeni lisatud arvutite tarkvaraauditi tegemise skript ###

```powershell
# Impordime vajalikud moodulid
Import-Module ActiveDirectory

# Sihtkataloog ja fail F:\ kettal
$TargetDir = "F:"
$OutputFile = "$TargetDir\AD_arvutite_tarkvara.html"

# Kontrollime, kas F:\ ketas on kättesaadav
if (-not (Test-Path $TargetDir)) {
    Write-Error "Ketas F:\ ei ole kättesaadav! Palun kontrolli kettatähist."
    return
}

Write-Host "1. Loetakse arvutite nimekirja Active Directoryst..." -ForegroundColor Cyan

# Küsime AD-st kõik arvutid, mis asuvad konkreetselt OU-s Arvutid
# NB! Muuda vajadusel domeeni osa (DC=sinunimi,DC=local) vastavalt oma seadistusele
$Computers = Get-ADComputer -Filter * -SearchBase "OU=Arvutid,DC=sinunimi,DC=local" | Select-Object -ExpandProperty Name

if ($Computers.Count -eq 0) {
    Write-Warning "OU-st Arvutid ei leitud ühtegi arvutit."
    return
}

Write-Host "Leiti $($Computers.Count) arvutit. Alustatakse tarkvara inventuuri üle võrgu..." -ForegroundColor Cyan

# See plokk käivitatakse klientmasinate sees (WinRM kaudu)
$ScriptBlock = {
    $RegPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    # Loeme registrist andmed, filtreerime tühjad ja süsteemsed uuendused välja
    Get-ItemProperty -Path $RegPaths -ErrorAction SilentlyContinue | 
        Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 } | 
        Select-Object DisplayName, DisplayVersion, InstallDate
}

$FullReport = @()

# Käime kõik arvutid ükshaaval läbi
foreach ($Computer in $Computers) {
    Write-Host "Küsitakse andmeid arvutist: $Computer..." -ForegroundColor Yellow
    
    # Kontrollime esmalt, kas arvuti on üldse võrgus (vastab pingile)
    if (Test-Connection -ComputerName $Computer -Count 1 -Quiet) {
        try {
            # Käivitame koodi distantsilt klientmasinas
            $RemoteApps = Invoke-Command -ComputerName $Computer -ScriptBlock $ScriptBlock -ErrorAction Stop
            
            # Töötleme tulemused ja lisame juurde, millise arvutiga on tegu
            foreach ($App in $RemoteApps) {
                $FormattedDate = $App.InstallDate
                if ($App.InstallDate -match '^\d{8}$') {
                    $FormattedDate = [datetime]::ParseExact($App.InstallDate, 'yyyyMMdd', $null).ToString('yyyy-MM-dd')
                }

                $FullReport += [PSCustomObject]@{
                    "Arvuti nimi"        = $Computer
                    "Tarkvara nimi"       = $App.DisplayName
                    "Versioon"            = $App.DisplayVersion
                    "Paigalduse kuupäev"  = if ($FormattedDate) { $FormattedDate } else { "Teadmata" }
                }
            }
        } catch {
            Write-Warning "Viga arvutiga $Computer ühendumisel (WinRM õigused puuduvad)."
            $FullReport += [PSCustomObject]@{ "Arvuti nimi" = $Computer; "Tarkvara nimi" = "VIGA: Ligipääs keelatud"; "Versioon" = "-"; "Paigalduse kuupäev" = "-" }
        }
    } else {
        Write-Warning "Arvuti $Computer ei ole võrgus (Offline)."
        $FullReport += [PSCustomObject]@{ "Arvuti nimi" = $Computer; "Tarkvara nimi" = "Masin on väljalülitatud (Offline)"; "Versioon" = "-"; "Paigalduse kuupäev" = "-" }
    }
}

# Genereerime viisaka HTML kujunduse ja tabeli
Write-Host "2. Koostatakse HTML raportit asukohta $OutputFile..." -ForegroundColor Cyan

$Header = @"
<style>
    body { font-family: Arial, sans-serif; margin: 20px; background-color: #f9f9f9; }
    h2 { color: #333; }
    table { border-collapse: collapse; width: 100%; background-color: #fff; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
    th { background-color: #0078D4; color: white; padding: 10px; text-align: left; }
    td { border: 1px solid #ddd; padding: 8px; font-size: 13px; }
    tr:nth-child(even) { background-color: #f2f2f2; }
    tr:hover { background-color: #ddd; }
    .error { color: red; font-weight: bold; }
</style>
"@

# Sorteerime tulemuse esmalt Arvuti nime ja siis Tarkvara nime järgi ning salvestame
$FullReport | Sort-Object "Arvuti nimi", "Tarkvara nimi" | 
    ConvertTo-Html -Head $Header -Title "AD Arvutite Tarkvara Audit" | 
    Out-File $OutputFile -Encoding UTF8

Write-Host "Valmis! Raport on edukalt loodud: $OutputFile" -ForegroundColor Green

```
