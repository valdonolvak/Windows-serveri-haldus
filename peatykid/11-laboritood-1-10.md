## 11. Laboritööd

Laborid on järjestikused: iga järgmine eeldab eelmise tulemust. Iga labori lõpus on **kontrollpunkt** (mida peab nägema, enne kui edasi minna) ja **küsimused**, millele vasta lühidalt laboripäevikus. Soovitus: tee enne iga laborit kõigist VM-idest hetktõmmis (*snapshot*), et vea korral saaks tagasi minna – v.a domeenikontrollerid pärast Labor 3, vt 10.3.

| Labor | Teema | Masinad | Aeg (ak h) |
| --- | --- | --- | --- |
| 1 | Serverite paigaldus ja esmane seadistus | DC1, CORE1 | 4 |
| 2 | Esimene domeenikontroller ja DNS | DC1 | 3 |
| 3 | Teine DC Server Core'ile, kaughaldus | DC1, CORE1 | 3 |
| 4 | DHCP ja klientide liitmine domeeni | CORE1, WIN11-01, WIN11-02 | 3 |
| 5 | OU-d, kasutajad, rühmad ja delegeerimine | DC1, WIN11-02 | 3 |
| 6 | Rühmapoliitika | DC1, WIN11-01, WIN11-02 | 4 |
| 7 | Failiserver ja õigused (AGDLP) | CORE1, WIN11-02 | 4 |
| 8 | Haldusjaam: RSAT ja PowerShell Remoting | WIN11-01, CORE1 | 2 |
| 9 | WDS ja Windows 11 võrgupaigaldus | DC1, WDS-KLIENT | 6 |
| 10 | Varundus, taastamine, turvaaudit ja tõrkeotsing | kõik | 4 |

Laborid 11–16 (FSRM, DFS, kaustade ümbersuunamine, rakenduste ligipääs, IIS + WordPress, AD CS + HTTPS) asuvad Osa II vastavate peatükkide lõpus.

### Labor 1. Serverite paigaldus ja esmane seadistus

**Eesmärk:** paigaldada Windows Server 2022 kahes variandis ja teha esmane seadistus nii GUI-s kui ka käsurealt.

> **Proxmoxi laboris** on sammud 1–4 (VM-ide loomine ja paigaldus) õpetaja poolt tehtud. Õppija alustab sammust 5 ja kontrollib sammus 4, et VirtIO draiverid ja QEMU guest agent töötavad (`Get-Service QEMU-GA`).

**Sammud:**

1. Loo hüperviisoris virtuaalvõrk `LABOR-LAN` (isoleeritud, **ilma** hüperviisori DHCP-ta).
2. Loo VM `DC1` peatüki 1 tabeli järgi (UEFI, 2 ketast: 60 GB + 40 GB) ja paigalda **Windows Server 2022 Standard (Desktop Experience)**.
3. Loo VM `CORE1` (2 ketast: 60 GB + 20 GB) ja paigalda **Windows Server 2022 Standard** (Server Core).
4. Paigalda mõlemale virtio-win külalistööriistad ja lülita Proxmoxis sisse QEMU Guest Agent.
5. **DC1 (GUI):** *Server Manager → Local Server* kaudu: arvutinimi `DC1`, IP 192.168.10.10/24, lüüs 192.168.10.1, DNS 127.0.0.1, ajavöönd (UTC+02:00) Helsinki, Kyiv, Riga, Sofia, Tallinn, Vilnius. Taaskäivita.
6. **CORE1 (sconfig):** menüü 2 → nimi `CORE1`; menüü 8 → IP 192.168.10.11/24, lüüs 192.168.10.1, DNS 192.168.10.10; menüü 9 → ajavöönd; menüü 7 → luba RDP. Taaskäivita.
7. Mõlemas luba ICMP (ping), vt 3.5.
8. Kontrolli PowerShellis `Get-NetIPConfiguration`, `hostname`, `Get-TimeZone`.
9. Paigalda mõlemale viimased uuendused (GUI: *Settings → Windows Update*; Core: sconfig 6).

**Kontrollpunkt:** `ping 192.168.10.11` DC1-st vastab; mõlema serveri nimi, IP ja ajavöönd on õiged.

**Küsimused:**

1. Mis on Desktop Experience'i ja Server Core'i kolm peamist erinevust? Miks soovitatakse taristurollidele Core'i?
2. Miks muudetakse arvutinimi enne domeeni liitmist?
3. Kui palju kettaruumi kasutab kumbki paigaldus kohe pärast paigaldust? (`Get-Volume`)

