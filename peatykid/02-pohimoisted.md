## 2. Põhimõisted ja terminid

Iga termini juures on eestikeelne nimetus, ingliskeelne originaal (sest ekraanil ja dokumentatsioonis näed peamiselt seda), selgitus ja näide meie laborist. Soovitus: ära õpi tabelit pähe, vaid tule selle juurde tagasi, kui laboritöös mõni sõna segaseks jääb.

### 2.1 Üldmõisted

| Termin (EN) | Selgitus | Näide laboris |
| --- | --- | --- |
| Server (*server*) | Arvuti või tarkvara, mis pakub teenust teistele arvutitele (klientidele). „Server“ on roll, mitte riistvara tüüp: ka virtuaalmasin võib olla server. | DC1 pakub DNS-i ja autentimist, CORE1 pakub DHCP-d ja failijagamist. |
| Klient (*client*) | Arvuti või programm, mis kasutab serveri teenuseid. | WIN11-01 küsib DHCP-st aadressi ja DC1-lt sisselogimise kinnitust. |
| Roll (*server role*) | Serveri põhifunktsioon, mis paigaldatakse Server Manageri või PowerShelliga (nt AD DS, DNS Server, DHCP Server, File and Storage Services, WDS). | `Install-WindowsFeature DHCP` paigaldab DHCP rolli. |
| Komponent (*feature*) | Lisavõimekus, mis toetab rolle või serverit ennast, kuid ei ole iseseisev teenus (nt Windows Server Backup, RSAT tööriistad, .NET Framework, Failover Clustering). | `Install-WindowsFeature Windows-Server-Backup`. |
| Rolliteenus (*role service*) | Rolli alamosa, mida saab eraldi valida. | Failiteenuste rolli all on rolliteenused *File Server*, *DFS Namespaces*, *File Server Resource Manager*. |
| Väljaanne (*edition*) | Litsentsi- ja funktsioonitase: Standard, Datacenter, Datacenter: Azure Edition, Essentials. | Laboris kasutame Standardit. |
| Paigaldusvalik (*installation option*) | Kas serveril on graafiline töölaud (*Desktop Experience*) või ainult käsur (*Server Core*). Valik tehakse paigaldamisel; Server 2022 puhul hiljem vahetada ei saa. | DC1 = Desktop Experience, CORE1 = Server Core. |
| LTSC (*Long-Term Servicing Channel*) | Uuenduskanal, kus uus versioon ilmub iga 2–3 aasta tagant ja saab 5 aastat põhituge + 5 aastat laiendatud tuge. Windows Server 2022 on LTSC väljalase. | Server 2022 → järgmine LTSC on Server 2025. |
| Virtuaalmasin (*virtual machine*, VM) | Tarkvaraliselt emuleeritud arvuti, mis jookseb hüperviisori (nt Proxmox VE (KVM/QEMU), VMware ESXi, Hyper-V) peal. | Kõik viis labori masinat on VM-id. |
| Tõmmis (*image*) | Fail, mis sisaldab terve operatsioonisüsteemi või ketta sisu. Windowsis on tõmmisfailid tavaliselt WIM-vormingus. | `install.wim`, `boot.wim`, ISO-tõmmisfail. |
| Kaughaldus (*remote management*) | Serveri haldamine teisest arvutist võrgu kaudu, ilma serveri konsooli ära kasutamata. | DC1-st CORE1 haldamine Server Manageri või `Enter-PSSession` abil. |

### 2.2 Active Directory mõisted

