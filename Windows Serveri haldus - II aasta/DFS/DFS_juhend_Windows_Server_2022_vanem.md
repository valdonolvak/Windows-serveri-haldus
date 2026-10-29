# DFS juhend Windows Server 2022 jaoks

Tudengite nimeruum ja lektorite kausta replikatsioon

Selles juhendis seadistad domeeni TEST.LOCAL failidele DFS-i nimeruumi, piirad tudengite ligipääsu turvagrupi abil ning kopeerid lektorite kausta AD1 serverist AD2 serverisse. Juhendis on nii graafilise liidese sammud kui ka PowerShelli näited. Tee tegevused administraatori õigustes ja kontrolli alati, millist serverit või ketast parajasti muudad.

> Oluline enne alustamist  
> Ülesandes kasutatakse grupi kohta kahte nime: DFS_Tudengitele ja DFS_Tudengid. Allpool kasutan õiguste grupina DFS_Tudengitele, sest see on ülesande esimeses kirjelduses. Kui õpetaja on määranud nimeks DFS_Tudengid, kasuta seda nime järjekindlalt nii Active Directorys, õigustes kui kontrollkäskudes.

## 1. Eesmärk ja vajalikud eeldused

Pärast juhendi läbimist peab kehtima järgmine:

- F-kettal on kaust F:\DFS_Tudengitele ja see on jagatud nimega DFS_Tudengitele.

- Domeenigrupis DFS_Tudengitele on tudengite turvagrupp Tudengid; õigused on samad mis lektorite kaustal, ainult kasutajate grupp on teine.

- Tudengid avavad failid teelt \\TEST.LOCAL\Tudengid\Tudengitele.

- F:\DFS_Lektoritele sisu sünkroonitakse AD1 serverist AD2 serveri teele F:\DFS_Lektoritele.

| Muutuja | Selles juhendis kasutatav näide | Asenda vajadusel |
| --- | --- | --- |
| Domeen | TEST.LOCAL | Kasuta oma labori domeeni DNS-nime. |
| Failiserver 1 | AD1 | Kasuta serveri tegelikku nime, kus lähtekaust asub. |
| Failiserver 2 | AD2 | AD2 peab olema domeeniga liidetud ja võrgus. |
| Tudengite õiguste grupp | DFS_Tudengitele | Ülesandes esineb ka nimi DFS_Tudengid. |
| Tudengite liikmesgrupp | Tudengid | Kasuta olemasolevat kasutajate gruppi. |

Enne alustamist kontrolli, et AD1 ja AD2 lahendavad teineteise nimesid DNS-i kaudu, mõlemad on samas AD metsas ning F:-ketas on mõlemas serveris NTFS-vormingus. DFS Replication ei toeta ReFS-i ega FAT-i. Algseisu kontrolli administraatori PowerShellis:

```powershell
Get-ComputerInfo | Select-Object CsName, WindowsProductName
Get-Volume | Select-Object DriveLetter, FileSystem, Size, SizeRemaining
Resolve-DnsName AD1.TEST.LOCAL
Resolve-DnsName AD2.TEST.LOCAL
```
> Mõiste  
> DFS koosneb siin kahest osast. DFS Namespaces ehk nimeruum annab kasutajale püsiva loogilise UNC-tee. DFS Replication ehk DFSR hoiab kaustade sisu mitmes serveris sünkroonis. Nimeruum üksi faile ei kopeeri.

## 2. Valmista AD2 andmeketas ette

Tee see osa ainult siis, kui AD2-s on uus või tühjaks tegemiseks mõeldud lisaketas. Vormindamine ja partitsiooni loomine võivad olemasolevad andmed hävitada. Ära vali Windowsi süsteemiketast. Kontrolli ketta numbrit suuruse järgi.

### 2.1 DiskPart käsurealt

Ava Command Prompt administraatorina ja käivita DiskPart. Sisesta käsud ükshaaval. Enne ketta valimist võrdle list disk tulemuses suurust ja vali kindlasti õige ketas:

