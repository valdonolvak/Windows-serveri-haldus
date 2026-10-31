# DFS juhend Windows Server 2022 jaoks

Tudengite kaust DFS-i nimeruumis ja replikatsioon AD1 ning AD2 vahel

Selles juhendis seadistad domeenis TEST.LOCAL tudengitele DFS-i nimeruumi `\\TEST.LOCAL\Tudengid\Tudengitele`. Kaust DFS_Tudengitele asub mõlemas serveris, AD1-s ja AD2-s, ning DFS Replication hoiab nende sisu sünkroonis. Kui AD1 ei ole kättesaadav, suunab nimeruum tudengid automaatselt AD2-le. Ligipääsu piirab turvagrupp. Juhendis on nii graafilise liidese sammud kui ka PowerShelli näited. Tee tegevused administraatori õigustes ja kontrolli alati, millist serverit või ketast parajasti muudad.

> **Oluline enne alustamist**  
> Ülesandes kasutatakse grupi kohta kahte nime: DFS_Tudengitele ja DFS_Tudengid. Allpool kasutan õiguste grupina DFS_Tudengitele. Kui õpetaja on määranud nimeks DFS_Tudengid, kasuta seda nime järjekindlalt nii Active Directorys, õigustes kui ka kontrollkäskudes.

## 1. Eesmärk ja vajalikud eeldused

Pärast juhendi läbimist peab kehtima järgmine:

- AD1 ja AD2 F:-kettal on kaust `F:\DFS_Tudengitele`. Mõlemas serveris on see jagatud nimega DFS_Tudengitele ja õigused on ühesugused.
- Domeenigrupi DFS_Tudengitele liige on tudengite turvagrupp Tudengid.
- Tudengid avavad failid teelt `\\TEST.LOCAL\Tudengid\Tudengitele`.
- Nimeruumi kaustal Tudengitele on kaks sihti: `\\AD1\DFS_Tudengitele` (eelistatud) ja `\\AD2\DFS_Tudengitele` (varu).
- DFS Replication sünkroonib kausta sisu AD1 ja AD2 vahel mõlemas suunas.
- Nimeruumi serverid on nii AD1 kui ka AD2. Nimeruum töötab ka siis, kui üks neist on maas.

```text
                         \\TEST.LOCAL\Tudengid\Tudengitele        ← tudeng kasutab ainult seda teed
                                        │
                       ┌────────────────┴────────────────┐
              1. eelistus                           2. varu
                       │                                 │
        \\AD1\DFS_Tudengitele                \\AD2\DFS_Tudengitele
        F:\DFS_Tudengitele   ◄── DFS Replication ──►   F:\DFS_Tudengitele
```

| Muutuja | Selles juhendis kasutatav näide | Asenda vajadusel |
| --- | --- | --- |
| Domeen | TEST.LOCAL (NetBIOS: TEST) | Kasuta oma labori domeeni nime. |
| Failiserver 1 | AD1 | Server, kus on algandmed. |
| Failiserver 2 | AD2 | Peab olema domeeniga liidetud ja võrgus. |
| Tudengite õiguste grupp | DFS_Tudengitele | Ülesandes esineb ka nimi DFS_Tudengid. |
| Tudengite liikmesgrupp | Tudengid | Kasuta olemasolevat kasutajate gruppi. |
| Replikatsioonigrupp | Tudengitele DFS | Vali vajadusel ise nimi ja kasuta seda järjekindlalt. |

Enne alustamist kontrolli, et AD1 ja AD2 lahendavad teineteise nimesid DNS-i kaudu, mõlemad on samas AD metsas ning F:-ketas on mõlemas serveris NTFS-vormingus. DFS Replication ei toeta ReFS-i ega FAT-i. Algseisu kontrolli administraatori PowerShellis mõlemas serveris:

```powershell
Get-ComputerInfo | Select-Object CsName, WindowsProductName
Get-Volume | Select-Object DriveLetter, FileSystem, Size, SizeRemaining
Resolve-DnsName AD1.TEST.LOCAL
Resolve-DnsName AD2.TEST.LOCAL
```

> **Mõiste**  
> DFS koosneb siin kahest osast. DFS Namespaces ehk nimeruum annab kasutajale püsiva loogilise UNC-tee ja suunab ta ühe sihtserveri juurde. DFS Replication ehk DFSR hoiab kaustade sisu mitmes serveris sünkroonis. Need on eraldi seadistused: nimeruum faile ei kopeeri ja replikatsioon ei lisa sihte nimeruumi.

## 2. Valmista AD2 andmeketas ette

Tee see osa ainult siis, kui AD2-s on uus või tühjaks tegemiseks mõeldud lisaketas. Vormindamine ja partitsiooni loomine võivad olemasolevad andmed hävitada. Ära vali Windowsi süsteemiketast. Kontrolli ketta numbrit suuruse järgi.

### 2.1 DiskPart käsurealt

Ava Command Prompt administraatorina ja käivita DiskPart. Sisesta käsud ükshaaval. Enne ketta valimist võrdle `list disk` tulemuses suurust ja vali kindlasti õige ketas:

