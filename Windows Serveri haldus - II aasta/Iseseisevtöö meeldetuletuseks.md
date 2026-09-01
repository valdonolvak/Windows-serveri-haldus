

# MEELDETULETUSEKS: Windows operatsioonisüsteemide haldus

### ⚠️ ETTEVALMISTUS JA LITSENTS

Windowsi prooviversioonid sulgevad end automaatselt iga tunni järel, kui litsentsi aeg on läbi.
**Kriitiline samm:** Kohe pärast masina nime ja võrguseadete muutmist ava **PowerShell** administraatori õigustes ja sisesta käsk:
`slmgr -rearm`
Pärast käsu kinnitamist tee masinale **Restart**.

---

### 1. Keskkond ja ligipääs

* **Aadress (sisevõrgus):** [https://193.40.178.155:8006/](https://193.40.178.155:8006/)
* **Aadress (väljast):** [https://193.40.178.155:8006/](https://193.40.178.155:8006/)
* **Realm:** `hkhk.edu.ee` | **Kasutaja:** eesnime esitäht + perekonnanimi
* **Info:** Töö ajal on lubatud kasutada internetis leiduvaid materjale ja juhendeid.

### 2. Virtuaalmasinad ja võrguseadistus (VNET)

Võrguaadress moodustub valemiga **192.168.XXX.0/24**, kus **XXX** on sinu virtuaalmasina võrguseadme **vnet** number.

> **Näide:** Kui vnet = 50, siis võrguaadress on **192.168.50.0/24**.

| Masina nimi Proxmoxis | Masina nimi süsteemis | IP-aadress | Roll |
| --- | --- | --- | --- |
| win-it25-NIMI-winserver2022-2605-1 | AD1 | `192.168.XXX.10` | DC, DNS, DHCP, IIS |
| win-it25-NIMI-winserver2022core-2605-1 | AD2 | `192.168.XXX.11` | Secondary DC, DHCP Failover |
| win-it25-NIMI-winklientwds-1 | Arvuti1 | DHCP | Klient (Win 11 / WDS) |
| win-it25-NIMI-win11ent2605-1 | Arvuti2 | DHCP | Klient (Win 11) |
| win-it25-NIMI-win11ent2605-2 | Arvuti3 | DHCP | Klient (Win 11) |

*Märkus: **NIMI** tähistab Proxmoxi masinate nimedes õpilase kasutajanime.*

* **Administraatori parool:** `Passw0rd`
* **Domeeni loodavate kasutajate parooliks tuleb panna:** `Par00LA!`

---

## TEHTAVAD TÖÖD

1. **AD ja DNS:** Seadista **AD1** domeenikontrolleriks, domeeninimeks pane `perenimi.local`. (1p.)
2. **Ketta initsialiseerimine:** Initsialiseeri serveris AD1 teine kõvaketas ja loo sellele partitsioon tähisega **F:**. (1p.)
* Loo kettale **F:** kaustad `STUFF`, `WWW` ja `Kasutajad$`. Kõik edasised jagatud ressursid peavad asuma sellel kettal.


3. **DHCP server:** Seadista AD1 peal DHCP skoop nimega **HKHK**. Vahemik: `192.168.XXX.100 - 120`. (1p.)
4. **Domeeniga liitumine:** Muuda klientarvutite nimed (**Arvuti1**, **Arvuti2**) ja lisa nad domeeni. (1p.)
5. **OU struktuur arvutite jaoks:** Loo domeeniarvutite jaoks OU nimega **ARVUTID** ning selle sisse alam-OU'd **Win10**, **Win11** ja **OFFICE**. Seejärel pane Windows 10 klientmasin OU sisse **Win10** ja Windows 11 operatsioonisüsteemiga klientmasin OU **Win11** alla. (1p.)
6. **OU struktuur kasutajatele:** Loo OU nimega **KASUTAJAD** ning selle alla alam-OU-d: **LEKTORID**, **TUDENGID** ja **VEEB**. (1p.)
7. **Kasutajad ja grupid:**
* **LEKTORID:** Grupp `Lektorid`, kasutajad `oppejoud1` ja `oppejoud2`.
* **TUDENGID:** Grupp `Tudengid`, kasutajad `tudeng1` ja `tudeng2`. Lubatud logida sisse E-R 08:00–19:00. (2p.)


8. **Taustapildi GPO:** Loo GPO nimega **`GPO_Taustapildid`**.
* Määrata erinevad taustapildid lektoritele ja tudengitele asukohast `F:\STUFF\`.
* Seadista NTFS õigused nii, et tudengid ei saaks ligi lektorite piltidele. (2p.)


9. **Kaustade suunamine (Folder Redirection):** Loo GPO nimega **`GPO_Folder_Redirection`**.
* Suuna kasutajate **Desktop** ja **Documents** kaustad serverisse `\\AD1\Kasutajad$`.
* *Juhend:* [https://shorturl.at/sZMcJ](https://shorturl.at/sZMcJ) (2p.)


10. **Tarkvara GPO-d:** Loo GPO-d **`GPO_Software_7zip`** ja **`GPO_Software_Chrome`** tarkvara automaatseks paigalduseks msi pakettidena. (2p.)
11. **Chrome seadistamine:** Lisa Chrome ADMX paketid ja loo GPO nimega **`GPO_Chrome_Settings`**. Määra koduleheks `https://www.hkhk.edu.ee`.(2p.)
12. **Sisselogimisekraani teavitustekst:** Loo GPO nimega **`GPO_autentimine`** ja lingi see OU-ga **OFFICE** (mis asub **ARVUTID** all).
* Seadista arvutipõhine poliitika (*Interactive Logon Message*) nii, et enne kasutaja sisselogimist kuvatakse ekraanil teavitustekst 'Ainult lubatud kasutajatele!' ja pealkirjaks 'Hoiatus!'."**GPO_autentimine**. (1p.)


13. **Teine DC (AD2):** Muuda AD2 nimi ja IP. Lisa see teiseks domeenikontrolleriks **PowerShelli** abil. (2p.)
* *Käsud:* `Install-WindowsFeature AD-Domain-Services -IncludeManagementTools` ja `Install-ADDSDomainController -InstallDns -DomainName perenimi.local -Credential (Get-Credential PERENIMI\administrator`
* *Juhend:* [RDR-IT juhend](https://rdr-it.com/en/active-directory-add-a-domain-controller-to-powershell/)


14. **DHCP Failover:** Seadista AD2-le DHCP roll ja loo AD1-st failover ühendus (Load balance) skoobile HKHK.
* *Video:* [https://www.youtube.com/watch?v=S7Eh7ubTVtY](https://www.youtube.com/watch?v=S7Eh7ubTVtY) (1p.)


15. **IIS ja Wordpress:** Paigalda IIS ja Wordpress.
* Nimi: `veebileht.perenimi.local` | Failid: `F:\WWW\veebileht.perenimi.local`
* AB: `wp_loputoo`, kasutaja `wpuser`, parool `Passw0rd!`. (2p.)
* *Juhend:* [https://docs.google.com/document/d/1PdVANFAdp5Q0HSk4ERyRxOv9Xincgx7x](https://docs.google.com/document/d/1PdVANFAdp5Q0HSk4ERyRxOv9Xincgx7x) - sellele saate ligi kooli Gmaili kontoga


16. **HTTPS seadistamine:** Seadista Wordpressi lehele HTTPS ühendus (Self-signed sertifikaat).
* *Juhend:* [https://shorturl.at/QkQHJ](https://shorturl.at/QkQHJ) (2p.)


17. **AD Autentimine WP-s:** Paigalda plugin, mis lubab **VEEB** OU kasutajatel (`Peatoimetaja`, `ToimetajaAbi`, parool `Toimetaja123!`) logida Wordpressi sisse oma domeenikasutajaga. (2p.)

---

## HINDAMISJUHEND

Maksimaalne punktisumma on **27 punkti**.

| Punktid | Hinne | Kirjeldus |
| --- | --- | --- |
| **23 - 25** | **5 (Väga hea)** | Kõik teenused töötavad veatult, GPO-d on korrektselt nimega ja lingitud, dokumentatsioon/failitee (F:) on õige. |
| **18 - 22** | **4 (Hea)** | Enamus teenuseid töötab, esineb väiksemaid loogikavigu või mõni GPO ei rakendu täielikult. |
| **13 - 17** | **3 (Rahuldav)** | Põhiteenused (AD, DNS, DHCP) töötavad, kuid keerukamad osad (Failover, HTTPS, AD Auth) on puudulikud. |
| **< 13** | **2 (Mittearvestatud)** | Kriitilised teenused ei tööta, masinad ei ole domeenis või seadistus on poolik. |

---

### Punktide detailne jaotus:

* **Infrastruktuur (4p):** AD/DNS seadistus, ketta F: initsialiseerimine, DHCP skoobi loomine, masinate domeeni lisamine.
* **Kasutajahaldus (4p):** OU struktuuri korrektsus, sisselogimispiirangud, gruppide loomine.
* **Grupipoliitikad (10p):** Taustapildid (õigustega), Kaustade suunamine, Tarkvara paigaldus, Chrome ADMX ja avaleht, Sisselogimisekraani teavitustekst.
* **Serveri haldus (3p):** AD2 lisamine PowerShelliga, DHCP Failover seadistus.
* **Veebiteenused (6p):** IIS/Wordpressi toimimine, HTTPS sertifikaat, AD kasutajatega autentimine Wordpressis.

---

**Edu lõputöö tegemisel! Kui kõik GPO-d on valmis, tee klientmasinatele `gpupdate /force` ja kontrolli tulemust.**
