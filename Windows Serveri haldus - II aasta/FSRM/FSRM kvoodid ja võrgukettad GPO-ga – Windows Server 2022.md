# FSRM kvoodid ja võrgukettad GPO-ga – Windows Server 2022

Oct 29, 2026 · @Valdo

Juhend on DFS-juhendi jätk. Iga tudeng saab jagatud kausta F:\\DFS\_Tudengitele alla isikliku kausta, millel on FSRM-i kõva kvoot 500 MB. GPO kaardistab sisselogimisel tudengile kaks võrguketast: **H:** isiklik kaust ja **T:** ühine tudengite kaust. Kõik teed kasutavad DFS-i nimeruumi \\\\TEST.LOCAL\\Tudengid, mitte serveri nime.

## 1. Eesmärk ja eeldused

Pärast juhendi läbimist peab kehtima järgmine:

- AD1-l on paigaldatud File Server Resource Manager (FSRM).
- Kaustas F:\\DFS\_Tudengitele\\Kodukaustad on igal tudengil oma alamkaust, näiteks Kodukaustad\\mari.maasikas.
- Igale alamkaustale rakendub automaatselt kvoot 500 MB. Uue kausta lisandumisel saab ka see kvoodi ise.
- Tudeng näeb ja muudab ainult oma kausta. Teiste tudengite kaustad ei ole talle nähtavad.
- Sisselogimisel tekivad tudengile kettad H: ja T:.

| Muutuja | Selles juhendis kasutatav näide | Asenda vajadusel |
| --- | --- | --- |
| Domeen | TEST.LOCAL (NetBIOS: TEST) | Kasuta oma labori domeeni nime. |
| Failiserver | AD1 | Server, kus asub F:\\DFS\_Tudengitele. |
| DFS-i kaust | \\\\TEST.LOCAL\\Tudengid\\Tudengitele | Loodud DFS-juhendi 5. peatükis. |
| Kodukaustade juur | F:\\DFS\_Tudengitele\\Kodukaustad | Muuda vaid siis, kui õpetaja määrab teisiti. |
| Õiguste grupp | DFS\_Tudengitele | Või DFS\_Tudengid, kui õpetaja on nii määranud. |
| Kasutajate grupp | Tudengid | Olemasolev tudengite turvagrupp. |
| Kasutajate OU | KASUTAJAD | OU, kus asuvad tudengite kasutajakontod. |
| Kvoot | 500 MB, hoiatus 85% juures | Määra vastavalt labori nõudele. |

Enne alustamist peavad olema tehtud DFS-juhendi peatükid 3–6. Grupp DFS\_Tudengitele on olemas, F:\\DFS\_Tudengitele on jagatud ja \\\\TEST.LOCAL\\Tudengid\\Tudengitele avaneb tudengi kontoga. Kontrolli algseisu AD1-s administraatori PowerShellis:

```powershell
Get-SmbShare -Name "DFS_Tudengitele"
Get-DfsnFolderTarget -Path "\\TEST.LOCAL\Tudengid\Tudengitele"
Get-ADGroupMember -Identity "DFS_Tudengitele"
Get-ADGroupMember -Identity "Tudengid" | Select-Object SamAccountName
```

> **Mõiste.** FSRM kvoot ei ole kasutajapõhine, vaid kaustapõhine. See piirab ühe kausta kogumahtu, sõltumata sellest, kes failid sinna kirjutas. Kasutajapõhise piirangu saad, kui igal kasutajal on oma kaust ja igale kaustale rakendub oma kvoot. Seda teeb automaatne kvoot (auto apply quota). NTFS-i kettakvoot on päris kasutajapõhine, kuid kehtib kogu F:-kettale, mitte ühele kaustale.

> **Mõiste.** DFS-il endal kvoodifunktsiooni ei ole. Nimeruum on ainult viide. Kvoot seadistatakse serveris, kus kaust füüsiliselt asub, ehk siin AD1-l.

## 2. Loo kodukaustade juurkaust ja määra õigused

Isiklikud kaustad paigutatakse jagatud kausta alamkausta Kodukaustad. Uut SMB-jagamist ega uut DFS-kausta selleks vaja ei ole. Tudeng jõuab oma kaustani olemasoleva DFS-tee kaudu:

