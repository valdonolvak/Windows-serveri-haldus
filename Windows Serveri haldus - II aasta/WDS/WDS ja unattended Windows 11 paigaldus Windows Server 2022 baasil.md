# WDS ja unattended Windows 11 paigaldus Windows Server 2022 baasil

*Samm-sammuline õppematerjal: PXE-võrgupaigaldus, vastusfailid graafilises liideses (Windows System Image Manager) ja selgitused, miks iga säte vajalik on.*

## 1. Eesmärk ja üldpilt

Materjali lõpuks oskad:

- paigaldada ja seadistada Windows Deployment Services (WDS) rolli Windows Server 2022 peal;
- importida Windows 11 käivitustõmmise (boot image) ja paigaldustõmmise (install image);
- koostada Windows System Image Manageris (WSIM) kaks vastusfaili ning mõista, mida kumbki teeb;
- mõista, kuidas Setup leiab WDS serverist paigaldustõmmise ja kuidas ta seal autentib;
- paigaldada Windows 11 arvutisse võrgu kaudu nii, et paigalduse ajal ei pea midagi käsitsi klõpsima.

> **Terminoloogia.** *Image* = tõmmis. *Boot image* = käivitustõmmis (`boot.wim`), *install image* = paigaldustõmmis (`install.wim`). Tõmmisfail on `.wim`-fail, mida WDS server hoiab.

### 1.1 Kuidas võrgupaigaldus toimib