```text
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

> **Tähelepanu**  
> Näites eeldatakse, et Disk 1 on tühi lisaketas ja F: pole kasutusel. Kui `list disk` näitab valel suurusel ketast või F: on juba kasutusel, peatu ja lahenda see enne. `clean` käsku pole siin vaja: see kustutab valitud kettalt partitsioonitabeli.

Mida käsud teevad: `select disk 1` valib ketta; `attributes disk clear readonly` eemaldab kirjutuskaitse; `online disk` toob ketta kasutusele; `create partition primary` teeb esmase partitsiooni; `format` vormindab selle NTFS-iks; `assign letter=F` määrab draivitähe.

Kui ketas on juba õigesti vormindatud, ära korda partitsiooni loomist ega vormindamist. Sel juhul kontrolli kettahalduses, et maht oleks Online, failisüsteem NTFS ja draivitäht F:. [1]

## 3. Loo Active Directory turvagrupp

Grupi lisamine OU-sse ei liiguta kasutajagruppe ise sinna. Veendu, et OU KASUTAJAD eksisteerib ja et Tudengid on olemasolev turvagrupp, kuhu kuuluvad tudengite kontod. Lahendus kasutab pesastatud gruppe: tudengite kasutajakontod kuuluvad gruppi Tudengid ning grupp Tudengid lisatakse kaustale õigusi saavasse gruppi DFS_Tudengitele.

### 3.1 Graafilise liidese abil

1. Ava Server Manager > Tools > Active Directory Users and Computers (ADUC).
2. Leia domeen TEST.LOCAL ja ava OU KASUTAJAD.
3. Tee OU-l paremklõps > New > Group. Pane nimeks DFS_Tudengitele.
4. Vali Group scope: **Domain local** ja Group type: **Security**. Vali OK.
5. Ava loodud grupp DFS_Tudengitele, vali Members > Add. Lisa grupp Tudengid ja kinnita nimi nupuga Check Names.
6. Kontrolli, et grupp Tudengid sisaldab tudengite kasutajakontosid. Kui ei sisalda, lisa kontod õigesse gruppi vastavalt labori juhisele.

Miks Domain local? See grupp saab samas domeenis failiserveri kaustaõigusi. Tudengid jääb kasutajaid koondavaks grupiks ja kausta ACL-i lisatakse DFS_Tudengitele. Nii saab hiljem õigusi hallata grupi liikmesust muutes.

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

> **Kontroll**  
> Viimases käsus peaks liikmena olema Tudengid. Kui kasutaja ei saa ligipääsu, kontrolli, et tema konto kuulub gruppi Tudengid ning kasutaja on Windowsist välja ja uuesti sisse loginud, et turbetoken värskeneks.

## 4. Loo ja jaga F:\DFS_Tudengitele kaust AD1-s

### 4.1 Loo kaust ja SMB-jagamine

Loo AD1 serveris kaust `F:\DFS_Tudengitele` ja jaga see viisardiga:

1. Ava Server Manager > File and Storage Services > Shares > Tasks > **New Share**.
2. **Select Profile**: vali **SMB Share – Quick**.
3. **Share Location**: vali server **AD1** ja **Type a custom path**: `F:\DFS_Tudengitele`.
4. **Share Name**: `DFS_Tudengitele`. Kontrolli, et Remote path to share oleks `\\AD1\DFS_Tudengitele`.

    <img width="313" height="230" alt="image" src="https://github.com/user-attachments/assets/a4dac210-6dae-4eb8-ace8-6f06ed1403cd" />
    <img width="301" height="205" alt="image" src="https://github.com/user-attachments/assets/9ab5234c-a6f1-4637-8c54-a5a334bf3506" />

5. **Other Settings**: märgi **Enable access-based enumeration**. Jäta **Allow caching of share** märgituks ja **Encrypt data access** märkimata.

    <img width="317" height="231" alt="image" src="https://github.com/user-attachments/assets/6d946182-71ed-4795-a740-e67159ef9fcb" />

6. **Permissions**: vali **Customize permissions…**. Avanevas aknas on kaks vahelehte, mis tuleb mõlemad üle vaadata:
    - Vahelehel **Share** (jagamisõigused) lisa **DFS_Tudengitele** ja **Administrators**, seejärel eemalda **Everyone**. Lisa uued kirjed enne Everyone eemaldamist.
    - Vahelehel **Permissions** (NTFS-õigused) vali **Disable inheritance** > **Convert inherited permissions into explicit permissions on this object**. Eemalda kõik **Users** kirjed ja lisa **DFS_Tudengitele** (Applies to: This folder, subfolders and files).
7. Vali OK, seejärel Next ja Create.

| Kus | Kellele | Õigus |
| --- | --- | --- |
| Share | Administrators | Full Control |
| Share | DFS_Tudengitele | Change (lugemine ja kirjutamine) |
| Permissions (NTFS) | SYSTEM, Administrators | Full control |
| Permissions (NTFS) | CREATOR OWNER | Full control (Subfolders and files only) |
| Permissions (NTFS) | DFS_Tudengitele | Modify |

Kui tudengid peavad saama ainult lugeda, kasuta jagamisel **Read** ja NTFS-is **Read & execute**. Kui ülesanne nõuab samu õigusi nagu mõnel olemasoleval kaustal, vaata need enne üle (`Get-SmbShareAccess -Name "<jagamine>"`, `icacls <kaust>`) ja korda sama loogikat.

> **Mis on access-based enumeration?**  
> Access-based enumeration (ABE) ei muuda õigusi. See peidab kasutaja eest kaustad ja failid, millele tal lugemisõigust ei ole. Kui kõigil tudengitel on kaustas samad õigused, ei muuda ABE praegu midagi. Kui kausta lisanduvad hiljem isiklikud kodukaustad, näeb iga tudeng tänu ABE-le ainult oma kausta. Säte on hea tava, sest kasutaja ei näe isegi nende kaustade nimesid, kuhu tal ligipääsu pole. Hiljem saab selle sisse või välja lülitada jagamise atribuutidest (Properties > Settings) või käsuga `Set-SmbShare -Name "DFS_Tudengitele" -FolderEnumerationMode AccessBased`.

> **Miks Users kirjed eemaldada?**  
> Uus kaust pärib F:-ketta juurest kirjed Users. Users sisaldab gruppi Domain Users, seega saaks iga domeeni kasutaja kausta lugeda ja sinna kaustu luua. Päritud kirjeid ei saa otse kustutada, seepärast tuleb enne pärimine katkestada.

Sama PowerShelliga AD1-s. Asenda TEST oma domeeni NetBIOS-nimega:

```powershell
New-Item -Path "F:\DFS_Tudengitele" -ItemType Directory -Force
New-SmbShare -Name "DFS_Tudengitele" -Path "F:\DFS_Tudengitele" `
    -ChangeAccess "TEST\DFS_Tudengitele" -FullAccess "BUILTIN\Administrators" `
    -FolderEnumerationMode AccessBased

