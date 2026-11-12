## 10. Uuendused, monitooring, varundus ja turvalisus

Serveri paigaldamine on 10% tööst, ülejäänud 90% on selle töökorras ja turvalisena hoidmine. See peatükk koondab igapäevase halduse põhitõed.

### 10.1 Uuendused

Microsoft avaldab turvauuendused iga kuu teisel teisipäeval (*Patch Tuesday*). Server 2022 saab kumulatiivseid uuendusi: üks uuendus sisaldab kõiki eelmisi parandusi.

| Lahendus | Kirjeldus | Sobib |
| --- | --- | --- |
| Windows Update otse | Iga server laeb uuendused ise Microsoftist | Labor, väike keskkond |
| GPO + Windows Update | Ajastus ja käitumine määratakse GPO-ga (vt 7.4) | Väike ja keskmine keskkond |
| WSUS (*Windows Server Update Services*) | Oma uuendusserver: administraator kinnitab uuendused, kliendid laevad kohalikust serverist. WSUS on aegunud (*deprecated*), kuid Server 2022-s endiselt olemas ja toetatud | Kontrolli vajav keskkond |
| Azure Update Manager / Intune / Configuration Manager | Pilvepõhine või ettevõtte haldus | Suur keskkond |

Hea tava: testi uuendusi esmalt testgrupil, uuenda domeenikontrollereid ükshaaval (mitte korraga) ja kontrolli pärast `dcdiag`-iga.

```powershell
# Server Core'is: sconfig → 6 või
Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 5
```

### 10.2 Monitooring ja logid

| Tööriist | Mida näitab | Kuidas avada |
| --- | --- | --- |
| Event Viewer | Sündmuste logid: *System*, *Application*, *Security*, *Directory Service*, *DNS Server*, *DFS Replication* | `eventvwr.msc`, `Get-WinEvent` |
| Task Manager / Resource Monitor | Protsessor, mälu, ketas, võrk reaalajas | `taskmgr`, `resmon` |
| Performance Monitor | Loendurid ajas, aruanded (*Data Collector Sets*) | `perfmon` |
| Server Manager | Rollide olek, teenused, sündmused, BPA (*Best Practices Analyzer*) | Dashboard |
| Reliability Monitor | Rakenduste ja süsteemi tõrked ajateljel | `perfmon /rel` |
| Väline monitooring | Keskne jälgimine ja häired (nt Zabbix, PRTG, Azure Monitor) | Agent serveril |

Tähtsamad sündmuste ID-d, mida tasub teada:

| ID | Logi | Tähendus |
| --- | --- | --- |
| 4624 / 4625 | Security | Edukas / ebaõnnestunud sisselogimine |
| 4740 | Security (DC) | Kasutajakonto lukustati |
| 4720 / 4726 | Security (DC) | Kasutaja loodi / kustutati |
| 4728 / 4732 / 4756 | Security (DC) | Liige lisati globaal- / domeenilokaal- / universaalrühma |
| 1074 | System | Kes ja miks serveri taaskäivitas |
| 6005 / 6006 / 6008 | System | Logiteenus käivitus / peatus / ootamatu seiskumine |
| 4013 | DNS Server | DNS ootab AD esmast replikatsiooni (tavaline DC käivitumisel) |
| 1311, 2042 | Directory Service | Replikatsiooni topoloogia probleem / replikatsioon pole ammu toimunud |

```powershell
# Viimased 20 ebaõnnestunud sisselogimist DC-l
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625} -MaxEvents 20 |
  Select-Object TimeCreated, @{n='Kasutaja';e={$_.Properties[5].Value}}
```

### 10.3 Varundus

**Reegel 3-2-1:** vähemalt 3 koopiat andmetest, 2 eri meediumil, 1 väljaspool asukohta (või võrguühenduseta, *offline/immutable*). Lunavara vastu on just see viimane koopia otsustav.

Windows Serveris on tasuta komponent **Windows Server Backup** (`wbadmin`). Domeenikontrolleri jaoks varundatakse **System State** (AD andmebaas, SYSVOL, register, boot-failid).

> **NB!** Allpool on sama töö kahel viisil: **A) GUI** ja **B) PowerShell**. Piisab ühest – kui teed GUI juhendi järgi, pole PowerShelli osa vaja (ja vastupidi).

#### Variant A: GUI (samm-sammult)

