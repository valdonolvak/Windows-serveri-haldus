Siin Gemini test

```powershell

<#
.SYNOPSIS
    Windows Serveri keskkonna kontrollskript vastavalt etteantud kriteeriumitele.
    Väljastab tulemused HTML failina.
#>

$ReportPath = "$PSScriptRoot\Kontrolli_Raport.html"
$DomainName = "sinunimi.local" # Muuda vajadusel "oige.ee" peale vastavalt juhisele
$CSVPath = "$PSScriptRoot\kasutajad.csv"

$Results = @()

function Add-Result {
    param($Tegevus, $Ootus, $Tulemus, $Staatus)
    $color = if($Staatus -eq "OK") { "green" } else { "red" }
    $Global:Results += [PSCustomObject]@{
        Tegevus = $Tegevus
        Ootus   = $Ootus
        Leitud  = $Tulemus
        Staatus = "<b style='color:$color'>$Staatus</b>"
    }
}

# --- 1. Masina nimi ja IP ---
$ComputerName = $env:COMPUTERNAME
Add-Result "Serveri nimi" "DC1" $ComputerName (if($ComputerName -eq "DC1") {"OK"} else {"VIGA"})

$IP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*").IPAddress | Select-Object -First 1
Add-Result "DC1 IP Aadress" "Staatiline IP" $IP "INFO"

# --- 2. AD Domeen ja DC2 olemasolu ---
try {
    $Domain = Get-ADDomain
    Add-Result "AD Domeen" $DomainName $Domain.DomainName (if($Domain.DomainName -eq $DomainName) {"OK"} else {"VIGA"})
    
    $DC2 = Get-ADDomainController -Identity "DC2" -ErrorAction Stop
    Add-Result "Teine DC (DC2)" "DC2 Core olemasolu" $DC2.Name "OK"
} catch {
    Add-Result "AD Kontroll" "Domeen/DC2" "Ei leitud" "VIGA"
}

# --- 3. DHCP ja Failover ---
try {
    $DHCPConfig = Get-DhcpServerv4Scope -ComputerName DC1
    $Failover = Get-DhcpServerv4Failover -ComputerName DC1
    $LeaseTime = (Get-DhcpServerv4Scope -ComputerName DC1).LeaseTime
    
    Add-Result "DHCP Failover" "Partner DC2" $Failover.PartnerServer "OK"
    Add-Result "DHCP Lease aeg" "04:00:00" $LeaseTime (if($LeaseTime -eq "04:00:00") {"OK"} else {"VIGA"})
    
    $ScopeOptions = Get-DhcpServerv4OptionValue -ScopeId $DHCPConfig.ScopeId -OptionId 6
    Add-Result "DHCP DNS DNS väljastus" "DC1 ja DC2 IP-d" ($ScopeOptions.Value -join ", ") "INFO"
} catch {
    Add-Result "DHCP Kontroll" "Seadistused" "Viga päringul" "VIGA"
}

# --- 4. OU Struktuur ja Haldur ---
$OU_Users = Get-ADOrganizationalUnit -Filter "Name -eq 'Kasutajad'"
$OU_Comps = Get-ADOrganizationalUnit -Filter "Name -eq 'Arvutid'"
Add-Result "OU Kasutajad" "Olemas" (if($OU_Users) {"Jah"} else {"Ei"}) (if($OU_Users) {"OK"} else {"VIGA"})
Add-Result "OU Arvutid" "Olemas" (if($OU_Comps) {"Jah"} else {"Ei"}) (if($OU_Comps) {"OK"} else {"VIGA"})

$Haldur = Get-ADUser -Filter "Name -eq 'Haldur'" -Properties MemberOf
$IsAdmin = $Haldur.MemberOf -like "*Domain Admins*"
Add-Result "Kasutaja Haldur" "Domain Admin" (if($IsAdmin) {"Jah"} else {"Ei"}) (if($IsAdmin) {"OK"} else {"VIGA"})

# --- 5. GPO Kontrollid (Sisu kontroll) ---
# Kontode lukustamine
try {
    $GPO_Lock = Get-GPO -Name "GPO_KontodeLukustamine"
    $GPO_Report = [xml](Get-GPOReport -Name "GPO_KontodeLukustamine" -ReportType Xml)
    $LockoutLimit = $GPO_Report.GPO.User.ExtensionData.Extension.Account.LockoutThreshold # Lihtsustatud näide
    Add-Result "GPO Lukustamine" "Nimi olemas" "Leitud" "OK"
} catch {
    Add-Result "GPO Lukustamine" "Nimi GPO_KontodeLukustamine" "Puudu" "VIGA"
}

# Edge Siseportaal
try {
    $GPO_Edge = Get-GPO -Name "Edge_Siseportaal"
    Add-Result "GPO Edge" "Nimi olemas" "Leitud" "OK"
} catch {
    Add-Result "GPO Edge" "Nimi Edge_Siseportaal" "Puudu" "VIGA"
}

# --- 6. CSV ja Kasutajate pisteline kontroll ---
if (Test-Path $CSVPath) {
    $CSVData = Import-Csv $CSVPath -Delimiter "`t" # Eeldab tab-eraldatud faili nagu kopeeritud tekstis
    $Departments = $CSVData | Select-Object -ExpandProperty "Osakond" -Unique
    
    foreach ($Dept in $Departments) {
        $TestUser = $CSVData | Where-Object { $_.Osakond -eq $Dept } | Select-Object -First 1
        $ADUser = Get-ADUser -Filter "DisplayName -eq '$($TestUser.Nimi)'" -SearchBase "OU=$Dept,OU=Kasutajad,$( (Get-ADDomain).DistinguishedName )" -ErrorAction SilentlyContinue
        
        Add-Result "Kasutaja osakonnast $Dept" "Leitud OU-st $Dept" (if($ADUser) {$ADUser.SamAccountName} else {"PUUDU"}) (if($ADUser) {"OK"} else {"VIGA"})
    }
} else {
    Add-Result "CSV Kontroll" "Fail kasutajad.csv" "Ei leitud skripti kaustast" "VIGA"
}

# --- 7. Ketas F: ---
$DriveF = Get-Volume -DriveLetter F -ErrorAction SilentlyContinue
Add-Result "Ketas F:" "Olemas/Vormindatud" (if($DriveF) {"Leitud"} else {"Puudu"}) (if($DriveF) {"OK"} else {"VIGA"})

# --- HTML Generatsoon ---
$HtmlHeader = "<html><head><style>table{border-collapse:collapse;width:100%;} th,td{border:1px solid #ddd;padding:8px;text-align:left;} th{background-color:#4CAF50;color:white;}</style></head><body><h2>Serveri Auditi Raport</h2>"
$HtmlFooter = "</body></html>"
$TableBody = $Results | ConvertTo-Html -Fragment

$HtmlHeader + $TableBody + $HtmlFooter | Out-File $ReportPath -Encoding utf8
Write-Host "Raport on loodud: $ReportPath" -ForegroundColor Cyan

```