icacls "F:\DFS_Tudengitele" /inheritance:d
icacls "F:\DFS_Tudengitele" /remove:g "BUILTIN\Users"
icacls "F:\DFS_Tudengitele" /grant "TEST\DFS_Tudengitele:(OI)(CI)M"
```

`New-SmbShare` ei lisa Everyone kirjet, kui õigused on käsus antud. `/inheritance:d` katkestab pärimise ja kopeerib päritud kirjed otsesteks, nagu GUI valik Convert. `(OI)(CI)M` tähendab Modify-õigust kaustale, alamkaustadele ja failidele.

SMB jagamisõigused ja NTFS-õigused on kaks eraldi kontrolli. Kasutaja peab pääsema läbi mõlemast ja tegelikuks õiguseks jääb neist kitsam. Kui jagamine lubab Change, kuid NTFS annab ainult Read, saab kasutaja ainult lugeda.

### 4.2 Kontrolli jagamist

```powershell
Get-SmbShare -Name "DFS_Tudengitele" | Select-Object Name, Path, FolderEnumerationMode
Get-SmbShareAccess -Name "DFS_Tudengitele"
icacls F:\DFS_Tudengitele
```

Veendu, et jagamise tee osutab õigele kettale ja `FolderEnumerationMode` on `AccessBased`. `Get-SmbShareAccess` peab näitama DFS_Tudengitele ja Administrators kirjeid, mitte Everyone kirjet. `icacls` peab näitama DFS_Tudengitele kirjet ja seal ei tohi olla BUILTIN\Users kirjeid. Graafiliselt saad tulemust kontrollida kausta Properties > Security > Advanced > **Effective Access** vahelehel tudengi kontoga.

## 5. Loo DFS-i nimeruum `\\TEST.LOCAL\Tudengid`

Domeenipõhine nimeruum laseb tudengitel kasutada domeeninimega UNC-teed, sõltumata failiserveri füüsilisest nimest. Selles peatükis loob nimeruumi AD1 ja kausta Tudengitele esimene siht on jagamine AD1-s. AD2 lisatakse peatükkides 8 ja 9. [2]

### 5.1 Paigalda DFS Namespaces AD1-le

Server Manageris vali Manage > Add Roles and Features > Role-based or feature-based installation > AD1 > File and Storage Services > File and iSCSI Services. Märgi **DFS Namespaces** ja **DFS Replication** ning lisa pakutud haldustööriistad. PowerShelli alternatiiv administraatorina:

```powershell
Install-WindowsFeature FS-DFS-Namespace, FS-DFS-Replication, RSAT-DFS-Mgmt-Con -IncludeManagementTools
Get-WindowsFeature FS-DFS-Namespace, FS-DFS-Replication, RSAT-DFS-Mgmt-Con
```

DFS Namespaces on nimeruumi teenus ja DFS Replication replikatsiooni teenus. DFS Management on haldustööriist, mis sisaldab konsooli ja PowerShelli mooduleid.

### 5.2 Loo nimeruum viisardis

1. Ava Server Manager > Tools > **DFS Management**.
2. Tee Namespaces sõlmel paremklõps > **New Namespace**.
3. Namespace Server: kirjuta **AD1** või vali see nimekirjast.
4. Namespace Name: kirjuta **Tudengid**.
5. Namespace Type: vali **Domain-based namespace** ja jäta märgituks **Enable Windows Server 2008 mode**, kui domeeni funktsionaalne tase seda lubab.
6. Kinnita. Loodud juur peab olema `\\TEST.LOCAL\Tudengid`.
7. Tee loodud nimeruumil paremklõps > **New Folder**. Name: **Tudengitele**. Vali Add ja lisa siht `\\AD1\DFS_Tudengitele`.
8. Kontrolli, et lõplik tee oleks `\\TEST.LOCAL\Tudengid\Tudengitele` ja siht `\\AD1\DFS_Tudengitele`.

Kausta tegelik juurdepääs määratakse sihtjagamise ja NTFS-i õigustega. Nimeruumi juurt peab kasutaja saama lugeda. Kui kasutaja näeb nimeruumis kausta, kuid selle avamisel kuvatakse Access denied, kontrolli kõigepealt jagamis- ja NTFS-õigusi, seejärel nimeruumi õigusi.

### 5.3 PowerShelli variant

Nimeruumi juurkausta jagamise (Tudengid$) loob viisard automaatselt. PowerShellis tuleb see enne ise luua ja jagada. Tee käsud AD1-s administraatoriõigustes:

```powershell
New-Item -Path "C:\DFSRoots\Tudengid" -ItemType Directory -Force
New-SmbShare -Name "Tudengid$" -Path "C:\DFSRoots\Tudengid" -ReadAccess "Everyone"
New-DfsnRoot -Path "\\TEST.LOCAL\Tudengid" -TargetPath "\\AD1\Tudengid$" -Type DomainV2
New-DfsnFolder -Path "\\TEST.LOCAL\Tudengid\Tudengitele" -TargetPath "\\AD1\DFS_Tudengitele"
Get-DfsnRoot
Get-DfsnFolderTarget -Path "\\TEST.LOCAL\Tudengid\Tudengitele"
```

> **PowerShelli näite kohta**  
> Juurjagamine Tudengid$ sisaldab ainult nimeruumi viiteid, mitte faile. Viisard annab sellele samuti lugemisõiguse kõigile. Andmete kaitse käib sihtjagamise DFS_Tudengitele õigustega.

## 6. Testi tudengite ligipääsu

Testi päris tudengi kasutajakontoga, mitte administraatorina, sest administraatori õigused võivad peita vale ACL-i. Logi tudengi arvutis sisse kontoga, mis kuulub gruppi Tudengid, ja ava File Exploreris:

```text
\\TEST.LOCAL\Tudengid\Tudengitele
```

- Kontrolli, et kasutaja saab kausta avada ja näeb selle sisu.
- Loo testfail. Kui õigused on seadistatud ainult lugemiseks, proovi avamist ja lugemist, mitte kirjutamist.
- Testi keelatud kontoga (kasutaja, kes ei kuulu gruppi Tudengid). Sellel ei tohi olla ligipääsu kausta sisule.
- Kui Windows hoiab vana ühenduse õigusi, logi kasutajast välja ja uuesti sisse. Vajadusel kontrolli värsket turbetokenit käsuga `whoami /groups`.

Kasulikud kontrollid serveris:

```powershell
Get-SmbShareAccess -Name "DFS_Tudengitele"
icacls F:\DFS_Tudengitele
Get-DfsnFolderTarget -Path "\\TEST.LOCAL\Tudengid\Tudengitele"
```

Kui AD1 kaudu kõik töötab, jätka AD2 lisamisega.

## 7. Valmista AD2 ette

AD2-s peab olema sama kaust samade õigustega. Kaust peab olema **tühi**, sest selle sisu tuleb replikatsiooniga AD1-st.

### 7.1 Paigalda rollid AD2-le

AD2 vajab DFS Replicationit (andmete sünkroonimiseks) ja DFS Namespacesi (et AD2 saaks olla ka nimeruumi server, peatükk 9.2). Paigalda need AD2-s:

```powershell
Install-WindowsFeature FS-DFS-Namespace, FS-DFS-Replication, RSAT-DFS-Mgmt-Con -IncludeManagementTools
Get-WindowsFeature FS-DFS-Namespace, FS-DFS-Replication
```

Kui AD2 on Server Core, käivita sama käsk AD2 PowerShellis või AD1-st käsuga `Invoke-Command -ComputerName AD2 -ScriptBlock { Install-WindowsFeature FS-DFS-Namespace, FS-DFS-Replication }`. Haldamist saab teha AD1 DFS Management konsoolist.

### 7.2 Loo kaust ja jagamine AD2-s

Tee AD2-s sama mis peatükis 4.1, ainult serveriks vali **AD2**:

1. Ava AD1 Server Manageris Manage > **Add Servers** ja lisa AD2, kui seda pole veel nimekirjas.
2. Ava File and Storage Services > Shares > Tasks > **New Share**.
3. Select Profile: **SMB Share – Quick**. Share Location: server **AD2**, custom path `F:\DFS_Tudengitele`.
4. Share Name: `DFS_Tudengitele`. Remote path peab olema `\\AD2\DFS_Tudengitele`.
5. Other Settings: märgi **Enable access-based enumeration**.
6. Permissions: **Customize permissions…**, seejärel seadista õigused täpselt nagu peatüki 4.1 tabelis. Lisa DFS_Tudengitele ja Administrators, eemalda Everyone, katkesta pärimine ja eemalda Users kirjed.
7. Vali Create.

PowerShelliga AD1-st (käsud käivitatakse AD2-s):

```powershell
Invoke-Command -ComputerName AD2 -ScriptBlock {
    New-Item -Path "F:\DFS_Tudengitele" -ItemType Directory -Force
    New-SmbShare -Name "DFS_Tudengitele" -Path "F:\DFS_Tudengitele" `
        -ChangeAccess "TEST\DFS_Tudengitele" -FullAccess "BUILTIN\Administrators" `
        -FolderEnumerationMode AccessBased
    icacls "F:\DFS_Tudengitele" /inheritance:d
    icacls "F:\DFS_Tudengitele" /remove:g "BUILTIN\Users"
    icacls "F:\DFS_Tudengitele" /grant "TEST\DFS_Tudengitele:(OI)(CI)M"
}
```

> **Tähelepanu**  
> Ära kopeeri faile käsitsi AD1-st AD2-sse. Kui AD2 kaustas on juba faile, võib algne replikatsioon need üle kirjutada või konfliktiks lugeda. Jäta AD2 kaust tühjaks ja lase DFSR-il sisu kopeerida.

### 7.3 Kontrolli AD2 jagamist

```powershell
Invoke-Command -ComputerName AD2 -ScriptBlock {
    Get-SmbShare -Name "DFS_Tudengitele" | Select-Object Name, Path, FolderEnumerationMode
    Get-SmbShareAccess -Name "DFS_Tudengitele"
    icacls F:\DFS_Tudengitele
    (Get-ChildItem F:\DFS_Tudengitele -Force | Measure-Object).Count
}
```

Väljund peab olema sama mis AD1-s (peatükk 4.2) ja viimane rida peab näitama 0 ehk kaust on tühi.

## 8. Lisa AD2 teiseks sihiks ja seadista replikatsioon

Selles peatükis lisatakse `\\AD2\DFS_Tudengitele` nimeruumi kaustale Tudengitele teiseks sihiks ja luuakse kahe sihi vahele replikatsioonigrupp. DFS Management pakub teise sihi lisamisel replikatsioonigrupi ise luua. [3] [5]

AD2 siht on kohe pärast lisamist kasutatav. Kliendid võidakse sinna suunata enne, kui failid on kohale jõudnud, ja siis näevad nad tühja kausta. Seepärast lülitatakse AD2 siht algse sünkroonimise ajaks välja.

### 8.1 Graafilise liidese abil

1. Ava AD1-s DFS Management > Namespaces > `\\TEST.LOCAL\Tudengid` > **Tudengitele**.
2. Tee paremklõps > **Add Folder Target**. Path to folder target: `\\AD2\DFS_Tudengitele`. Vali OK.
3. Konsool küsib: *„A replication group can be used to keep these folder targets synchronized. Do you want to create a replication group?“* Vali **Yes**. Avaneb **Replicate Folder Wizard**.
4. **Replication Group and Replicated Folder Name**: Replication group name: `Tudengitele DFS`. Replicated folder name: `DFS_Tudengitele`. Vali Next.
5. **Replication Eligibility**: viisard kontrollib mõlemat sihti. Mõlemad peavad olema Eligible. Vali Next.
6. **Primary Member**: vali **AD1**. See server on algallikas ja AD2 sisu kirjutatakse algse sünkroonimise ajal AD1 järgi üle.
7. **Topology of Connections**: vali **Full mesh**.
8. **Replication Group Schedule and Bandwidth**: vali **Replicate continuously using the specified bandwidth**, Bandwidth: **Full**.
9. Vaata kokkuvõte üle ja vali **Create**, seejärel Close. Teade, et replikatsioon algab pärast seadete levimist AD-s, on tavaline.
10. Vahekaardil **Folder Targets** tee `\\AD2\DFS_Tudengitele` kirjel paremklõps > **Disable Folder Target**. AD2 jääb replikatsiooni liikmeks, kuid kliente sinna veel ei suunata.

Seejärel käivita mõlemas serveris administraatori käsuviibas, et serverid loeksid uued seaded AD-st kohe:

```text
dfsrdiag pollad
```

### 8.2 PowerShelli alternatiiv

Käivita AD1-s. Käsud loovad replikatsioonigrupi, seovad selle nimeruumi kaustaga ja lisavad AD2 sihi esialgu välja lülitatuna:

```powershell
Import-Module DFSR