```powershell
diskpart
list disk
select disk 1
detail disk
attributes disk clear readonly
online disk
create partition primary
select partition 1
format fs=ntfs quick label=DFSData
assign letter=F
list volume
exit
```
> Tähelepanu  
> Näites eeldatakse, et Disk 1 on tühi lisaketas ja F: pole kasutusel. Kui `list disk` näitab valel suurusel ketast või F: on juba kasutusel, peatu ja lahenda see enne. `clean` käsku pole siin vaja: see kustutab valitud kettalt partitsioonitabeli.

Mida käsud teevad: `select disk 1` valib ketta; `attributes disk clear readonly` eemaldab kirjutuskaitse; `online disk` toob ketta kasutusele; `create partition primary` teeb esmase partitsiooni; `format` vormindab selle NTFS-iks; `assign letter=F` määrab draivitähe.

Kui ketas on juba õigesti vormindatud, ära korda partitsiooni loomist ega vormindamist. Sel juhul kontrolli kettahalduses, et maht oleks Online, failisüsteem NTFS ja draivitäht F:. DiskParti objektide valimine mõjutab järgnevaid käske, seega vaata valitud ketas alati enne vormindamist üle. [1]

## 3. Loo Active Directory turvagrupp

Grupi lisamine OU-sse ei liiguta kasutajagruppe ise sinna. Veendu, et OU KASUTAJAD eksisteerib ja et Tudengid on olemasolev turvagrupp, kuhu kuuluvad tudengite kontod. Juhendi lahendus kasutab pesastatud gruppe: tudengite kasutajakontod kuuluvad gruppi Tudengid ning Tudengid lisatakse kaustale õigusi saava gruppi DFS_Tudengitele.

### 3.1 Graafilise liidese abil

- Ava Server Manager > Tools > Active Directory Users and Computers (ADUC).

- Leia domeen TEST.LOCAL ja ava OU KASUTAJAD.

- Tee OU-l paremklõps > New > Group. Pane nimeks DFS_Tudengitele.

- Vali Group scope: Domain local ja Group type: Security. Vali OK.

- Ava loodud DFS_Tudengitele grupp, vali Members > Add. Lisa Tudengid grupp ning kinnita nimi Check Names abil.

- Kontrolli, et Tudengid ise sisaldab õpilaste kasutajakontosid. Kui ei sisalda, lisa kontod õigesse gruppi vastavalt labori juhisele.

Miks Domain local? See grupp saab samas domeenis failiserveri kaustaõigusi. Tudengid jääb kasutajaid koondavaks grupiks; kausta ACL-i lisatakse DFS_Tudengitele. Nii saab hiljem õigusi hallata grupi liikmesust muutes.

### 3.2 PowerShelli abil

Käivita domeenikontrolleris või RSAT-iga haldusmasinas administraatori PowerShell. Kui OU DN või grupi nimi on teistsugune, kohanda käsku:

```powershell
Import-Module ActiveDirectory
New-ADGroup -Name "DFS_Tudengitele" -SamAccountName "DFS_Tudengitele" `
-GroupScope DomainLocal -GroupCategory Security `
-Path "OU=KASUTAJAD,DC=TEST,DC=LOCAL"
Add-ADGroupMember -Identity "DFS_Tudengitele" -Members "Tudengid"
Get-ADGroupMember -Identity "DFS_Tudengitele"
```
> Kontroll  
> Viimases käsus peaks liikmena olema Tudengid. Kui kasutaja ei saa ligipääsu, kontrolli lisaks, et kasutaja konto kuulub gruppi Tudengid ning kasutaja on Windowsist välja ja uuesti sisse loginud, et värskendada turbetokenit.

## 4. Loo ja jaga F:\DFS_Tudengitele kaust

### 4.1 Loo kaust ja SMB-jagamine

AD1 serveris loo F:-kettale kaust DFS_Tudengitele. Ava Server Manager > File and Storage Services > Shares > Tasks > New Share. Vali SMB Share – Quick, server AD1 ja kaust F:\DFS_Tudengitele. Jaga kaust nimega DFS_Tudengitele.