```text
F:\DFS_Tudengitele\                     ← jagatud (DFS_Tudengitele), ühine kaust → ketas T:
└── Kodukaustad\                        ← kodukaustade juur, automaatne kvoot
    ├── mari.maasikas\                  ← kvoot 500 MB → mari ketas H:
    └── jaan.tamm\                      ← kvoot 500 MB → jaani ketas H:
```

Kodukaustad peab **katkestama õiguste pärimise**. Muidu pärib see ülemkaustalt DFS\_Tudengitele grupi õigused ja iga tudeng näeks ning muudaks kõigi teiste kaustu. Juurkaustas saab tudengite grupp ainult kausta avamise ja sirvimise õiguse ning ainult sellele kaustale endale.

### 2.1 Graafilise liidese abil

1. Loo AD1 serveris kaust F:\\DFS\_Tudengitele\\Kodukaustad.
2. Tee kaustal paremklõps > Properties > Security > Advanced.
3. Vali Disable inheritance > Convert inherited permissions into explicit permissions on this object.
4. Eemalda kõik kirjed peale SYSTEM ja Administrators. Kontrolli, et nendel kahel oleks Full control ja Applies to: This folder, subfolders and files.
5. Vali Add > Select a principal > DFS\_Tudengitele. Applies to: **This folder only**. Märgi ainult Read & execute, List folder contents ja Read.
6. Vali OK ja rakenda muudatused.

### 2.2 PowerShelli abil

```powershell
New-Item -Path "F:\DFS_Tudengitele\Kodukaustad" -ItemType Directory -Force
icacls "F:\DFS_Tudengitele\Kodukaustad" /inheritance:r `
    /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" `
    "TEST\DFS_Tudengitele:(RX)"
icacls "F:\DFS_Tudengitele\Kodukaustad"
```

`/inheritance:r` eemaldab päritud õigused. `(OI)(CI)F` tähendab, et Full control kehtib kaustale, alamkaustadele ja failidele. DFS\_Tudengitele kirjel pole pärimislippe, seega kehtib see ainult kaustale endale.

> **Jagamisõigused.** Tudeng peab saama oma kausta kirjutada, seega peab DFS\_Tudengitele jagamise Share Permissions lubama vähemalt **Change**. Kui seadsid DFS-juhendi järgi tudengitele jagamisel ainult Read, ei saa tudeng H:-kettale midagi salvestada. Sel juhul muuda jagamisõigus Change'iks ja piira ligipääsu NTFS-õigustega. Kontrolli: `Get-SmbShareAccess -Name "DFS_Tudengitele"`.

## 3. Paigalda FSRM AD1-le

FSRM on File and Storage Services rolli teenus. Paigalda see serverisse, kus kaust füüsiliselt asub, ehk AD1-le.

1. Ava Server Manager > Manage > Add Roles and Features.
2. Vali Role-based or feature-based installation > AD1.
3. Ava File and Storage Services > File and iSCSI Services ja märgi **File Server Resource Manager**. Lisa pakutud haldustööriistad (Add Features).
4. Vali Install ja oota paigalduse lõppu. Taaskäivitust tavaliselt vaja ei ole.

PowerShelli alternatiiv administraatorina:

```powershell
Install-WindowsFeature FS-Resource-Manager -IncludeManagementTools
Get-WindowsFeature FS-Resource-Manager, RSAT-FSRM-Mgmt
```

Pärast paigaldust leiad konsooli Server Manager > Tools > File Server Resource Manager. Nüüd on New Share viisardis ka profiil **SMB Share – Advanced** saadaval. Olemasoleva jagamise uuesti loomist see ei nõua, sest kvoot seotakse kausta teega, mitte jagamisega.

> **Kui sihtkohti on mitu.** Kui lisad hiljem \\\\TEST.LOCAL\\Tudengid\\Tudengitele kaustale teise sihi (näiteks \\\\AD2\\DFS\_Tudengitele) ja replikeerid sisu DFS-R-iga, paigalda FSRM ka AD2-le. Seadista seal samad kvoodid. DFS Replication kvoodiseadeid ei kopeeri.

## 4. Loo kvoodimall

Mall kirjeldab kvoodi ühe korra: suurus, tüüp ja hoiatused. Automaatne kvoot kasutab malli igal alamkaustal. Kui muudad hiljem malli, saad muudatuse rakendada kõigile sellest tuletatud kvootidele.

| Kvoodi tüüp | Mis juhtub piiri ületamisel | Millal kasutada |
| --- | --- | --- |
| Hard quota | Kirjutamine keelatakse, kasutaja saab teate „There is not enough space“ | Kasutajate kaustade päris piiramiseks. Kasutame seda. |
| Soft quota | Kirjutamine on lubatud, tekib ainult hoiatus | Kasutuse jälgimiseks enne piirangu kehtestamist. |

### 4.1 Graafilise liidese abil

1. Ava Server Manager > Tools > File Server Resource Manager.
2. Ava Quota Management > Quota Templates. Tee paremklõps > Create Quota Template.
3. Template name: **Tudeng 500 MB**. Space limit: **500 MB**. Vali **Hard quota: Do not allow users to exceed limit**.
4. Notification thresholds juures vali Add. Generate notifications when usage reaches: **85** %.
5. Ava vaheleht Event Log ja märgi Send warning to event log. Kirjuta teade, näiteks: `Kasutaja [Source Io Owner] on kasutanud [Quota Used Percent]% kvoodist kaustas [Quota Path].` Vali OK.
6. Lisa sama moodi teine lävi **100** %, mis kirjutab hoiatuse sündmuste logisse.
7. Vali OK. Mall ilmub nimekirja.

E-kirjaga teavitamiseks peab FSRM-is olema seadistatud SMTP-server (File Server Resource Manager > Configure Options > Email Notifications). Laboris piisab sündmuste logist.

### 4.2 PowerShelli abil

```powershell
$teade85 = New-FsrmAction -Type Event -EventType Warning `
    -Body "Kasutaja [Source Io Owner] on kasutanud [Quota Used Percent]% kvoodist kaustas [Quota Path]." `
    -RunLimitInterval 60