New-DfsReplicationGroup -GroupName "Tudengitele DFS" |
    New-DfsReplicatedFolder -FolderName "DFS_Tudengitele" -DfsnPath "\\TEST.LOCAL\Tudengid\Tudengitele" |
    Out-Null
Add-DfsrMember -GroupName "Tudengitele DFS" -ComputerName "AD1", "AD2"
Add-DfsrConnection -GroupName "Tudengitele DFS" -SourceComputerName "AD1" -DestinationComputerName "AD2"

Set-DfsrMembership -GroupName "Tudengitele DFS" -FolderName "DFS_Tudengitele" -ComputerName "AD1" `
    -ContentPath "F:\DFS_Tudengitele" -PrimaryMember $true -Force
Set-DfsrMembership -GroupName "Tudengitele DFS" -FolderName "DFS_Tudengitele" -ComputerName "AD2" `
    -ContentPath "F:\DFS_Tudengitele" -PrimaryMember $false -Force

New-DfsnFolderTarget -Path "\\TEST.LOCAL\Tudengid\Tudengitele" `
    -TargetPath "\\AD2\DFS_Tudengitele" -State Offline

Get-DfsrMembership -GroupName "Tudengitele DFS" -FolderName "DFS_Tudengitele" |
    Select-Object ComputerName, ContentPath, PrimaryMember, Enabled
Get-DfsnFolderTarget -Path "\\TEST.LOCAL\Tudengid\Tudengitele"
```

