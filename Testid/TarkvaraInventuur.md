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