$teade100 = New-FsrmAction -Type Event -EventType Warning `
    -Body "Kasutaja [Source Io Owner] jõudis kvoodi piirini kaustas [Quota Path]." `
    -RunLimitInterval 60
$lavi85  = New-FsrmQuotaThreshold -Percentage 85  -Action $teade85
$lavi100 = New-FsrmQuotaThreshold -Percentage 100 -Action $teade100
New-FsrmQuotaTemplate -Name "Tudeng 500 MB" -Size 500MB -Threshold $lavi85, $lavi100
Get-FsrmQuotaTemplate -Name "Tudeng 500 MB"
```

`-RunLimitInterval 60` tähendab, et sama hoiatus kirjutatakse logisse kõige rohkem kord 60 minuti jooksul. Ilma `-SoftLimit` lülitita on kvoot kõva (hard).

## 5. Rakenda automaatne kvoot kodukaustadele

Automaatne kvoot (auto apply quota) seotakse kaustaga Kodukaustad. See loob igale selle **vahetule alamkaustale** eraldi kvoodi malli Tudeng 500 MB põhjal, nii olemasolevatele kui ka hiljem lisatud kaustadele. Kausta Kodukaustad kogumahtu see ei piira, piiratakse iga kasutaja kausta eraldi.

Tee see samm **enne** kasutajate kaustade loomist. Siis saab iga kaust kvoodi kohe tekkimisel.

### 5.1 Graafilise liidese abil

1. FSRM konsoolis ava Quota Management > Quotas. Tee paremklõps > Create Quota.
2. Quota path: **F:\\DFS\_Tudengitele\\Kodukaustad**.
3. Vali **Auto apply template and create quotas on existing and new subfolders**.
4. Derive properties from this quota template: vali **Tudeng 500 MB**. Kontrolli kokkuvõttes, et limiit on 500 MB (Hard).
5. Vali Create.

Quotas nimekirjas on nüüd kirje, mille Quota Type on Auto Apply. Iga kasutajakausta loomise järel lisandub nimekirja selle kausta enda kvoot.

### 5.2 PowerShelli abil

```powershell
New-FsrmAutoQuota -Path "F:\DFS_Tudengitele\Kodukaustad" -Template "Tudeng 500 MB"
Get-FsrmAutoQuota -Path "F:\DFS_Tudengitele\Kodukaustad"
```

> **Valikuline: ühise kausta piirang.** Kui soovid piirata ka ühist kausta kokku, näiteks 20 GB peale, loo kaustale F:\\DFS\_Tudengitele tavaline kvoot: `New-FsrmQuota -Path "F:\DFS_Tudengitele" -Size 20GB`. Kodukaustade maht arvestatakse siis ka sellesse 20 GB sisse, sest Kodukaustad asub selle kausta all. Kehtivad mõlemad piirangud ja kitsam neist rakendub esimesena.

## 6. Loo tudengite isiklikud kaustad

Iga tudeng saab kausta, mille nimi on tema kasutajanimi (sAMAccountName). Sama nime kasutab hiljem GPO muutuja %LogonUser%. Kaustal on Modify-õigus ainult selle kasutaja jaoks. SYSTEM ja Administrators pärivad Full control õiguse juurkaustalt.

### 6.1 Graafilise liidese abil (üks kasutaja)

1. Loo kaust `F:\DFS_Tudengitele\Kodukaustad\mari.maasikas`. Nimi peab täpselt vastama kasutajanimele.
2. Paremklõps > Properties > Security > Edit > Add. Lisa kasutaja TEST\\mari.maasikas.
3. Märgi Allow: **Modify**. Vali OK.
4. FSRM konsoolis Quotas all peab nüüd olema kirje …\\Kodukaustad\\mari.maasikas limiidiga 500 MB.

### 6.2 PowerShelli abil (kõik grupi Tudengid liikmed)

Skript loob kausta igale grupi Tudengid liikmele, ka pesastatud gruppide kaudu. Olemasolevaid kaustu see üle ei kirjuta, vaid lisab ainult puuduva õiguse. Uute tudengite lisandumisel käivita skript uuesti.

```powershell
Import-Module ActiveDirectory
$juur = "F:\DFS_Tudengitele\Kodukaustad"
$tudengid = Get-ADGroupMember -Identity "Tudengid" -Recursive |
    Where-Object objectClass -eq "user"