- Jaga valitud kaust viisardis nimega DFS_Tudengitele. Kui viisard avab õiguste muutmise akna, vali kohandatud õigused ja kontrolli neid järgmises sammus.
<img width="313" height="230" alt="image" src="https://github.com/user-attachments/assets/a4dac210-6dae-4eb8-ace8-6f06ed1403cd" />
<img width="301" height="205" alt="image" src="https://github.com/user-attachments/assets/9ab5234c-a6f1-4637-8c54-a5a334bf3506" />

Lehel **Other Settings** märgi **Enable access-based enumeration**. Jäta **Allow caching of share** märgituks ja **Encrypt data access** märkimata.
<img width="317" height="231" alt="image" src="https://github.com/user-attachments/assets/6d946182-71ed-4795-a740-e67159ef9fcb" />

- Lehel **Permissions** vali **Customize permissions…**. Avanevas aknas määra vahelehtedel **Share** (jagamisõigused) ja **Permissions** (NTFS-õigused) õigused järgmise sammu järgi.

> **Mis on access-based enumeration?**
> Access-based enumeration (ABE) ei muuda õigusi. See peidab kasutaja eest kaustad ja failid, millele tal lugemisõigust ei ole. Kui kõigil tudengitel on kaustas samad õigused, ei muuda ABE praegu midagi. Kui kausta lisanduvad hiljem isiklikud kodukaustad, näeb iga tudeng tänu ABE-le ainult oma kausta. Säte on hea tava, sest kasutaja ei näe isegi nende kaustade nimesid, kuhu tal ligipääsu pole. Hiljem saab selle sisse või välja lülitada jagamise atribuutidest (Properties > Settings) või käsuga `Set-SmbShare -Name "DFS_Tudengitele" -FolderEnumerationMode AccessBased`.




- Share Permissions all määra õigused sama moodi nagu olemasoleval DFS_Lektoritele jagamisel. Asenda ainult ÕPPEJÕUD_DFS grupiga DFS_Tudengitele. Säilita administraatorite vajalik haldusõigus.

- Security ehk NTFS Permissions vahelehel määra samuti sama põhimõttega õigused nagu F:\DFS_Lektoritele kaustal, kasutades DFS_Tudengitele gruppi. Jäta süsteemi ja administraatorite vajalikud õigused alles.

- Rakenda muudatused ja veendu, et jagamise UNC-tee oleks \\AD1\DFS_Tudengitele.

SMB jagamisõigused ja NTFS-õigused on kaks eraldi kontrolli. Kasutaja peab pääsema läbi mõlemast. Efektiivne ligipääs on kitsam piirang neist kahest. Mõnes keskkonnas lubab jagamine Change, kuid NTFS annab ainult Read; siis jääb kasutajale tegelikuks õiguseks Read.

> Ära kopeeri pimesi  
> Ülesanne ütleb kasutada samu õigusi nagu lektorite kaustal. Ava F:\DFS_Lektoritele jagamise Share Permissions ja Security sätted ning korda nende loogikat. Kui lektoritele on näiteks ainult lugemisõigus, ära anna tudengitele Full Control õigust.

### 4.2 Kontrolli jagamist

```powershell
Get-SmbShare -Name "DFS_Tudengitele"
Get-SmbShareAccess -Name "DFS_Tudengitele"
icacls F:\DFS_Tudengitele
```

Veendu, et share tee osutab õigele kettale ja DFS_Tudengitele on nimekirjas. `Get-SmbShareAccess` näitab jagamisõigusi; `icacls` näitab NTFS-i ACL-i. Kontrolli mõlemast, et sobiv grupp oleks lisatud ja kõrvalised õigused vastaksid labori nõuetele.

## 5. Loo DFS nimeruum \\TEST.LOCAL\Tudengid

Domeenipõhine nimeruum laseb tudengitel kasutada domeeninimega UNC-teed, sõltumata failiserveri füüsilisest nimest. Selles harjutuses loob DFS-i juure AD1 ning kaustalingi siht on SMB-jagamine AD1-l. DFS-i nimeruum ise on loogiline aadress; see ei sisalda failide koopiat. [2]

### 5.1 Paigalda DFS Namespaces AD1-le