`Add-DfsrConnection` loob ühenduse mõlemas suunas, kui lülitit `-CreateOneWay` ei kasutata. `-State Offline` lisab AD2 sihi välja lülitatuna.

> **Kontrolli liikmesusi**  
> `Get-DfsrMembership` peab näitama kahte liiget. AD1 ContentPath on `F:\DFS_Tudengitele` ja PrimaryMember on True. AD2 ContentPath on sama tee ja PrimaryMember on False. `Get-DfsnFolderTarget` peab näitama kahte sihti: AD1 on Online ja AD2 Offline.

### 8.3 Oota algset sünkroonimist ja lülita AD2 siht sisse

Algne sünkroonimine algab alles siis, kui mõlemad serverid on uued seaded AD-st kätte saanud. Laboris võtab see tavaliselt mõne minuti. Kontrolli:

```powershell
Get-DfsrBacklog -GroupName "Tudengitele DFS" -FolderName "DFS_Tudengitele" `
    -SourceComputerName AD1 -DestinationComputerName AD2 | Measure-Object
Get-WinEvent -ComputerName AD2 -LogName "DFS Replication" -MaxEvents 10 |
    Select-Object TimeCreated, Id, Message
```

Kui backlog on 0 ja AD2 logis on sündmus **4104** (algne replikatsioon on lõppenud), lülita AD2 siht sisse. Graafiliselt: Folder Targets > `\\AD2\DFS_Tudengitele` > paremklõps > **Enable Folder Target**. PowerShelliga:

```powershell
Set-DfsnFolderTarget -Path "\\TEST.LOCAL\Tudengid\Tudengitele" `
    -TargetPath "\\AD2\DFS_Tudengitele" -State Online
```