foreach ($t in $tudengid) {
    $nimi  = $t.SamAccountName
    $kaust = Join-Path $juur $nimi
    if (-not (Test-Path $kaust)) {
        New-Item -Path $kaust -ItemType Directory | Out-Null
    }
    icacls $kaust /grant "TEST\${nimi}:(OI)(CI)M" | Out-Null
    Write-Host "Valmis: $kaust"
}
```

Kontrolli tulemust:

```powershell
Get-ChildItem "F:\DFS_Tudengitele\Kodukaustad"
icacls "F:\DFS_Tudengitele\Kodukaustad\mari.maasikas"
Get-FsrmQuota | Where-Object Path -like "F:\DFS_Tudengitele\Kodukaustad\*" |
    Select-Object Path, @{n='Limiit MB';e={$_.Size/1MB}}, @{n='Kasutus MB';e={[math]::Round($_.Usage/1MB,1)}}, SoftLimit
```

Iga kasutajakausta kohta peab olema üks kvoot limiidiga 500 ja SoftLimit väärtusega False.

> **Miks Modify, mitte Full control?** Modify lubab faile luua, muuta ja kustutada. Kausta õigusi kasutaja muuta ei saa. Full control lubaks tudengil õigusi muuta ja näiteks oma kausta teistele avada.

## 7. Peida teiste tudengite kaustad (Access-Based Enumeration)

NTFS-õigused juba keelavad võõra kausta avamise. Ilma ABE-ta näeb tudeng kaustas Kodukaustad siiski kõigi kaaslaste kaustade nimesid. Access-Based Enumeration näitab kasutajale ainult neid kaustu ja faile, millele tal on lugemisõigus.

### 7.1 Graafilise liidese abil

1. Ava AD1-s Server Manager > File and Storage Services > Shares.
2. Tee jagamisel DFS\_Tudengitele paremklõps > Properties > Settings.
3. Märgi **Enable access-based enumeration**. Vali OK.

### 7.2 PowerShelli abil

```powershell
Set-SmbShare -Name "DFS_Tudengitele" -FolderEnumerationMode AccessBased -Force
Get-SmbShare -Name "DFS_Tudengitele" | Select-Object Name, Path, FolderEnumerationMode
```

`FolderEnumerationMode` peab olema AccessBased. See säte kehtib SMB-jagamise sisule. DFS-i nimeruumi ABE (`dfsutil property abe enable \\TEST.LOCAL\Tudengid`) on vaja ainult siis, kui tahad peita nimeruumi kaustu endid, näiteks Tudengitele kausta. Selles juhendis seda ei tehta.

## 8. Kaardista võrgukettad GPO-ga

Kettad kaardistatakse Group Policy Preferences osa **Drive Maps** abil. GPO lingitakse OU-ga, kus asuvad tudengite kasutajakontod. Item-level targeting piirab kettad grupi Tudengid liikmetele. Kaks kaardistust:

| Ketas | Silt | Tee | Kellele |
| --- | --- | --- | --- |
| H: | Minu kaust | `\\TEST.LOCAL\Tudengid\Tudengitele\Kodukaustad\%LogonUser%` | Grupp Tudengid |
| T: | Tudengite ühine | `\\TEST.LOCAL\Tudengid\Tudengitele` | Grupp Tudengid |

%LogonUser% on Group Policy Preferences muutuja. Klientarvutis asendub see sisseloginud kasutaja nimega, näiteks mari.maasikas. Nii piisab kõigi tudengite jaoks ühest kaardistusest.

> **Kontrolli enne, kus kasutajakontod asuvad.** Kasutaja seadetega GPO rakendub ainult nendele kasutajatele, kelle konto on lingitud OU-s või selle alam-OU-s. Grupi liikmesus ei tähenda, et konto asub samas OU-s. Kontrolli: `Get-ADUser mari.maasikas | Select-Object DistinguishedName`. Kui kontod asuvad mujal, lingi GPO sellele OU-le.

### 8.1 Loo ja lingi GPO

1. Ava Server Manager > Tools > Group Policy Management.
2. Ava Forest > Domains > TEST.LOCAL. Tee OU-l **KASUTAJAD** paremklõps > Create a GPO in this domain, and Link it here.
3. Name: **Tudengid\_Kettad**. Vali OK.

PowerShelli alternatiiv GPO loomiseks ja linkimiseks:

```powershell
New-GPO -Name "Tudengid_Kettad" |
    New-GPLink -Target "OU=KASUTAJAD,DC=TEST,DC=LOCAL"