1. Klientarvuti käivitub võrgust (PXE boot): saadab DHCP-päringu ja saab IP-aadressi.
2. PXE-klient leiab WDS-serveri (samas alamvõrgus broadcast'iga, DHCP option 60 või 66/67 abil).
3. Klient laeb TFTP kaudu käivitusprogrammi (UEFI puhul `wdsmgfw.efi`) ja seejärel käivitustõmmise (`boot.wim`) ehk väikese Windows PE keskkonna, mis töötab mälus.
4. Windows PE-s käivitub Windows Setup, ühendub autentides WDS-serveri jagatud kaustaga (`REMINST`), leiab sealt paigaldustõmmise ja partitsioneerib ketta (täpne mehhanism on peatükis 7).
5. Paigaldustõmmis (`install.wim`) laotakse kettale, arvuti taaskäivitub ning läbib `specialize` ja `oobeSystem` faasid (arvuti nimi, domeeniga liitumine, kasutajad, OOBE).

Ilma vastusfailita küsib süsteem igas punktis midagi (keel, ketas, tõmmis, parool, kasutaja). Vastusfaili ülesanne on need küsimused ette ära vastata.

### 1.2 Kaks vastusfaili: kogu teema võti

WDS kasutab *kahte eraldi* vastusfaili. Mõlemad on XML-failid ja neil on erinev ülesanne:

|  | WDS kliendi vastusfail (WDS Client Unattend) | Tõmmisfaili vastusfail (Image Unattend) |
| --- | --- | --- |
| Millal kasutatakse | Windows PE faasis, enne kui tõmmis kettale pannakse (`windowsPE` pass) | Pärast tõmmise kopeerimist (`specialize` ja `oobeSystem` passid) |
| Mida seadistab | WDS kliendi liides: keel, WDS-i sisselogimine, tõmmise valik, ketta partitsioonid, EULA | Paigaldatav Windows: arvuti nimi, ajavöönd, domeeniga liitumine, OOBE, kohalik administraator |
| Kus seotakse | WDS serveri Properties → Client | Konkreetse tõmmise Properties → Allow image to install in unattended mode |
| Ulatus | Kogu server (arhitektuuri kohta üks) | Iga paigaldustõmmise külge eraldi |

Mõlemad failid koostad samas tööriistas (WSIM) ja mõlemad põhinevad samal Windows 11 `install.wim` kataloogil.

## 2. Eeldused ja õpikeskkond

Soovituslik laborikeskkond (nt VMware):

| Masin | Roll | Märkused |
| --- | --- | --- |
| DC01 | Active Directory, DNS, (DHCP) | Domeen nt `lab.local` |
| WDS01 | Windows Server 2022 + WDS | Staatiline IP, domeeni liige, eraldi andmeketas tõmmiste jaoks |
| CLIENT01 | Tühi VM | **UEFI** püsivara, vähemalt 4 GB RAM, 64 GB ketas, vTPM (vt peatükk 11) |

Vaja läheb:

- Windows 11 ISO (64-bit, Pro väljaanne);
- Windows ADK, millest vajame ainult komponenti *Deployment Tools* (sisaldab WSIM-i);
- DHCP-server samas võrgus;
- kaks domeenikontot: `svc-wds-read` (loeb WDS jagatud kausta) ja `svc-domjoin` (ainult arvutite domeeni lisamise õigusega, vt peatükk 13).

**Miks eraldi andmeketas?** `RemoteInstall` kaustas on tõmmisfailid mitme GB suurused ja need kogunevad. Süsteemiketta täitumine ohustaks serverit, seepärast soovitab WDS hoida kausta väljaspool süsteemiketast.

## 3. WDS rolli paigaldus

### 3.1 Graafilises liideses

1. **Server Manager → Manage → Add Roles and Features**.
2. *Installation Type*: Role-based or feature-based installation, vali server.
3. *Server Roles*: märgi **Windows Deployment Services** ja nõustu management tools'i lisamisega.
4. *Role Services*: jäta märgituks nii **Deployment Server** kui ka **Transport Server**.
5. **Install** ja oota lõpuni (taaskäivitust ei nõua).

### 3.2 PowerShellis

```powershell
Install-WindowsFeature -Name WDS -IncludeManagementTools
```

**Miks kaks rolliteenust?** Transport Server tegeleb andmete edastamisega (TFTP, multicast), Deployment Server lisab peale tõmmiste halduse ja kliendi paigalduskogemuse. Tavalise PXE-paigalduse jaoks on vaja mõlemat.

## 4. WDS algseadistus

1. Ava **Tools → Windows Deployment Services**.
2. Paremklõps serveril → **Configure Server**.
3. *Install Options*: domeeni liikmel vali **Integrated with Active Directory** (võimaldab eelregistreeritud arvuteid ja domeenikontosid).
4. *Remote Installation Folder Location*: nt `D:\RemoteInstall` (NTFS, mitte süsteemiketas). WDS jagab selle kausta nimega `REMINST`.
5. *Proxy DHCP Server* (kuvatakse, kui DHCP töötab samas serveris): märgi **Do not listen on DHCP ports** ja **Configure DHCP options for proxy**. Kui DHCP on eraldi serveris, jäta märkimata.
6. *PXE Server Initial Settings*: **Respond to all client computers (known and unknown)**. Tootmises nõua tundmatute arvutite puhul administraatori kinnitust.
7. *Operation Complete*: **eemalda** märge „Add images to the server now“, sest impordime tõmmised järgmises peatükis käsitsi.

Sama käsureal:

```powershell
wdsutil /initialize-server /reminst:D:\RemoteInstall
wdsutil /set-server /answerclients:all
```

### 4.1 DHCP ja PXE: miks need on seotud

WDS ja DHCP kasutavad mõlemad UDP porti 67. Kui nad töötavad samas serveris, ei tohi WDS seda porti blokeerida (seepärast „Do not listen“) ja DHCP-le lisatakse **option 60 = PXEClient**, mis ütleb PXE-klientidele, et see server pakub ka PXE-teenust.

Kui DHCP ja WDS on eri serverites **samas alamvõrgus**, ei vaja DHCP erisätteid: klient leiab WDS-i broadcast'iga. **Eri alamvõrkudes** on kaks varianti: (a) IP helper / DHCP relay ruuteris, mis edastab PXE-päringu ka WDS-ile (eelistatud), või (b) DHCP option **66** (WDS IP) ja **67** (`boot\x64\wdsmgfw.efi`). Variant (b) on jäigem, sest ei võimalda kliendi arhitektuuri järgi valida.

### 4.2 Boot program ja tulemüür

WDS server → Properties → **Boot**: kontrolli, et x64 UEFI kliendi boot program oleks `boot\x64\wdsmgfw.efi`. Windows 11 nõuab UEFI-d, seega legacy BIOS variandid sind ei huvita.

Rolli paigaldus loob Windows Defender Firewalli reeglid automaatselt. Kui võrgus on vahel muu tulemüür, peavad olema lubatud UDP 67, 68, 69 (TFTP), 4011, TFTP dünaamiline UDP pordivahemik ja SMB (TCP 445), mille kaudu Setup hiljem paigaldustõmmist loeb.

## 5. Tõmmiste import

### 5.1 Ettevalmistus

Monteeri Windows 11 ISO (paremklõps → Mount), olgu draiv `E:`. Vajame kahte tõmmisfaili:

- `E:\sources\boot.wim`: käivitustõmmis ehk WinPE keskkond, millega klient käivitub;
- `E:\sources\install.wim`: paigaldustõmmis ehk tegelik Windows 11.

> **install.esd.** Media Creation Tooliga tehtud ISO-s on tihti `install.esd`. WDS vajab `.wim` formaati. Konverteeri: `dism /Export-Image /SourceImageFile:E:\sources\install.esd /SourceIndex:6 /DestinationImageFile:D:\Temp\install.wim /Compress:max /CheckIntegrity`. Õige indeksi (tavaliselt Pro) leiad käsuga `dism /Get-WimInfo /WimFile:E:\sources\install.esd`.

> **Windows 11 24H2.** Server 2022 WDS-iga on 24H2 käivitustõmmisega esinenud ühilduvusprobleeme. Kui 24H2 `boot.wim` ei käivitu või Setup jookseb kokku, proovi käivitustõmmisena Windows Server 2022 või Windows 11 23H2 `boot.wim`-i ja jäta paigaldustõmmis 24H2-ks. Kontrolli alati Microsofti hetkel kehtivat dokumentatsiooni, sest see võib muutuda.

### 5.2 Käivitustõmmise lisamine

1. WDS konsool → **Boot Images** → paremklõps → **Add Boot Image**.
2. Vali `E:\sources\boot.wim`.
3. Nimeks nt `Windows 11 WinPE x64`, lõpeta viisard.

**Miks käivitustõmmis?** See on väike Windows PE, mis laetakse kliendi mällu. Setup ise töötab sealt. Käivitustõmmis ei ole paigaldatav operatsioonisüsteem, vaid *paigaldaja kandja*.

### 5.3 Paigaldustõmmise lisamine

1. **Install Images** → paremklõps → **Add Install Image**.
2. Loo uus tõmmisegrupp (Image Group), nt `Windows11`.
3. Vali `install.wim` (või konverteeritud fail).
4. Jäta ainult need väljaanded, mida tõesti vajad (nt **Windows 11 Pro**).

Pärast importi asub tõmmisfail serveris kataloogis `D:\RemoteInstall\Images\Windows11\`. Täpselt neile nimedele (tõmmisegrupp, failinimi, tõmmise nimi) viitab hiljem WDS kliendi vastusfail (vt peatükk 7).

**Miks tõmmisegrupp?** Grupp on ühine õiguste konteiner ja samas grupis olevad tõmmised jagavad dubleeritud faile (single instance storage), mis säästab ruumi.

PowerShellis:

```powershell
Import-WdsBootImage -Path E:\sources\boot.wim -NewImageName 'Windows 11 WinPE x64'
New-WdsInstallImageGroup -Name Windows11
Import-WdsInstallImage -ImageGroup Windows11 -Path D:\Temp\install.wim -ImageName 'Windows 11 Pro'
```

## 6. Windows ADK ja WSIM

### 6.1 Paigaldus

Paigalda Windows ADK admin-arvutisse (WDS01 või eraldi tööjaam). Installeris vali ainult **Deployment Tools**. WinPE lisa pole WSIM-i jaoks vaja.

**Miks WSIM, mitte Notepad?** XML-i saab käsitsi kirjutada, aga komponentide nimed, passid ja väärtused on tundlikud ning vead põhjustavad vaikseid tõrkeid (Setup lihtsalt ignoreerib vigast sätet). WSIM valideerib failis olevad sätted kataloogi vastu.

### 6.2 Kataloogi loomine

1. Kopeeri `install.wim` kohalikule kettale (nt `C:\WIM\install.wim`). Kataloogi loomine võrgukettalt võib ebaõnnestuda.
2. Ava **Windows System Image Manager**.
3. **File → Select Windows Image** → vali `install.wim` ja väljaanne **Windows 11 Pro**; nõustu kataloogi (`.clg`) loomisega.
4. **File → New Answer File**.

**Miks kataloog?** Kataloog on tõmmise komponentide ja sätete loend. WSIM näitab ainult neid sätteid, mis selles tõmmises tegelikult olemas on, ja valideerib väärtusi nende vastu. Seetõttu peab tõmmis olema sama versiooni ja arhitektuuriga kui paigaldatav.

### 6.3 WSIM-i liides

- **Windows Image** (all vasakul): komponentide puu.
- **Answer File** (üleval vasakul): sinu vastusfail passide kaupa (1 windowsPE, 2 offlineServicing, 3 generalize, 4 specialize, 5 auditSystem, 6 auditUser, 7 oobeSystem).
- **Properties** (paremal): valitud elemendi sätted.
- **Messages** (all): Validation, XML ja Configuration Set vahekaardid.

Komponendi lisamine: paremklõps komponendil Windows Image paneelis → **Add Setting to Pass N**.

## 7. Kuidas Setup leiab tõmmise WDS serverist

Paigaldaja ei otsi tõmmist ise ega arva seda ära: WDS kliendi vastusfail ütleb talle, **kes ta on** (autentimine) ja **millist tõmmist** ta peab võtma (viide tõmmisfailile). Serveri nime vastusfaili ei kirjutata, sest Windows PE teab, millisest WDS serverist ta käivitati.

### 7.1 Ühendus samm-sammult

1. Windows PE käivitub käivitustõmmisest (`boot.wim`) ja Setup käivitub.
2. Setup ühendab SMB kaudu WDS serveri jagatud kausta `\\WDS01\REMINST` (füüsiliselt `D:\RemoteInstall`).
3. **Autentimine:** Setup kasutab vastusfaili sätet **WindowsDeploymentServices → Login → Credentials** (domeen, kasutajanimi, parool). Kui sätet pole, kuvab Setup sisselogimisakna ja paigaldus jääb ootama.
4. **Tõmmise valik:** Setup loeb sätteid **WindowsDeploymentServices → ImageSelection → InstallImage** (tõmmisegrupp, failinimi, tõmmise nimi) ja leiab nende järgi serverist õige paigaldustõmmise.
5. **Paigaldus:** Setup laotab tõmmise sätte **InstallTo** määratud kettale ja partitsioonile.

**Miks SMB ja autentimine?** TFTP, millega käivitustõmmis laeti, ei autentimi ja sobib ainult väikeste käivitusfailide jaoks. Mitme GB suurune paigaldustõmmis loetakse SMB kaudu ning see nõuab õigustega kontot.

### 7.2 Mida WDS konsoolis näed ja kuhu see vastusfailis läheb

| WDS-is | Vastusfaili säte | Näide |
| --- | --- | --- |
| Tõmmisegrupp (Install Images → grupi nimi) | `ImageGroup` | `Windows11` |
| Tõmmisfaili nimi serveris | `Filename` | `install.wim` |
| Tõmmise nimi (tõmmise Properties → Image name) | `ImageName` | `Windows 11 Pro` |
| Konto, millega Setup ühendub | `Login → Credentials` | `lab.local`, `svc-wds-read` |
| Jagatud kaust ja selle kataloog | ei kirjutata vastusfaili | `\\WDS01\REMINST` = `D:\RemoteInstall` |

Füüsiliselt asub tõmmisfail kataloogis `D:\RemoteInstall\Images\Windows11\install.wim`: `ImageGroup` on alamkataloog ja `Filename` on selle failinimi. `ImageName` on aga WDS-i imporditud tõmmise nimi, mitte failinimi, sest ühes `.wim`-failis võib olla mitu väljaannet (Home, Pro jne).

Kontrolli väärtused PowerShellis, et vältida trükivigu, ja kopeeri need vastusfaili sõna-sõnalt:

```powershell
Get-WdsInstallImage | Format-List ImageName, ImageGroup, FileName
```

### 7.3 Nõuded kontole

- Konto peab saama lugeda jagatud kausta `REMINST` (nii share kui ka NTFS õigused).
- Kontrolli tõmmisegrupi (`Windows11`) Properties → Security: grupp võib piirata ligipääsu.
- Kasuta eraldi kontot, millel on **ainult lugemisõigus** (vt peatükk 13).

**Miks viide tõmmisele vastusfailis?** Ilma `ImageSelection` sätteta kuvab Setup tõmmiste loendi ja jääb valikut ootama, st paigaldus ei ole unattended.

### 7.4 Mida tõmmisfaili vastusfail ei tee

Tõmmisfaili vastusfail (peatükk 9) ei sisalda viidet WDS serverile ega tõmmisele. WDS seostab selle tõmmisega (peatükk 10) ja Setup rakendab seda alles pärast seda, kui tõmmis on kettale laotatud.

## 8. Vastusfail 1: WDS kliendi vastusfail

Loo uus vastusfail ja lisa järgmised komponendid **windowsPE** passi.

### 8.1 Microsoft-Windows-International-Core-WinPE

| Säte | Väärtus | Miks |
| --- | --- | --- |
| InputLocale | `et-EE` | Klaviatuuripaigutus WinPE-s |
| SystemLocale, UserLocale | `et-EE` | Vormingud |
| UILanguage | `en-US` | **Peab olema keel, mis on tõmmises olemas.** Ingliskeelsel ISO-l on see `en-US` |
| SetupUILanguage → UILanguage | `en-US` | Keel, milles Setup ise kuvatakse |

**Miks?** Ilma selle komponendita küsib Setup keelt ja klaviatuuri. Kui UILanguage ei vasta tõmmises olevale keelele, lõpetab Setup veaga.

### 8.2 Autentimine WDS serveriga: WindowsDeploymentServices → Login → Credentials

Komponent: **Microsoft-Windows-Setup → WindowsDeploymentServices → Login → Credentials**.

| Säte | Väärtus |
| --- | --- |
| Domain | `lab.local` |
| Username | `svc-wds-read` |
| Password | konto parool |

**Miks?** Windows PE ühendub WDS-i `REMINST` jagatud kaustaga ja peab seal end autentima (vt peatükk 7). Ilma selle sätteta kuvab Setup sisselogimisakna. Kasuta kontot, millel on **ainult lugemisõigus**.

### 8.3 Viide WDS-is olevale tõmmisele: WindowsDeploymentServices → ImageSelection

Komponent: **Microsoft-Windows-Setup → WindowsDeploymentServices → ImageSelection**.

- **WillShowUI** = `OnError` (kuvab akna ainult vea korral);
- **InstallImage → ImageGroup** = `Windows11` (tõmmisegrupp WDS-is);
- **InstallImage → Filename** = `install.wim` (tõmmisfaili nimi serveris);
- **InstallImage → ImageName** = `Windows 11 Pro` (tõmmise nimi WDS-is);
- **InstallTo → DiskID** = `0`;
- **InstallTo → PartitionID** = `3` (partitsioon, mille loome järgmises punktis).

**Miks?** Need sätted ütlevad, millist tõmmist ja kuhu paigaldada. Tõmmisegrupp, failinimi ja tõmmise nimi peavad WDS-is nähtavaga täpselt kokku langema, muidu Setup tõmmist ei leia (väärtuste kontroll: peatükk 7.2).

### 8.4 Microsoft-Windows-Setup → DiskConfiguration

- **WillShowUI** = `OnError`;
- **Disk** (lisa uus): **DiskID** = `0`, **WillWipeDisk** = `true`.

Disk alla lisa **CreatePartitions** (kolm CreatePartition) ja **ModifyPartitions** (kolm ModifyPartition):

| Order | CreatePartition | ModifyPartition |
| --- | --- | --- |
| 1 | Type = `EFI`, Size = `260` | PartitionID = `1`, Format = `FAT32`, Label = `System` |
| 2 | Type = `MSR`, Size = `16` | PartitionID = `2` (vormindust ei vaja) |
| 3 | Type = `Primary`, Extend = `true` | PartitionID = `3`, Format = `NTFS`, Label = `Windows`, Letter = `C` |

**Miks just selline paigutus?**

- Windows 11 nõuab UEFI-d ja **GPT** ketast. GPT-ketas vajab EFI System Partitionit (ESP), kuhu läheb bootloader. 100 MB on miinimum, 260 MB sobib ka 4K-sektoriga ketastele.
- **MSR** (Microsoft Reserved) on GPT-ketta reserveeritud partitsioon Windowsi sisemiseks kasutuseks.
- **Primary** võtab kogu ülejäänud ruumi (`Extend`).
- **WillWipeDisk = true** kustutab ketta enne paigaldust, seega **kõik andmed kaovad**. Laboris see ongi soov, tootmises ole ettevaatlik.
- Eraldi recovery partitsiooni selles materjalis ei loo, WinRE jääb C: peale.

**Variant: kaks partitsiooni (EFI + Windows).** MSR partitsioon on valikuline, seega võib selle ära jätta. `Disk` sätted jäävad samaks (`DiskID` = `0`, `WillWipeDisk` = `true`), muutub ainult partitsioonide loend:

| Order | CreatePartition | ModifyPartition |
| --- | --- | --- |
| 1 | Type = `EFI`, Size = `500` | PartitionID = `1`, Format = `FAT32`, Label = `System` |
| 2 | Type = `Primary`, Extend = `true` | PartitionID = `2`, Format = `NTFS`, Label = `Windows`, Letter = `C` |

**Oluline:** Windowsi partitsioon on nüüd number **2**, seega peab peatüki 8.3 säte **InstallTo → PartitionID** olema `2`, mitte `3`. Kui `PartitionID` ei vasta tegelikule paigutusele, ei leia Setup paigalduse sihtpartitsiooni ja paigaldus ebaõnnestub. EFI suurus 500 MB on lubatud (miinimum on 100 MB), kuna ESP-le kirjutatakse aja jooksul ka alglaaduri värskendusi. Kolme partitsiooniga paigutus ülalpool jääb selle materjali põhivariandiks, sest see vastab Microsofti standardpaigutusele.

### 8.5 Microsoft-Windows-Setup → UserData

- **AcceptEula** = `true`;
- **ProductKey → Key**: KMS-keskkonnas kasuta Microsofti avaldatud üldist KMS-kliendivõtit (Microsofti lehelt *KMS client setup keys*). See **ei aktiveeri** Windowsi, vaid ütleb, et aktiveerimine tuleb KMS-serverilt.

**Miks?** EULA-ga nõustumine on kohustuslik ja Setup küsib muidu tooteklahvi. Kui tõmmises on ainult üks väljaanne ja aktiveerid hiljem, võid võtme ära jätta.

### 8.6 Valideerimine ja salvestamine

1. **Tools → Options**: kontrolli, et **Hide sensitive data in an answer file** oleks märgitud (paroolid salvestatakse Base64 kujul).
2. **Tools → Validate Answer File**: Messages paneelis ei tohi olla vigu.
3. Salvesta nt `D:\Unattend\Win11-wds-client.xml`.

> **Oluline:** „peidetud“ ei tähenda krüpteeritud. Base64 dekodeeritakse ühe käsuga.

## 9. Vastusfail 2: tõmmisfaili vastusfail

Loo **uus** vastusfail (File → New Answer File) samast kataloogist.

### 9.1 specialize pass

**Microsoft-Windows-Shell-Setup**

| Säte | Väärtus | Miks |
| --- | --- | --- |
| ComputerName | `*` | Genereerib unikaalse juhusliku nime. Fikseeritud nimi sobib ainult ühe masina korraga paigaldamiseks |
| TimeZone | `FLE Standard Time` | Eesti ajavöönd |
| ProductKey | nagu eespool | Aktiveerimine ja väljaanne |

**Microsoft-Windows-International-Core**: InputLocale `et-EE`, SystemLocale `et-EE`, UILanguage `en-US`, UserLocale `et-EE`.

**Microsoft-Windows-UnattendedJoin → Identification**

- **JoinDomain** = `lab.local`;
- **MachineObjectOU** = `OU=Workstations,DC=lab,DC=local`;
- **Credentials**: Domain, Username = `svc-domjoin`, Password.

**Miks `specialize` faasis?** Specialize on faas, kus Windows kohandatakse konkreetse masina jaoks (nimi, SID, võrk, domeen). Domeeniga liitumine käib siin, sest alles nüüd on masinal oma identiteet. Klient peab kasutama DNS-iks domeenikontrollerit, muidu liitumine ebaõnnestub.

### 9.2 oobeSystem pass

**Microsoft-Windows-Shell-Setup → OOBE**

| Säte | Väärtus | Miks |
| --- | --- | --- |
| HideEULAPage | `true` | EULA on juba heaks kiidetud |
| HideOnlineAccountScreens | `true` | Peidab Microsofti konto sisselogimise |
| HideLocalAccountScreen | `true` | Peidab kohaliku konto lehe |
| HideWirelessSetupInOOBE | `true` | Peidab Wi-Fi seadistuse |
| ProtectYourPC | `3` | Ei kuva kaitse-seadistuse lehte |
| NetworkLocation | `Work` | Võrguprofiil |

**UserAccounts → LocalAccounts → LocalAccount**: Name = `localadmin`, Group = `Administrators`, Password. Lisa ka **Microsoft-Windows-International-Core** oobeSystem passi samade `et-EE` väärtustega.

**Miks oobeSystem passis?** OOBE (Out-Of-Box Experience) on esmakäivituse kogemus: keel, konto, privaatsus. Ilma nende sätteteta jääb paigaldus selle ekraani taha ootama. Windows 11 Pro tahab tavaliselt internetti ja Microsofti kontot. Kohaliku konto määramine ja domeeniga liitumine vastusfailis väldivad seda.

> **Hoiatus:** OOBE piiramise nipid (nt `BypassNRO`) on uuemates Windows 11 ehitustes eemaldatud. Ära toetu neile, vaid tugine domeeniga liitumisele ja kohalikule kontole.

### 9.3 FirstLogonCommands (valikuline)

**Microsoft-Windows-Shell-Setup → FirstLogonCommands → SynchronousCommand** (Order = 1, CommandLine nt PowerShelli skripti käivitus). Sobib tarkvara paigaldamiseks või seadistuste rakendamiseks esimesel sisselogimisel.

Salvesta fail nt `D:\Unattend\Win11-image.xml`.

## 10. Vastusfailide seostamine WDS-iga

### 10.1 WDS kliendi vastusfail

1. WDS konsool → serveri Properties → **Client**.
2. Märgi **Enable unattended installation**.
3. Arhitektuuri **x64** juures **Browse** ja vali `Win11-wds-client.xml`.

### 10.2 Tõmmisfaili vastusfail

1. **Install Images → Windows11** → paremklõps tõmmisel **Windows 11 Pro** → **Properties**.
2. Märgi **Allow image to install in unattended mode**.
3. **Select File** ja vali `Win11-image.xml`. WDS kopeerib faili `RemoteInstall` kausta.

**Miks kaks eraldi kohta?** WDS rakendab kliendi vastusfaili käivitustõmmise töö ajal (enne tõmmise valikut), tõmmisfaili vastusfaili aga alles pärast tõmmise kettale laotamist. Seetõttu seostatakse need eri tasanditel.

## 11. Testimine

1. Loo VM CLIENT01: **UEFI** püsivara, 4 GB RAM, 64 GB ketas, võrk samas segmendis WDS01 ja DHCP-ga.
2. Windows 11 nõuab **TPM 2.0** ja **Secure Boot**. VMware's lisa vTPM (nõuab VM krüpteerimist) ja lülita Secure Boot sisse. WDS-i `wdsmgfw.efi` on Microsofti allkirjastatud ja töötab Secure Bootiga.
3. Käivita VM ja vajadusel vali boot menüüst võrgust käivitus (PXE).
4. Oodata tuleb: IP aadress → „Windows Boot Manager“ → käivitustõmmis → Setup → ühendus WDS-iga ja tõmmise leidmine → kopeerimine ja taaskäivitused → OOBE → sisselogimisekraan.
5. Kontrolli: arvuti on domeenis, ajavöönd õige, kohalik administraator toimib, ühtegi küsimust ei esitatud.

> **Ainult laboris:** kui vTPM-i pole, saab Windows 11 nõuete kontrolli Setupis vältida `LabConfig` registrivõtmetega (`BypassTPMCheck`, `BypassSecureBootCheck`, `BypassRAMCheck`) käsuga `RunSynchronous` windowsPE passis. WDS-i puhul tuleb see eraldi läbi testida ja tootmises ei tohi seda kasutada.

## 12. Veaotsing

| Sümptom | Põhjus | Lahendus |
| --- | --- | --- |
| `PXE-E53: No boot filename received` | WDS ei vasta | Kontrolli „Respond to all client computers“, DHCP option 60 või relay, tulemüür |
| Klient ei saa IP-d / käivitustõmmis ei lae | Võrgukaardi draiver puudub WinPE-s | Lisa draiver käivitustõmmisesse (Boot Images → Add Driver Packages) või kasuta VMware's e1000e adapterit |
| „This PC can't run Windows 11“ | TPM, Secure Boot, RAM või ketas ei vasta nõuetele | Lisa vTPM, lülita Secure Boot sisse, kontrolli mälu ja ketast |
| Setup küsib sisselogimist | `Login → Credentials` puudub või on vale | Kontrolli sätet ja konto õigust `REMINST` kaustale (peatükk 7) |
| Setup ei leia tõmmist | `ImageGroup`, `Filename` või `ImageName` vale | Võrdle väärtusi käsu `Get-WdsInstallImage` väljundiga (peatükk 7.2) |
| Setup küsib kettavalikut | DiskConfiguration või InstallTo ei vasta | Kontrolli DiskID ja PartitionID (peab olema 3) |
| Domeeniga liitumine ebaõnnestub | DNS, konto õigused või OU vale | Kontrolli kliendi DNS-i (DC), delegeerimist ja OU-d |
| Vastusfail ei rakendu | Vale pass või valideerimisviga | Valideeri WSIM-is, kontrolli Messages paneeli |

**Logid:** WinPE-s ava **Shift+F10** käsuaken ja vaata `X:\Windows\Panther\` (setupact.log, setuperr.log). Paigaldatud Windowsis vaata `C:\Windows\Panther\` ja `C:\Windows\Panther\UnattendGC\` (specialize ja OOBE faasi logid).

## 13. Turvamärkused

- **Paroolid vastusfailis** on Base64-s, mitte krüpteeritud. Kasuta minimaalsete õigustega teenusekontosid, mitte administraatorit.
- **Domeeniga liitumise konto:** delegeeri `svc-domjoin` kontole ainult õigus luua arvutiobjekte kindlas OU-s.
- **WDS lugemiskonto:** `svc-wds-read` vajab ainult lugemisõigust `REMINST` kaustale.
- **Vastusfaili koopia** võib paigaldatud arvutisse jääda (`C:\Windows\Panther\`). Kontrolli ja vajadusel kustuta see FirstLogonCommands abil.
- **PXE avatud võrgus:** kasuta paigalduse jaoks eraldi VLAN-i ja nõua tootmises tundmatute arvutite puhul administraatori kinnitust.
- **WDS-i tulevik:** Microsoft on WDS-i funktsioone vananevaks kuulutanud. Server 2022-s töötab see edasi, aga pikaajaliselt vaata alternatiive (Intune/Autopilot, Configuration Manager). Kontrolli Microsofti hetkeseisu.

## 14. Harjutused

1. Paigalda WDS01-le WDS roll ja impordi Windows 11 Pro tõmmis.
2. Koosta WSIM-is mõlemad vastusfailid ja seosta need WDS-iga.
3. Paigalda CLIENT01 täielikult ilma sekkumiseta ja kontrolli, et domeeniga liitumine toimis.
4. Muuda ketta paigutust (nt lisa recovery partitsioon) ja selgita, mis muutub.
5. Põhjusta teadlikult viga (vale `ImageName`) ja leia põhjus logidest.
6. **Kontrollküsimused:** Miks on kaks vastusfaili? Kuidas leiab Setup WDS serverist paigaldustõmmise ja kuidas ta seal autentib? Millises passis toimub domeeniga liitumine ja miks? Miks ei ole Base64 turvaline? Miks vajab Windows 11 GPT-ketast?

## 15. Kontrollnimekiri

- [ ] WDS roll paigaldatud ja initsialiseeritud (`RemoteInstall` eraldi kettal)
- [ ] PXE vastab, DHCP option 60 või relay seadistatud
- [ ] Käivitus- ja paigaldustõmmis imporditud
- [ ] ADK Deployment Tools paigaldatud, kataloog loodud
- [ ] WDS kliendi vastusfail (windowsPE) valmis, seotud ja sisaldab `Login` ning `ImageSelection` sätteid
- [ ] Tõmmisfaili vastusfail (specialize, oobeSystem) valmis ja seotud
- [ ] Testpaigaldus õnnestus ilma küsimusteta


