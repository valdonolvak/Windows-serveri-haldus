/**
 * Terminoloogia test -> Google Forms (automaatselt hinnatav quiz)
 * Allikas: "Windows serveri haldus", peatükk 2 (100 terminit).
 *
 * MIDA SEE TEEB
 *   Iga käivitus loob UUE Google Formsi, millesse valitakse terminipangast
 *   juhuslikult KYSIMUSI (vaikimisi 25) terminit juhuslikus jarjekorras.
 *   Iga kusimus: "Millisele terminile vastab selgitus?" + 4 varianti
 *   (1 oige + 3 juhuslikku eksitajat, eelistatult samast teemast), segatud.
 *
 * KUIDAS KASUTADA
 *   1. Ava https://script.google.com -> New project.
 *   2. Kleebi see fail sisse (asenda kogu Code.gs sisu).
 *   3. Vali funktsioon looTerminoloogiaTest -> Run. Esimesel korral kusib
 *      Google loa (Authorize) -> luba.
 *   4. Execution log naitab vormi lingid (muutmine + taitmine).
 *
 * "Igale kasutajale/korrale eraldi 25" kohta vt testid/README.md -
 *   Forms ei vali vastaja kohta ise juhuslikku alamhulka; see skript
 *   teeb selle valiku genereerimisel. Uus juhuslik komplekt = kaivita uuesti.
 */

var KYSIMUSI = 25;              // mitu kusimust igasse vormi
var SEGA_JARJEKORD_VASTAJALE = true;  // Forms segab 25 kusimuse jarjekorda iga vastaja jaoks