```

Drive Maps sätteid PowerShelli GroupPolicy moodul seadistada ei võimalda. Kaardistused tee graafilises liideses.

### 8.2 Lisa ketas H: (isiklik kaust)

1. Tee GPO-l Tudengid\_Kettad paremklõps > Edit.
2. Ava **User Configuration > Preferences > Windows Settings > Drive Maps**.
3. Tee paremklõps > New > Mapped Drive.
4. Vahelehel General:
   - Action: **Update**. See loob ketta, kui seda pole, ja uuendab olemasolevat.
   - Location: `\\TEST.LOCAL\Tudengid\Tudengitele\Kodukaustad\%LogonUser%`. Muutujate nimekirja saad väljal klahviga F3.
   - Märgi Reconnect. Label as: **Minu kaust**.
   - Drive Letter: Use **H**.
   - Hide/Show this drive ja Hide/Show all drives: jäta No change.
5. Vahelehel Common märgi **Item-level targeting** ja vali Targeting.
6. Vali New Item > **Security Group**. Group: **TEST\\Tudengid**. Jäta valituks User in group. Vali OK.
7. Vali OK. Ketas H: ilmub Drive Maps nimekirja.

### 8.3 Lisa ketas T: (ühine kaust)

Korda samme 8.2 punktidest 3–7 järgmiste väärtustega:

- Action: Update
- Location: `\\TEST.LOCAL\Tudengid\Tudengitele`
- Reconnect märgitud, Label as: **Tudengite ühine**
- Drive Letter: Use **T**
- Item-level targeting: Security Group TEST\\Tudengid

> **Miks DFS-tee, mitte \\AD1?** Kui hiljem lisad kaustale teise sihi või kolid andmed teise serverisse, ei pea GPO-d muutma. Kliendid järgivad nimeruumi suunamist automaatselt.

> **Alternatiiv ilma GPO-ta.** ADUC-s kasutaja Properties > Profile > Home folder: Connect **H:** To `\\TEST.LOCAL\Tudengid\Tudengitele\Kodukaustad\%username%`. ADUC loob kausta ise ja annab kasutajale Full control õiguse. Kvoot rakendub automaatselt, sest kaust tekib kausta Kodukaustad alla. Puudus: säte tuleb määrata igale kasutajale eraldi ja Full control on vajalikust laiem. Seepärast kasutab see juhend GPO-d.

## 9. Testi kliendiarvutis

Testi päris tudengi kontoga, mitte administraatorina. Administraatoril on Full control ja ta näeb kõiki kaustu, mis peidab vale ACL-i.

### 9.1 Kas GPO rakendus ja kettad tekkisid

Logi domeeniga liidetud kliendiarvutisse sisse kontoga mari.maasikas. Ava käsuviip:

```powershell
gpupdate /force
gpresult /r /scope user
net use
```

Pärast `gpupdate /force` logi välja ja uuesti sisse, sest kettad kaardistatakse kindlalt sisselogimisel. `gpresult` väljundis peab Applied Group Policy Objects all olema **Tudengid\_Kettad**. `net use` peab näitama kettaid H: ja T:.

Ava File Explorer > This PC:

- **Minu kaust (H:)** näitab mahuna 500 MB. FSRM esitab kõva kvoodi piiri kliendile ketta suurusena.
- **Tudengite ühine (T:)** avab ühise kausta. Kaustas Kodukaustad on näha ainult mari.maasikas kaust.

### 9.2 Kas kvoot töötab

Proovi luua kvoodist suurem fail. Käivita tudengi PowerShellis:

```powershell
# 600 MB - peab ebaõnnestuma
$f = [System.IO.File]::Create("H:\test_600MB.bin"); $f.SetLength(600MB); $f.Close()