1. *Server Manager → Add Roles and Features* → *Features*: **Windows Server Backup** → *Install*.
2. *Tools → Windows Server Backup* (`wbadmin.msc`) → *Local Backup* → paremal **Backup Once...**.
3. *Different options* → *Select Backup Configuration*: **Custom** → *Add Items* → märgi **System state** → OK → *Next*.
4. *Specify Destination Type*: **Local drives** → *Select Backup Destination*: `E:` → *Next* → **Backup**.
5. Kontroll: akna *Messages* osas on varundus olekuga *Successful*. Ajastatud varunduse jaoks kasuta *Backup Schedule...* viisardit.

#### Variant B: PowerShell

```powershell
Install-WindowsFeature Windows-Server-Backup
# System State varundus eraldi kettale
wbadmin start systemstatebackup -backupTarget:E: -quiet
wbadmin get versions
```

**AD taastamise viisid:**

1. **AD prügikast** (*Recycle Bin*) – kustutatud objekti taastamine ilma varunduseta. Tuleb **enne** kustutamist sisse lülitada (ei saa välja lülitada): `Enable-ADOptionalFeature 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target perenimi.local`.
2. **Mitteautoriteetne taastamine** (*non-authoritative restore*) – DC taastatakse varundusest ja saab uuemad muudatused teistelt DC-delt replikatsiooniga.
3. **Autoriteetne taastamine** (*authoritative restore*) – DSRM-režiimis `ntdsutil` abil märgitakse taastatud objektid „kõige uuemaks“, et need replikeeruksid teistele DC-dele.

> **VM-i hetktõmmis ei ole varundus.** Domeenikontrolleri VM-i vana hetktõmmise taastamine võib tekitada USN rollbacki ja rikkuda replikatsiooni. Kaasaegsed hüperviisorid toetavad *VM-Generation ID*-d, mis seda leevendab, kuid laboris tee enne hetktõmmise taastamist DC-st alati teadlik otsus.

### 10.4 Turvalisuse põhitõed

AD on ründajale „võti kogu kuningriiki“: kes saab domeeniadministraatori õigused, saab kõik. Allolevad meetmed on ka E-ITS-i ja CIS-i juhiste põhiosa.

| Valdkond | Meede |
| --- | --- |
| Kontod | Eraldi administraatorikonto (`adm-...`) igapäevasest; Domain Admins rühmas minimaalne arv kontosid; nimeta `Administrator` ümber või keela; **Protected Users** rühm administraatoritele |
| Paroolid | Vähemalt 12–14 märki, paroolifraasid; konto lukustus; teenusekontode jaoks **gMSA** (*group Managed Service Account*), mille parooli haldab AD ise |
| Kohalikud administraatorid | **Windows LAPS** – iga arvuti kohaliku administraatori parool on unikaalne, vahetub automaatselt ja on talletatud AD-s (sisseehitatud alates 2023. aasta aprilli uuendustest) |
| Tasandimudel | *Tiering*: DC-de (Tier 0), serverite (Tier 1) ja tööjaamade (Tier 0/1/2) administraatorid on eri kontod; domeeniadministraator ei logi tööjaamadesse sisse |
| Protokollid | Keela SMBv1 (Server 2022-s vaikimisi puudub); LDAP signing ja channel binding; NTLM-i piiramine; SMB signing |
| Ründepind | Server Core; ainult vajalikud rollid; tulemüür sees kõigis profiilides; RDP ainult haldusvõrgust |
| Kaitse | Microsoft Defender Antivirus sees; *Credential Guard*; BitLocker füüsilistel serveritel; Secure Boot |
| Auditeerimine | *Advanced Audit Policy* GPO-ga (sisselogimised, konto- ja rühmamuudatused, GPO muudatused); logide tsentraalne kogumine |
| Hindamine | Microsoft **Security Compliance Toolkit** (baasjooned GPO-dena), **PingCastle** või **Purple Knight** AD turvaauditiks |

```powershell
# Kiirkontroll
Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, RequireSecuritySignature
Get-NetFirewallProfile | Select-Object Name, Enabled
Get-ADGroupMember "Domain Admins" | Select-Object Name
Search-ADAccount -PasswordNeverExpires -UsersOnly | Select-Object Name
Search-ADAccount -AccountInactive -TimeSpan 90.00:00:00 -UsersOnly | Select-Object Name
```

---

[← 9. WDS ja võrgupaigaldus (PXE)](09-wds-ja-vorgupaigaldus.md) · [Sisukord](../README.md) · [11. Laboritööd →](11-laboritood-1-10.md)
