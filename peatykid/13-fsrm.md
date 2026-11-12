## 13. FSRM – failiserveri ressursihaldur

FSRM (*File Server Resource Manager*) on failiserveri rolliteenus, millega administraator **piirab ja jälgib** failiserveri kasutust: kui palju ruumi keegi võtab (kvoodid), milliseid faile tohib salvestada (failiekraanid) ja mis kettal toimub (aruanded). NTFS-õigused vastavad küsimusele „kes tohib?“, FSRM küsimustele „kui palju?“ ja „mida?“.

### 13.1 Mõisted

| Termin (EN) | Selgitus | Näide laboris |
| --- | --- | --- |
| Kvoot (*quota*) | Ruumipiirang kaustale (mitte kasutajale!). FSRM kvoot kehtib kausta kogumahule, olenemata failide omanikust. Erineb NTFS-i vanast köite kvoodist, mis piirab kasutajat terve köite ulatuses. | `F:\Kasutajad\mari.maasikas` ≤ 100 MB |
| Range kvoot (*hard quota*) | Piiri ületamine on keelatud: salvestamine ebaõnnestub teatega „There is not enough space“. Kasutaja näeb ketta mahuna kvoodi suurust. | Isiklik kaust 100 MB |
| Pehme kvoot (*soft quota*) | Piiri võib ületada; kasutatakse ainult jälgimiseks ja teavitamiseks. | Osakonna kaust, häire 5 GB juures |
| Lävi (*threshold*) | Protsent kvoodist, mille ületamisel käivitub tegevus: e-kiri, sündmus logis, käsk või aruanne. | 85% → hoiatus logisse |
| Kvoodimall (*quota template*) | Korduvkasutatav kvoodi kirjeldus (suurus, tüüp, läved). Malli muutmine võib uuendada kõiki sellest tehtud kvoote. | `Kasutaja 100 MB` |
| Automaatkvoot (*auto apply quota*) | Kvoot, mis rakendub automaatselt **igale olemasolevale ja uuele alamkaustale**. Just see teeb võimalikuks, et uue kasutaja kaust saab kohe 100 MB piirangu. | `F:\Kasutajad` |
| Failiekraan (*file screen*) | Reegel, mis blokeerib või jälgib teatud tüüpi failide salvestamist kausta. Kontroll käib faililaiendi järgi, mitte sisu järgi. | MP3 ja MP4 failid keelatud `F:\Osakonnad` |
| Aktiivne / passiivne ekraan | **Active screening** keelab salvestamise; **passive screening** lubab, kuid teavitab ja logib. | Passiivne `.exe` jälgimine |
| Failirühm (*file group*) | Laiendite nimekiri, mida ekraan kasutab (nt *Audio and Video Files*, *Executable Files*). Saab luua oma rühmi. | `*.mp3`, `*.mp4`, `*.mkv` |
| Erand (*file screen exception*) | Alamkaust, kus ülemkausta ekraan ei kehti. | `F:\Osakonnad\Turundus\Videod` |
| Hoiuaruanne (*storage report*) | Aruanne kettakasutusest: suured failid, duplikaadid, failid omaniku järgi, kvootide kasutus, failiekraani rikkumised. | Iganädalane aruanne HTML-ina |
| Klassifitseerimine (*classification*) | Failidele omaduste (nt „Konfidentsiaalne“) määramine asukoha või sisu järgi; failihaldusülesanded saavad nende alusel faile teisaldada või aegunuks märkida. | Lisateema |

### 13.2 Kuidas FSRM töötab

FSRM-i filter (`DataScrn` ja `Quota` failisüsteemi minifilter-draiverid) jälgib iga kirjutamist köitel reaalajas. Kui kirjutamine ületaks ranget kvooti või rikub aktiivset failiekraani, keelab draiver selle enne, kui fail kettale jõuab. Seetõttu kehtib FSRM ka kohapeal sisse loginud administraatorile ja võrgu kaudu salvestajale ühtemoodi.

Olulised piirangud:

- FSRM töötab ainult **NTFS** köitel (ReFS-il kvoodid ja ekraanid ei tööta).
- Kvoot loeb faili **tegelikku suurust kettal**; tihendatud faili puhul loeb tihendatud suurust.
- Failiekraan kontrollib ainult laiendit: ümbernimetatud `film.mp4 → film.txt` pääseb läbi. See on distsipliini, mitte turvalisuse vahend.
- FSRM seaded on serveri-põhised: DFS replikatsiooni korral tuleb kvoodid ja ekraanid seadistada **igas** liikmes eraldi (vt 14).

### 13.3 Paigaldus ja üldseaded

```powershell
# CORE1-l
Install-WindowsFeature FS-Resource-Manager -IncludeManagementTools

# E-posti teavitused (kui laboris on SMTP-server; muidu kasuta sündmuste logi)
Set-FsrmSetting -SmtpServer "smtp.perenimi.local" -AdminEmailAddress "it@perenimi.local" `
  -FromEmailAddress "fsrm@perenimi.local"

# Aruannete asukoht
Set-FsrmSetting -ReportLocationIncident F:\FSRM\Aruanded\Intsidendid `
  -ReportLocationScheduled F:\FSRM\Aruanded\Ajastatud -ReportLocationOnDemand F:\FSRM\Aruanded\Kohe
```

GUI-s hallatakse FSRM-i DC1-lt: `fsrm.msc` → paremklikk *File Server Resource Manager (Local)* → *Connect to Another Computer* → CORE1.

### 13.4 Kvoodid

```powershell
# Läved: 85% -> hoiatus logisse, 100% -> viga logisse
$hoiatus = New-FsrmAction -Type Event -EventType Warning `
  -Body "Kasutaja [Source Io Owner] on täitnud [Quota Used Percent]% kvoodist kaustas [Quota Path]."
$t85  = New-FsrmQuotaThreshold -Percentage 85  -Action $hoiatus
$viga = New-FsrmAction -Type Event -EventType Error -Body "Kvoot täis: [Quota Path] ([Source Io Owner])."
$t100 = New-FsrmQuotaThreshold -Percentage 100 -Action $viga

# Mall: range kvoot 100 MB
New-FsrmQuotaTemplate -Name "Kasutaja 100 MB" -Size 100MB -Threshold $t85, $t100

# Mall: pehme kvoot 5 GB osakondadele
New-FsrmQuotaTemplate -Name "Osakond 5 GB pehme" -Size 5GB -SoftLimit -Threshold $t85

# Automaatkvoot: iga F:\Kasutajad alla tekkiv kaust saab 100 MB
New-FsrmAutoQuota -Path F:\Kasutajad -Template "Kasutaja 100 MB"

# Tavaline kvoot ühele kaustale
New-FsrmQuota -Path F:\Osakonnad\Raamatupidamine -Template "Osakond 5 GB pehme"

# Ülevaade
Get-FsrmQuota | Select-Object Path, @{n='Piir_MB';e={$_.Size/1MB}}, @{n='Kasutus_MB';e={[math]::Round($_.Usage/1MB,1)}}, SoftLimit
```

Muutujad nagu `[Source Io Owner]`, `[Quota Path]`, `[Quota Used Percent]` asendab FSRM teate saatmisel tegelike väärtustega. Teated ilmuvad CORE1 logis *Application*, allikas **SRMSVC**, sündmus 12325 (kvoodi lävi).

### 13.5 Failiekraanid

```powershell
# Oma failirühm (vaikimisi rühmad on inglise keeles: "Audio and Video Files", "Executable Files")
New-FsrmFileGroup -Name "Meedia" -IncludePattern "*.mp3","*.mp4","*.mkv","*.avi","*.wav","*.flac"

# Aktiivne ekraan: meediafailid keelatud osakondade kaustas
$teade = New-FsrmAction -Type Event -EventType Warning `
  -Body "[Source Io Owner] proovis salvestada keelatud faili [Source File Path] kausta [File Screen Path]."
New-FsrmFileScreen -Path F:\Osakonnad -IncludeGroup "Meedia" -Notification $teade -Active

# Passiivne ekraan: käivitatavad failid üldkaustas ainult logitakse
New-FsrmFileScreen -Path F:\Yldine -IncludeGroup "Executable Files" -Notification $teade

# Erand alamkaustale
New-Item F:\Osakonnad\IT\Koolitusvideod -ItemType Directory
New-FsrmFileScreenException -Path F:\Osakonnad\IT\Koolitusvideod -IncludeGroup "Meedia"
```

