# Labor14-kontroll.ps1 – Labor 14 (rakenduste ligipääs AD rühmade järgi) kontrollskript
# Käivita AD1-l administraatorina:
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\Labor14-kontroll.ps1                 # vaikimisi failiserver AD2
#   .\Labor14-kontroll.ps1 -Failiserver CORE1
# Skript ainult loeb – ta ei muuda midagi.

param([string]$Failiserver = 'AD2')

Import-Module ActiveDirectory, GroupPolicy -ErrorAction Stop

$domeen  = Get-ADDomain
$dn      = $domeen.DistinguishedName
$labor   = "OU=Labor,$dn"
$ouKas   = "OU=Kasutajad,$labor"
$ouArv   = "OU=Arvutid,$labor"
$sysvol  = "\\$($domeen.DNSRoot)\SYSVOL\$($domeen.DNSRoot)\Policies"

$script:kokku = 0; $script:saadud = 0; $script:vead = @()

function Kontroll {
    param([string]$Nimi, [int]$Punktid, [scriptblock]$Test, [string]$Vihje)
    $script:kokku += $Punktid
    $ok = $false
    try { $ok = [bool](& $Test) } catch { $ok = $false }
    if ($ok) {
        $script:saadud += $Punktid
        Write-Host ("  [OK]   {0}" -f $Nimi) -ForegroundColor Green
    } else {
        Write-Host ("  [VIGA] {0}" -f $Nimi) -ForegroundColor Red
        if ($Vihje) { Write-Host ("         → {0}" -f $Vihje) -ForegroundColor Yellow }
        $script:vead += $Nimi
    }
}
function Liikmed($grupp) { (Get-ADGroupMember -Identity $grupp -ErrorAction Stop | Select-Object -ExpandProperty Name) }
function GpoLink($gpo, $ou) { (Get-GPInheritance -Target $ou).GpoLinks | Where-Object { $_.DisplayName -eq $gpo -and $_.Enabled } }
function GpoOigus($gpo, $kes) { (Get-GPPermission -Name $gpo -All -ErrorAction Stop | Where-Object { $_.Trustee.Name -eq $kes }).Permission }

Write-Host "`nLabor 14 kontroll – domeen $($domeen.DNSRoot), failiserver $Failiserver`n" -ForegroundColor Cyan

# ---------- 1. Rühmad ----------
Write-Host "1. Rakendusrühmad (AGDLP)" -ForegroundColor Cyan
$oodatud = [ordered]@{
  'DL_APP_7Zip'           = @('GG_IT')
  'DL_APP_Firefox'        = @('GG_IT','GG_Raamatupidamine','GG_Myyk')
  'DL_APP_VLC'            = @('GG_IT')
  'DL_APP_Raamat'         = @('GG_Raamatupidamine')
  'DL_APP_Laoseis'        = @('GG_Myyk','GG_Raamatupidamine')
  'DL_APP_Laoseis_Muutja' = @('GG_Myyk')
}
foreach ($g in $oodatud.Keys) {
    Kontroll "$g on domeenilokaalne turvarühm" 1 {
        $r = Get-ADGroup -Identity $g -ErrorAction Stop
        $r.GroupScope -eq 'DomainLocal' -and $r.GroupCategory -eq 'Security'
    } "Loo rühm: New-ADGroup -Name $g -GroupScope DomainLocal -GroupCategory Security"
    Kontroll "$g liikmed: $($oodatud[$g] -join ', ')" 1 {
        $m = @(Liikmed $g)
        -not (Compare-Object ($m | Sort-Object) ($oodatud[$g] | Sort-Object))
    } "Rühmas peavad olema täpselt need globaalrühmad (mitte kasutajad otse)"
}

# ---------- 2. Tarkvara jagamine ----------
Write-Host "`n2. Tarkvara jagamine" -ForegroundColor Cyan
Kontroll "\\$Failiserver\Tarkvara on olemas ja sisaldab vähemalt 3 MSI-faili" 3 {
    @(Get-ChildItem "\\$Failiserver\Tarkvara\*.msi" -ErrorAction Stop).Count -ge 3
} "Loo jagamine Tarkvara ja kopeeri MSI-failid (etapp 2)"
Kontroll "Jagamisel Tarkvara on Authenticated Users lugemisõigus" 2 {
    $a = Invoke-Command -ComputerName $Failiserver { Get-SmbShareAccess -Name Tarkvara } -ErrorAction Stop
    $a | Where-Object { $_.AccountName -like '*Authenticated Users' -and $_.AccessControlType -eq 'Allow' }
} "Grant-SmbShareAccess -Name Tarkvara -AccountName 'Authenticated Users' -AccessRight Read"

