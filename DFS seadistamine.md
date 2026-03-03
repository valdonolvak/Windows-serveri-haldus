DFS (Jaotatud failisüsteem) ja selle seadistamine
Windows Server 2022-l
DFS (Distributed File System) võimaldab ühendada mitme serveri jagatud kaustad ühe loogilise
nimeruumi alla, nii et kasutajad näevad ühte ühtset teed, mille taga võivad asuda failid eri serverites
. Nimeruum koosneb mitmest komponendist: domeenipõhise nimeruumi puhul hoitakse
metaandmed AD-s ning nimeruumi root (juur) ja alamkaustad (folders) juhivad kasutajaid jagatud
kaustadele (tuntud ka kui folder targets) . DFS toob kaasa parema kättesaadavuse ja lihtsama
halduse – saate näiteks kasvatada andmete vastupidavust, seadistades mitu folder target‘i sama
loogilise kausta jaoks eri serverites.
Jaotatud failisüsteemi seadistamiseks tuleb serveritesse installeerida vajalikud rollid ja kasutusele võtta
DFS haldustööriistad. Windows Server 2022 puhul on DFS Namespaces ja DFS Replication mõlemad File
and Storage Services rolli teenused. Administraator saab need lisada nii GUI kaudu kui PowerShelliga.
Näiteks saab Windows PowerShelli administraatori režiimis käivitada käsu:
Install-WindowsFeature FS-DFS-Namespace -IncludeManagementTools
Install-WindowsFeature FS-DFS-Replication -IncludeManagementTools
millele järgneb vastav tulemus, et teenused õnnestusid . Esimene käsk lubab hallata DFS
nimeruume ja mahte, teine käsk võimaldab seada üles ka andmete replikatsiooni. Pärast installi
muutub võimalikuks käivitada DFS halduskonsool ( DFS Management ) või kasutada PowerShelli DFS-i
cmdlet’e. Alloleval joonisel on näha, kuidas Windows Serveri Server Managerist avada DFS Management
tööriist (menüüs Tools on valik “DFS Management”)【13†】:
Joonis: Server Manageri Tools-menüüst pääseb ligi DFS haldustööriistale, kust saab hallata nimeruume ja
replikatsiooni.
1
2 3
4 5
1
Kausta loomine ja jagamine
Esiteks loome lokaliseeritud mahu (F:) juures uue kausta. NTFS-i failisüsteemiga kettal (nt AD2 serveris)
käivitame DiskPart või kasutame PowerShelli nt New-Item . Näiteks DiskPart käsurealt:
diskpart
list disk
select disk 1
attributes disk clear readonly
online disk
create partition primary
select partition 1
format fs=ntfs quick
assign letter=F
exit
Peale seda tekib F:-kettale NTFS-i partitsioon. Loome selles partitsioonis kausta „DFS_Tudengitele“ (kas
GUI kaudu New Folder või PowerShelliga: New-Item -Path F:\DFS_Tudengitele -ItemType
Directory ). Seejärel jagame selle kausta võrku. Näiteks PowerShelliga saab selle teha käsklusega:
New-SmbShare -Name "DFS_Tudengitele" -Path "F:\DFS_Tudengitele" -FullAccess
"TEST\DFS_Tudengitele"
kus “TEST\DFS_Tudengitele” on hilisemaks ligipääsuks loodav turbarühma nimi. Kui gruppide täpseid
õiguseid eelistada GUI kaudu, võib kasutada File Explorerit: valik “Give Access to > Specific people” ja
määrata grupi FULL CONTROL (või mõistlikud õigused).
Folder target’ide loomine ja jagamine tähendab tavaliselt, et luuakse jagamine (share) F:
\DFS_Tudengitele loomiseks ning selle tekitatud jagamiserikkadust hallatakse DFS kaudu. Siin jagame
kausta samade õigustega, mis lektoritele, aga kasutajate grupiks on DFS_Tudengitele (mitte
õppejõud). See tagab, et grupi DFS_Tudengid kuuluvatele kasutajatele on kaust täielikult ligipääsetav.
(NB! NTFS õigusi võib vajadusel ka rakendada grupi Tudengid või OU=Kasutajad tasandil.)
Uue AD-grupi loomine
AD-s loome uue turbarühma, mis kannab nime DFS_Tudengid. PowerShellis saab kasutada NewADGroup cmdlet’i näiteks nii:
New-ADGroup -Name "DFS_Tudengid" -GroupScope Global -Path
"OU=Kasutajad,DC=TEST,DC=LOCAL"
See loob globaalse grupi vastavas OU-s . Seejärel lisame sinna olemasoleva rühma (nt “Tudengid”)
liikmeks:
Add-ADGroupMember -Identity "DFS_Tudengid" -Members "Tudengid"
6
2
See käsk lisab grupi Tudengid liikmeks uude grupisse DFS_Tudengid . Nii on meil grupi
DFS_Tudengid all kõik õppurite kasutajakontod, kellele me talitame juurdepääsu DFS kaustadele.
Nimeruumi loomine ja kausta lisamine
Nüüd loome DFS nimeruumi (namespace). AD-s nimega “TEST.LOCAL” saame luua uue nimeruumi
\TEST.LOCAL\Tudengid. Seda saab teha nii graafiliselt kui käsurealt. Näiteks PowerShelliga (DFS
Namespaces moodul) järgmise käsuga:
New-DfsnRoot -Path "\\TEST.LOCAL\Tudengid" -Type DomainV2 -TargetPath "\
\AD\DFS_Tudengitele"
Siin on Path uus nimeruumi nimi ja TargetPath on esialgne jagatud kausta path (AD serveri F-kettal
loodud jagamisena näiteks \AD\DFS_Tudengitele) . See loob domeenipõhise (DomainV2) nimeruumi.
Alternatiivina võib kasutada DFS Management konsooli: Start > Windows Administraatori tööriistad > DFS
Management, seejärel parempoolsel puus „Namespaces“ peale hiireklõps, valida New Namespace.
Avanevas dialoogis valime servers „AD“ (või selle nime, millel hakata nimeruumi hostima), anname
uuele jagamisele nime (nt „Tudengid“), valime tüübi Domain-based ja lubame Windows 2008 režiimi
(vanemad klientide ühilduvuseks) 【16†】.
Joonis: DFS Managementis valime puust üles Namespaces > New Namespace, et alustada uue nimeruumi
loomist.
Nimeruumi loomise käigus tuleb määrata ka nimeruumi jagamiskausta nimi. Näiteks sisestame nime
„Tudengid“ ja lühikirjeldused, klõpsame Next ja Create. Alloleval joonisel on näide Wizardi aknast, kus
valitakse nimeruumi nimi (Name) ja jagamise nimi (Share name)【15†】:
7
8
9
3
Joonis: Nimeruumi aknas märgime nimeruumi jagamise nime (antud näites „DFSShare“). Selles aknas saab
fikseerida äsja loodava nimeruumi juur-jaotuse (namespace root).
Pärast seda küsitakse nimeruumi tüüpi. Valime tavaliselt Domain-based namespace (domeenipõhine),
mis on AD-s replikatsiooniga ja mitmel serveril hostitav. Kui valite, tehke linnuke ka Enable Windows
Server 2008 mode – see tagab kaasaegseima režiimi kasutamise【16†】.
Joonis: Nimeruumi tüübi valik – kasutame domeenipõhist (Domain-based) nimeruumi ja lubame Windows
2008 režiimi.
Loome nimeruumi. Kui kõik sammud õnnestuvad, ilmub uus nimeruum „Tudengid“ loendisse. DFS
halduskonsoolis näeme nüüd \TEST.LOCAL\Tudengid nimekirjas【18†】. Nimeruum ise praegu veel
tühjaks; et sinna sisu lisada, tuleb luua nimeruumi kaust.
4
Kausta (Folder target) lisamine nimeruumi
DFS nimeruumi kaust (namespace folder) on loogiline kaust, mida kasutaja näeb nimeruumis. Selle
kausta alla saab lisada folder target’e ehk tegelikke jagatud kaustu. Näites loome nimeruumi alla uue
kausta nimega „Tudengitele“ ja seame selle jaoks targetiks äsja jagatud F:\DFS_Tudengitele. Graafilises
halduses DFS Management tuleb puu all \TEST.LOCAL\Tudengid peal klõpsata hiire parema nupuga ning
valida New Folder. Avanenud aknas anname uuele kaustale nime „Tudengitele“ ja klikime Add – seejärel
sisestame UNC-tee kausta väljajakuks, näiteks \\AD\DFS_Tudengitele , ning kinnitame .
Teine võimalus on PowerShelliga: kasutame käsku New-DfsnFolder näiteks nii:
New-DfsnFolder -Path "\\TEST.LOCAL\Tudengid\Tudengitele" -TargetPath "\
\AD\DFS_Tudengitele"
See loob nimeruumi kausta Tudengitele ning seob selle sihtteega \\AD\DFS_Tudengitele .
Käsurea -EnableTargetFailback $true jms parameetrite asemel võib lisada vastavalt vajadusele
(nt replikatsiooni siirde või istekorraga seotud seadeid). Pärast seda on
\TEST.LOCAL\Tudengid\Tudengitele käesolev loogiline tee, mis suunab sidumiskaustale F:
\DFS_Tudengitele.
Ligipääsu kontroll
Lõpuks tasub kontrollida, et tudengid reaalselt jõuavad nimeruumi alla loodud kaustani. Võtame
testkasutaja (kuulub grupi DFS_Tudengid) ja püüame tema masinast avada
\TEST.LOCAL\Tudengid\Tudengitele. Kui õigused on korrektselt seatud, peaks jagatud kaust ilmuma
ning lugemine/kirjutamine olema lubatud. Edu korral on õppuritel ligipääs Ühtsele DFS-ressursile, mis
suunab ta automaatselt serveri AD F-kettale loodud kausta. Kui on mitu serverit, saab klient kasutada ka
koondatud replikatsiooni (vt allpool), et satub lähimasse võrgupaika.
DFS replikatsioon (Õpetajatele)
Nüüd seadistame DFS replikatsiooni Õpetajatele nimeruumi tarvis (keskkonnas on õppejõudude
materjalid). Eeldame, et meil on juba loodud kaust F:\DFS_Lektoritele nii põhiserveris (AD) kui ka teises
domeenikontrolleris AD2. Me soovime, et need kaks kausta sünkroniseeriksid end DFSR kaudu. Võta
kasutusele DFS Replication Service mõlemas masinas, kui juba ei ole (vt eelnevalt InstallWindowsFeature ülesehitust).
Replikatsiooni seadistamiseks loome uue replikatsioonigrupi. PowerShelli näite kohaselt võiksime
käivitada (mõlemas serveris admin-režiimis):
# Loo uus replikatsioonigrupp
New-DfsReplicationGroup -GroupName "LektoridReplication"
# Lisa gruppi mõlemad masinad
Add-DfsrMember -GroupName "LektoridReplication" -ComputerName "AD","AD2"
# Sea ühendusmasinad (suunatud käsud, valige allikas ja siht)
Add-DfsrConnection -GroupName "LektoridReplication" -SourceComputerName "AD"
-DestinationComputerName "AD2"
Add-DfsrConnection -GroupName "LektoridReplication" -SourceComputerName
10
11
5
"AD2" -DestinationComputerName "AD"
# Loo sünkroniseeritavad kaustad mõlemas serveris
# (eeldame, et F:\DFS_Lektoritele on olemas või loome)
New-Item -Path "F:\DFS_Lektoritele" -ItemType Directory
# Määra replikatsiooniliikmed kausta radadega
Set-DfsrMembership -GroupName "LektoridReplication" -FolderName
"LektoridFolder" -ContentPath "F:\DFS_Lektoritele" -ComputerName "AD"
Set-DfsrMembership -GroupName "LektoridReplication" -FolderName
"LektoridFolder" -ContentPath "F:\DFS_Lektoritele" -ComputerName "AD2"
Siin New-DfsReplicationGroup loob uue grupi, Add-DfsrMember lisab masinad ning SetDfsrMembership määrab mõlema serveri sünkroniseeritava kaustatee . DFS Replication tagab, et
ükskõik kumma masinasse faili pannakse, ilmub see ka teises serveris. Nagu server-world
dokumentatsioon selgitab: DFS Replication’iga on võimalik “replikeerida andmeid ühest kaustast teise
serverisse” . Kui konstruktsioon on valmis, võib kontrollimiseks luua näiteks mõlemas kaustas
testifaili ja vaadata, et see jõuab ka teise serveri vastavasse kausta.
GUI kaudu võib sama teha läbi DFS Management > Replication. Seal valime New Replication Group,
anname nime, valime n-üles serveri topoloogia ja määrame sünkroniseeritavad kaustad ning liikmed
(AD ja AD2). Lõpuks kontrollime Replication haru alt, et groupe ja säted valmis.
Käsurea nüansid
Kogu ülaltoodud saab vajadusel sooritada täielikult käsurealt. Näiteks kausta loomise ja nimeruumi
määramise puhul on PowerShelli käsud ülal toodud. Lihtsamad operatsioonid (kausta loomine,
jagamine) saab teha New-Item ja New-SmbShare cmdlet’idega.
Kui aga küsimus on kuidas kõik see käib käsurealt, võib märkida ka, et dfsutil ja muud Dfs-i
käsureatööriistad olid varasemates Windowsis. Tänapäeval eelistatakse PowerShelli DFSN ja DFSR
mooduleid, mis lubavad kõiki toiminguid teha skriptina. Näiteks nime loomine net use jms on
vanaaegne; parem on kasutada New-DfsnRoot, New-DfsnFolder, Add-DfsrMember jne.
Lõpuks veel kord teooria ja otstarve: DFS nimeruum (Distributed File System Namespace) annab
kasutajale ühe loogilise „leviku“ (namespace), mis koondab mitme serveri jagatud kaustad ühte puusse
. DFS Replication pakub täiendavat töökindlust, korrastades andmete duplitseerimist serverite
vahel, nii et kriitilisi faile saaks jagada ja varundada mitmes asukohas . Ülesande käigus loodud
gruppide ja õigustega tagame, et ainult tudengid (grupis DFS_Tudengid) pääsevad ligi tudengite
failikaustale. Samal ajal saavad õppejõud oma materjalile ligi läbi „Õpetajatele“ nimeruumi.
Allikad: Microsofti ja server-world info spetsifikatsioonid DFS haldamiseks, ning PowerShelli DFS
cmdlet’id on dokumenteeritud Learn portaalis . Ekraanitõmmised pärinevad serverworld näidetest, mis demonstreerivad DFS Management konsooli kasutust.
DFS Namespaces overview in Windows Server | Microsoft Learn
https://learn.microsoft.com/en-us/windows-server/storage/dfs-namespaces/dfs-overview
Add folder targets in Windows Server | Microsoft Learn
https://learn.microsoft.com/et-ee/windows-server/storage/dfs-namespaces/add-folder-targets
12 13
14
15
1
15
1 3 8 11 12
1 2
3
6
Windows Server 2022 : File Server : Install DFS NameSpace : Server World
https://www.server-world.info/en/note?os=Windows_Server_2022&p=smb&f=9
Windows Server 2022 : File Server : Install DFS Replication : Server World
https://www.server-world.info/en/note?os=Windows_Server_2022&p=smb&f=12
Active Directory: Create a group in PowerShell - RDR-IT
https://rdr-it.com/en/active-directory-create-a-group-in-powershell/
Add-ADGroupMember (ActiveDirectory) | Microsoft Learn
https://learn.microsoft.com/en-us/powershell/module/activedirectory/add-adgroupmember?view=windowsserver2025-ps
Windows Server 2022 : File Server : Create DFS NameSpaces : Server World
https://www.server-world.info/en/note?os=Windows_Server_2022&p=smb&f=10
Create a Folder in a DFS Namespace | Microsoft Learn
https://learn.microsoft.com/en-us/windows-server/storage/dfs-namespaces/create-a-folder-in-a-dfs-namespace
New-DfsnFolder (DFSN) | Microsoft Learn
https://learn.microsoft.com/en-us/powershell/module/dfsn/new-dfsnfolder?view=windowsserver2025-ps
Windows Server 2022 : File Server : Configure DFS Replication : Server World
https://www.server-world.info/en/note?os=Windows_Server_2022&p=smb&f=13
4
5
6
7
8 9
10
11
12 13 14 15
7
