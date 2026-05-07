# LÕPUTÖÖ: Windows operatsioonisüsteemide haldus

### ⚠️ ETTEVALMISTUS JA LITSENTS
Windowsi prooviversioonid sulgevad end automaatselt iga tunni järel, kui litsentsi aeg on läbi. 
**Kriitiline samm:** Kohe pärast masina nime ja võrguseadete muutmist ava **PowerShell** administraatori õigustes ja sisesta käsk:
`slmgr -rearm`
Pärast käsu kinnitamist tee masinale **Restart**.

---

### 1. Keskkond ja ligipääs
*   **Aadress (sisevõrgus):** [https://10.231.231.2:8007](https://10.231.231.2:8007)
*   **Aadress (väljast):** [https://proxmox.hkhk.edu.ee:8007](https://proxmox.hkhk.edu.ee:8007)
*   **Realm:** `hkhk.edu.ee` | **Kasutaja:** eesnime esitäht + perekonnanimi
*   **Info:** Töö ajal on lubatud kasutada internetis leiduvaid materjale ja juhendeid.

### 2. Virtuaalmasinad ja võrguseadistus (VNET)
Võrguaadress moodustub valemiga **192.168.XXX.0/24**, kus **XXX** on sinu virtuaalmasina võrguseadme **vnet** number.
> **Näide:** Kui vnet = 50, siis võrguaadress on **192.168.50.0/24**.

| Masina nimi Proxmoxis | Masina nimi süsteemis | IP-aadress | Roll |
| :--- | :--- | :--- | :--- |
| TOO-WinServer-IT25-Nimi | **AD1** | `192.168.XXX.10` | DC, DNS, DHCP, IIS |
| TOO-Win2022Core-IT25-Nimi | **AD2** | `192.168.XXX.11` | Secondary DC, DHCP Failover |
| TOO-Winklient-IT25-Nimi | **Arvuti1** | DHCP | Klient (Win 10) |
| TOO-Win11Ent-IT25-Nimi | **Arvuti2** | DHCP | Klient (Win 11) |

*   **Administraatori parool:** `Passw0rd`
*   **Kasutajate paroolid:** `Par00LA!`

---

## TEHTAVAD TÖÖD

1.  **AD ja DNS:** Seadista **AD1** domeenikontrolleriks, domeeninimeks pane `perenimi.local`. (1p.)
2.  **Ketta initsialiseerimine:** Initsialiseeri serveris AD1 teine kõvaketas ja loo sellele partitsioon tähisega **F:**. (1p.)
    *   Loo kettale **F:** kaustad `STUFF`, `WWW` ja `Kasutajad$`. Kõik edasised jagatud ressursid peavad asuma sellel kettal.
3.  **DHCP server:** Seadista AD1 peal DHCP skoop nimega **HKHK**. Vahemik: `192.168.XXX.100 - 120`. (1p.)
4.  **Domeeniga liitumine:** Muuda klientarvutite nimed (**Arvuti1**, **Arvuti2**) ja lisa nad domeeni. (1p.)
5.   **OU struktuur arvutite jaoks**: Loo domeeniarvutite jaoks OU nimega **ARVUTID** ning selle sisse OU'd **Win10** ja **Win11**. Seejärel pane Windows10 klientmasin OU sisse **Win10** ja Windows 11 operatsioonisüsteemiga klientmasin OU **Win11** alla. (1p.)
6.   **OU struktuur:** Loo OU nimega **KASUTAJAD** ning selle alla alam-OU-d: **LEKTORID**, **TUDENGID** ja **VEEB**. (1p.)
7.  **Kasutajad ja grupid:**
    *   **LEKTORID:** Grupp `Lektorid`, kasutajad `oppejoud1` ja `oppejoud2`.
    *   **TUDENGID:** Grupp `Tudengid`, kasutajad `tudeng1` ja `tudeng2`. Lubatud logida sisse E-R 08:00–19:00. (2p.)
8.  **Taustapildi GPO:** Loo GPO nimega **`GPO_Taustapildid`**.
    *   Määrata erinevad taustapildid lektoritele ja tudengitele asukohast `F:\STUFF\`.
    *   Seadista NTFS õigused nii, et tudengid ei saaks ligi lektorite piltidele. (2p.)
9.  **Kaustade suunamine (Folder Redirection):** Loo GPO nimega **`GPO_Folder_Redirection`**.
    *   Suuna kasutajate **Desktop** ja **Documents** kaustad serverisse `\\AD1\Kasutajad$`.
    *   *Juhend:* [https://shorturl.at/sZMcJ](https://shorturl.at/sZMcJ) (2p.)
10.  **Tarkvara GPO-d:** Loo GPO-d **`GPO_Software_7zip`** ja **`GPO_Software_Chrome`** tarkvara automaatseks paigalduseks msi pakettidena. (2p.)
11. **Chrome seadistamine:** Lisa Chrome ADMX paketid ja loo GPO nimega **`GPO_Chrome_Settings`**. Määra koduleheks `[https://www.hkhk.edu.ee](https://www.hkhk.edu.ee)`.
    *   *Juhend:* [https://shorturl.at/RFQ5U](https://shorturl.at/RFQ5U) (2p.)
12. **Teine DC (AD2):** Muuda AD2 nimi ja IP. Lisa see teiseks domeenikontrolleriks **PowerShelli** abil. (2p.)
    *   *Käsud:* `Install-WindowsFeature AD-Domain-Services...` ja `Install-ADDSDomainController...`
    *   *Juhend:* [RDR-IT juhend](https://rdr-it.com/en/active-directory-add-a-domain-controller-to-powershell/)
13. **DHCP Failover:** Seadista AD2-le DHCP roll ja loo AD1-st failover ühendus (Load balance) skoobile HKHK.
    *   *Video:* [https://www.youtube.com/watch?v=S7Eh7ubTVtY](https://www.youtube.com/watch?v=S7Eh7ubTVtY) (1p.)
14. **IIS ja Wordpress:** Paigalda IIS ja Wordpress.
    *   Nimi: `veebileht.perenimi.local` | Failid: `F:\WWW\veebileht.perenimi.local`
    *   AB: `wp_loputoo`, kasutaja `wpuser`, parool `Passw0rd!`. (2p.)
15. **HTTPS seadistamine:** Seadista Wordpressi lehele HTTPS ühendus (Self-signed sertifikaat).
    *   *Juhend:* [https://shorturl.at/QkQHJ](https://shorturl.at/QkQHJ) (2p.)
16. **AD Autentimine WP-s:** Paigalda plugin, mis lubab **VEEB** OU kasutajatel (`Peatoimetaja`, `ToimetajaAbi`, parool `Toimetaja123!`) logida Wordpressi sisse oma domeenikasutajaga. (2p.)

---

## HINDAMISJUHEND

Maksimaalne punktisumma on **25 punkti**.

| Punktid | Hinne | Kirjeldus |
| :--- | :--- | :--- |
| **22 - 25** | **5 (Väga hea)** | Kõik teenused töötavad veatult, GPO-d on korrektselt nimega ja lingitud, dokumentatsioon/failitee (F:) on õige. |
| **17 - 21** | **4 (Hea)** | Enamus teenuseid töötab, esineb väiksemaid loogikavigu või mõni GPO ei rakendu täielikult. |
| **12 - 16** | **3 (Rahuldav)** | Põhiteenused (AD, DNS, DHCP) töötavad, kuid keerukamad osad (Failover, HTTPS, AD Auth) on puudulikud. |
| **< 12** | **2 (Mittearvestatud)** | Kriitilised teenused ei tööta, masinad ei ole domeenis või seadistus on poolik. |

---

### Punktide detailne jaotus:
*   **Infrastruktuur (4p):** AD/DNS seadistus, ketta F: initsialiseerimine, DHCP skoobi loomine, masinate domeeni lisamine.
*   **Kasutajahaldus (4p):** OU struktuuri korrektsus, sisselogimispiirangud, gruppide loomine.
*   **Grupipoliitikad (8p):** Taustapildid (õigustega), Kaustade suunamine, Tarkvara paigaldus, Chrome ADMX ja avaleht.
*   **Serveri haldus (3p):** AD2 lisamine PowerShelliga, DHCP Failover seadistus.
*   **Veebiteenused (6p):** IIS/Wordpressi toimimine, HTTPS sertifikaat, AD kasutajatega autentimine Wordpressis.

---
**Edu eksamil! Kui kõik GPO-d on valmis, tee klientmasinatele `gpupdate /force` ja kontrolli tulemust.**
http://googleusercontent.com/youtube_content/1
