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

# 1. TUVASTAME AUTOMAATSELT DOMEENI JA OU TEEKONNA
# See rida leiab ise üles domeeni (nt DC=test,DC=local)
$DomainDN = (Get-ADDomain).DistinguishedName
$TargetOU = "OU=Arvutid,$DomainDN"

# Sihtfail F:\ kettal
$TargetDir = "F:"
$OutputFile = "$TargetDir\AD_arvutite_tarkvara.html"

Write-Host "1. Tuvastatud domeen: $DomainDN" -ForegroundColor Green
Write-Host "Otsitakse arvuteid asukohast: $TargetOU" -ForegroundColor Cyan

# Kontrollime, kas F:\ ketas on olemas
if (-not (Test-Path $TargetDir)) {
    Write-Error "Ketas F:\ ei ole kättesaadav!"
    return
}

# 2. LOETAKSE ARVUTID AD-ST
try {
    $Computers = Get-ADComputer -Filter * -SearchBase $TargetOU | Select-Object -ExpandProperty Name
} catch {
    Write-Error "Viga OU leidmisel! Kontrolli, kas OU nimena on kirjas 'Arvutid' (mitte 'Arvutid-OU' vms)."
    return
}

if ($null -eq $Computers -or $Computers.Count -eq 0) {
    Write-Warning "OU-st Arvutid ei leitud ühtegi arvutit!"
    return
}

Write-Host "Leiti $($Computers.Count) arvutit. Alustatakse tarkvara inventuuri..." -ForegroundColor Cyan

# 3. SKRIPTIPLOKK KLIENDIMASINATE JAOKS
$ScriptBlock = {
    $RegPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    Get-ItemProperty -Path $RegPaths -ErrorAction SilentlyContinue | 
        Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 } | 
        Select-Object DisplayName, DisplayVersion, InstallDate
}

$FullReport = @()

# 4. KÄIME ARVUTID LÄBI
foreach ($Computer in $Computers) {
    Write-Host "Küsitakse andmeid arvutist: $Computer..." -ForegroundColor Yellow
    
    if (Test-Connection -ComputerName $Computer -Count 1 -Quiet) {
        try {
            $RemoteApps = Invoke-Command -ComputerName $Computer -ScriptBlock $ScriptBlock -ErrorAction Stop
            foreach ($App in $RemoteApps) {
                $FullReport += [PSCustomObject]@{
                    "Arvuti nimi"   = $Computer
                    "Tarkvara nimi" = $App.DisplayName
                    "Versioon"      = $App.DisplayVersion
                    "Paigaldatud"   = $App.InstallDate
                }
            }
        } catch {
            $FullReport += [PSCustomObject]@{ "Arvuti nimi" = $Computer; "Tarkvara nimi" = "VIGA: Ligipääs keelatud (WinRM)"; "Versioon" = "-"; "Paigaldatud" = "-" }
        }
    } else {
        $FullReport += [PSCustomObject]@{ "Arvuti nimi" = $Computer; "Tarkvara nimi" = "OFFLINE"; "Versioon" = "-"; "Paigaldatud" = "-" }
    }
}

# 5. GENEREERIME HTML RAPORTI
$Header = "<style>body{font-family:Arial;} table{border-collapse:collapse; width:100%;} th{background-color:#0078D4; color:white; padding:10px;} td{border:1px solid #ddd; padding:8px;} tr:nth-child(even){background-color:#f2f2f2;}</style>"
$FullReport | Sort-Object "Arvuti nimi" | ConvertTo-Html -Head $Header -Title "Tarkvara Audit" | Out-File $OutputFile -Encoding UTF8

Write-Host "Valmis! Raport asub: $OutputFile" -ForegroundColor Green
```
