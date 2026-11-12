## 8. Failiteenused ja õigused

Failiserveri põhiprintsiip on **vähima õiguse põhimõte** (*least privilege*): igal kasutajal on täpselt need õigused, mida töö nõuab, ja õigused antakse rühmadele, mitte üksikutele kasutajatele. Laboris on failiserveriks CORE1, andmed asuvad eraldi kettal `F:` (mitte süsteemikettal).

### 8.1 Kaks õiguste kihti

Võrgu kaudu ligi pääsedes läbib kasutaja kaks värava: esmalt jagamisõigused, siis NTFS-õigused. Tulemuseks on **piiravam** neist kahest. Kohapeal (konsoolis või RDP-ga) kehtivad ainult NTFS-õigused.

| Jagamisõigus | NTFS-õigus | Efektiivne õigus võrgust |
| --- | --- | --- |
| Full Control | Read | Read |
| Read | Modify | Read |
| Change | Modify | Modify |
| Full Control | Modify | Modify |

**Kaasaegne tava:** pane jagamisõiguseks *Authenticated Users: Full Control* (või *Change*) ja reguleeri kõike NTFS-õigustega. Nii on üks koht, kus õigusi hallata ja kontrollida.

### 8.2 NTFS-õigused

| Standardõigus | Mida lubab |
| --- | --- |
| Full control | Kõike, sh õiguste muutmist ja omanikuks saamist |
| Modify | Lugeda, kirjutada, muuta, kustutada |
| Read & execute | Lugeda ja programme käivitada |
| List folder contents | Näha kausta sisu (ainult kaustadel) |
| Read | Lugeda faile ja atribuute |
| Write | Luua faile ja kirjutada, aga mitte kustutada |

Iga standardõigus on kogum täpsemaid eripärasid õigusi (*special permissions*, näha *Advanced* nupu alt). Lisaks kehtivad reeglid:

- **Pärimine:** uued failid ja alamkaustad pärivad ülemkausta õigused. Pärimise saab katkestada (*Disable inheritance*), kuid tee seda teadlikult ja dokumenteeri.
- **Kumulatiivsus:** kui kasutaja on mitmes rühmas, liidetakse lubatud õigused kokku.
- **Deny võidab** üldjuhul *Allow*-d (selgesti määratud Deny võidab ka päritud Allow). Kasuta Deny-d väga harva.
- **Kopeerimine vs teisaldamine:** fail kopeerimisel pärib sihtkausta õigused; teisaldamisel sama ketta piires säilitab oma õigused.
- **CREATOR OWNER** on eriline identiteet, mis annab faili loojale õigused tema enda loodud failidele (kasulik kodukaustades).

### 8.3 AGDLP mudel

AGDLP vastab küsimusele „kuidas anda õigusi nii, et 3 aasta pärast oleks veel aru saada, kellel milline ligipääs on“:

1. **A**ccount – kasutajakonto (`mari.maasikas`) ...
2. ... lisatakse **G**lobal rühma, mis kirjeldab **rolli** (`GG_Raamatupidamine` – „kes nad on“) ...
3. ... mis lisatakse **D**omain **L**ocal rühma, mis kirjeldab **ligipääsu** (`DL_Raamatupidamine_RW` – „mida tohib“) ...
4. ... millele antakse **P**ermission – NTFS-õigus kaustal (`F:\Osakonnad\Raamatupidamine`: Modify).

Kasu: kui uus raamatupidaja tuleb tööle, lisatakse ta ainult `GG_Raamatupidamine` rühma ja ta saab automaatselt kõik vajalikud ligipääsud. Kui aga ülemus küsib „kes pääseb raamatupidamise kausta ligi?“, vaatad ühe `DL_` rühma liikmeid. Mitme domeeniga metsas lisandub universaalrühm: **AGUDLP**.

### 8.4 Laboris loodav kaustastruktuur

| Kaust (CORE1) | Jagamine | NTFS-õigused |
| --- | --- | --- |
| `F:\Osakonnad` | `Osakonnad` (ABE sees) | Administrators: Full; Authenticated Users: Read & execute **ainult sellel kaustal** |
| `F:\Osakonnad\Raamatupidamine` | — | `DL_Raamatupidamine_RW`: Modify; `DL_Raamatupidamine_R`: Read |
| `F:\Osakonnad\IT` | — | `DL_IT_RW`: Modify |
| `F:\Yldine` | `Yldine` | Domain Users: Modify |
| `F:\Kasutajad` | `Kasutajad$` (peidetud jagamine) | Isiklikud kaustad, vt peatükk 15.3 |

Lisamärk `$` jagamise nime lõpus teeb jagamise sirvimisel nähtamatuks (nt `Kasutajad$`), kuid see **ei ole** turvameede – ligipääsu piiravad endiselt õigused.

```powershell
# CORE1-l (või Invoke-Command kaudu)
Install-WindowsFeature FS-FileServer -IncludeManagementTools

# Andmeketas F:: initsialiseeri, partitsioneeri, vorminda
Get-Disk | Where-Object PartitionStyle -eq 'RAW' |
  Initialize-Disk -PartitionStyle GPT -PassThru |
  New-Partition -DriveLetter F -UseMaximumSize |
  Format-Volume -FileSystem NTFS -NewFileSystemLabel "Andmed" -Confirm:$false

New-Item -Path F:\Osakonnad\Raamatupidamine, F:\Osakonnad\IT, F:\Yldine -ItemType Directory -Force
New-SmbShare -Name Osakonnad -Path F:\Osakonnad -FullAccess "PERENIMI\Domain Admins" `
  -ChangeAccess "Authenticated Users" -FolderEnumerationMode AccessBased
New-SmbShare -Name Yldine -Path F:\Yldine -FullAccess "PERENIMI\Domain Admins" -ChangeAccess "Authenticated Users"

# NTFS-õigused icacls-iga: (OI)(CI) = pärimine failidele ja kaustadele, M = Modify
icacls F:\Osakonnad\Raamatupidamine /grant "PERENIMI\DL_Raamatupidamine_RW:(OI)(CI)M"
icacls F:\Osakonnad\Raamatupidamine /grant "PERENIMI\DL_Raamatupidamine_R:(OI)(CI)RX"
icacls F:\Osakonnad\Raamatupidamine                       # vaata tulemust

# Kasutajakaustad, 100 MB kvoot ja FSRM: vt peatükid 13 ja 15
```

### 8.5 Kodukaustad

Isiklik kaust on igale kasutajale oma kaust serveris. Vanem viis on määrata see kasutaja omadustes (ADUC → *Profile* → *Home folder*), kuid see nõuab iga kasutaja juures käsitööd. Selles materjalis tehakse isiklikud kaustad Osa II peatükis 15 täielikult GPO-ga: Töölaud ja Dokumendid suunatakse serverisse, kasutaja kaust `F:\Kasutajad\<kasutaja>` luuakse esimesel sisselogimisel automaatselt, see kaardistatakse võrgukettaks `H:` ja FSRM piirab selle 100 MB-ga.

### 8.6 Varjukoopiad (Shadow Copies)

*Volume Shadow Copy Service* teeb ketta seisust ajastatud hetktõmmiseid. Kasutaja saab ise kustutatud või rikutud faili taastada: paremklikk kaustal → *Properties → Previous Versions*. See **ei asenda varundust**, sest koopiad asuvad samal kettal.

---

[← 7. Rühmapoliitika (GPO)](07-ruhmapoliitika-gpo.md) · [Sisukord](../README.md) · [9. WDS ja võrgupaigaldus (PXE) →](09-wds-ja-vorgupaigaldus.md)