Server Manageris vali Manage > Add Roles and Features > Role-based or feature-based installation > AD1 > File and Storage Services > File and iSCSI Services. Märgi DFS Namespaces ja lisa pakutud haldustööriistad. PowerShelli alternatiiv administraatorina:

```powershell
Install-WindowsFeature FS-DFS-Namespace, RSAT-DFS-Mgmt-Con -IncludeManagementTools
Get-WindowsFeature FS-DFS-Namespace, RSAT-DFS-Mgmt-Con
```

DFS Management tööriistad avavad konsooli ja PowerShelli moodulid; DFS Namespaces on nimeruumi teenus. DFSR tuleb paigaldada mõlemale replikatsiooni liikmeserverile eraldi; sellest järgmises osas.

### 5.2 Loo nimeruum viisardis

- Ava Server Manager > Tools > DFS Management.

- Tee Namespaces sõlmel paremklõps > New Namespace.

- Namespace Server väljale kirjuta AD1 või vali see nimekirjast.

- Namespace Name väljale kirjuta Tudengid. Namespace Type juures vali Domain-based namespace. Kui saad valida Windows Server 2008 mode, kasuta seda ainult siis, kui domeeni metsa funktsionaalne tase seda toetab.

- Kinnita. Loodud juur peab olema \\TEST.LOCAL\Tudengid.

- Tee loodud nimeruumil paremklõps > New Folder. Folder name: Tudengitele. Lisa Folder target: \\AD1\DFS_Tudengitele.

- Kontrolli, et lõplik tee oleks \\TEST.LOCAL\Tudengid\Tudengitele ja siht \\AD1\DFS_Tudengitele.

Õpilase kasutajale võib juurnimeruumis vaja olla lugemisõigust selle sirvimiseks ning kausta tegelik juurdepääs määratakse sihtjagamise ja NTFS-i õigustega. Kui kasutaja näeb nimeruumis kausta, kuid selle avamisel kuvatakse Access denied, kontrolli kõigepealt jagamis- ja NTFS-õigusi, seejärel nimeruumi õigusi.

### 5.3 PowerShelli variant

Näide eeldab, et AD1 nimi lahendub domeenis ja jagamine on juba loodud. Nimeruumi juur-sihtkausta jagamise (Tudengid$) loob viisard automaatselt; PowerShellis tuleb sihtkaust enne jagada. Kui kasutad allolevaid käske, tee need AD1-s administraatoriõigustes:

```powershell
New-Item -Path "C:\DFSRoots\Tudengid" -ItemType Directory -Force
New-SmbShare -Name "Tudengid$" -Path "C:\DFSRoots\Tudengid" `
-ReadAccess "TEST\DFS_Tudengitele"
New-DfsnRoot -Path "\\TEST.LOCAL\Tudengid" `
-TargetPath "\\AD1\Tudengid$" -Type DomainV2
New-DfsnFolder -Path "\\TEST.LOCAL\Tudengid\Tudengitele" `
-TargetPath "\\AD1\DFS_Tudengitele"
Get-DfsnRoot
Get-DfsnFolderTarget -Path "\\TEST.LOCAL\Tudengid\Tudengitele"
```
> PowerShelli näite kohta  
> Juurjagamise ReadAccess peab sisaldama kasutajagruppi, kellel on lubatud nimeruumi avada. Kui domeeni NetBIOS nimi või grupi nimi erineb, asenda TEST\DFS_Tudengitele õige väärtusega. Namespace rooti õigused ja sihtkausta andmeõigused on eri asjad.

## 6. Testi tudengite ligipääsu

Testi päris tudengi kasutajakontoga, mitte administraatorina: administraatori õigused võivad peita vale ACL-i. Logi tudengi arvutis Tudengid gruppi kuuluva kontoga sisse; seejärel ava File Exploreris:

```powershell
\\TEST.LOCAL\Tudengid\Tudengitele
```

- Kontrolli, et kasutaja saab avada kausta ja näeb sisu.

- Proovi luua testfail ainult siis, kui lektorite lähtekausta õiguste näidis lubab tudengitel kirjutada. Kui õigus peaks olema ainult lugemine, proovi avamist ja lugemist, mitte kirjutamist.

- Testi keelatud kontoga (kasutaja, kes ei kuulu gruppi Tudengid). Sellel ei tohiks olla ligipääsu kausta sisule.

- Kui Windows hoiab vana ühenduse õigusi, sulge SMB ühendused või logi kasutajast välja ja uuesti sisse. Vajadusel kontrolli värske turbetokeni jaoks `whoami /groups`.

Kasulikud kontrollid serveris:

```powershell
Get-SmbShareAccess -Name "DFS_Tudengitele"
icacls F:\DFS_Tudengitele
Get-DfsnFolderTarget -Path "\\TEST.LOCAL\Tudengid\Tudengitele"
dfsutil /pktinfo
```

## 7. Replikeeri lektorite kaust AD1-st AD2-sse

DFS Replication loob mitme serveri vahel pidevalt sünkroonitava koopia. Tee replikatsioonigrupi liikmeteks AD1 ja AD2, kaustaks DFS_Lektoritele ning määra mõlema serveri sisuteeks F:\DFS_Lektoritele. AD1 määratakse esialgseks autoriteetseks ehk Primary Member liikmeks, sest selle olemasolev sisu on algallikas. DFSR võib muuta kausta sisu mõlemas serveris; ära lase kasutajatel sama faili korraga eri serverites muuta, kui töökorraldus seda ei arvesta. [3]

> Enne alustamist  
> Kontrolli, et AD1 F:\DFS_Lektoritele sisaldab õiget algsisu, AD2 F:-ketas on NTFS ja AD2-s pole seal säilitamist vajavaid teistsuguseid faile. Esialgse sünkroonimise ajal on AD1 valitud algallikaks. Ära vali Primary Member serveriks AD2, kui lähteandmed on AD1-s.

### 7.1 Paigalda DFS Replication teenus mõlemale serverile

Paigalda DFS Replication AD1-le ja AD2-le. Kui AD2 on Server Core, saad teenuse paigaldada PowerShelli kaudu; haldamist saab teha AD1-lt DFS Management konsoolist.

```powershell
Install-WindowsFeature FS-DFS-Replication
Install-WindowsFeature RSAT-DFS-Mgmt-Con -IncludeManagementTools
Get-WindowsFeature FS-DFS-Replication, RSAT-DFS-Mgmt-Con
```

Esimene käsk paigaldab DFSR teenuse. Teine paigaldab DFS-i haldustööriistad juhul, kui seda serverit kasutatakse haldamiseks. Microsofti nõuete järgi peab replikeeritav maht olema NTFS ja liikmeserverid samas AD metsas. [4]

### 7.2 Loo replikatsioonigrupp DFS Managementiga

- Ava DFS Management > Replication. Tee paremklõps > New Replication Group.

- Vali Multipurpose replication group (või wizardi vastav valik mitme üldotstarbelise serveri vahel).

- Replication Group Name pane täpselt Õpeta DFS, nagu ülesandes kirjas.

- Lisa liikmeteks AD1 ja AD2. Jätka topoloogiaga Hub and spoke ainult siis, kui wizard nõuab ning üks server on keskne; kahe serveri harjutuses vali Full mesh.

- Määra ajakava Full bandwidth / Replicate continuously. Laboris võimaldab see pidevat sünkroonimist.

- Lisa replicated folder nimega DFS_Lektoritele.

- Määra AD1 kausta tee F:\DFS_Lektoritele ja AD2 tee F:\DFS_Lektoritele. Kui tee AD2-s puudub, loo tühi sihtkaust enne või lase viisardil see seadistada.

- Primary member väljale vali AD1. Kinnita ja lõpeta wizard.

- Kui wizard küsib, kas luua lektorite jagamine AD2-s või lisada teine DFS namespace target, jäta see eraldi tööks, kui ülesanne nõuab ainult replikatsiooni. Replikatsioon üksi ei lisa AD2 kausta nimeruumi sihiks.

Kuna rühm luuakse AD-sse, peab konfiguratsioon levima domeenikontrolleritesse ja liikmeserverid peavad selle üles küsima. See võib võtta aega. Uuenduse kiiremaks küsimiseks käivita mõlemas liikmeserveris administraatori käsuviibas:

```powershell
dfsrdiag pollad
```

Seejärel oota algset sünkroonimist. Ära hinda tulemust kohe viisardi sulgemise järel: replikatsioonigrupi sätted peavad jõudma AD-st DFSR teenuseni ning failid peavad seejärel liikuma partnerisse. [5]

### 7.3 PowerShelli alternatiiv

Käivita käsud domeeniga seotud serveris, millel on DFSR PowerShelli moodul. Asenda AD1 ja AD2 tegelike arvutinimedega, kui need erinevad.

```powershell
Import-Module DFSR
New-DfsReplicationGroup -GroupName "Õpeta DFS" | `
New-DfsReplicatedFolder -FolderName "DFS_Lektoritele" | `
Add-DfsrMember -ComputerName "AD1","AD2"
Add-DfsrConnection -GroupName "Õpeta DFS" `
-SourceComputerName "AD1" -DestinationComputerName "AD2"
Set-DfsrMembership -GroupName "Õpeta DFS" `
-FolderName "DFS_Lektoritele" -ComputerName "AD1" `
-ContentPath "F:\DFS_Lektoritele" -PrimaryMember $true -Force
Set-DfsrMembership -GroupName "Õpeta DFS" `
-FolderName "DFS_Lektoritele" -ComputerName "AD2" `
-ContentPath "F:\DFS_Lektoritele" -PrimaryMember $false -Force
Get-DfsrMembership -GroupName "Õpeta DFS" -FolderName "DFS_Lektoritele"
```
> Kontrolli liikmesusi  
> `Get-DfsrMembership` peab näitama kaht liiget. AD1 ContentPath on F:\DFS_Lektoritele ja PrimaryMember väärtus True; AD2 ContentPath on sama kohalik tee ning PrimaryMember on False. Veendu, et käsud lõppesid vigadeta.