| Termin (EN) | Selgitus | Näide laboris |
| --- | --- | --- |
| Kataloogiteenus (*directory service*) | Keskne andmebaas, kus hoitakse võrgu objekte (kasutajad, arvutid, rühmad) ja nende atribuute ning mis vastab küsimusele „kes sa oled ja mida sa tohid?“. | Active Directory. |
| AD DS (*Active Directory Domain Services*) | Windows Serveri roll, mis teeb serverist domeenikontrolleri ja pakub kataloogiteenust, autentimist (Kerberos/NTLM) ja poliitikate rakendamist. | Paigaldatakse DC1-le ja CORE1-le. |
| Domeen (*domain*) | Halduslik ja turvalisuse piir: ühine kasutajate andmebaas, ühised paroolireeglid, ühine nimi DNS-is. | `perenimi.local`. |
| Domeenikontroller (*domain controller*, DC) | Server, kus jookseb AD DS ja mis hoiab domeeni andmebaasi koopiat (`NTDS.dit`) ning kontrollib sisselogimisi. | DC1 ja CORE1. Kaks DC-d = ühe rikke korral domeen töötab edasi. |
| Mets (*forest*) | Kõige kõrgem AD struktuur: ühe või mitme domeeni kogum ühise skeemi ja globaalkataloogiga. Mets on tegelik turvapiir. | Meie mets koosneb ühest domeenist `perenimi.local`. |
| Puu (*tree*) | Domeenid, millel on järjestikune DNS-nimeruum. | `perenimi.local` + `tartu.perenimi.local`. |
| Skeem (*schema*) | Reeglid, mis kirjeldavad, milliseid objektitüüpe (klassid) ja atribuute AD-s olla saab. Üks skeem kogu metsale. | Exchange'i paigaldus laiendab skeemi. |
| Organisatsiooniüksus (*organizational unit*, OU) | Konteiner objektide rühmitamiseks domeeni sees. OU-le saab linkida GPO-sid ja delegeerida haldusõigusi. | `OU=Arvutid,OU=Labor,DC=perenimi,DC=local`. |
| Konteiner (*container*) | Vaikimisi olemasolev kaust (nt `Users`, `Computers`), millele **ei saa** GPO-d linkida. Seetõttu loome oma OU-d. | Uued domeeni liidetud arvutid satuvad `CN=Computers`. |
| Objekt (*object*) | Üks kirje AD-s: kasutaja, arvuti, rühm, printer, OU, GPO. Igal objektil on unikaalne GUID ja SID. | Kasutaja `mari.maasikas`. |
| DN (*distinguished name*) | Objekti täielik „aadress“ AD-s, kirjutatud alt üles. | `CN=Mari Maasikas,OU=Kasutajad,OU=Labor,DC=perenimi,DC=local`. |
| UPN (*user principal name*) | Kasutaja sisselogimisnimi e-posti kujul. | `mari.maasikas@perenimi.local`. |
| sAMAccountName | Vana (pre-Windows 2000) sisselogimisnimi kujul `DOMEEN\kasutaja`, kuni 20 märki. | `PERENIMI\mari.maasikas`. |
| SID (*security identifier*) | Unikaalne turvaidentifikaator, mille järgi Windows õigusi tegelikult kontrollib. Kasutaja ümbernimetamine SID-i ei muuda. | `S-1-5-21-…-1105`. |
| Turvarühm (*security group*) | Rühm, mida saab kasutada õiguste andmiseks. Erineb levirühmast (*distribution group*), mis on ainult e-posti jaoks. | `GG_Raamatupidamine`. |
| Rühma ulatus (*group scope*) | Määrab, kust rühma liikmed võivad tulla ja kus rühma saab kasutada: **Domain Local** (õigused ressursile), **Global** (kasutajad oma domeenist), **Universal** (kogu metsas). | Vt AGDLP peatükis 8. |
| Replikatsioon (*replication*) | AD muudatuste kopeerimine DC-de vahel, et kõigil oleks sama andmebaas. AD kasutab mitme ülemaga (*multi-master*) replikatsiooni. | Kasutaja loomine DC1-l jõuab mõne sekundiga CORE1-le. |
| Sait (*site*) | AD-s kirjeldatud füüsiline asukoht (IP-alamvõrgud), mille järgi suunatakse kliendid lähima DC juurde ja ajastatakse replikatsiooni. | Vaikimisi `Default-First-Site-Name`. |
| Globaalkataloog (*global catalog*, GC) | DC, mis hoiab osalist koopiat kõigi metsa domeenide objektidest ja on vajalik sisselogimiseks (universaalrühmad) ja otsinguks. | Mõlemad meie DC-d on GC-d. |
| FSMO rollid (*Flexible Single Master Operations*) | Viis eriulesannet, mida korraga täidab ainult üks DC: Schema Master, Domain Naming Master (metsa tasandil), RID Master, PDC Emulator, Infrastructure Master (domeeni tasandil). | Esimene DC (DC1) saab kõik viis. `netdom query fsmo`. |
| PDC Emulator | FSMO roll, mis on domeeni ajaallikas, töötleb paroolimuudatusi kiiremini ja on GPO-de vaikimisi muutmiskoht. | DC1. |
| Kerberos | Vaikimisi autentimisprotokoll domeenis. Kasutaja saab DC-lt „pileti“ (*ticket*) ja näitab seda teenustele ilma parooli uuesti saatmata. Nõuab, et kellaajad erineksid alla 5 minuti. | Kui kliendi kell on vale, sisselogimine ebaõnnestub. |
| Usaldussuhe (*trust*) | Seos domeenide või metsade vahel, mis lubab ühe domeeni kasutajatel kasutada teise ressursse. | Metsa sees on usaldussuhted automaatsed. |
| Metsa/domeeni funktsionaaltase (*functional level*) | Määrab, milliseid AD võimalusi saab kasutada ja milliseid vanemaid DC versioone lubatakse. Server 2022-l on kõrgeim tase *Windows Server 2016*. | Paigaldusel valime 2016 taseme. |
| DSRM (*Directory Services Restore Mode*) | DC erirežiim AD andmebaasi taastamiseks; selle jaoks määratakse eraldi parool. | Parool sisestatakse DC paigaldusel. |
| Delegeerimine (*delegation of control*) | Piiratud haldusõiguste andmine (nt „võib lähtestada paroole OU-s Kasutajad“) ilma Domain Admins rühma lisamata. | Labor 5. |