### Labor 2. Esimene domeenikontroller ja DNS

**Eesmärk:** luua uus mets `perenimi.local`, seadistada DNS ja kontrollida domeeni tervist.

**Sammud:**

1. DC1-l: *Server Manager → Manage → Add Roles and Features* → *Role-based* → vali **Active Directory Domain Services** (koos haldustööriistadega) ja **DNS Server**.
2. Pärast paigaldust klõpsa lipukesel → *Promote this server to a domain controller*.
3. *Add a new forest*, *Root domain name*: `perenimi.local`.
4. Funktsionaaltasemed: *Windows Server 2016*. Linnukesed: *DNS server*, *Global Catalog*. Sisesta DSRM parool ja kirjuta see laboripäevikusse.
5. DNS delegeerimise hoiatus (*A delegation for this DNS server cannot be created...*) on laboris ootuslik – jätka.
6. NetBIOS nimi: `PERENIMI`. Teed (NTDS, SYSVOL) jäta vaikimisi.
7. Vaata *Review Options* lehel nuppu **View script** – salvesta PowerShelli skript laboripäevikusse.
8. *Prerequisites Check* → *Install*. Server taaskäivitub. Logi sisse kui `PERENIMI\Administrator`.
9. Ava `dnsmgmt.msc`: vaata tsooni `perenimi.local` ja `_msdcs.perenimi.local` kirjeid (`_ldap`, `_kerberos` SRV-kirjed).
10. Loo pöördtsoon 192.168.10.0/24 (*Reverse Lookup Zones → New Zone → Primary, AD-integrated, IPv4, 192.168.10, Allow only secure dynamic updates*).
11. Loo DC1 jaoks PTR-kirje: ava DC1 A-kirje omadused ja märgi *Update associated pointer (PTR) record* või käivita `ipconfig /registerdns`.
12. Kui laboris on internet, lisa edastajad (*DC1 Properties → Forwarders*).
13. Lülita sisse AD prügikast (vt 10.3).

**Kontrollpunkt:**

```powershell
Get-ADDomain | Select-Object DNSRoot, NetBIOSName, DomainMode
nslookup dc1.perenimi.local          # vastus 192.168.10.10 ja server "dc1.perenimi.local" (mitte "Unknown")
nslookup -type=SRV _ldap._tcp.dc._msdcs.perenimi.local
dcdiag /q                         # /q = näita ainult vigu; tühi väljund = korras
```

**Küsimused:**

1. Milliseid SRV-kirjeid DC registreeris ja milleks klient neid vajab?
2. Miks näitas `nslookup` enne pöördtsooni loomist serveri nimena „Unknown“?
3. Mis vahe on `perenimi.local` ja `_msdcs.perenimi.local` tsooni replikatsiooniulatusel?
4. Kus asub AD andmebaasi fail ja kuidas nimetatakse kausta, mida jagatakse kõigi DC-de vahel?

### Labor 3. Teine domeenikontroller Server Core'ile ja kaughaldus

**Eesmärk:** muuta CORE1 teiseks domeenikontrolleriks, hallata seda kaugelt ja kontrollida replikatsiooni.

**Sammud:**

1. CORE1-l veendu, et DNS osutab DC1-le (192.168.10.10): `Get-DnsClientServerAddress`.
2. Liida CORE1 domeeni: sconfig → 1 → *D* → `perenimi.local` → `PERENIMI\Administrator` → taaskäivita, või `Add-Computer -DomainName perenimi.local -Restart`.
3. DC1-l: *Server Manager → Manage → Add Servers → Find Now* → lisa CORE1. Vaata, et olek on *Online*.
4. Paigalda CORE1-le AD DS roll **DC1 Server Managerist**: *Add Roles and Features* → vali sihtserveriks CORE1 → *Active Directory Domain Services*.
5. Ülenda CORE1 DC1 Server Managerist (lipuke → *Promote*) või CORE1 käsurealt (vt 5.3): *Add a domain controller to an existing domain*, DNS ja GC sees, *Replicate from: dc1.perenimi.local*.
6. Pärast taaskäivitust seadista DNS-id ristiti (tabel 5.4):

```powershell
# CORE1-l
Set-DnsClientServerAddress -InterfaceAlias Ethernet0 -ServerAddresses 192.168.10.10,127.0.0.1
# DC1-l
Set-DnsClientServerAddress -InterfaceAlias Ethernet0 -ServerAddresses 192.168.10.11,127.0.0.1
```

