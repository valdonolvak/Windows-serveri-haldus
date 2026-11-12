## 12. Enesekontroll, tõrkeotsing ja käskude spikker

### 12.1 Enesekontrolli küsimused

Vasta oma sõnadega 2–4 lausega. Kui vastus ei tule, mine tagasi viidatud peatükki.

1. Mis vahe on domeenil ja metsal? Kumb on tegelik turvapiir? (2.2)
2. Miks ei saa GPO-d linkida konteinerile `Computers`? Kuidas tagada, et uued arvutid satuvad OU-sse? (2.2, 5.5)
3. Kirjelda, kuidas Windows 11 klient leiab domeenikontrolleri. Mis juhtub, kui kliendi DNS on vale? (5.2)
4. Nimeta viis FSMO rolli ja nende tasand (mets/domeen). (2.2)
5. Miks peab domeenis kellaaeg olema täpne? Kust saavad aja DC-d ja kliendid? (2.2)
6. Selgita DORA-t ja APIPA aadressi tähendust tõrkeotsingus. (6.1, 6.6)
7. Mis vahe on DHCP välistusel ja reserveeringul? (2.3)
8. Mis järjekorras rakenduvad GPO-d ja kuidas mõjutavad seda *Block Inheritance* ja *Enforced*? (7.2)
9. Kasutaja on rühmades A (Modify) ja B (Read), jagamisõigus on *Read*. Mis on efektiivne õigus võrgust? (8.1, 8.2)
10. Kirjelda AGDLP-d näitega oma töökohast või koolist. (8.3)
11. Millal valiksid Server Core'i ja millal Desktop Experience'i? (3.2)
12. Mis on WDS-i roll Windows 11 paigaldusel 2026. aastal ja mis on muutunud? (9.1)
13. Mis on konfiguratsioonikäigud vastusfailis ja millises käigus toimub domeeni liitmine? (9.6)
14. Mis on 3-2-1 reegel ja miks VM-i hetktõmmis ei ole DC varundus? (10.3)
15. Nimeta viis meedet domeeni turvalisuse tõstmiseks. (10.4)

### 12.2 Kiire tõrkeotsingu tabel

| Probleem | Esimesed kontrollid |
| --- | --- |
| Klient ei liitu domeeniga | `ipconfig /all` (DNS = DC?), `nslookup perenimi.local`, `Test-NetConnection dc1 -Port 389`, kell, Windows 11 väljaanne (Home ei sobi) |
| Domeenikasutaja ei saa sisse logida | Konto lukus/keelatud (`Get-ADUser -Properties LockedOut,Enabled`), parool aegunud, `Test-ComputerSecureChannel`, kellaaja vahe |
| „The trust relationship between this workstation and the primary domain failed“ | Arvutikonto parool ei klapi (nt vana hetktõmmis): `Test-ComputerSecureChannel -Repair -Credential PERENIMI\Administrator` |
| GPO ei rakendu | `gpresult /r`, objekti OU, link lubatud, turvafiltreerimine, replikatsioon, GroupPolicy Operational logi |
| Replikatsioon ei tööta | `repadmin /replsummary`, `dcdiag /test:replications`, DNS (DC-de üksteise nimelahendus), tulemüür, kell |
| DHCP ei jaga aadresse | Teenus, ulatus aktiivne, autoriseeritud (`Get-DhcpServerInDC`), aadressid otsas, hüperviisori võrk |
| Jagamisele ei pääse | `Test-NetConnection core1 -Port 445`, jagamis- ja NTFS-õigused, *Effective Access*, rühmaliikmesus (vajab uut sisselogimist või `klist purge`) |
| PXE ei käivitu | DHCP pakkumine, `WDSServer` teenus, *AnswerClients*, DHCP/WDS samas serveris, Secure Boot, alglaadimistõmmise arhitektuur |
| Kaughaldus ei tööta | Nimelahendus, `Test-NetConnection -Port 5985`, `winrm quickconfig`, tulemüüri rühmad (4.2) |