### 2.3 Võrgu ja nimelahenduse mõisted

| Termin (EN) | Selgitus | Näide laboris |
| --- | --- | --- |
| IP-aadress, alamvõrgu mask | Seadme aadress võrgus ja märge, milline osa aadressist tähistab võrku. `/24` = 255.255.255.0. | 192.168.10.10/24. |
| Vaikelüüs (*default gateway*) | Ruuter, kuhu saadetakse liiklus teistesse võrkudesse. | 192.168.10.1. |
| DNS (*Domain Name System*) | Nimelahendus: tõlgib nimed IP-aadressideks ja vastupidi. AD ei tööta ilma DNS-ita, sest kliendid leiavad DC-d DNS-i SRV-kirjete kaudu. | `dc1.perenimi.local` → 192.168.10.10. |
| Tsoon (*zone*) | DNS-i nimeruumi osa, mille kirjeid üks server haldab. **Forward lookup zone** = nimi→IP, **reverse lookup zone** = IP→nimi. | `perenimi.local` ja `10.168.192.in-addr.arpa`. |
| AD-integreeritud tsoon (*AD-integrated zone*) | DNS-tsoon, mida hoitakse AD andmebaasis ja replikeeritakse koos AD-ga; lubab turvalisi dünaamilisi uuendusi. | Mõlemad tsoonid. |
| DNS-kirje (*resource record*) | Üks rida tsoonis. **A** = nimi→IPv4, **AAAA** = nimi→IPv6, **PTR** = IP→nimi, **CNAME** = varjunimi, **MX** = meiliserver, **SRV** = teenuse asukoht, **NS** = nimeserver, **SOA** = tsooni põhiandmed. | `_ldap._tcp.dc._msdcs.perenimi.local` (SRV). |
| FQDN (*fully qualified domain name*) | Arvuti täielik DNS-nimi. | `core1.perenimi.local`. |
| Edastaja (*forwarder*) | Väline DNS-server, kelle poole meie DNS pöördub nimedega, mida ta ise ei tea (nt internet). | 1.1.1.1 või kooli DNS. |
| Dünaamiline uuendus (*dynamic update*) | Kliendid registreerivad ise oma A- ja PTR-kirjed DNS-is. | WIN11-01 ilmub tsooni automaatselt. |
| DHCP (*Dynamic Host Configuration Protocol*) | Protokoll, mis jagab klientidele automaatselt IP-aadressi, maski, lüüsi, DNS-serverid jm. | CORE1 jagab aadresse. |
| Ulatus (*scope*) | DHCP aadressivahemik koos seadetega ühe alamvõrgu jaoks. | 192.168.10.100–200. |
| Välistus (*exclusion*) | Aadressid ulatuse sees, mida DHCP ei jaga. | 192.168.10.100–110 (printerid). |
| Reserveering (*reservation*) | Konkreetsele MAC-aadressile alati sama IP. | WIN11-01 saab alati .150. |
| Rent (*lease*) | Aeg, mille jooksul klient võib aadressi kasutada; poole aja möödudes püüab ta seda pikendada. | Vaikimisi 8 päeva. |
| DHCP valikud (*options*) | Lisaseaded: **003** ruuter, **006** DNS-serverid, **015** DNS-domeeninimi, **066/067** PXE alglaadimisserver ja -fail. | 006 = 192.168.10.10, 192.168.10.11. |
| DORA | DHCP neljaastmeline protsess: **D**iscover → **O**ffer → **R**equest → **A**cknowledge. | Vt skeemi peatükis 6. |
| APIPA | Aadress 169.254.x.x, mille Windows endale võtab, kui DHCP ei vasta. Märk, et DHCP ei tööta. | `ipconfig` näitab 169.254.12.7. |
| Autoriseerimine (*DHCP authorization*) | Domeenis peab DHCP-server olema AD-s autoriseeritud, muidu ta ei jaga aadresse. Kaitseb „võõraste“ DHCP-serverite eest. | `Add-DhcpServerInDC`. |