7. Luba CORE1-l MMC kaughalduse tulemüüri reeglid (4.2).
8. Ava DC1-l `compmgmt.msc` → *Connect to another computer* → CORE1. Vaata teenuseid ja sündmusi.
9. Testi PowerShell Remotingut: `Enter-PSSession CORE1`, seejärel `Get-Service NTDS, DNS, Netlogon`, `exit`.
10. **Replikatsioonikatse:** loo DC1-l ADUC-s kasutaja `test.replikatsioon`. Kontrolli CORE1-l: `Get-ADUser test.replikatsioon -Server core1`. Kustuta kasutaja CORE1-lt ja kontrolli, et see kaob ka DC1-lt.

**Kontrollpunkt:**

```powershell
Get-ADDomainController -Filter * | Select-Object Name, IPv4Address, IsGlobalCatalog, OperatingSystem
repadmin /replsummary        # 0 viga
netdom query fsmo            # kõik 5 rolli DC1-l
```

**Küsimused:**

1. Miks peab CORE1 DNS osutama enne ülendamist DC1-le?
2. Mis juhtub sisselogimisega, kui DC1 välja lülitada? Proovi WIN11 kliendiga pärast Labor 4.
3. Milliste FSMO rollide kadumist märkaks kasutaja esimesena ja miks?
4. Mis on multi-master replikatsioon ja mis vahe on sellel FSMO rollidega?

### Labor 4. DHCP ja klientide liitmine domeeni

**Eesmärk:** paigaldada DHCP Server Core'ile kaugelt, seadistada ulatus ja liita Windows 11 kliendid domeeni.

**Sammud:**

1. Paigalda DHCP roll CORE1-le (DC1 Server Manager → sihtserver CORE1 → *DHCP Server*) või PowerShelli kaudu (vt 6.3).
2. *Complete DHCP configuration* viisard: autoriseeri server AD-s.
3. Ava DC1-l `dhcpmgmt.msc` → *Add Server* → `core1.perenimi.local`.
4. Loo ulatus `Labor-LAN` tabeli 6.2 järgi (vahemik, välistus, rendiaeg, valikud 003, 006, 015). Aktiveeri ulatus.
5. Loo VM-id WIN11-01 ja WIN11-02 (UEFI, Secure Boot, vTPM) ja paigalda Windows 11 Pro ISO-st. OOBE ajal vali *Set up for work or school → Sign-in options → Domain join instead* ja loo kohalik konto `kohalik`.
6. Klientidel: `ipconfig /all` – kontrolli IP-aadressi, DNS-servereid, *DHCP Server* = 192.168.10.11, *Connection-specific DNS Suffix* = `perenimi.local`.
7. Muuda arvutinimed (`WIN11-01`, `WIN11-02`) ja liida domeeni (`sysdm.cpl` või `Add-Computer`).
8. Logi WIN11-01-sse sisse kontoga `PERENIMI\Administrator`.
9. Loo WIN11-01 jaoks reserveering 192.168.10.150 (MAC leiad DHCP konsoolis *Address Leases* alt). Kliendil `ipconfig /release` ja `ipconfig /renew`.
10. Vaata DNS-is, kas klientide A- ja PTR-kirjed tekkisid automaatselt.

**Kontrollpunkt:** WIN11-01 aadress on 192.168.10.150, WIN11-02 aadress vahemikus .110–.200; mõlemad on ADUC-s näha (konteineris `Computers`); `nltest /dsgetdc:perenimi.local` kliendil tagastab DC.

**Küsimused:**

1. Kirjelda DORA protsessi ja millal klient rendi pikendamist alustab.
2. Miks ei tohi kliendi DNS-serveriks olla 8.8.8.8?
3. Mis juhtub, kui DHCP-server ei ole autoriseeritud?
4. **Katse:** peata CORE1-l teenus `DHCPServer`, kliendil `ipconfig /release` ja `/renew`. Mis aadressi klient sai? Käivita teenus uuesti.
5. **Boonus:** paigalda DC1-le DHCP ja seadista *DHCP failover* (Load balance 50/50) CORE1-ga. Mida tuleb siis WDS-i jaoks muuta (vt 9.3)?

### Labor 5. OU-d, kasutajad, rühmad ja delegeerimine

