# Laoseis.ps1 – lihtne laoseisu rakendus (peatükk 16, Labor 14B)
# Asukoht: \\perenimi.local\Andmed\Rakendused\Laoseis\Laoseis.ps1
# Käivitus: powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "\\perenimi.local\Andmed\Rakendused\Laoseis\Laoseis.ps1"
#
# Kaks kontrolli:
#  1) Rakenduse enda kontroll (mugavus): kas kasutaja on rühmas DL_APP_Laoseis_Muutja? Kui ei, on tabel kirjutuskaitstud ja nupp „Salvesta“ hall.
#  2) NTFS (turvalisus): kaustale andmed\ on Modify õigus ainult rühmal DL_APP_Laoseis_Muutja. Isegi kui keegi kontrolli 1 mööda läheb, keelab failiserver salvestamise.

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$juur  = '\\perenimi.local\Andmed\Rakendused\Laoseis'   # muuda perenimi enda domeeni nimeks
$csv   = Join-Path $juur 'andmed\laoseis.csv'
$logi  = Join-Path $juur 'andmed\muudatused.log'

# Kes on sisse loginud ja millistes rühmades ta on (rühmad tulevad sisselogimisel loodud juurdepääsuloast)
$id     = [Security.Principal.WindowsIdentity]::GetCurrent()
$roll   = New-Object Security.Principal.WindowsPrincipal($id)
$muutja = $roll.IsInRole("$env:USERDOMAIN\DL_APP_Laoseis_Muutja")

# Andmete lugemine – kui NTFS lugemist ei luba, lõpetame veateatega
try {
    $read = Import-Csv -Path $csv -Delimiter ';' -Encoding UTF8 -ErrorAction Stop
} catch {
    [Windows.Forms.MessageBox]::Show("Laoseisu ei saa avada:`n$($_.Exception.Message)", 'Laoseis', 'OK', 'Error') | Out-Null
    exit 1
}

# CSV -> DataTable, et tabelit saaks vormis näidata ja muuta
$tabel = New-Object System.Data.DataTable
$read[0].PSObject.Properties.Name | ForEach-Object { [void]$tabel.Columns.Add($_) }
foreach ($r in $read) {
    $rida = $tabel.NewRow()
    foreach ($c in $tabel.Columns) { $rida[$c.ColumnName] = $r.($c.ColumnName) }
    $tabel.Rows.Add($rida)
}

# Vorm
$vorm = New-Object Windows.Forms.Form
$vorm.Text = "Laoseis – $($id.Name) – " + $(if ($muutja) { 'muutja' } else { 'ainult vaatamine' })
$vorm.Size = New-Object Drawing.Size(640, 420)
$vorm.StartPosition = 'CenterScreen'

$grid = New-Object Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.DataSource = $tabel
$grid.ReadOnly = -not $muutja
$grid.AllowUserToAddRows = $muutja
$grid.AutoSizeColumnsMode = 'Fill'

$nupp = New-Object Windows.Forms.Button
$nupp.Text = 'Salvesta'
$nupp.Dock = 'Bottom'
$nupp.Height = 36
$nupp.Enabled = $muutja
$nupp.Add_Click({
    try {
        $tabel | Select-Object -Property ($tabel.Columns | ForEach-Object ColumnName) |
            Export-Csv -Path $csv -Delimiter ';' -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Add-Content -Path $logi -Value "$(Get-Date -Format s);$($id.Name);salvestas" -ErrorAction Stop
        [Windows.Forms.MessageBox]::Show('Salvestatud.', 'Laoseis') | Out-Null
    } catch {
        [Windows.Forms.MessageBox]::Show("Salvestamine ebaõnnestus:`n$($_.Exception.Message)", 'Laoseis', 'OK', 'Error') | Out-Null
    }
})

$vorm.Controls.Add($grid)
$vorm.Controls.Add($nupp)
[void]$vorm.ShowDialog()