## 9. Määra eelistatud siht ja lisa AD2 nimeruumi serveriks

### 9.1 Hoia AD1 eelistatud sihtina

DFSR on mitme ülemaga (multi-master) replikatsioon. Kui üks tudeng on suunatud AD1-le ja teine AD2-le ning mõlemad muudavad sama faili enne replikatsiooni, jääb alles hiljem salvestatud versioon. Teine versioon liigub kausta `DfsrPrivate\ConflictAndDeleted`. Selle vältimiseks suunatakse kõik kliendid tavaolukorras AD1-le ja AD2 jääb varuks. [7]

1. DFS Management > Namespaces > `\\TEST.LOCAL\Tudengid` > Tudengitele > vahekaart **Folder Targets**.
2. Tee `\\AD1\DFS_Tudengitele` kirjel paremklõps > **Properties** > vahekaart **Advanced**.
3. Märgi **Override referral ordering** ja vali **First among all targets**. Vali OK.
4. Soovi korral määra `\\AD2\DFS_Tudengitele` kirjele **Last among all targets**.

PowerShelliga:

```powershell
Set-DfsnFolderTarget -Path "\\TEST.LOCAL\Tudengid\Tudengitele" `
    -TargetPath "\\AD1\DFS_Tudengitele" -ReferralPriorityClass GlobalHigh
Set-DfsnFolderTarget -Path "\\TEST.LOCAL\Tudengid\Tudengitele" `
    -TargetPath "\\AD2\DFS_Tudengitele" -ReferralPriorityClass GlobalLow
Get-DfsnFolderTarget -Path "\\TEST.LOCAL\Tudengid\Tudengitele" |
    Select-Object TargetPath, State, ReferralPriorityClass
```

Kliendid jäävad kasutama sihti, mille nad said, kuni see on kättesaadav. Kui AD1 kaob, lähevad kliendid üle AD2-le ega lähe pärast AD1 taastumist automaatselt tagasi. Tagasipöördumise saab sisse lülitada kausta Tudengitele Properties > Referrals > **Clients fail back to preferred targets**.

### 9.2 Lisa AD2 nimeruumi serveriks

Praegu hoiab nimeruumi juurt `\\TEST.LOCAL\Tudengid` ainult AD1. Kui AD1 on maas, ei avane nimeruum üldse, kuigi andmed on AD2-s olemas. Lisa AD2 nimeruumi teiseks serveriks. [6]

1. DFS Management > Namespaces > tee `\\TEST.LOCAL\Tudengid` kirjel paremklõps > **Add Namespace Server**.
2. Namespace server: **AD2**. Vali OK. Viisard loob AD2-s kausta `C:\DFSRoots\Tudengid` ja jagamise Tudengid$.
3. Kontrolli nimeruumi vahekaardil **Namespace Servers**, et seal on nii `\\AD1\Tudengid` kui ka `\\AD2\Tudengid`.