**Eesmärk:** kavandada ja luua AD struktuur, luua kasutajad massiliselt ning delegeerida piiratud haldusõigused.

**Sammud:**

1. Loo OU-struktuur (5.5 skript või ADUC-s). Linnuke *Protect container from accidental deletion* jääb sisse.
2. Suuna uued arvutid OU-sse `Arvutid`: `redircmp "OU=Arvutid,OU=Labor,DC=perenimi,DC=local"`. Teisalda WIN11-01 ja WIN11-02 OU-sse `Arvutid`, CORE1 jääb OU-sse `Domain Controllers`.
3. Loo fail `C:\Labor\kasutajad.csv`:

```csv
Eesnimi,Perenimi,Osakond
Mari,Maasikas,Raamatupidamine
Juhan,Juurikas,Raamatupidamine
Kati,Karu,IT
Peeter,Paju,IT
Liis,Lepp,Myyk
```

4. Impordi kasutajad skriptiga:

```powershell
$ou = "OU=Kasutajad,OU=Labor,DC=perenimi,DC=local"
$algparool = Read-Host -AsSecureString "Algparool"
Import-Csv C:\Labor\kasutajad.csv | ForEach-Object {
  $sam = ("{0}.{1}" -f $_.Eesnimi, $_.Perenimi).ToLower()
  New-ADUser -Name "$($_.Eesnimi) $($_.Perenimi)" -GivenName $_.Eesnimi -Surname $_.Perenimi `
    -SamAccountName $sam -UserPrincipalName "$sam@perenimi.local" -Department $_.Osakond `
    -Path $ou -AccountPassword $algparool -ChangePasswordAtLogon $true -Enabled $true
}
```

5. Loo rühmad OU-sse `Ryhmad`: globaalrühmad `GG_Raamatupidamine`, `GG_IT`, `GG_Myyk` ja domeenilokaalrühmad `DL_Raamatupidamine_RW`, `DL_Raamatupidamine_R`, `DL_IT_RW`.
6. Lisa kasutajad osakonna järgi globaalrühmadesse automaatselt:

```powershell
Get-ADUser -Filter * -SearchBase $ou -Properties Department | ForEach-Object {
  Add-ADGroupMember -Identity "GG_$($_.Department)" -Members $_
}
```

7. Pane globaalrühmad domeenilokaalrühmadesse (AGDLP): `GG_Raamatupidamine` → `DL_Raamatupidamine_RW`; `GG_Myyk` → `DL_Raamatupidamine_R`; `GG_IT` → `DL_IT_RW`.
8. **Delegeerimine:** ADUC-s paremklikk OU `Kasutajad` → *Delegate Control* → lisa `GG_IT` → *Reset user passwords and force password change at next logon*.
9. Logi WIN11-02-sse sisse kui `kati.karu` (muuda parool). Paigalda RSAT AD tööriistad (või kasuta `Set-ADAccountPassword` DC1-l `runas`-iga) ja proovi lähtestada kasutaja `liis.lepp` parooli – peab õnnestuma. Proovi kustutada kasutajat – peab ebaõnnestuma.
10. Loo administraatorikonto `adm-kati.karu` ja lisa see rühma `Domain Admins`.

**Kontrollpunkt:** `Get-ADGroupMember DL_Raamatupidamine_RW -Recursive` näitab Marit ja Juhanit; Kati saab paroole lähtestada, kuid ei saa kasutajaid kustutada.

**Küsimused:**

1. Miks ei anta õigusi otse kasutajatele? Selgita AGDLP kasu näitega.
2. Mis vahe on konteineril `Users` ja OU-l?
3. Milleks on vaja eraldi `adm-` kontot, kui Kati on niikuinii IT-s?
4. Kus ADUC-s näeb delegeeritud õigusi? (Vihje: *View → Advanced Features* → OU → *Security*.)

### Labor 6. Rühmapoliitika

**Eesmärk:** luua, linkida ja testida GPO-sid ning mõista rakendamise järjekorda.

**Sammud:**