## 8. Kontrolli replikatsiooni tulemust

Pane AD1 lähtekausta üks uus väike tekstifail, näiteks DFS-test.txt. Oota veidi ja kontrolli, et sama fail tekib AD2-s kausta F:\DFS_Lektoritele. Muuda faili nime või sisu ainult kontrolli jaoks, et näha muudatuste levimist. Seejärel eemalda testfail mõlemast serverist vastavalt õpetaja juhisele.

```powershell
Get-DfsrState -ComputerName AD1
Get-DfsrState -ComputerName AD2
Get-DfsrBacklog -GroupName "Õpeta DFS" `
-FolderName "DFS_Lektoritele" `
-SourceComputerName AD1 -DestinationComputerName AD2
Get-WinEvent -LogName "DFS Replication" -MaxEvents 30 | `
Select-Object TimeCreated, Id, LevelDisplayName, Message
```

Backlog väärtus 0 tähendab, et hetkel pole AD1-st AD2-sse saatmist ootavaid faile. Kui AD2 on olnud tühi, võib algne sünkroonimine võtta aega. Vaata DFS Replication logi Event Viewerist: Applications and Services Logs > DFS Replication.

### Nimeruumi siht on eri seadistus

Kui õpetaja soovib, et kasutajad võiksid lektorite faile avada nii AD1 kui AD2 kaudu, lisa pärast sünkroonimise kontrolli lektorite DFS-kaustale teine folder target, näiteks \\AD2\DFS_Lektoritele. Selleks loo AD2-s SMB jagamine nimega DFS_Lektoritele ja pane jagamis- ning NTFS-õigused samaks mis AD1-l. Seejärel lisa siht DFS Managementis. Alles siis saavad kliendid nimeruumist suunamise teise serveri jagamisele. Ära lisa sihti enne, kui õigused ja andmed AD2-s on kontrollitud.

## 9. Veaotsing

| Sümptom | Kontrolli / lahendus |
| --- | --- |
| DFS tee ei avane | Kontrolli, et klient kasutab domeeni DNS-serverit; testige `Resolve-DnsName TEST.LOCAL` ja kas `\\TEST.LOCAL\Tudengid` avaneb. |
| Access denied, kuigi nimeruumi kausta näeb | Kontrolli DFS_Tudengitele liikmesust, SMB jagamisõigusi, NTFS ACL-i ja nimeruumi juure lugemisõigust. Logi kasutaja välja ja tagasi sisse. |
| Kaust on olemas, aga DFS ei näita sihti | Kontrolli `Get-DfsnFolderTarget` väljundit ja sihtjagamise UNC-teed; DNS peab lahendama AD1 nime. |
| DFS Replication pole saadaval | Paigalda FS-DFS-Replication mõlemale serverile; kontrolli, et serverid on samas AD metsas ja ketas on NTFS. |
| AD2 kaust ei uuene | Käivita `dfsrdiag pollad`, kontrolli replikatsioonigrupi liikmeid, ühendust ja DFS Replication sündmuste logi. Oota algse sünkroonimise lõppu. |
| Ketas ei saa F: tähte | Kontrolli `list volume`; F: võib olla juba kasutuses. Ära vorminda ketast uuesti enne, kui õige ketas ja andmete vajadus on selged. |
| Uus grupp pole kasutajale mõjunud | Kontrolli `Get-ADGroupMember DFS_Tudengitele` ja kasutaja `whoami /groups`; uuenda sisselogimistokenit väljalogimise/sisselogimisega. |

## 10. Esitamise kontrollnimekiri

- ☐ ADUC: OU KASUTAJAD sisaldab turvagruppi DFS_Tudengitele ja selle liige on Tudengid.

- ☐ AD1: F:\DFS_Tudengitele olemas; jagamise nimi on DFS_Tudengitele.

- ☐ Õigused: share ACL ja NTFS ACL vastavad lektorite näitele; õppejõudude grupp on asendatud tudengite grupiga.

- ☐ DFS Management: nimeruum on \\TEST.LOCAL\Tudengid ja folder Tudengitele sihib \\AD1\DFS_Tudengitele.

- ☐ Tudengikonto saab avada \\TEST.LOCAL\Tudengid\Tudengitele; volitamata konto ei saa sisule ligi.

- ☐ AD1 ja AD2: DFS Replication teenus paigaldatud.

- ☐ Replikatsioonigrupp Õpeta DFS sisaldab AD1 ja AD2; replitseeritav kaust DFS_Lektoritele.

- ☐ AD1 lähtekaust F:\DFS_Lektoritele on Primary Member; AD2 sihtkaust on F:\DFS_Lektoritele.

- ☐ Kontrollfail jõuab AD1-st AD2-sse ning backlog väheneb pärast sünkroonimist.

## Allikad

Microsoft Learn. Windows Server 2022 kohta kehtivad juhendid ja käsuviited. Lingid avanevad veebibrauseris.

[[1] DiskPart käsuviide](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/diskpart)

[[2] DFS nimeruumi loomine](https://learn.microsoft.com/en-us/windows-server/storage/dfs-namespaces/create-a-dfs-namespace)

[[3] DFS Replication ülevaade](https://learn.microsoft.com/en-us/windows-server/storage/dfs-replication/dfs-replication-overview)

[[4] DFS Replication paigaldamine ja eeldused](https://learn.microsoft.com/en-us/windows-server/storage/dfs-replication/install-dfs-replication)

[[5] DFS Replicationi abil kaustasihtide replikeerimine](https://learn.microsoft.com/en-us/windows-server/storage/dfs-namespaces/replicate-folder-targets-using-dfs-replication)

[[6] DFS nimeruumide ülevaade](https://learn.microsoft.com/en-us/windows-server/storage/dfs-namespaces/dfs-overview)

[[7] New-DfsnRoot PowerShelli viide](https://learn.microsoft.com/en-us/powershell/module/dfsn/new-dfsnroot?view=windowsserver2025-ps)

[[8] DFSR PowerShelli moodul](https://learn.microsoft.com/en-us/powershell/module/dfsr/?view=windowsserver2025-ps)

[[9] Access-Based Enumeration nimeruumis](https://learn.microsoft.com/en-us/windows-server/storage/dfs-namespaces/enable-access-based-enumeration-on-a-namespace)