### 2.4 Rühmapoliitika mõisted

| Termin (EN) | Selgitus | Näide laboris |
| --- | --- | --- |
| Rühmapoliitika (*Group Policy*) | Mehhanism, millega domeen keskselt seadistab arvuteid ja kasutajaid (turva-, töölaua-, tarkvara-, registriseaded). | Paroolireeglid, draivide kaardistamine. |
| GPO (*Group Policy Object*) | Üks nimeline seadete komplekt. Koosneb kahest osast: **GPC** (AD-s) ja **GPT** (failid kaustas SYSVOL). | `GPO_Kasutajad_Toolaud`. |
| Link (*GPO link*) | GPO sidumine saidi, domeeni või OU-ga. Ilma lingita GPO ei mõju. Ühe GPO võib linkida mitmesse kohta. | GPO lingitud OU-le `Kasutajad`. |
| Arvuti- ja kasutajakonfiguratsioon | GPO kaks poolt: arvutiseaded rakenduvad arvuti käivitumisel, kasutajaseaded sisselogimisel. **Arvutiseaded mõjuvad arvutiobjektidele, kasutajaseaded kasutajaobjektidele** – olenevalt sellest, kus objekt AD-s asub. | Klassikaline viga: kasutajaseadega GPO lingitakse arvutite OU-le. |
| Policies vs Preferences | **Policies** on jõustatud ja kasutaja ei saa neid muuta; **Preferences** on eelistused (nt draivid, otseteed, registrivõtmed), mida kasutaja võib muuta. | Draivi kaardistus = Preference. |
| LSDOU | GPO-de rakendamise järjekord: **L**ocal → **S**ite → **D**omain → **O**U (vanem OU → laps-OU). Hilisem võidab konflikti korral. | Vt skeemi peatükis 7. |
| Pärimine ja selle blokeerimine (*Block Inheritance*) | OU võib keelata ülemate GPO-de pärimise. | Testi-OU. |
| Jõustamine (*Enforced*) | Lingi omadus, mis sunnib GPO rakenduma ka siis, kui allpool on pärimine blokeeritud või vastupidine seade. | Turvapoliitika domeeni tasemel. |
| Turvafiltreerimine (*security filtering*) | GPO rakendub ainult neile, kellel on GPO-l õigused *Read* + *Apply group policy*. | GPO ainult rühmale `GG_IT`. |
| WMI-filter | GPO rakendub ainult arvutitele, mis vastavad WMI-päringule (nt OS-i versioon). | Ainult Windows 11 arvutitele. |
| Loopback-töötlus (*loopback processing*) | Kasutajaseaded võetakse arvuti asukoha järgi, mitte kasutaja asukoha järgi. Kasutatakse arvutiklassides ja kioskites. | Arvutiklassi OU. |
| SYSVOL | Jagatud kaust igal DC-l (`C:\Windows\SYSVOL`), kus asuvad GPO failid ja sisselogimisskriptid; replikeeritakse DFSR-iga. | `\\perenimi.local\SYSVOL`. |
| gpupdate / gpresult | Käsud poliitikate kohe rakendamiseks ja rakendunud poliitikate kontrollimiseks. | `gpupdate /force`, `gpresult /r`. |