1. Ava DC1-l `gpmc.msc`. Uuri *Default Domain Policy* seadeid (*Settings* vahekaart).
2. Muuda *Default Domain Policy*-s paroolipoliitikat: minimaalne pikkus 12, konto lukustus 10 katset / 15 min.
3. Loo ja lingi OU-le `Kasutajad` GPO `U_Piirangud`: keela juhtpaneel ja *Settings* (*Prohibit access to Control Panel and PC settings*), keela käsurida (*Prevent access to the command prompt*, skriptid lubatud).
4. Loo GPO `U_Taust`: kopeeri pilt `\\perenimi.local\NETLOGON\taust.jpg` ja määra see töölaua taustaks.
5. Loo ja lingi OU-le `Arvutid` GPO `C_KohalikudAdminid`: lisa *Preferences* abil rühm `PERENIMI\GG_IT` arvutite kohalikku *Administrators* rühma (*Action: Update*).
6. WIN11-02-l: logi sisse kui `liis.lepp`, käivita `gpupdate /force`, logi välja ja sisse. Kontrolli, et juhtpaneel on keelatud ja taust muutunud.
7. Uuri tulemust: `gpresult /r` ja `gpresult /h C:\Users\Public\gp.html` (ava brauseris).
8. **Turvafiltreerimine:** `U_Piirangud` ei tohi mõjuda IT-le. GPO → *Delegation* → *Advanced* → lisa `GG_IT` → *Apply group policy*: **Deny**. Logi sisse kui `kati.karu` ja kontrolli, et juhtpaneel on lubatud. (Alternatiiv ilma Deny-ta: eemalda *Authenticated Users* filtrist ja lisa sinna ainult tavakasutajate rühm.)
9. **Järjekorra katse:** loo domeeni tasemel GPO `Test_Taust_Domeen` teise taustapildiga. Kumb taust rakendub Liisile? Seejärel märgi domeeni lingil *Enforced*. Mis muutus? Kustuta testi-GPO.
10. Varunda kõik GPO-d: `Backup-GPO -All -Path C:\GPO-varukoopia`.

**Kontrollpunkt:** `gpresult /r /scope user` Liisi seansis näitab `U_Piirangud` ja `U_Taust`; Kati seansis on `U_Piirangud` *Denied (Security)* all; `net localgroup administrators` WIN11-01-l sisaldab `PERENIMI\GG_IT`.

**Küsimused:**

1. Miks paroolipoliitikat ei saa OU tasemel kasutajatele määrata? Mis on alternatiiv?
2. Selgita LSDOU järjekorda oma katse tulemuse põhjal.
3. Mis vahe on *Policies* ja *Preferences* osal?
4. Kasutaja on OU-s `Kasutajad`, arvuti OU-s `Arvutid`. GPO kasutajaseadetega on lingitud OU-le `Arvutid`. Kas seade mõjub? Millal mõjuks?

### Labor 7. Failiserver ja õigused (AGDLP)

**Eesmärk:** seadistada CORE1 failiserveriks, rakendada AGDLP-põhiseid õigusi, kodukaustu ja kvoote.

**Sammud:**

1. Lisa CORE1-le 40 GB ketas ja `initsialiseeri see F: kettaks (peatükk 3.6`). Paigalda `FS-FileServer`.
2. Loo kaustad: `F:\Osakonnad\Raamatupidamine`, `F:\Osakonnad\IT`, `F:\Yldine`.
3. Loo jagamised `Osakonnad` (ABE-ga) ja `Yldine`. Jagamisõigused: *Authenticated Users – Change*, *Domain Admins – Full*.
4. Määra NTFS-õigused `icacls`-iga või DC1-st Exploreris (`\\core1\f$\Osakonnad` → *Properties → Security*). Kausta `F:\Osakonnad` juurel eemalda päritud *Users* õigused ja anna *Authenticated Users*-ile ainult *Read & execute – This folder only*.
5. Lülita `F:` köitel sisse varjukoopiad: `vssadmin add shadowstorage /for=F: /on=F: /maxsize=10%` ja `vssadmin create shadow /for=F:` (või DC1-st `compmgmt.msc` → CORE1 → *Shared Folders* → *Configure Shadow Copies*).
6. Testi WIN11-02-l:
   - `mari.maasikas`: saab kirjutada kausta Raamatupidamine, ei näe kausta IT (ABE).
   - `liis.lepp`: saab lugeda Raamatupidamist, ei saa kirjutada.
   - `kati.karu`: näeb ainult IT kausta.
7. Kustuta Mari kaustast fail ja taasta see *Previous Versions* kaudu.
8. Kontrolli efektiivseid õigusi: kausta *Properties → Security → Advanced → Effective Access* → vali `liis.lepp`.
9. Isiklikud kaustad, kvoodid ja failiekraanid tehakse Osa II laborites 11 ja 13.

