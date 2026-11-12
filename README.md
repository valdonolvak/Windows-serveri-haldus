# Windows Server 2022 haldus — õppematerjal ja laboritööd

Õppematerjal Windows Server 2022 haldusest: mõisted, selgitused, joonised ja 19 laboritööd. Labor töötab **Proxmox VE** keskkonnas: DC1 (Windows Server 2022 Desktop Experience), CORE1 (Windows Server 2022 Server Core), kaks Windows 11 klienti ja üks WDS-klient.

**Domeeninimi = õppija perekonnanimi.** Kus materjalis on `perenimi`, kirjuta oma perekonnanimi väiketähtedega ja ilma täpitähtedeta (nt Tõnisson → `tonisson.local`, NetBIOS `TONISSON`).

**GUI või PowerShell.** Teenuste paigaldus ja seadistus on kirjeldatud kahel viisil: **Variant A – GUI samm-sammult** (alati esimesena) ja **Variant B – PowerShell**. Piisab ühest: kui teed GUI juhendi järgi, pole PowerShelli osa vaja. Server Core'i (CORE1) GUI-sammud tehakse DC1-st Server Manageri ja MMC-konsoolide kaudu.

## Interaktiivsed harjutused

| Simulaator | Teema |
| --- | --- |
| [Autentimise ja autoriseerimise simulaator](https://valdonolvak.github.io/windows-server-2022-oppematerjal/interaktiivne/autentimise-simulaator.html) | Domeeniga liitmine, arvuti käivitamine, kasutaja sisselogimine (Kerberos, PAC, token, GPO-d), ligipääs failiserverile; rikked |
| [GPO rakendamise simulaator](https://valdonolvak.github.io/windows-server-2022-oppematerjal/interaktiivne/gpo-simulaator.html) | LSDOU järjekord, Enforced, Block Inheritance, turvafilter; 6 stsenaariumiülesannet |

## Sisukord

### Osa I – põhiteenused (laborid 1–10)

- [1. Sissejuhatus ja laborikeskkond](peatykid/01-sissejuhatus-ja-laborikeskkond.md)
- [2. Põhimõisted ja terminid](peatykid/02-pohimoisted.md)
- [3. Windows Server 2022: väljaanded, paigaldus, Desktop Experience vs Server Core](peatykid/03-valjaanded-paigaldus-core.md)
- [4. Haldusvahendid](peatykid/04-haldusvahendid.md)
- [5. Active Directory Domain Services ja DNS](peatykid/05-active-directory-ja-dns.md)
- [6. DHCP](peatykid/06-dhcp.md)
- [7. Rühmapoliitika (GPO)](peatykid/07-ruhmapoliitika-gpo.md)
- [8. Failiteenused ja õigused](peatykid/08-failiteenused-ja-oigused.md)
- [9. WDS ja võrgupaigaldus (PXE)](peatykid/09-wds-ja-vorgupaigaldus.md)
- [10. Uuendused, monitooring, varundus ja turvalisus](peatykid/10-uuendused-monitooring-varundus-turvalisus.md)
- [11. Laboritööd](peatykid/11-laboritood-1-10.md)
- [12. Enesekontroll, tõrkeotsing ja käskude spikker](peatykid/12-enesekontroll-ja-spikker.md)

### Osa II – laiendatud teenused (laborid 11–19)

- [Osa II. Laiendatud teenused](peatykid/13-00-osa-2-sissejuhatus.md)
- [13. FSRM – failiserveri ressursihaldur](peatykid/13-fsrm.md)
- [14. DFS – hajutatud failisüsteem](peatykid/14-dfs.md)
- [15. Kaustade ümbersuunamine ja isiklik võrguketas](peatykid/15-kaustade-umbersuunamine-ja-vorguketas.md)
- [16. Rakenduste ligipääs AD rühmade järgi](peatykid/16-rakenduste-ligipaas-ad-ruhmadega.md)
- [17. IIS ja WordPress](peatykid/17-iis-ja-wordpress.md)
- [18. AD CS sertifikaadiasutus ja HTTPS](peatykid/18-ad-cs-ja-https.md)
- [19. Kellaaja sünkroniseerimine (W32Time)](peatykid/19-kellaaja-sunkroniseerimine.md)
- [20. WSUS – uuenduste tsentraalne haldus](peatykid/20-wsus.md)
- [21. WiFi ja 802.1X: NPS ja RADIUS](peatykid/21-wifi-8021x-nps.md)
- [Osa II allikad](peatykid/22-osa-2-allikad.md)

## Repo ülesehitus

```text
README.md                 sisukord (see fail)
peatykid/                 iga peatükk eraldi .md failina
peatykid/joonised/        skeemid PNG-failidena
interaktiivne/            simulaatorid (HTML, avanevad GitHub Pagesi kaudu)
```