PowerShelliga:

```powershell
Invoke-Command -ComputerName AD2 -ScriptBlock {
    New-Item -Path "C:\DFSRoots\Tudengid" -ItemType Directory -Force
    New-SmbShare -Name "Tudengid$" -Path "C:\DFSRoots\Tudengid" -ReadAccess "Everyone"
}
New-DfsnRootTarget -Path "\\TEST.LOCAL\Tudengid" -TargetPath "\\AD2\Tudengid$"
Get-DfsnRootTarget -Path "\\TEST.LOCAL\Tudengid"
```

Domeenipõhise nimeruumi kaustad ja sihid on salvestatud Active Directorysse. Kausta `C:\DFSRoots\Tudengid` ei ole vaja replikeerida.

> **Kui kasutad ka FSRM kvoote**  
> FSRM kvoodid ja kvoodimallid ei replikeeru. Kui seadistad kodukaustad ja kvoodid juhendi „FSRM kvoodid ja võrgukettad GPO-ga“ järgi, paigalda FSRM ka AD2-le ning loo seal sama kvoodimall ja automaatne kvoot. Isiklikud kaustad loo ainult AD1-s. AD2 saab need replikatsiooniga. Kui sama nimega kaust tekib enne replikatsiooni mõlemas serveris, tekib DFSR-i nimekonflikt.

## 10. Kontrolli replikatsiooni ja tõrkesiiret

### 10.1 Replikatsioon mõlemas suunas

1. Loo AD1 kausta `F:\DFS_Tudengitele` fail **test-AD1.txt**. Mõne hetke pärast peab see tekkima AD2 kausta `F:\DFS_Tudengitele`.
2. Loo AD2 kausta fail **test-AD2.txt**. See peab tekkima AD1 kausta.
3. Kustuta testfailid ühest serverist ja kontrolli, et need kaovad ka teisest.

```powershell
Get-DfsrState -ComputerName AD1
Get-DfsrState -ComputerName AD2
Get-DfsrBacklog -GroupName "Tudengitele DFS" -FolderName "DFS_Tudengitele" `
    -SourceComputerName AD1 -DestinationComputerName AD2
Get-DfsrBacklog -GroupName "Tudengitele DFS" -FolderName "DFS_Tudengitele" `
    -SourceComputerName AD2 -DestinationComputerName AD1
Get-WinEvent -LogName "DFS Replication" -MaxEvents 30 |
    Select-Object TimeCreated, Id, LevelDisplayName, Message
```

Backlog väärtus 0 tähendab, et saatmist ootavaid faile pole. Vaata vajadusel DFS Replication logi Event Viewerist: Applications and Services Logs > DFS Replication.

### 10.2 Milline siht on kliendil kasutusel

Ava tudengi arvutis File Exploreris `\\TEST.LOCAL\Tudengid\Tudengitele`. Tee kaustal paremklõps > **Properties** > vahekaart **DFS**. Nimekirjas on mõlemad sihid ja aktiivne siht on märgitud **Active**. Tavaolukorras peab aktiivne olema `\\AD1\DFS_Tudengitele`.

Käsurealt (kui kliendis on RSAT-i failiteenuste tööriistad):

```text
dfsutil cache referral
```

### 10.3 Tõrkesiirde test

1. Lülita DFS Managementis AD1 siht välja: Folder Targets > `\\AD1\DFS_Tudengitele` > **Disable Folder Target**.
2. Tühjenda tudengi arvutis DFS-i vahemälu ja ava kaust uuesti:
    ```text
    dfsutil cache referral flush
    ```
    Kui kliendis käsku `dfsutil` pole (see tuleb RSAT-i failiteenuste tööriistadega), logi kasutajast välja ja uuesti sisse.
3. Kontrolli vahekaardil DFS, et aktiivne siht on nüüd `\\AD2\DFS_Tudengitele` ja failid on nähtavad.
4. Lülita AD1 siht tagasi sisse: **Enable Folder Target**.

Põhjalikum test: ühenda AD1 virtuaalmasina võrguadapter VMware'is lahti ja proovi kausta avada. See töötab ainult siis, kui AD2 on samuti domeenikontroller ja DNS-server ning klient kasutab AD2 DNS-i. Muidu ei leia klient domeeni üles ja test ebaõnnestub DNS-i, mitte DFS-i tõttu.

## 11. Veaotsing