**Kontrollpunkt:** kõik punkti 8 testid vastavad oodatule; `Get-SmbShare` CORE1-l näitab kahte jagamist.

**Küsimused:**

1. Jagamisõigus on *Read*, NTFS-õigus *Modify*. Mida kasutaja võrgust teha saab? Aga kohapeal?
2. Miks antakse `F:\Osakonnad` juurel *Authenticated Users*-ile ainult *Read & execute – This folder only*?
3. Kas `$` jagamise nime lõpus on turvameede? Põhjenda.
4. Miks ei asenda varjukoopiad varundust?

### Labor 8. Haldusjaam: RSAT ja PowerShell Remoting

**Eesmärk:** hallata kogu domeeni Windows 11 tööjaamast ilma serverisse sisse logimata.

**Sammud:**

1. Logi WIN11-01-sse sisse kui `PERENIMI\adm-kati.karu`.
2. Paigalda RSAT tööriistad (4.3).
3. Ava *Server Manager* WIN11-01-l, lisa DC1 ja CORE1. Vaata mõlema rolle ja sündmusi.
4. Ava WIN11-01-l `dsa.msc`, `dnsmgmt.msc`, `dhcpmgmt.msc`, `gpmc.msc` ja veendu, et kõik töötavad.
5. Käivita käsk mitmes serveris korraga:

```powershell
Invoke-Command -ComputerName DC1, CORE1 -ScriptBlock {
  [pscustomobject]@{
    Server   = $env:COMPUTERNAME
    Uptime   = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    VabaC_GB = [math]::Round((Get-Volume C).SizeRemaining / 1GB, 1)
    Teenused = (Get-Service NTDS, DNS, Netlogon | Where-Object Status -ne 'Running').Name -join ','
  }
} | Format-Table Server, Uptime, VabaC_GB, Teenused
```

6. Kirjuta skript `C:\Labor\raport.ps1`, mis koostab HTML-aruande: domeeni kasutajate arv, keelatud kontod, 30 päeva jooksul mitte sisse loginud kasutajad, DHCP ulatuse kasutus (`Get-DhcpServerv4ScopeStatistics -ComputerName core1`). Vihje: `ConvertTo-Html`.
7. *(Valikuline)* Paigalda Windows Admin Center WIN11-01-le ja lisa CORE1. Võrdle kogemust MMC tööriistadega.

**Kontrollpunkt:** punkt 5 väljastab mõlema serveri rea; HTML-aruanne avaneb brauseris.

**Küsimused:**

1. Milliseid porte ja protokolle kasutab PowerShell Remoting?
2. Miks on parem hallata servereid tööjaamast kui RDP-ga serverisse sisse logides?
3. Mis vahe on `Enter-PSSession` ja `Invoke-Command` kasutusel?

### Labor 9. WDS ja Windows 11 võrgupaigaldus

**Eesmärk:** paigaldada Windows 11 tühjale arvutile üle võrgu, kasutades WDS-i PXE-alglaadimiseks ja kohandatud WinPE tõmmist.

**Ettevalmistus:**

1. DC1 teisel kettal loo köide `E:` (NTFS, nimi `Deploy`).
2. Laadi alla ja paigalda DC1-le **Windows ADK** (komponent *Deployment Tools*) ja **Windows PE add-on for the ADK**.
3. Loo AD-s teenusekontod: `svc-deploy` (ainult jagamise lugemiseks) ja `svc-join` (arvutite domeeni liitmiseks). Delegeeri `svc-join`-ile OU-s `Arvutid` õigus *Create, delete, and manage computer accounts* (Delegate Control → *Create a custom task* → *Computer objects* → *Create selected objects*, *Full control*).

**Sammud:**