# ---------- 3. GPO tarkvara paigaldus ----------
Write-Host "`n3. GPO tarkvara paigaldus" -ForegroundColor Cyan
Kontroll "C_Oota_Vorku on lingitud OU-le Arvutid (või sama seade muus GPO-s)" 2 {
    (GpoLink 'C_Oota_Vorku' $ouArv) -or
    ((Get-GPInheritance -Target $ouArv).InheritedGpoLinks | ForEach-Object {
        Get-GPRegistryValue -Name $_.DisplayName -Key 'HKLM\Software\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon' -ValueName SyncForegroundPolicy -ErrorAction SilentlyContinue
    } | Where-Object { $_.Value -eq 1 })
} "Etapp 3.1: Always wait for the network at computer startup and logon"
foreach ($app in '7Zip','Firefox','VLC') {
    $gpo = "U_APP_$app"
    Kontroll "$gpo on lingitud OU-le Kasutajad" 2 { GpoLink $gpo $ouKas } "New-GPLink -Name $gpo -Target '$ouKas'"
    Kontroll "$gpo turvafilter: DL_APP_$app = Apply" 2 { (GpoOigus $gpo "DL_APP_$app") -eq 'GpoApply' } "Scope → Security Filtering → Add DL_APP_$app"
    Kontroll "$gpo Authenticated Users = ainult Read (mitte Apply)" 2 { (GpoOigus $gpo 'Authenticated Users') -eq 'GpoRead' } "Eemalda filtrist, Delegation → Authenticated Users: Read"
    Kontroll "$gpo sisaldab MSI paketti (UNC-teega)" 2 {
        $id = (Get-GPO -Name $gpo).Id
        $aas = Get-ChildItem "$sysvol\{$id}\User\Applications\*.aas" -ErrorAction Stop
        $xml = [xml](Get-GPOReport -Name $gpo -ReportType Xml)
        $aas -and ($xml.OuterXml -match '\\\\[^<]+\.msi')
    } "Edit → User → Software Settings → Software installation → New Package (tee \\$Failiserver\Tarkvara\...)"
}

# ---------- 4. Otseteed ----------
Write-Host "`n4. Otseteed (GPP + item-level targeting)" -ForegroundColor Cyan
Kontroll "U_Otseteed on lingitud OU-le Kasutajad" 2 { GpoLink 'U_Otseteed' $ouKas } "Loo ja lingi GPO U_Otseteed"
$scXml = $null
try { $id = (Get-GPO -Name U_Otseteed -ErrorAction Stop).Id; $scXml = [xml](Get-Content "$sysvol\{$id}\User\Preferences\Shortcuts\Shortcuts.xml" -Raw -Encoding UTF8 -ErrorAction Stop) } catch {}
foreach ($pair in @(@('Laoseis','DL_APP_Laoseis'), @('Raamatupidamine','DL_APP_Raamat'))) {
    $scNimi = $pair[0]; $scGrp = $pair[1]
    Kontroll "Otsetee „$scNimi“ on olemas" 2 { $scXml.Shortcuts.Shortcut | Where-Object { $_.name -eq $scNimi } } "User → Preferences → Windows Settings → Shortcuts → New"
    Kontroll "Otsetee „$scNimi“: targeting rühmale $scGrp ja 'Remove this item'" 3 {
        $sc = $scXml.Shortcuts.Shortcut | Where-Object { $_.name -eq $scNimi }
        ($sc.Filters.FilterGroup | Where-Object { $_.name -like "*\$scGrp" }) -and $sc.removePolicy -eq '1'
    } "Common → Item-level targeting → Security Group $scGrp; ☑ Remove this item when it is no longer applied"
}