### 2.5 Failiteenuste ja õiguste mõisted

| Termin (EN) | Selgitus | Näide laboris |
| --- | --- | --- |
| NTFS-õigused | Failisüsteemi tasemel õigused (Full control, Modify, Read & execute, List, Read, Write). Kehtivad nii kohapeal kui ka võrgu kaudu. | Kaust `F:\Osakonnad\Raamatupidamine`. |
| Jagamisõigused (*share permissions*) | Võrgujagamise õigused (Full, Change, Read). Kehtivad ainult võrgu kaudu ligipääsul. | Jagamine `\\core1\Raamatupidamine`. |
| Efektiivne õigus (*effective access*) | Võrgu kaudu kehtib **piiravam** kahest: jagamisõigus vs NTFS-õigus. | Share = Full, NTFS = Read → tulemus Read. |
| ACL / ACE | *Access Control List* on objekti õiguste nimekiri; iga rida on *Access Control Entry*. | `icacls F:\Osakonnad`. |
| Pärimine (*inheritance*) | Alamkaustad ja failid saavad õigused ülemkaustalt. | Uus fail pärib kausta õigused. |
| Deny | Keelav ACE, mis üldjuhul võidab lubava. Kasuta säästlikult. | — |
| ABE (*Access-Based Enumeration*) | Kasutaja ei näe jagamises kaustu, kuhu tal õigust pole. | Sisse lülitatud jagamisel `Osakonnad`. |
| AGDLP | Soovitatav õiguste andmise mudel: **A**ccou ta → **G**lobal group → **D**omain **L**ocal group → **P**ermission. | Vt peatükki 8. |
| UNC-tee | Võrguressursi aadress kujul `\\server\jagamine\kaust`. | `\\perenimi.local\Andmed\Kasutajad`. |
| DFS Namespace | Virtuaalne kaustapuu, mis peidab tegelikud serverinimed. | `\\perenimi.local\Andmed`. |
| FSRM | *File Server Resource Manager*: kvoodid, failitüüpide blokeerimine, aruanded. | Kasutajakausta kvoot 100 MB (ptk 13). |

### 2.6 Paigalduse ja WDS-i mõisted