### 12.3 Käskude spikker

| Valdkond | Käsk | Mida teeb |
| --- | --- | --- |
| Võrk | `ipconfig /all`, `Get-NetIPConfiguration` | IP-seaded |
| Võrk | `Test-NetConnection <host> -Port <nr>` | Kas port on avatud |
| DNS | `nslookup <nimi>`, `Resolve-DnsName <nimi> -Type SRV` | Nimelahenduse test |
| DNS | `ipconfig /flushdns`, `ipconfig /registerdns` | Vahemälu tühjendamine / kirjete registreerimine |
| DNS | `Get-DnsServerResourceRecord -ZoneName perenimi.local` | Tsooni kirjed |
| AD | `Get-ADUser -Filter * -SearchBase "OU=..."` | Kasutajad OU-s |
| AD | `Unlock-ADAccount`, `Set-ADAccountPassword -Reset` | Konto avamine, parooli lähtestamine |
| AD | `Get-ADGroupMember <rühm> -Recursive` | Rühma liikmed |
| AD | `dcdiag`, `repadmin /replsummary`, `netdom query fsmo` | DC tervis |
| AD | `nltest /dsgetdc:perenimi.local` | Millise DC klient leiab |
| Kerberos | `klist`, `klist purge` | Piletid ja nende tühjendamine |
| DHCP | `Get-DhcpServerv4Scope`, `Get-DhcpServerv4Lease -ScopeId ...` | Ulatused ja rendid |
| DHCP | `ipconfig /release`, `ipconfig /renew` | Rendi vabastamine / uuendamine |
| GPO | `gpupdate /force`, `gpresult /r`, `gpresult /h fail.html` | Rakendamine ja aruanne |
| GPO | `Get-GPInheritance -Target "OU=..."` | Päritavad GPO-d |
| Failid | `Get-SmbShare`, `New-SmbShare`, `icacls <kaust>` | Jagamised ja õigused |
| Failid | `Get-SmbSession`, `Get-SmbOpenFile` | Kes on ühendatud, mis on avatud |
| Roll | `Get-WindowsFeature`, `Install-WindowsFeature <nimi> -IncludeManagementTools` | Rollide haldus |
| Kaughaldus | `Enter-PSSession <host>`, `Invoke-Command -ComputerName ...` | PowerShell Remoting |
| Süsteem | `sconfig`, `Rename-Computer`, `Add-Computer`, `Restart-Computer` | Server Core'i põhikäsud |
| Logid | `Get-WinEvent -LogName System -MaxEvents 20` | Viimased sündmused |
| WDS | `wdsutil /Get-Server /Show:Config`, `Get-WdsBootImage` | WDS-i seaded ja tõmmised |
| Varundus | `wbadmin start systemstatebackup`, `wbadmin get versions` | System State varundus |

### 12.4 Allikad ja edasine lugemine

- [Windows Server 2022 elutükkel – Microsoft Lifecycle](https://learn.microsoft.com/lifecycle/products/windows-server-2022)
- [WDS boot.wim tugi – Microsoft Learn](https://learn.microsoft.com/windows/deployment/wds-boot-support)
- [WDS hands-free paigalduse karmistamine, CVE-2026-0386 – KB5074952](https://support.microsoft.com/kb/5074952)
- [Windows Server 2022-s eemaldatud ja aegunud funktsioonid](https://learn.microsoft.com/windows-server/get-started/removed-deprecated-features-windows-server-2022)
- Microsoft Learn: *Active Directory Domain Services overview*, *DHCP*, *Group Policy*, *Windows LAPS* (otsi learn.microsoft.com)

---

[← 11. Laboritööd](11-laboritood-1-10.md) · [Sisukord](../README.md) · [Osa II. Laiendatud teenused →](13-00-osa-2-sissejuhatus.md)