# 450 MB - peab õnnestuma ja ületama 85% hoiatuspiiri
$f = [System.IO.File]::Create("H:\test_450MB.bin"); $f.SetLength(450MB); $f.Close()
```

Esimene käsk peab andma vea teatega, et kettal pole piisavalt ruumi. Teine peab õnnestuma. Kui käsud ei sobi, kopeeri H:-kettale lihtsalt suur fail, näiteks ISO-tõmmis. Lõpuks kustuta testfailid.

AD1-s kontrolli kasutust ja hoiatust sündmuste logis:

```powershell
Get-FsrmQuota -Path "F:\DFS_Tudengitele\Kodukaustad\mari.maasikas" |
    Select-Object Path, @{n='Limiit MB';e={$_.Size/1MB}}, @{n='Kasutus MB';e={[math]::Round($_.Usage/1MB,1)}}
Get-WinEvent -LogName Application -MaxEvents 50 |
    Where-Object ProviderName -eq "SRMSVC" |
    Select-Object TimeCreated, Id, Message
```

FSRM kirjutab kvoodihoiatused Application logisse allikaga SRMSVC. Event Vieweris: Windows Logs > Application, filtreeri allika SRMSVC järgi.

### 9.3 Kas võõras kaust on suletud

1. Proovi avada tudengina `\\TEST.LOCAL\Tudengid\Tudengitele\Kodukaustad\jaan.tamm`. Tulemus peab olema Access denied.
2. Logi sisse kontoga, mis ei kuulu gruppi Tudengid. Kettaid H: ja T: tekkida ei tohi.

## 10. Veaotsing

| Sümptom | Kontrolli / lahendus |
| --- | --- |
| New Share viisardis on Advanced profiil hall | FSRM pole paigaldatud. Paigalda FS-Resource-Manager (peatükk 3), vajuta Server Manageris Refresh ja ava viisard uuesti. |
| Kasutaja kaustal puudub kvoot | Kaust loodi enne automaatset kvooti. Ava FSRM-is Auto Apply kvoot > Edit Quota Properties ja kinnita, et kvoot rakendataks ka olemasolevatele kaustadele. Kontrolli, et kaust asub otse kaustas Kodukaustad. |
| Kasutaja saab kirjutada üle 500 MB | Kontrolli `Get-FsrmQuota`, et SoftLimit on False. Administraatorina kirjutamisel kvoot samuti kehtib, aga testi alati tudengi kontoga. |
| Ketast H: ega T: ei teki | Kontrolli `gpresult /r /scope user`. Kas GPO on lingitud OU-ga, kus kasutaja konto asub? Kas kasutaja kuulub gruppi Tudengid? Logi välja ja uuesti sisse. Vigade korral vaata kliendi Application logi, allikas Group Policy Drive Maps (sündmus 4098). |
| H: tekib, kuid avamisel tuleb viga „path not found“ | Kausta nimi ei vasta kasutajanimele. Võrdle `$env:USERNAME` väärtust kausta nimega kaustas Kodukaustad. |
| H:-kettale ei saa salvestada | Jagamisõigus on Read. Muuda DFS\_Tudengitele jagamise õigus Change'iks (peatükk 2). Kontrolli ka kasutaja Modify-õigust: `icacls`. |
| Tudeng näeb teiste kaustu | ABE pole sisse lülitatud (peatükk 7) või Kodukaustad pärib ülemkausta õigused. Kontrolli `icacls F:\DFS_Tudengitele\Kodukaustad`. |
| Kvoodihoiatusi logis pole | Kontrolli mallis lävendite Event Log tegevust. `-RunLimitInterval` takistab sama hoiatuse kordumist 60 minuti jooksul. |

## 11. Esitamise kontrollnimekiri

- [ ] AD1: FSRM on paigaldatud (`Get-WindowsFeature FS-Resource-Manager`).
- [ ] F:\\DFS\_Tudengitele\\Kodukaustad on olemas ja õiguste pärimine on katkestatud.
- [ ] Kvoodimall Tudeng 500 MB: 500 MB, Hard, lävendid 85% ja 100%.
- [ ] Automaatne kvoot kaustal F:\\DFS\_Tudengitele\\Kodukaustad kasutab malli Tudeng 500 MB.
- [ ] Igal grupi Tudengid liikmel on oma kaust, millel on kasutaja Modify-õigus ja 500 MB kvoot.
- [ ] Jagamisel DFS\_Tudengitele on Access-Based Enumeration sisse lülitatud.
- [ ] GPO Tudengid\_Kettad on lingitud OU-ga KASUTAJAD ja sisaldab kaardistusi H: ja T:.
- [ ] Tudengi kontoga tekivad H: (500 MB) ja T:, üle 500 MB faili salvestada ei saa.
- [ ] Tudeng ei näe ega ava teiste tudengite kaustu. Grupivälisel kontol kettaid ei teki.

## Allikad

- [DFS juhend Windows Server 2022 jaoks](https://github.com/valdonolvak/Windows-serveri-haldus/blob/main/Windows%20Serveri%20haldus%20-%20II%20aasta/DFS/DFS_juhend_Windows_Server_2022.md), eelmine juhend, mille keskkonda see juhend jätkab
- [Microsoft Learn: Quota Management](https://learn.microsoft.com/en-us/windows-server/storage/fsrm/quota-management)
- [Microsoft Learn: Create an Auto Apply Quota](https://learn.microsoft.com/en-us/windows-server/storage/fsrm/create-auto-apply-quota)
- [Microsoft Learn: New-FsrmAutoQuota](<https://learn.microsoft.com/en-us/previous-versions/windows/powershell-scripting/jj900649(v=wps.630)>)
- [Microsoft Learn: New-FsrmQuota](<https://learn.microsoft.com/en-us/previous-versions/windows/powershell-scripting/jj900591(v=wps.630)>)
- [Microsoft Learn: Group Policy Preferences](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/group-policy/group-policy-preferences)
- [Microsoft AskDS: Using Group Policy Preferences to map drives based on group membership](https://learn.microsoft.com/en-us/archive/blogs/askds/using-group-policy-preferences-to-map-drives-based-on-group-membership)
- [Microsoft Learn: Access-Based Enumeration nimeruumis](https://learn.microsoft.com/en-us/windows-server/storage/dfs-namespaces/enable-access-based-enumeration-on-a-namespace)