| Termin (EN) | Selgitus | Näide laboris |
| --- | --- | --- |
| WDS (*Windows Deployment Services*) | Serveri roll operatsioonisüsteemide paigaldamiseks üle võrgu. Pakub PXE-alglaadimist ja tõmmiste hoidlat. Osaliselt aegunud (*deprecated*), vt peatükk 9. | Paigaldatakse DC1-le. |
| PXE (*Preboot Execution Environment*) | Võrgukaardi püsivara standard, mis lubab arvutil käivituda võrgust enne, kui kettal on OS. | WDS-KLIENT käivitub PXE-ga. |
| TFTP (*Trivial File Transfer Protocol*) | Lihtne UDP-põhine failiedastus (port 69), millega PXE klient laeb alglaadimisfaili. | `wdsmgfw.efi` laaditakse TFTP-ga. |
| NBP (*Network Boot Program*) | Esimene fail, mille PXE klient alla laeb ja käivitab. UEFI puhul `boot\x64\wdsmgfw.efi`. | — |
| WinPE (*Windows Preinstallation Environment*) | Väike Windows, mis jookseb mälus ja millest käivitatakse paigaldus või taastetööriistad. | Kohandatud WinPE alglaadimistõmmis. |
| Alglaadimistõmmis (*boot image*) | WinPE tõmmis (`boot.wim`), mille PXE klient mällu laeb. | `WinPE_amd64.wim`. |
| Paigaldustõmmis (*install image*) | Operatsioonisüsteem ise (`install.wim`), mis kettale kirjutatakse. Sisaldab mitut väljaannet (indeksit). | Windows 11 Pro = üks indeks. |
| WIM (*Windows Imaging Format*) | Failipõhine tõmmisvorming; üks WIM-fail võib sisaldada mitut tõmmist. | — |
| Windows ADK | *Assessment and Deployment Kit*: tööriistad (DISM, WSIM, copype) paigaldusmaterjalide loomiseks; WinPE on eraldi lisandmoodul. | Paigaldatakse DC1-le. |
| Vastusfail (*answer file*, `unattend.xml`) | XML-fail, mis vastab paigaldusküsimustele automaatselt. Luuakse WSIM-iga (*Windows System Image Manager*). | `autounattend.xml`. |
| Sysprep | Tööriist, mis eemaldab Windowsi paigalduselt unikaalsed andmed (SID, arvutinimi), et sellest saaks teha üldist tõmmist. | `sysprep /generalize /oobe /shutdown`. |
| UEFI / Secure Boot / TPM | Kaasaegne püsivara (asendab BIOS-i), alglaadimise allkirjakontroll ja krüptokiip. Windows 11 nõuab kõiki kolme. | WDS-KLIENT VM-i seaded. |

### 2.7 Halduse mõisted

| Termin (EN) | Selgitus | Näide laboris |
| --- | --- | --- |
| PowerShell | Objektipõhine käsukest ja skriptikeel, Windows Serveri peamine automatiseerimisvahend. Käsud (*cmdlet*) on kujul *Verb-Nimisõna*. | `Get-Service`, `New-ADUser`. |
| Moodul (*module*) | Seotud käskude komplekt. | `ActiveDirectory`, `DhcpServer`, `DnsServer`. |
| WinRM / PowerShell Remoting | Kaughalduse protokoll (HTTP 5985 / HTTPS 5986), millega PowerShell käivitab käske teistes masinates. Domeenis vaikimisi lubatud. | `Invoke-Command -ComputerName CORE1`. |
| sconfig | Server Core'i tekstipõhine seadistusmenüü (nimi, IP, domeen, uuendused, kaugtöölaud). Server 2022-s PowerShelli põhine. | CORE1 esmane seadistus. |
| RSAT (*Remote Server Administration Tools*) | Haldustööriistad (ADUC, DNS, DHCP, GPMC jt) klientarvutile või serverile. Windows 11-s paigaldatakse *Optional features* alt. | WIN11-01 haldusjaamana. |
| MMC (*Microsoft Management Console*) | Raamistik, milles jooksevad haldustööriistad (*snap-in*). | `dsa.msc`, `dnsmgmt.msc`, `dhcpmgmt.msc`, `gpmc.msc`. |
| Windows Admin Center (WAC) | Brauseripõhine tasuta haldustool serverite ja klientide jaoks. | Paigaldatakse soovi korral WIN11-01-le. |
| Event Viewer (sündmuste vaatur) | Logide vaatamise tööriist: System, Application, Security ja teenuste logid. | `eventvwr.msc`. |
| Teenus (*service*) | Taustal jooksev programm, nt `NTDS`, `DNS`, `DHCPServer`, `WDSServer`. | `Get-Service DHCPServer`. |

---

[← 1. Sissejuhatus ja laborikeskkond](01-sissejuhatus-ja-laborikeskkond.md) · [Sisukord](../README.md) · [3. Windows Server 2022: väljaanded, paigaldus, Desktop Experience vs Server Core →](03-valjaanded-paigaldus-core.md)