var PANK = [
{
"id": 0,
"term": "Server",
"en": "server",
"def": "Arvuti või tarkvara, mis pakub teenust teistele arvutitele (klientidele). „Server“ on roll, mitte riistvara tüüp: ka virtuaalmasin võib olla server.",
"ex": "DC1 pakub DNS-i ja autentimist, CORE1 pakub DHCP-d ja failijagamist.",
"cat": "Üldmõisted"
},
{
"id": 1,
"term": "Klient",
"en": "client",
"def": "Arvuti või programm, mis kasutab serveri teenuseid.",
"ex": "WIN11-01 küsib DHCP-st aadressi ja DC1-lt sisselogimise kinnitust.",
"cat": "Üldmõisted"
},
{
"id": 2,
"term": "Roll",
"en": "server role",
"def": "Serveri põhifunktsioon, mis paigaldatakse Server Manageri või PowerShelliga (nt AD DS, DNS Server, DHCP Server, File and Storage Services, WDS).",
"ex": "Install-WindowsFeature DHCP paigaldab DHCP rolli.",
"cat": "Üldmõisted"
},
{
"id": 3,
"term": "Komponent",
"en": "feature",
"def": "Lisavõimekus, mis toetab rolle või serverit ennast, kuid ei ole iseseisev teenus (nt Windows Server Backup, RSAT, .NET Framework, Failover Clustering).",
"ex": "Install-WindowsFeature Windows-Server-Backup.",
"cat": "Üldmõisted"
},
{
"id": 4,
"term": "Rolliteenus",
"en": "role service",
"def": "Rolli alamosa, mida saab eraldi valida.",
"ex": "Failiteenuste rolli all on File Server, DFS Namespaces, File Server Resource Manager.",
"cat": "Üldmõisted"
},
{
"id": 5,
"term": "Väljaanne",
"en": "edition",
"def": "Litsentsi- ja funktsioonitase: Standard, Datacenter, Datacenter: Azure Edition, Essentials.",
"ex": "Laboris kasutame Standardit.",
"cat": "Üldmõisted"
},
{
"id": 6,
"term": "Paigaldusvalik",
"en": "installation option",
"def": "Kas serveril on graafiline töölaud (Desktop Experience) või ainult käsurida (Server Core). Valik tehakse paigaldamisel; Server 2022 puhul hiljem vahetada ei saa.",
"ex": "DC1 = Desktop Experience, CORE1 = Server Core.",
"cat": "Üldmõisted"
},
{
"id": 7,
"term": "LTSC",
"en": "Long-Term Servicing Channel",
"def": "Uuenduskanal, kus uus versioon ilmub iga 2–3 aasta tagant ja saab 5 aastat põhituge + 5 aastat laiendatud tuge. Windows Server 2022 on LTSC väljalase.",
"ex": "Server 2022 → järgmine LTSC on Server 2025.",
"cat": "Üldmõisted"
},
{
"id": 8,
"term": "Virtuaalmasin",
"en": "virtual machine, VM",
"def": "Tarkvaraliselt emuleeritud arvuti, mis jookseb hüperviisori (nt Proxmox VE (KVM/QEMU), VMware ESXi, Hyper-V) peal.",
"ex": "Kõik viis labori masinat on VM-id.",
"cat": "Üldmõisted"
},
{
"id": 9,
"term": "Tõmmis",
"en": "image",
"def": "Fail, mis sisaldab terve operatsioonisüsteemi või ketta sisu. Windowsis on tõmmisfailid tavaliselt WIM-vormingus.",
"ex": "install.wim, boot.wim, ISO-tõmmisfail.",
"cat": "Üldmõisted"
},
{
"id": 10,
"term": "Kaughaldus",
"en": "remote management",
"def": "Serveri haldamine teisest arvutist võrgu kaudu, ilma serveri konsooli taga istumata.",
"ex": "DC1-st CORE1 haldamine Server Manageri või Enter-PSSession abil.",
"cat": "Üldmõisted"
},
{
"id": 11,
"term": "Kataloogiteenus",
"en": "directory service",
"def": "Keskne andmebaas, kus hoitakse võrgu objekte (kasutajad, arvutid, rühmad) ja nende atribuute ning mis vastab küsimusele „kes sa oled ja mida sa tohid?“.",
"ex": "Active Directory.",
"cat": "Active Directory"
},
{
"id": 12,
"term": "AD DS",
"en": "Active Directory Domain Services",
"def": "Windows Serveri roll, mis teeb serverist domeenikontrolleri ja pakub kataloogiteenust, autentimist (Kerberos/NTLM) ja poliitikate rakendamist.",
"ex": "Paigaldatakse DC1-le ja CORE1-le.",
"cat": "Active Directory"
},
{
"id": 13,
"term": "Domeen",
"en": "domain",
"def": "Halduslik ja turvalisuse piir: ühine kasutajate andmebaas, ühised paroolireeglid, ühine nimi DNS-is.",
"ex": "perenimi.local.",
"cat": "Active Directory"
},
{
"id": 14,
"term": "Domeenikontroller",
"en": "domain controller, DC",
"def": "Server, kus jookseb AD DS ja mis hoiab domeeni andmebaasi koopiat (NTDS.dit) ning kontrollib sisselogimisi.",
"ex": "DC1 ja CORE1. Kaks DC-d = ühe rikke korral domeen töötab edasi.",
"cat": "Active Directory"
},
{
"id": 15,
"term": "Mets",
"en": "forest",
"def": "Kõige kõrgem AD struktuur: ühe või mitme domeeni kogum ühise skeemi ja globaalkataloogiga. Mets on tegelik turvapiir.",
"ex": "Meie mets koosneb ühest domeenist perenimi.local.",
"cat": "Active Directory"
},
{
"id": 16,
"term": "Puu",
"en": "tree",
"def": "Domeenid, millel on järjestikune DNS-nimeruum.",
"ex": "perenimi.local + tartu.perenimi.local.",
"cat": "Active Directory"
},
{
"id": 17,
"term": "Skeem",
"en": "schema",
"def": "Reeglid, mis kirjeldavad, milliseid objektitüüpe (klassid) ja atribuute AD-s olla saab. Üks skeem kogu metsale.",
"ex": "Exchange’i paigaldus laiendab skeemi.",
"cat": "Active Directory"
},
{
"id": 18,
"term": "Organisatsiooniüksus",
"en": "organizational unit, OU",
"def": "Konteiner objektide rühmitamiseks domeeni sees. OU-le saab linkida GPO-sid ja delegeerida haldusõigusi.",
"ex": "OU=Arvutid,OU=Labor,DC=perenimi,DC=local.",
"cat": "Active Directory"
},
{
"id": 19,
"term": "Konteiner",
"en": "container",
"def": "Vaikimisi olemasolev kaust (nt Users, Computers), millele EI saa GPO-d linkida. Seetõttu loome oma OU-d.",
"ex": "Uued domeeni liidetud arvutid satuvad CN=Computers.",
"cat": "Active Directory"
},
{
"id": 20,
"term": "Objekt",
"en": "object",
"def": "Üks kirje AD-s: kasutaja, arvuti, rühm, printer, OU, GPO. Igal objektil on unikaalne GUID ja SID.",
"ex": "Kasutaja mari.maasikas.",
"cat": "Active Directory"
},
{
"id": 21,
"term": "DN",
"en": "distinguished name",
"def": "Objekti täielik „aadress“ AD-s, kirjutatud alt üles.",
"ex": "CN=Mari Maasikas,OU=Kasutajad,OU=Labor,DC=perenimi,DC=local.",
"cat": "Active Directory"
},
{
"id": 22,
"term": "UPN",
"en": "user principal name",
"def": "Kasutaja sisselogimisnimi e-posti kujul.",
"ex": "mari.maasikas@perenimi.local.",
"cat": "Active Directory"
},
{
"id": 23,
"term": "sAMAccountName",
"en": "",
"def": "Vana (pre-Windows 2000) sisselogimisnimi kujul DOMEEN\\kasutaja, kuni 20 märki.",
"ex": "PERENIMI\\mari.maasikas.",
"cat": "Active Directory"
},
{
"id": 24,
"term": "SID",
"en": "security identifier",
"def": "Unikaalne turvaidentifikaator, mille järgi Windows õigusi tegelikult kontrollib. Kasutaja ümbernimetamine SID-i ei muuda.",
"ex": "S-1-5-21-…-1105.",
"cat": "Active Directory"
},
{
"id": 25,
"term": "Turvarühm",
"en": "security group",
"def": "Rühm, mida saab kasutada õiguste andmiseks. Erineb levirühmast (distribution group), mis on ainult e-posti jaoks.",
"ex": "GG_Raamatupidamine.",
"cat": "Active Directory"
},
{
"id": 26,
"term": "Rühma ulatus",
"en": "group scope",
"def": "Määrab, kust rühma liikmed võivad tulla ja kus rühma saab kasutada: Domain Local (õigused ressursile), Global (kasutajad oma domeenist), Universal (kogu metsas).",
"ex": "Vt AGDLP peatükis 8.",
"cat": "Active Directory"
},
{
"id": 27,
"term": "Replikatsioon",
"en": "replication",
"def": "AD muudatuste kopeerimine DC-de vahel, et kõigil oleks sama andmebaas. AD kasutab mitme ülemaga (multi-master) replikatsiooni.",
"ex": "Kasutaja loomine DC1-l jõuab mõne sekundiga CORE1-le.",
"cat": "Active Directory"
},
{
"id": 28,
"term": "Sait",
"en": "site",
"def": "AD-s kirjeldatud füüsiline asukoht (IP-alamvõrgud), mille järgi suunatakse kliendid lähima DC juurde ja ajastatakse replikatsiooni.",
"ex": "Vaikimisi Default-First-Site-Name.",
"cat": "Active Directory"
},
{
"id": 29,
"term": "Globaalkataloog",
"en": "global catalog, GC",
"def": "DC, mis hoiab osalist koopiat kõigi metsa domeenide objektidest ja on vajalik sisselogimiseks (universaalrühmad) ja otsinguks.",
"ex": "Mõlemad meie DC-d on GC-d.",
"cat": "Active Directory"
},
{
"id": 30,
"term": "FSMO rollid",
"en": "Flexible Single Master Operations",
"def": "Viis eriülesannet, mida korraga täidab ainult üks DC: Schema Master, Domain Naming Master (metsa tasandil), RID Master, PDC Emulator, Infrastructure Master (domeeni tasandil).",
"ex": "Esimene DC saab kõik viis. netdom query fsmo.",
"cat": "Active Directory"
},
{
"id": 31,
"term": "PDC Emulator",
"en": "",
"def": "FSMO roll, mis on domeeni ajaallikas, töötleb paroolimuudatusi kiiremini ja on GPO-de vaikimisi muutmiskoht.",
"ex": "DC1.",
"cat": "Active Directory"
},
{
"id": 32,
"term": "Kerberos",
"en": "",
"def": "Vaikimisi autentimisprotokoll domeenis. Kasutaja saab DC-lt „pileti“ (ticket) ja näitab seda teenustele ilma parooli uuesti saatmata. Nõuab, et kellaajad erineksid alla 5 minuti.",
"ex": "Kui kliendi kell on vale, sisselogimine ebaõnnestub.",
"cat": "Active Directory"
},
{
"id": 33,
"term": "Usaldussuhe",
"en": "trust",
"def": "Seos domeenide või metsade vahel, mis lubab ühe domeeni kasutajatel kasutada teise ressursse.",
"ex": "Metsa sees on usaldussuhted automaatsed.",
"cat": "Active Directory"
},
{
"id": 34,
"term": "Funktsionaaltase",
"en": "functional level",
"def": "Määrab, milliseid AD võimalusi saab kasutada ja milliseid vanemaid DC versioone lubatakse. Server 2022-l on kõrgeim tase Windows Server 2016.",
"ex": "Paigaldusel valime 2016 taseme.",
"cat": "Active Directory"
},
{
"id": 35,
"term": "DSRM",
"en": "Directory Services Restore Mode",
"def": "DC erirežiim AD andmebaasi taastamiseks; selle jaoks määratakse eraldi parool.",
"ex": "Parool sisestatakse DC paigaldusel.",
"cat": "Active Directory"
},
{
"id": 36,
"term": "Delegeerimine",
"en": "delegation of control",
"def": "Piiratud haldusõiguste andmine (nt „võib lähtestada paroole OU-s Kasutajad“) ilma Domain Admins rühma lisamata.",
"ex": "Labor 5.",
"cat": "Active Directory"
},
{
"id": 37,
"term": "IP-aadress ja alamvõrgu mask",
"en": "",
"def": "Seadme aadress võrgus ja märge, milline osa aadressist tähistab võrku. /24 = 255.255.255.0.",
"ex": "192.168.10.10/24.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 38,
"term": "Vaikelüüs",
"en": "default gateway",
"def": "Ruuter, kuhu saadetakse liiklus teistesse võrkudesse.",
"ex": "192.168.10.1.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 39,
"term": "DNS",
"en": "Domain Name System",
"def": "Nimelahendus: tõlgib nimed IP-aadressideks ja vastupidi. AD ei tööta ilma DNS-ita, sest kliendid leiavad DC-d DNS-i SRV-kirjete kaudu.",
"ex": "dc1.perenimi.local → 192.168.10.10.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 40,
"term": "Tsoon",
"en": "zone",
"def": "DNS-i nimeruumi osa, mille kirjeid üks server haldab. Forward lookup zone = nimi→IP, reverse lookup zone = IP→nimi.",
"ex": "perenimi.local ja 10.168.192.in-addr.arpa.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 41,
"term": "AD-integreeritud tsoon",
"en": "AD-integrated zone",
"def": "DNS-tsoon, mida hoitakse AD andmebaasis ja replikeeritakse koos AD-ga; lubab turvalisi dünaamilisi uuendusi.",
"ex": "Mõlemad tsoonid.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 42,
"term": "DNS-kirje",
"en": "resource record",
"def": "Üks rida tsoonis. A = nimi→IPv4, AAAA = nimi→IPv6, PTR = IP→nimi, CNAME = varjunimi, MX = meiliserver, SRV = teenuse asukoht, NS = nimeserver, SOA = tsooni põhiandmed.",
"ex": "_ldap._tcp.dc._msdcs.perenimi.local (SRV).",
"cat": "Võrk ja nimelahendus"
},
{
"id": 43,
"term": "FQDN",
"en": "fully qualified domain name",
"def": "Arvuti täielik DNS-nimi.",
"ex": "core1.perenimi.local.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 44,
"term": "Edastaja",
"en": "forwarder",
"def": "Väline DNS-server, kelle poole meie DNS pöördub nimedega, mida ta ise ei tea (nt internet).",
"ex": "1.1.1.1 või kooli DNS.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 45,
"term": "Dünaamiline uuendus",
"en": "dynamic update",
"def": "Kliendid registreerivad ise oma A- ja PTR-kirjed DNS-is.",
"ex": "WIN11-01 ilmub tsooni automaatselt.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 46,
"term": "DHCP",
"en": "Dynamic Host Configuration Protocol",
"def": "Protokoll, mis jagab klientidele automaatselt IP-aadressi, maski, lüüsi, DNS-serverid jm.",
"ex": "CORE1 jagab aadresse.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 47,
"term": "Ulatus (DHCP)",
"en": "scope",
"def": "DHCP aadressivahemik koos seadetega ühe alamvõrgu jaoks.",
"ex": "192.168.10.100–200.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 48,
"term": "Välistus",
"en": "exclusion",
"def": "Aadressid ulatuse sees, mida DHCP ei jaga.",
"ex": "192.168.10.100–110 (printerid).",
"cat": "Võrk ja nimelahendus"
},
{
"id": 49,
"term": "Reserveering",
"en": "reservation",
"def": "Konkreetsele MAC-aadressile alati sama IP.",
"ex": "WIN11-01 saab alati .150.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 50,
"term": "Rent",
"en": "lease",
"def": "Aeg, mille jooksul klient võib aadressi kasutada; poole aja möödudes püüab ta seda pikendada.",
"ex": "Vaikimisi 8 päeva.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 51,
"term": "DHCP valikud",
"en": "options",
"def": "Lisaseaded: 003 ruuter, 006 DNS-serverid, 015 DNS-domeeninimi, 066/067 PXE alglaadimisserver ja -fail.",
"ex": "006 = 192.168.10.10, 192.168.10.11.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 52,
"term": "DORA",
"en": "",
"def": "DHCP neljaastmeline protsess: Discover → Offer → Request → Acknowledge.",
"ex": "Vt skeemi peatükis 6.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 53,
"term": "APIPA",
"en": "",
"def": "Aadress 169.254.x.x, mille Windows endale võtab, kui DHCP ei vasta. Märk, et DHCP ei tööta.",
"ex": "ipconfig näitab 169.254.12.7.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 54,
"term": "Autoriseerimine (DHCP)",
"en": "DHCP authorization",
"def": "Domeenis peab DHCP-server olema AD-s autoriseeritud, muidu ta ei jaga aadresse. Kaitseb „võõraste“ DHCP-serverite eest.",
"ex": "Add-DhcpServerInDC.",
"cat": "Võrk ja nimelahendus"
},
{
"id": 55,
"term": "Rühmapoliitika",
"en": "Group Policy",
"def": "Mehhanism, millega domeen keskselt seadistab arvuteid ja kasutajaid (turva-, töölaua-, tarkvara-, registriseaded).",
"ex": "Paroolireeglid, draivide kaardistamine.",
"cat": "Rühmapoliitika"
},
{
"id": 56,
"term": "GPO",
"en": "Group Policy Object",
"def": "Üks nimeline seadete komplekt. Koosneb kahest osast: GPC (AD-s) ja GPT (failid kaustas SYSVOL).",
"ex": "GPO_Kasutajad_Toolaud.",
"cat": "Rühmapoliitika"
},
{
"id": 57,
"term": "Link",
"en": "GPO link",
"def": "GPO sidumine saidi, domeeni või OU-ga. Ilma lingita GPO ei mõju. Ühe GPO võib linkida mitmesse kohta.",
"ex": "GPO lingitud OU-le Kasutajad.",
"cat": "Rühmapoliitika"
},
{
"id": 58,
"term": "Arvuti- ja kasutajakonfiguratsioon",
"en": "",
"def": "GPO kaks poolt: arvutiseaded rakenduvad arvuti käivitumisel, kasutajaseaded sisselogimisel. Arvutiseaded mõjuvad arvutiobjektidele, kasutajaseaded kasutajaobjektidele – olenevalt sellest, kus objekt AD-s asub.",
"ex": "Klassikaline viga: kasutajaseadega GPO lingitakse arvutite OU-le.",
"cat": "Rühmapoliitika"
},
{
"id": 59,
"term": "Policies vs Preferences",
"en": "",
"def": "Policies on jõustatud ja kasutaja ei saa neid muuta; Preferences on eelistused (nt draivid, otseteed, registrivõtmed), mida kasutaja võib muuta.",
"ex": "Draivi kaardistus = Preference.",
"cat": "Rühmapoliitika"
},
{
"id": 60,
"term": "LSDOU",
"en": "",
"def": "GPO-de rakendamise järjekord: Local → Site → Domain → OU (vanem OU → laps-OU). Hilisem võidab konflikti korral.",
"ex": "Vt skeemi peatükis 7.",
"cat": "Rühmapoliitika"
},
{
"id": 61,
"term": "Pärimise blokeerimine",
"en": "Block Inheritance",
"def": "OU võib keelata ülemate GPO-de pärimise.",
"ex": "Testi-OU.",
"cat": "Rühmapoliitika"
},
{
"id": 62,
"term": "Jõustamine",
"en": "Enforced",
"def": "Lingi omadus, mis sunnib GPO rakenduma ka siis, kui allpool on pärimine blokeeritud või vastupidine seade.",
"ex": "Turvapoliitika domeeni tasemel.",
"cat": "Rühmapoliitika"
},
{
"id": 63,
"term": "Turvafiltreerimine",
"en": "security filtering",
"def": "GPO rakendub ainult neile, kellel on GPO-l õigused Read + Apply group policy.",
"ex": "GPO ainult rühmale GG_IT.",
"cat": "Rühmapoliitika"
},
{
"id": 64,
"term": "WMI-filter",
"en": "",
"def": "GPO rakendub ainult arvutitele, mis vastavad WMI-päringule (nt OS-i versioon).",
"ex": "Ainult Windows 11 arvutitele.",
"cat": "Rühmapoliitika"
},
{
"id": 65,
"term": "Loopback-töötlus",
"en": "loopback processing",
"def": "Kasutajaseaded võetakse arvuti asukoha järgi, mitte kasutaja asukoha järgi. Kasutatakse arvutiklassides ja kioskites.",
"ex": "Arvutiklassi OU.",
"cat": "Rühmapoliitika"
},
{
"id": 66,
"term": "SYSVOL",
"en": "",
"def": "Jagatud kaust igal DC-l (C:\\Windows\\SYSVOL), kus asuvad GPO failid ja sisselogimisskriptid; replikeeritakse DFSR-iga.",
"ex": "\\\\perenimi.local\\SYSVOL.",
"cat": "Rühmapoliitika"
},
{
"id": 67,
"term": "gpupdate / gpresult",
"en": "",
"def": "Käsud poliitikate kohe rakendamiseks ja rakendunud poliitikate kontrollimiseks.",
"ex": "gpupdate /force, gpresult /r.",
"cat": "Rühmapoliitika"
},
{
"id": 68,
"term": "NTFS-õigused",
"en": "",
"def": "Failisüsteemi tasemel õigused (Full control, Modify, Read & execute, List, Read, Write). Kehtivad nii kohapeal kui ka võrgu kaudu.",
"ex": "Kaust F:\\Osakonnad\\Raamatupidamine.",
"cat": "Failiteenused ja õigused"
},
{
"id": 69,
"term": "Jagamisõigused",
"en": "share permissions",
"def": "Võrgujagamise õigused (Full, Change, Read). Kehtivad ainult võrgu kaudu ligipääsul.",
"ex": "Jagamine \\\\core1\\Raamatupidamine.",
"cat": "Failiteenused ja õigused"
},
{
"id": 70,
"term": "Efektiivne õigus",
"en": "effective access",
"def": "Võrgu kaudu kehtib piiravam kahest: jagamisõigus vs NTFS-õigus.",
"ex": "Share = Full, NTFS = Read → tulemus Read.",
"cat": "Failiteenused ja õigused"
},
{
"id": 71,
"term": "ACL / ACE",
"en": "",
"def": "Access Control List on objekti õiguste nimekiri; iga rida on Access Control Entry.",
"ex": "icacls F:\\Osakonnad.",
"cat": "Failiteenused ja õigused"
},
{
"id": 72,
"term": "Pärimine (õigused)",
"en": "inheritance",
"def": "Alamkaustad ja failid saavad õigused ülemkaustalt.",
"ex": "Uus fail pärib kausta õigused.",
"cat": "Failiteenused ja õigused"
},
{
"id": 73,
"term": "Deny",
"en": "",
"def": "Keelav ACE, mis üldjuhul võidab lubava. Kasuta säästlikult.",
"ex": "—",
"cat": "Failiteenused ja õigused"
},
{
"id": 74,
"term": "ABE",
"en": "Access-Based Enumeration",
"def": "Kasutaja ei näe jagamises kaustu, kuhu tal õigust pole.",
"ex": "Sisse lülitatud jagamisel Osakonnad.",
"cat": "Failiteenused ja õigused"
},
{
"id": 75,
"term": "AGDLP",
"en": "",
"def": "Soovitatav õiguste andmise mudel: Account → Global group → Domain Local group → Permission.",
"ex": "Vt peatükki 8.",
"cat": "Failiteenused ja õigused"
},
{
"id": 76,
"term": "UNC-tee",
"en": "",
"def": "Võrguressursi aadress kujul \\\\server\\jagamine\\kaust.",
"ex": "\\\\perenimi.local\\Andmed\\Kasutajad.",
"cat": "Failiteenused ja õigused"
},
{
"id": 77,
"term": "DFS Namespace",
"en": "",
"def": "Virtuaalne kaustapuu, mis peidab tegelikud serverinimed.",
"ex": "\\\\perenimi.local\\Andmed.",
"cat": "Failiteenused ja õigused"
},
{
"id": 78,
"term": "FSRM",
"en": "File Server Resource Manager",
"def": "Failiserveri haldus: kvoodid, failitüüpide blokeerimine, aruanded.",
"ex": "Kasutajakausta kvoot 100 MB (ptk 13).",
"cat": "Failiteenused ja õigused"
},
{
"id": 79,
"term": "WDS",
"en": "Windows Deployment Services",
"def": "Serveri roll operatsioonisüsteemide paigaldamiseks üle võrgu. Pakub PXE-alglaadimist ja tõmmiste hoidlat. Osaliselt aegunud (deprecated).",
"ex": "Paigaldatakse DC1-le.",
"cat": "Paigaldus ja WDS"
},
{
"id": 80,
"term": "PXE",
"en": "Preboot Execution Environment",
"def": "Võrgukaardi püsivara standard, mis lubab arvutil käivituda võrgust enne, kui kettal on OS.",
"ex": "WDS-KLIENT käivitub PXE-ga.",
"cat": "Paigaldus ja WDS"
},
{
"id": 81,
"term": "TFTP",
"en": "Trivial File Transfer Protocol",
"def": "Lihtne UDP-põhine failiedastus (port 69), millega PXE klient laeb alglaadimisfaili.",
"ex": "wdsmgfw.efi laaditakse TFTP-ga.",
"cat": "Paigaldus ja WDS"
},
{
"id": 82,
"term": "NBP",
"en": "Network Boot Program",
"def": "Esimene fail, mille PXE klient alla laeb ja käivitab. UEFI puhul boot\\x64\\wdsmgfw.efi.",
"ex": "—",
"cat": "Paigaldus ja WDS"
},
{
"id": 83,
"term": "WinPE",
"en": "Windows Preinstallation Environment",
"def": "Väike Windows, mis jookseb mälus ja millest käivitatakse paigaldus või taastetööriistad.",
"ex": "Kohandatud WinPE alglaadimistõmmis.",
"cat": "Paigaldus ja WDS"
},
{
"id": 84,
"term": "Alglaadimistõmmis",
"en": "boot image",
"def": "WinPE tõmmis (boot.wim), mille PXE klient mällu laeb.",
"ex": "WinPE_amd64.wim.",
"cat": "Paigaldus ja WDS"
},
{
"id": 85,
"term": "Paigaldustõmmis",
"en": "install image",
"def": "Operatsioonisüsteem ise (install.wim), mis kettale kirjutatakse. Sisaldab mitut väljaannet (indeksit).",
"ex": "Windows 11 Pro = üks indeks.",
"cat": "Paigaldus ja WDS"
},
{
"id": 86,
"term": "WIM",
"en": "Windows Imaging Format",
"def": "Failipõhine tõmmisvorming; üks WIM-fail võib sisaldada mitut tõmmist.",
"ex": "—",
"cat": "Paigaldus ja WDS"
},
{
"id": 87,
"term": "Windows ADK",
"en": "Assessment and Deployment Kit",
"def": "Tööriistad (DISM, WSIM, copype) paigaldusmaterjalide loomiseks; WinPE on eraldi lisandmoodul.",
"ex": "Paigaldatakse DC1-le.",
"cat": "Paigaldus ja WDS"
},
{
"id": 88,
"term": "Vastusfail",
"en": "answer file, unattend.xml",
"def": "XML-fail, mis vastab paigaldusküsimustele automaatselt. Luuakse WSIM-iga (Windows System Image Manager).",
"ex": "autounattend.xml.",
"cat": "Paigaldus ja WDS"
},
{
"id": 89,
"term": "Sysprep",
"en": "",
"def": "Tööriist, mis eemaldab Windowsi paigalduselt unikaalsed andmed (SID, arvutinimi), et sellest saaks teha üldist tõmmist.",
"ex": "sysprep /generalize /oobe /shutdown.",
"cat": "Paigaldus ja WDS"
},
{
"id": 90,
"term": "UEFI / Secure Boot / TPM",
"en": "",
"def": "Kaasaegne püsivara (asendab BIOS-i), alglaadimise allkirjakontroll ja krüptokiip. Windows 11 nõuab kõiki kolme.",
"ex": "WDS-KLIENT VM-i seaded.",
"cat": "Paigaldus ja WDS"
},
{
"id": 91,
"term": "PowerShell",
"en": "",
"def": "Objektipõhine käsukest ja skriptikeel, Windows Serveri peamine automatiseerimisvahend. Käsud (cmdlet) on kujul Verb-Nimisõna.",
"ex": "Get-Service, New-ADUser.",
"cat": "Haldus"
},
{
"id": 92,
"term": "Moodul",
"en": "module",
"def": "Seotud käskude komplekt.",
"ex": "ActiveDirectory, DhcpServer, DnsServer.",
"cat": "Haldus"
},
{
"id": 93,
"term": "WinRM / PowerShell Remoting",
"en": "",
"def": "Kaughalduse protokoll (HTTP 5985 / HTTPS 5986), millega PowerShell käivitab käske teistes masinates. Domeenis vaikimisi lubatud.",
"ex": "Invoke-Command -ComputerName CORE1.",
"cat": "Haldus"
},
{
"id": 94,
"term": "sconfig",
"en": "",
"def": "Server Core’i tekstipõhine seadistusmenüü (nimi, IP, domeen, uuendused, kaugtöölaud). Server 2022-s PowerShelli põhine.",
"ex": "CORE1 esmane seadistus.",
"cat": "Haldus"
},
{
"id": 95,
"term": "RSAT",
"en": "Remote Server Administration Tools",
"def": "Haldustööriistad (ADUC, DNS, DHCP, GPMC jt) klientarvutile või serverile. Windows 11-s paigaldatakse Optional features alt.",
"ex": "WIN11-01 haldusjaamana.",
"cat": "Haldus"
},
{
"id": 96,
"term": "MMC",
"en": "Microsoft Management Console",
"def": "Raamistik, milles jooksevad haldustööriistad (snap-in).",
"ex": "dsa.msc, dnsmgmt.msc, dhcpmgmt.msc, gpmc.msc.",
"cat": "Haldus"
},
{
"id": 97,
"term": "Windows Admin Center",
"en": "WAC",
"def": "Brauseripõhine tasuta haldustool serverite ja klientide jaoks.",
"ex": "Paigaldatakse soovi korral WIN11-01-le.",
"cat": "Haldus"
},
{
"id": 98,
"term": "Event Viewer",
"en": "sündmuste vaatur",
"def": "Logide vaatamise tööriist: System, Application, Security ja teenuste logid.",
"ex": "eventvwr.msc.",
"cat": "Haldus"
},
{
"id": 99,
"term": "Teenus",
"en": "service",
"def": "Taustal jooksev programm, nt NTDS, DNS, DHCPServer, WDSServer.",
"ex": "Get-Service DHCPServer.",
"cat": "Haldus"
}
];

