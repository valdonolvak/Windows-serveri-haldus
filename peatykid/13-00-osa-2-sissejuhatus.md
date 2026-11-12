# Osa II. Laiendatud teenused

Osa II ehitab Osa I domeenile peale failiteenuste täiendused (FSRM, DFS, kaustade ümbersuunamine), rakenduste ligipääsu AD rühmade kaudu, veebiserveri (IIS + WordPress) ja oma sertifikaadiasutuse (AD CS), mis annab veebile usaldusväärse HTTPS-i. Eeldus: Osa I laborid 1–10 on tehtud.

### Nimetamise reegel: iga õppija oma domeen

Igal õppijal on oma domeen, mille nimi on tema **perekonnanimi**. Kogu materjalis tähendab `perenimi` sinu perekonnanime väikestähtedega ja ilma täpitähtedeta (ä → a, õ → o, ö → o, ü → u, š → s, ž → z) ning `PERENIMI` sama nime suurtähtedega (NetBIOS-nimi, max 15 märki).

| Materjalis | Näide õppijale Mari Tõnisson |
| --- | --- |
| `perenimi.local` | `tonisson.local` |
| `PERENIMI` (NetBIOS) | `TONISSON` |
| `DC=perenimi,DC=local` | `DC=tonisson,DC=local` |
| `veeb.perenimi.local` | `veeb.tonisson.local` |
| `PERENIMI-CA` | `TONISSON-CA` |

### Muudatused laborikeskkonnas

| Masin | Lisandub Osa II-s | Ketas |
| --- | --- | --- |
| DC1 | DFS nimeruumiserver, DFS replikatsiooni liige, IIS + PHP + MySQL + WordPress (`veeb.perenimi.local`) | **uus 40 GB ketas → `F:`** (DFS replikad) |
| CORE1 | FSRM, DFS nimeruumiserver ja replikatsiooni esmane liige, kasutajakaustad, AD CS sertifikaadiasutus `PERENIMI-CA` | andmeketas on **`F:`** (Osa I-s kasutatud `D:` asemel) |
| WIN11-01, WIN11-02 | GPO-ga töölaua ja dokumentide ümbersuunamine, isiklik võrguketas `H:` (100 MB), rakendused rühmade järgi, HTTPS kontroll | — |

> **Tootmises tehtaks teisiti.** Laboris on IIS ja sertifikaadiasutus domeenikontrolleritel, sest serveri-VM-e on ainult kaks. Päris ettevõttes oleksid veebiserver ja CA eraldi liikmesserverid (nt WEB1 ja CA1): DC peab olema võimalikult „puhas“, sest iga lisateenus on lisaründepind kõige tähtsamal serveril. Samuti ei saa CA-ga serverit hiljem ümber nimetada ega domeenist eemaldada.

### Osa II laborid

| Labor | Teema | Masinad | Aeg (ak h) |
| --- | --- | --- | --- |
| 11 | FSRM: kvoodid, failiekraanid, aruanded | CORE1, WIN11-02 | 3 |
| 12 | DFS nimeruum ja replikatsioon | CORE1, DC1, WIN11-01 | 4 |
| 13 | Kaustade ümbersuunamine ja isiklik 100 MB võrguketas | DC1, CORE1, WIN11-02 | 4 |
| 14 | Rakenduste ligipääs AD rühmade järgi | DC1, WIN11-01, WIN11-02 | 4 |
| 15 | IIS ja WordPress | DC1, WIN11-01 | 5 |
| 16 | AD CS ja HTTPS | CORE1, DC1, WIN11-01 | 4 |
| 17 | Kellaaja sünkroniseerimine | kõik | 2 |
| 18 | WSUS | CORE1, DC1, WIN11-01, WIN11-02 | 4 |
| 19 | NPS ja WiFi 802.1X (RADIUS-testiga) | DC1, CORE1, WIN11-01 | 4 |

---

[← 12. Enesekontroll, tõrkeotsing ja käskude spikker](12-enesekontroll-ja-spikker.md) · [Sisukord](../README.md) · [13. FSRM – failiserveri ressursihaldur →](13-fsrm.md)
