## 4. Haldusvahendid

Sama tööd saab teha mitmel viisil; hea administraator oskab kõiki ja valib olukorrale sobiva. Graafiline liides sobib ükskordseks tööks ja ülevaate saamiseks, PowerShell korduvaks ja massiliseks tööks ning dokumenteerimiseks (skript on ise dokumentatsioon).

| Vahend | Kus töötab | Milleks sobib | Kuidas avada |
| --- | --- | --- | --- |
| Server Manager | Desktop Experience serveril, RSAT-iga Windows 11-l | Mitme serveri ülevaade, rollide paigaldus (ka kaugserverisse), teenuste olek, sündmused | Avaneb sisselogimisel; `ServerManager.exe` |
| MMC haldustööriistad | GUI-server, RSAT-iga klient | AD, DNS, DHCP, GPO, WDS igapäevane haldus | `dsa.msc` (ADUC), `dssite.msc`, `domain.msc`, `dnsmgmt.msc`, `dhcpmgmt.msc`, `gpmc.msc`, `wdsmgmt.msc`, `compmgmt.msc` |
| Active Directory Administrative Center | GUI-server, RSAT | Täpsem AD haldus: AD prügikast, peenhäälestatud paroolipoliitikad (FGPP); näitab iga toimingu PowerShelli käsku (*PowerShell History*) | `dsac.exe` |
| sconfig | Server Core (ja GUI) | Esmane seadistus: nimi, IP, domeen, uuendused, RDP | `sconfig` |
| PowerShell | Kõikjal | Automatiseerimine, massilised muudatused, Core'i haldus | `powershell`, `pwsh` (PowerShell 7) |
| PowerShell Remoting | Domeenis kõikjal, WinRM kaudu | Käskude käivitamine teistes masinates, ka mitmes korraga | `Enter-PSSession`, `Invoke-Command` |
| Windows Admin Center | Paigaldatakse serverile või Windows 11-le, kasutatakse brauseris | Kaasaegne veebipõhine haldus, sobib eriti Core'i jaoks (failid, register, teenused, sündmused, uuendused) | `https://<host>:<port>` |
| RSAT | Windows 11 Pro/Enterprise | Haldustööriistad administraatori tööjaamas | *Settings → System → Optional features* või PowerShell |

### 4.1 PowerShelli põhitõed

PowerShelli käsud (*cmdlet*) on alati kujul **Verb-Nimisõna**: `Get-Service`, `Set-NetIPAddress`, `New-ADUser`, `Remove-DhcpServerv4Reservation`. Levinumad verbid: `Get` (loe), `Set` (muuda), `New` (loo), `Remove` (kustuta), `Add`, `Enable`, `Disable`, `Install`, `Test`.

PowerShell edastab torus (`|`) **objekte**, mitte teksti. Seetõttu saab tulemusi filtreerida ja vormindada ilma tekstitöötluseta.

```powershell
# Abi ja käskude leidmine
Get-Help New-ADUser -Examples
Get-Command -Module DhcpServer
Get-Command *dns*record*

# Objektid ja toru
Get-Service | Where-Object Status -eq 'Stopped' | Select-Object Name, StartType
Get-ADUser -Filter * | Measure-Object

# Rollide ja komponentide paigaldus
Get-WindowsFeature | Where-Object Installed
Install-WindowsFeature DHCP -IncludeManagementTools

# Kaughaldus
Enter-PSSession -ComputerName CORE1             # interaktiivne seanss
Invoke-Command -ComputerName CORE1, DC1 -ScriptBlock { Get-Service DNS }   # üks käsk mitmes masinas
```

**Tähtis eristus:** `-IncludeManagementTools` paigaldab koos rolliga ka haldustööriistad. Server Core'is GUI tööriistu ei paigaldata, kuid PowerShelli moodul paigaldatakse.

### 4.2 Server Core'i haldamine kaugelt

Core'i haldamiseks on kolm peamist viisi:

1. **Server Manager DC1-l:** *Manage → Add Servers → Active Directory → Find Now* → lisa CORE1. Pärast seda saab CORE1-le rolle paigaldada (*Add Roles and Features* → vali sihtserveriks CORE1) ja paremklikiga avada tema MMC tööriistu.
2. **MMC tööriistad DC1-l või WIN11-01-l:** näiteks `dhcpmgmt.msc` → *Add Server* → `core1.perenimi.local`. *Computer Management* (`compmgmt.msc`) → *Connect to another computer*.
3. **PowerShell Remoting:** `Enter-PSSession CORE1` või `Invoke-Command`.

Kui kaughaldus ei tööta, kontrolli järjekorras: nimelahendust (`Resolve-DnsName core1`), ühendust (`Test-NetConnection core1 -Port 5985`), WinRM-i (`winrm quickconfig` Core'is) ja tulemüüri reegleid (*Remote Event Log Management*, *Remote Service Management*, *Windows Firewall Remote Management* MMC kaughalduseks).

```powershell
# CORE1-l: luba MMC kaughalduse tulemüüri reeglid
Enable-NetFirewallRule -DisplayGroup "Remote Event Log Management"
Enable-NetFirewallRule -DisplayGroup "Remote Service Management"
Enable-NetFirewallRule -DisplayGroup "Remote Volume Management"
Enable-NetFirewallRule -DisplayGroup "Windows Defender Firewall Remote Management"
```

### 4.3 RSAT Windows 11-l

Windows 11-l on RSAT „Features on Demand“, mis laaditakse alla Windows Update'ist (võrguühendus vajalik):

> **NB!** Allpool on sama töö kahel viisil: **A) GUI** ja **B) PowerShell**. Piisab ühest – kui teed GUI juhendi järgi, pole PowerShelli osa vaja (ja vastupidi).

#### Variant A: GUI (samm-sammult)

1. Logi WIN11-01-le sisse administraatori õigustega kontoga.
2. *Settings → System → Optional features* → *Add an optional feature* → **View features**.
3. Kirjuta otsingusse `RSAT` ja märgi:
   - *RSAT: Active Directory Domain Services and Lightweight Directory Services Tools*
   - *RSAT: DNS Server Tools*
   - *RSAT: DHCP Server Tools*
   - *RSAT: Group Policy Management Tools*
   - *RSAT: Server Manager*
4. *Next* → *Add* (või *Install*). Paigalduse edenemist näeb samal lehel jaotises *Recent actions*.
5. Kontroll: *Start → All apps → Windows Tools* – seal on nt *Active Directory Users and Computers*, *DNS*, *DHCP*, *Group Policy Management*.

#### Variant B: PowerShell

```powershell
# Käivita administraatorina WIN11-01-l
Get-WindowsCapability -Online -Name RSAT* | Select-Object Name, State
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
Add-WindowsCapability -Online -Name Rsat.Dns.Tools~~~~0.0.1.0
Add-WindowsCapability -Online -Name Rsat.DHCP.Tools~~~~0.0.1.0
Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0
Add-WindowsCapability -Online -Name Rsat.ServerManager.Tools~~~~0.0.1.0
```

Kui laboril pole internetti, tuleb kasutada *Features on Demand* ISO-tõmmisfaili (`-Source` parameeter) või hallata DC1-st.

---

[← 3. Windows Server 2022: väljaanded, paigaldus, Desktop Experience vs Server Core](03-valjaanded-paigaldus-core.md) · [Sisukord](../README.md) · [5. Active Directory Domain Services ja DNS →](05-active-directory-ja-dns.md)