1. Paigalda WDS roll ja tee esmaseadistus (9.4).
2. Kopeeri Windows 11 ISO-tõmmisfaili sisu kausta `E:\Win11` ja jaga: `New-SmbShare -Name 'Win11$' -Path E:\Win11 -ReadAccess 'PERENIMI\svc-deploy','PERENIMI\Domain Admins'`.
3. Tee kohandatud WinPE (9.5): `copype`, haagi, muuda `startnet.cmd`, eemalda haakimine `/Commit`-iga.
4. Lisa WinPE alglaadimistõmmisena WDS-i (*Boot Images → Add Boot Image*).
5. Loo WSIM-is vastusfail või kasuta allolevat näidist; salvesta `E:\Win11\autounattend.xml`. Asenda paroolid.
6. Loo VM `WDS-KLIENT`: Windows 11 tüüp, UEFI, Secure Boot, vTPM, 4 GB RAM, 64 GB ketas, võrk `LABOR-LAN`, **ilma** ISO-ta. *Proxmoxis: BIOS OVMF, TPM State v2.0, Options → Boot Order: net0 esimesena*.
7. Käivita VM, vajuta **F12** ja vali alglaadimistõmmis „Win11 WinPE“.
8. Sisesta `svc-deploy` parool, kui `net use` seda küsib. Jälgi paigaldust.
9. Pärast paigaldust kontrolli ADUC-s: uus arvutiobjekt on OU-s `Arvutid`. Logi sisse domeenikontoga.
10. Vaata WDS-i logisid: *Event Viewer → Applications and Services Logs → Microsoft → Windows → Deployment-Services-Diagnostics*.

Minimaalne vastusfail (Windows 11 Pro, UEFI/GPT, domeeni liitmine):

```xml
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage><UILanguage>en-US</UILanguage></SetupUILanguage>
      <InputLocale>0425:00000425</InputLocale>
      <SystemLocale>et-EE</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>et-EE</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>260</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>FAT32</Format><Label>System</Label></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>3</Order><PartitionID>3</PartitionID><Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter></ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData wcm:action="add"><Key>/IMAGE/NAME</Key><Value>Windows 11 Pro</Value></MetaData>
          </InstallFrom>
          <InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>
        </OSImage>
      </ImageInstall>
      <UserData>
        <AcceptEula>true</AcceptEula>
        <ProductKey><Key>VK7JG-NPHTM-C97JM-9MPGT-3V66T</Key></ProductKey>
      </UserData>
    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComputerName>WIN11-03</ComputerName>
      <TimeZone>FLE Standard Time</TimeZone>
    </component>
    <component name="Microsoft-Windows-UnattendedJoin" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <Identification>
        <Credentials>
          <Domain>perenimi.local</Domain>
          <Username>svc-join</Username>
          <Password>ASENDA_PAROOL</Password>
        </Credentials>
        <JoinDomain>perenimi.local</JoinDomain>
        <MachineObjectOU>OU=Arvutid,OU=Labor,DC=perenimi,DC=local</MachineObjectOU>
      </Identification>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>kohalik</Name>
            <Group>Administrators</Group>
            <Password><Value>ASENDA_PAROOL</Value><PlainText>true</PlainText></Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
    </component>
  </settings>
</unattend>
```

Vastusfaili märkused: `VK7JG-...` on Microsofti avalik Windows 11 Pro üldvõti, mis ainult valib väljaande ega aktiveeri Windowsi. `/IMAGE/NAME` väärtus peab vastama täpselt `install.wim`-is olevale nimele: `dism /Get-WimInfo /WimFile:E:\Win11\sources\install.wim`. Kui meedias on `install.esd`, kasuta seda faili. Paroolid on vastusfailis loetaval kujul – seetõttu ainult piiratud õigustega kontod. WSIM-is saab paroolid peita (*Hide Sensitive Data*), kuid see on ainult kodeering, mitte krüpteering.

**Kontrollpunkt:** WDS-KLIENT käivitub võrgust, Windows 11 paigaldub ilma küsimusteta (v.a `net use` parool), arvuti `WIN11-03` on domeenis OU-s `Arvutid` ja saab GPO-d.

**Küsimused:**

1. Kirjelda PXE-alglaadimise samme alates sisselülitamisest kuni WinPE käivitumiseni. Millised protokollid ja pordid on kasutusel?
2. Miks ei saa Windows 11 puhul kasutada paigaldusmeedia `boot.wim`-i WDS-i alglaadimistõmmisena?
3. Mis on CVE-2026-0386 ja miks keelati WDS-i *hands-free* paigaldus vaikimisi?
4. Mida peaks muutma, kui DHCP asuks samuti DC1-l?
5. Milliseid tööriistu soovitatakse tootmises WDS-i asemel ja miks?

### Labor 10. Varundus, taastamine, turvaaudit ja tõrkeotsing

**Eesmärk:** harjutada AD taastamist, hinnata domeeni turvalisust ja lahendada tahtlikult tekitatud tõrkeid.

**A osa – varundus ja taastamine:**

1. Paigalda CORE1-le `Windows-Server-Backup` ja tee System State varundus: varunduse sihtkohaks jagatud kaust või eraldi ketas.
2. **AD prügikast:** kustuta kasutaja `juhan.juurikas` ja taasta see:

```powershell
Get-ADObject -Filter 'isDeleted -eq $true -and samAccountName -eq "juhan.juurikas"' -IncludeDeletedObjects |
  Restore-ADObject
Get-ADUser juhan.juurikas -Properties MemberOf | Select-Object -ExpandProperty MemberOf
```

3. Kontrolli, et Juhani rühmaliikmesused taastusid. Mida see ütleb prügikasti kohta võrreldes taastamisega varundusest?
4. Varunda kõik GPO-d, muuda `U_Piirangud` GPO-d ja taasta see varundusest: `Restore-GPO -Name U_Piirangud -Path C:\GPO-varukoopia`.

**B osa – turvaaudit:**

1. Käivita 10.4 kiirkontrolli käsud ja dokumenteeri tulemused.
2. Juuruta **Windows LAPS** kliendiarvutitele: `Update-LapsADSchema`, `Set-LapsADComputerSelfPermission -Identity "OU=Arvutid,OU=Labor,DC=perenimi,DC=local"`, GPO *Computer → Admin Templates → System → LAPS*: *Configure password backup directory = Active Directory*. Kliendil `gpupdate /force`, DC1-l `Get-LapsADPassword WIN11-01 -AsPlainText`.
3. Lisa `adm-kati.karu` rühma *Protected Users*. Mida see muudab?
4. *(Valikuline)* Käivita PingCastle või Purple Knight ja vali raportist kolm kõige olulisemat leidu koos parandusplaaniga.

**C osa – tõrkeotsing:** õpetaja (või paariline) tekitab ühe tõrke korraga; õppija leiab põhjuse, parandab ja kirjeldab diagnoosi käike.

| Nr | Tõrke tekitamine (õpetajale) | Sümptom õppijale |
| --- | --- | --- |
| 1 | WIN11-02 DNS-serveriks seatakse 8.8.8.8 | Domeenikasutaja ei saa sisse logida, „The trust relationship...“ või „No logon servers“ |
| 2 | DHCP ulatus deaktiveeritakse | Uus klient saab 169.254.x.x aadressi |
| 3 | WIN11-01 kell nihutatakse 15 min edasi | Ligipääs jagamistele ebaõnnestub, Kerberose vead |
| 4 | GPO `U_Taust` link keelatakse (*Link Enabled* maha) | Taust ei muutu |
| 5 | `DL_Raamatupidamine_RW`-st eemaldatakse `GG_Raamatupidamine` | Mari ei saa enam kaustas kirjutada |
| 6 | `WDSServer` teenus peatatakse | PXE-E53 / *No boot filename received* |
| 7 | CORE1 tulemüüris blokeeritakse port 5985 | `Enter-PSSession CORE1` ebaõnnestub |

**Tõrkeotsingu metoodika** (kirjuta iga tõrke kohta laboripäevikusse):

1. **Kirjelda sümptom** täpselt: mis ei tööta, kellel, millest alates, milline on veateade.
2. **Määra ulatus:** kas probleem on ühel kasutajal/arvutil või kõigil?
3. **Kontrolli kihtide kaupa alt üles:** füüsiline/virtuaalvõrk → IP (`ipconfig /all`) → nimelahendus (`nslookup`, `Resolve-DnsName`) → ühendus (`Test-NetConnection -Port`) → teenus (`Get-Service`) → autentimine/õigused → rakendus.
4. **Vaata logisid** (Event Viewer) ja võrdle töötava süsteemiga.
5. **Muuda üht asja korraga** ja testi uuesti.
6. **Dokumenteeri** põhjus, lahendus ja kuidas korduvat probleemi vältida.

**Kontrollpunkt:** kõik seitse tõrget on lahendatud ja igaühe diagnoosikäik on dokumenteeritud.

**Küsimused:**

1. Mis vahe on autoriteetsel ja mitteautoriteetsel AD taastamisel? Millal kumbagi kasutada?
2. Milliseid ründeid aitab vältida Windows LAPS?
3. Milline seitsmest tõrkest oli kõige raskem leida ja miks?

---

[← 10. Uuendused, monitooring, varundus ja turvalisus](10-uuendused-monitooring-varundus-turvalisus.md) · [Sisukord](../README.md) · [12. Enesekontroll, tõrkeotsing ja käskude spikker →](12-enesekontroll-ja-spikker.md)