### 13.6 Aruanded

| Aruanne | Milleks |
| --- | --- |
| Large Files | Leia suurimad failid, mis ruumi võtavad |
| Duplicate Files | Sama faili mitu koopiat eri kohtades |
| Files by Owner | Kes kui palju salvestab |
| Least Recently Accessed Files | Ammu kasutamata failid (arhiveerimiskandidaadid) |
| Quota Usage | Kvootide täituvus |
| File Screening Audit | Kes proovis keelatud faile salvestada |

```powershell
# Kohene aruanne
New-FsrmStorageReport -Name "Kasutajate kvoodid" -Namespace @("F:\Kasutajad") `
  -ReportType QuotaUsage, LargeFiles -Interactive
# Ajastatud aruanne igal esmaspäeval kell 06:00
$aeg = New-FsrmScheduledTask -Time (Get-Date "06:00") -Weekly Monday
New-FsrmStorageReport -Name "Nädalaaruanne" -Namespace @("F:\") -ReportType LargeFiles, DuplicateFiles, FilesByOwner -Schedule $aeg
```

### Labor 11. FSRM: kvoodid, failiekraanid ja aruanded

**Eesmärk:** seadistada CORE1-l kvoodid, failiekraanid ja aruanded ning testida neid kliendist.

**Eeldused:** Labor 7 on tehtud, CORE1 andmeketas on `F:` (kui see oli `D:`, muuda täht: `Get-Partition -DriveLetter D | Set-Partition -NewDriveLetter F`, seejärel kontrolli jagamised üle: `Get-SmbShare`).

**Sammud:**

1. Paigalda FSRM ja ühenda DC1-st `fsrm.msc` CORE1-ga.
2. Loo kaust `F:\Kasutajad` (õigused ja jagamine tehakse Labor 13-s).
3. Loo kvoodimallid `Kasutaja 100 MB` (range, läved 85% ja 100%) ja `Osakond 5 GB pehme`.
4. Rakenda automaatkvoot `F:\Kasutajad` ja pehme kvoot `F:\Osakonnad\Raamatupidamine`.
5. Loo testkaust `F:\Kasutajad\test` ja kontrolli: `Get-FsrmQuota -Path F:\Kasutajad\test` peab näitama 100 MB piiri, kuigi sa ise seda kaustale ei määranud.
6. Loo failirühm `Meedia` ja aktiivne ekraan `F:\Osakonnad`; passiivne ekraan `F:\Yldine` käivitatavatele failidele; erand `F:\Osakonnad\IT\Koolitusvideod`.
7. WIN11-02-l kasutajana `mari.maasikas`: proovi salvestada `laul.mp3` kausta Raamatupidamine (peab ebaõnnestuma) ja `programm.exe` üldkausta (õnnestub, kuid logitakse).
8. Testi kvooti: loo testkaustas 120 MB fail CORE1-l `fsutil file createnew F:\Kasutajad\test\suur.bin 125829120` – peab ebaõnnestuma. 90 MB fail õnnestub ja logisse tekib 85% hoiatus.
9. Vaata sündmusi: `Get-WinEvent -ComputerName CORE1 -FilterHashtable @{LogName='Application'; ProviderName='SRMSVC'} -MaxEvents 10`.
10. Tee kohene aruanne (*Quota Usage*, *File Screening Audit*) ja ava HTML aruandekaustast.
11. Kustuta testkaust `F:\Kasutajad\test`.

**Kontrollpunkt:** 120 MB fail ei mahu, MP3 salvestamine keelatakse, logis on SRMSVC hoiatused, aruanne avaneb.

**Küsimused:**

1. Mis vahe on FSRM kaustakvoodil ja NTFS köite kvoodil?
2. Miks kasutatakse kasutajakaustade puhul automaatkvooti, mitte tavalist kvooti?
3. Kas failiekraan on turvameede? Põhjenda näitega.
4. Mida näeb kasutaja Exploreris oma 100 MB kaustaga ühendatud võrgukettal mahuna?

---

[← Osa II. Laiendatud teenused](13-00-osa-2-sissejuhatus.md) · [Sisukord](../README.md) · [14. DFS – hajutatud failisüsteem →](14-dfs.md)