# ---------- 5. AppLocker ----------
Write-Host "`n5. AppLocker" -ForegroundColor Cyan
Kontroll "C_AppLocker on lingitud OU-le Arvutid" 2 { GpoLink 'C_AppLocker' $ouArv } "Loo GPO C_AppLocker ja lingi OU-le Arvutid"
$al = $null
try {
    $id  = (Get-GPO -Name C_AppLocker -ErrorAction Stop).Id
    $al  = [xml](Get-AppLockerPolicy -Domain -LDAP "LDAP://CN={$id},CN=Policies,CN=System,$dn" -Xml -ErrorAction Stop)
} catch {}
$exe = $al.AppLockerPolicy.RuleCollection | Where-Object { $_.Type -eq 'Exe' }
$vlcSid = (Get-ADGroup DL_APP_VLC -ErrorAction SilentlyContinue).SID.Value
Kontroll "EXE vaikereeglid on olemas (vähemalt 3 reeglit)" 3 { @($exe.FilePathRule).Count -ge 3 } "Executable Rules → Create Default Rules"
Kontroll "Program Files reeglil on VideoLAN-i erand" 3 {
    $exe.FilePathRule | Where-Object { $_.Exceptions.FilePathCondition.Path -like '*VideoLAN*' }
} "Ava (Default Rule) Program Files → Exceptions → Path %PROGRAMFILES%\VideoLAN\*"
Kontroll "Allow-reegel rühmale DL_APP_VLC (VideoLAN)" 4 {
    $exe.FilePathRule | Where-Object { $_.Action -eq 'Allow' -and $_.UserOrGroupSid -eq $vlcSid -and $_.Conditions.FilePathCondition.Path -like '*VideoLAN*' }
} "Create New Rule → Allow → DL_APP_VLC → Path %PROGRAMFILES%\VideoLAN\*"
Kontroll "EXE reeglid on jõustatud (Enforce rules)" 3 { $exe.EnforcementMode -eq 'Enabled' } "AppLocker → Properties → Enforcement → Enforce rules (pärast auditi kontrolli)"
Kontroll "Application Identity teenus käivitub automaatselt (GPO-s)" 3 {
    $xml = [xml](Get-GPOReport -Name C_AppLocker -ReportType Xml)
    $xml.OuterXml -match 'AppIDSvc' -and $xml.OuterXml -match 'Automatic'
} "Security Settings → System Services → Application Identity → Automatic"

# ---------- 6. Laoseis ----------
Write-Host "`n6. Rakendus Laoseis" -ForegroundColor Cyan
$lao = "\\$Failiserver\Rakendused\Laoseis"
Kontroll "Jagamine Rakendused on ABE-ga" 3 {
    (Invoke-Command -ComputerName $Failiserver { Get-SmbShare -Name Rakendused } -ErrorAction Stop).FolderEnumerationMode -eq 'AccessBased'
} "Set-SmbShare -Name Rakendused -FolderEnumerationMode AccessBased"
Kontroll "Laoseis.ps1 ja andmed\laoseis.csv on olemas" 2 { (Test-Path "$lao\Laoseis.ps1") -and (Test-Path "$lao\andmed\laoseis.csv") } "Etapp 6.2"
Kontroll "Kaustal Laoseis: DL_APP_Laoseis = ReadAndExecute" 4 {
    (Get-Acl $lao).Access | Where-Object { $_.IdentityReference -like '*\DL_APP_Laoseis' -and $_.FileSystemRights -match 'ReadAndExecute' -and $_.AccessControlType -eq 'Allow' }
} "icacls F:\Rakendused\Laoseis /grant DOMEEN\DL_APP_Laoseis:(OI)(CI)RX"
Kontroll "Kaustal andmed: DL_APP_Laoseis_Muutja = Modify" 4 {
    (Get-Acl "$lao\andmed").Access | Where-Object { $_.IdentityReference -like '*\DL_APP_Laoseis_Muutja' -and $_.FileSystemRights -match 'Modify' -and $_.AccessControlType -eq 'Allow' }
} "icacls F:\Rakendused\Laoseis\andmed /grant DOMEEN\DL_APP_Laoseis_Muutja:(OI)(CI)M"
Kontroll "Kaustal Laoseis pole Users / Authenticated Users / Everyone õigust" 3 {
    -not ((Get-Acl $lao).Access | Where-Object { $_.IdentityReference -match 'Users$|Everyone' })
} "Rakendused: Disable inheritance, Authenticated Users ainult 'This folder only'"
Kontroll "muudatused.log sisaldab liis.lepp salvestust (test tehtud)" 3 {
    Select-String -Path "$lao\andmed\muudatused.log" -Pattern 'liis\.lepp' -Quiet
} "Etapp 7.2: Liis muudab ja salvestab Laoseisus"
Kontroll "muudatused.log ei sisalda mari.maasikas ega kati.karu ridu" 2 {
    -not (Select-String -Path "$lao\andmed\muudatused.log" -Pattern 'mari\.maasikas|kati\.karu' -Quiet)
} "Kui etapis 8.3 Mari salvestas muutjana, on see rida ootuspärane – siis ignoreeri"

# ---------- Kokkuvõte ----------
$pr = [math]::Round(100 * $script:saadud / [math]::Max($script:kokku,1))
Write-Host "`n==============================================" -ForegroundColor Cyan
Write-Host (" Tulemus: {0} / {1} punkti ({2}%)" -f $script:saadud, $script:kokku, $pr) -ForegroundColor $(if ($pr -ge 90) {'Green'} elseif ($pr -ge 60) {'Yellow'} else {'Red'})
Write-Host (" Arvuti: {0}   Aeg: {1}" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm'))
if ($script:vead.Count) { Write-Host " Parandamist vajab: $($script:vead.Count) punkti" -ForegroundColor Yellow }
Write-Host "==============================================`n" -ForegroundColor Cyan