| Sümptom | Kontrolli / lahendus |
| --- | --- |
| DFS-i tee ei avane | Kontrolli, et klient kasutab domeeni DNS-serverit: `Resolve-DnsName TEST.LOCAL`. Kontrolli, kas `\\TEST.LOCAL\Tudengid` avaneb. |
| Access denied, kuigi nimeruumi kausta näeb | Kontrolli DFS_Tudengitele liikmesust, SMB jagamisõigusi ja NTFS ACL-i **mõlemas** serveris. Logi kasutaja välja ja tagasi sisse. |
| Iga domeeni kasutaja pääseb kausta | Kaust pärib F:-ketta juurest Users kirjed või jagamisel on Everyone. Katkesta pärimine, eemalda Users ja Everyone ning lisa DFS_Tudengitele (peatükid 4.1 ja 7.2). |
| Add Folder Target ei paku replikatsiooni | DFS Replication pole ühes serveris paigaldatud. Paigalda FS-DFS-Replication mõlemale ja loo replikatsioon käsitsi: Replication > New Replication Group. |
| Replication Eligibility näitab viga | Kontrolli, et F: on mõlemas serveris NTFS, kaust on olemas ja serverid on samas AD metsas. |
| AD2 kaust ei uuene | Käivita mõlemas serveris `dfsrdiag pollad`. Kontrolli liikmeid (`Get-DfsrMembership`), ühendusi ja DFS Replication logi. Oota algse sünkroonimise lõppu (sündmus 4104). |
| Kliendid näevad AD2-s tühja kausta | AD2 siht lülitati sisse enne algse sünkroonimise lõppu. Lülita see välja ja oota backlog 0 ja sündmust 4104 (peatükk 8.3). |
| Faili muudatus kadus | DFSR-i konflikt: sama faili muudeti mõlemas serveris. Vaata kausta `F:\DFS_Tudengitele\DfsrPrivate\ConflictAndDeleted` ja kontrolli, et AD1 on eelistatud siht (peatükk 9.1). |
| Kui AD1 on maas, ei avane `\\TEST.LOCAL\Tudengid` | AD2 ei ole nimeruumi server (peatükk 9.2) või klient ei leia DNS-i kaudu domeeni. |
| Ketas ei saa F: tähte | Kontrolli `list volume`. F: võib olla juba kasutuses. Ära vorminda ketast uuesti enne, kui õige ketas ja andmete vajadus on selged. |
| Uus grupp pole kasutajale mõjunud | Kontrolli `Get-ADGroupMember DFS_Tudengitele` ja kasutaja `whoami /groups`. Uuenda sisselogimistokenit välja- ja sisselogimisega. |

## 12. Esitamise kontrollnimekiri

- [ ] ADUC: OU KASUTAJAD sisaldab turvagruppi DFS_Tudengitele ja selle liige on Tudengid.
- [ ] AD1 ja AD2: kaust `F:\DFS_Tudengitele` on olemas ja jagatud nimega DFS_Tudengitele, access-based enumeration on sisse lülitatud.
- [ ] Õigused on mõlemas serveris ühesugused: jagamisel DFS_Tudengitele ja Administrators, NTFS-is DFS_Tudengitele; Everyone ja Users kirjeid pole.
- [ ] Nimeruum `\\TEST.LOCAL\Tudengid` on olemas ja selle nimeruumi serverid on AD1 ja AD2.
- [ ] Kaustal Tudengitele on sihid `\\AD1\DFS_Tudengitele` (First among all targets) ja `\\AD2\DFS_Tudengitele`, mõlemad Online.
- [ ] Replikatsioonigrupp Tudengitele DFS sisaldab AD1 (Primary member) ja AD2, replikeeritav kaust on DFS_Tudengitele.
- [ ] Testfail liigub AD1-st AD2-sse ja AD2-st AD1-sse, backlog on mõlemas suunas 0.
- [ ] Tudengi konto saab avada `\\TEST.LOCAL\Tudengid\Tudengitele`, volitamata konto ei saa sisule ligi.
- [ ] Kui AD1 siht välja lülitada, avab tudeng kausta AD2 kaudu (vahekaart DFS näitab aktiivsena AD2).

## Allikad

Microsoft Learn. Windows Server 2022 kohta kehtivad juhendid ja käsuviited.

[[1] DiskPart käsuviide](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/diskpart)

[[2] DFS nimeruumi loomine](https://learn.microsoft.com/en-us/windows-server/storage/dfs-namespaces/create-a-dfs-namespace)

[[3] DFS Replication ülevaade](https://learn.microsoft.com/en-us/windows-server/storage/dfs-replication/dfs-replication-overview)

[[4] DFS Replication paigaldamine ja eeldused](https://learn.microsoft.com/en-us/windows-server/storage/dfs-replication/install-dfs-replication)

[[5] DFS Replicationi abil kaustasihtide replikeerimine](https://learn.microsoft.com/en-us/windows-server/storage/dfs-namespaces/replicate-folder-targets-using-dfs-replication)

[[6] Nimeruumi serverite lisamine domeenipõhisele nimeruumile](https://learn.microsoft.com/en-us/windows-server/storage/dfs-namespaces/add-namespace-servers-to-increase-availability)

[[7] Sihi prioriteedi määramine (referral ordering)](https://learn.microsoft.com/en-us/windows-server/storage/dfs-namespaces/set-target-priority-to-override-referral-ordering)

[[8] DFS nimeruumide ülevaade](https://learn.microsoft.com/en-us/windows-server/storage/dfs-namespaces/dfs-overview)

[[9] DFSN PowerShelli moodul](https://learn.microsoft.com/en-us/powershell/module/dfsn/?view=windowsserver2025-ps)

[[10] DFSR PowerShelli moodul](https://learn.microsoft.com/en-us/powershell/module/dfsr/?view=windowsserver2025-ps)

[[11] Access-Based Enumeration nimeruumis](https://learn.microsoft.com/en-us/windows-server/storage/dfs-namespaces/enable-access-based-enumeration-on-a-namespace)