function sega_(a){ a=a.slice(); for(var i=a.length-1;i>0;i--){var j=Math.floor(Math.random()*(i+1)); var x=a[i];a[i]=a[j];a[j]=x;} return a; }
function silt_(t){ return t.term + (t.en ? " (" + t.en + ")" : ""); }
function eksitajad_(oige, mitu){
  var samad = sega_(PANK.filter(function(x){return x.id!==oige.id && x.cat===oige.cat;}));
  var pool = samad.slice(0, mitu);
  if(pool.length < mitu){
    var muud = sega_(PANK.filter(function(x){return x.id!==oige.id && x.cat!==oige.cat;}));
    pool = pool.concat(muud.slice(0, mitu - pool.length));
  }
  return pool;
}

function looTerminoloogiaTest(){
  var valitud = sega_(PANK).slice(0, Math.min(KYSIMUSI, PANK.length));

  var form = FormApp.create("Terminoloogia test - Windows serveri haldus (ptk 2)");
  form.setIsQuiz(true);
  form.setDescription(
    valitud.length + " juhuslikku kusimust peatuki 2 terminitest. " +
    "Vali igale selgitusele oige termin. Iga vormikaivitus loob uue juhusliku komplekti."
  );
  form.setCollectEmail(true);           // kes vastas (voib eemaldada)
  form.setShuffleQuestions(SEGA_JARJEKORD_VASTAJALE);
  form.setProgressBar(true);

  valitud.forEach(function(t, i){
    var item = form.addMultipleChoiceItem();
    var variandid = sega_([t].concat(eksitajad_(t, 3)));
    var choices = variandid.map(function(o){
      return item.createChoice(silt_(o), o.id === t.id);  // oige = o.id === t.id
    });
    var selgitus = t.ex && t.ex !== "\u2014"
      ? "Oige vastuse naide: " + t.ex : "";
    item.setTitle("Millisele terminile vastab jargmine selgitus?\n\n\u00AB" + t.def + "\u00BB")
        .setChoices(choices)
        .setPoints(1)
        .setRequired(true);
    if(selgitus){
      var fbOk = FormApp.createFeedback().setText(selgitus).build();
      item.setFeedbackForCorrect(fbOk);
    }
  });

  Logger.log("VALMIS. Kusimusi: " + valitud.length);
  Logger.log("Muutmine:  " + form.getEditUrl());
  Logger.log("Taitmine:  " + form.getPublishedUrl());
}
