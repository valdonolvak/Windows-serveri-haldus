# WDS: Windowsi tööjaama tõmmise (capture image) tegemine ja paigaldamine klientidele

Õpijuhis Windows Server 2022 + WDS keskkonnale. Eesmärk: võtta valmisseadistatud Windowsi tööjaamast (näidisarvutist) tõmmisfail (.wim), laadida see WDS-serverisse ja paigaldada see hiljem teistele klientidele üle võrgu (PXE).

## 1. Üldpilt: kuidas see töötab

Protsess koosneb viiest etapist:

1. **Näidisarvuti ettevalmistus**: paigaldad Windowsi, uuendused ja vajaliku tarkvara.
2. **Sysprep**: eemaldad arvutispetsiifilise info (SID, arvuti nimi jm), et tõmmist saaks mitmele arvutile paigaldada.
3. **Capture-tõmmise loomine WDS-is**: see on spetsiaalne käivitustõmmis, mis käivitab näidisarvutis tõmmise tegemise viisardi.
4. **Tõmmise tegemine**: näidisarvuti käivitatakse PXE kaudu capture-tõmmisest, viisard teeb C: kettast .wim-faili ja laeb selle serverisse.
5. **Paigaldamine**: kliendid käivitatakse PXE kaudu, valivad paigaldustõmmise ja Windows paigaldatakse.

Terminid, mida selles juhises kasutatakse:

| Termin | Tähendus |
| --- | --- |
| Käivitustõmmis (boot image) | Väike WinPE-tõmmis, mille klient PXE kaudu laadib ja mis käivitab paigaldusviisardi |
| Paigaldustõmmis (install image) | Täielik Windowsi tõmmis (.wim), mida kliendile paigaldatakse |
| Capture-tõmmis (capture image) | Spetsiaalne käivitustõmmis, mis teeb näidisarvutist paigaldustõmmise |
| Tõmmiste grupp (image group) | Kaust WDS-is paigaldustõmmiste jaoks, grupeerib neid ja hoiab kokku ruumi |

## 2. Eeldused

- WDS-i roll on Windows Server 2022 peal paigaldatud ja **konfigureeritud** (Configure Server on tehtud, RemoteInstall kaust olemas, soovitavalt eraldi NTFS-kettal, mitte C: peal).
- Serveris on olemas vähemalt üks käivitustõmmis (boot.wim) ja üks paigaldustõmmis. Võta paigaldustõmmis Windows 11 meediast ja käivitustõmmis Windows 10 meediast, mõlemad kaustast `sources` (`boot.wim` ja `install.wim`).
- DHCP töötab ja kliendid jõuavad PXE kaudu WDS-serverini (sama võrk või DHCP relay/IP helper).
- Näidisarvuti ja kliendid on **sama käivitusrežiimiga**: UEFI tõmmis paigaldatakse UEFI arvutisse, BIOS tõmmis BIOS-arvutisse. Segamini minnes paigaldus ei käivitu.
- Kontol, millega serverisse tõmmist laed, on WDS-i halduse õigused (nt Domain Admins või WDS Administrators).

**Proxmoxi labori märkused:**

- Näidisarvuti VM-is kasuta võrgukaardina **Intel E1000**. VirtIO kaardi draiver puudub standardses boot.wim-is ja PXE-käivitus tõmmisesse ei jõua, kui draiverit ei lisa.
- Windows 11 nõuab TPM 2.0 ja Secure Booti. Lisa VM-ile **OVMF (UEFI)** BIOS, **EFI disk** ja **TPM state** (v2.0). Kui klient-VM-is neid pole, ütleb Windows 11 paigaldusviisard, et arvuti ei vasta nõuetele.
- Võta enne sysprepi Proxmoxis **snapshot**. Pärast sysprepi on süsteem üldistatud ja seda enam hästi muuta ei saa.

## 3. Näidisarvuti ettevalmistus

1. Paigalda Windows 11 puhtalt. Soovitatav on **mitte** liita arvutit domeeni, vaid jätta see töörühma (WORKGROUP). Domeeni liitmine tõmmises tekitab hiljem probleeme.
2. Paigalda kõik Windowsi uuendused ja taaskäivita, kuni uuendusi enam ei tule.
3. Paigalda vajalik tarkvara (nt Office, brauser, PDF-lugeja, kooli/ettevõtte rakendused) ja seadista vaikesätted.
4. Eemalda mittevajalikud rakendused. **Microsoft Store'i rakendused võivad sysprepi katki teha**: kui mõni rakendus on ühe kasutaja jaoks uuendatud, aga mitte kõigile, siis sysprep ebaõnnestub. Kui kasutad ainult kohalikku administraatori kontot ja Store'i ei kasuta, on risk väike.
5. Puhasta ajutised failid (Disk Cleanup, `C:\Windows\Temp`, ajutiste profiilide kaustad).
6. Veendu, et kettal on piisavalt vaba ruumi: tõmmise tegemisel luuakse .wim-fail kohalikku kettale ja sinna on vaja vähemalt sama palju ruumi, kui on kasutatud ruumi C: kettal.

## 4. Sysprep

> **Hoiatus: sysprepi tohib käivitada ainult näidisarvutis (kliendi Windowsis), mitte WDS-serveris ega üheski teises serveris.** Sysprep eemaldab arvuti SID-i, domeeniliikmelisuse ja muu arvutispetsiifilise info ning lülitab arvuti välja. Serveril rikub see seadistuse: rollid (nt AD, DNS, DHCP, WDS) võivad lakata töötamast ja server tuleb hiljem uuesti seadistada või paigaldada. Enne käsu käivitamist kontrolli käsurealt käsuga `hostname`, et oled kindlasti näidisarvutis, mitte serveris.

Ava käsurida administraatorina ja käivita:

```
C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
```

Sätete tähendus:

- `/generalize` eemaldab arvutispetsiifilise info (SID, seadmedraiverid jm), et tõmmist saaks paigaldada erinevale riistvarale.
- `/oobe` paneb Windowsi järgmisel käivitusel käivituma esmakäivituse viisardiga.
- `/shutdown` lülitab arvuti pärast sysprepi välja. **Ära käivita arvutit enam Windowsi sisse!** Kui see käivitub Windowsi, tuleb sysprep uuesti teha.

Kui sysprep annab veateate, vaata logi: `C:\Windows\System32\Sysprep\Panther\setuperr.log`. Tavalisim põhjus on Store'i rakendus (Appx pakett), mis pole kõigile kasutajatele paigaldatud.

## 5. Capture-tõmmise loomine WDS-is

See tehakse **WDS-serveris**.

1. Ava **Windows Deployment Services** konsool (Server Manager → Tools → Windows Deployment Services).
2. Laienda serveri nimi ja vali **Boot Images**.
3. Kui Boot Images all pole veel ühtegi käivitustõmmist, lisa see: paremklõps **Boot Images** → **Add Boot Image** → vali `boot.wim` Windows 10 meedia `sources` kaustast.
4. Paremklõps käivitustõmmisel (nt *Microsoft Windows Setup (x64)*) → **Create Capture Image...**
5. Täida viisard:
   - **Image Name**: nt `Capture Win11 x64`
   - **Image Description**: lühike kirjeldus
   - **Location and File Name**: kuhu capture-fail salvestatakse, nt `D:\RemoteInstall\Boot\x64\Images\capture.wim`
6. Vajuta **Next** ja oota, kuni tõmmis on loodud.
7. Viisardi lõpus märgi **Add image to the Windows Deployment Server now** ja vajuta **Finish**. Kui seda linnukest ei olnud, lisa fail käsitsi: paremklõps **Boot Images** → **Add Boot Image** → vali loodud `capture.wim`.
8. Kontrolli, et **Boot Images** all on nüüd nii tavaline käivitustõmmis kui ka capture-tõmmis.

**Soovitus:** loo capture-tõmmis alati **Windows 10 meedia boot.wim-ist** (Windows 10), sest see töötab ilma muudatusteta. Windows 11 boot.wim kontrollib paigaldusel arvuti nõudeid (TPM 2.0, Secure Boot) ja vajab seetõttu eriti virtuaalmasinas lisamuudatusi. Windows 10 boot.wim ei takista Windows 11 paigaldustõmmise paigaldamist, sest käivitustõmmis ja paigaldustõmmis võivad olla eri versioonidest.

## 6. Paigaldustõmmiste grupi ja jagatud kausta loomine

Tõmmise üleslaadimisel peab olema grupp, kuhu see paigutatakse.

1. Paremklõps **Install Images** → **Add Image Group...**
2. Anna grupile nimi (nt `Windows 11 Tööjaamad`) ja vajuta **OK**.

**Jagatud kaust tõmmise üleslaadimiseks**

Laboris tee serverisse kaust, mis on jagatud kõigile kirjutusõigusega. Ilma selleta võib tõmmise üleslaadimine võrku ebaõnnestuda.

1. Tee serveris kaust, nt `D:\Tõmmised`.
2. Ava kausta **Properties** → **Sharing** → **Advanced Sharing**, märgi **Share this folder** ja anna jagatud nimeks nt `tõmmised`.
3. Vajuta **Permissions**, lisa **Everyone** ja anna talle **Change** õigus (vajadusel **Full Control**).
4. Lisa kaardil **Security** kasutaja **Everyone** ja anna talle **Modify** õigus.
5. Kontrolli teisest arvutist, et `\\\\server\\tõmmised` avaneb ja sinna saab faili kirjutada.

Jagamise saab luua ka PowerShellis (NTFS-õigused tuleb lisada eraldi kaardil **Security**):

```
New-Item -Path D:\Tõmmised -ItemType Directory
New-SmbShare -Name tõmmised -Path D:\Tõmmised -FullAccess Everyone
```

> **Hoiatus:** Everyone õigus sobib ainult laborisse või õppekeskkonda. Päris keskkonnas kasuta kitsamat gruppi (nt WDS-i administraatorid) ja eemalda jagamine, kui seda enam vaja pole.

## 7. Tõmmise tegemine näidisarvutist

1. Veendu, et sysprepitud näidisarvuti on välja lülitatud. Käivita see ja vajuta PXE-käivituse klahvi (tavaliselt **F12**, Proxmoxis **Esc** → võrgukaart, või jälgi ekraanil olevat teksti). Kui sul on UEFI, võib olla vaja valida *UEFI PXE IPv4*.
2. Vajuta nõudmisel **F12** (*Press F12 for network service boot*).
3. WDS-i käivitusmenüüs vali **capture-tõmmis** (nt *Capture Win11 x64*).
4. Avaneb **Windows Deployment Services Image Capture Wizard**. Vajuta **Next**.
5. **Directory to Capture**: vali rippmenüüst ketas (tavaliselt `C:\`). Kui rippmenüü on tühi, polnud arvuti korralikult sysprepitud, tee sysprep uuesti.
6. Täida:
   - **Image name**: nt `Windows 11 Pro Tööjaam v1`
   - **Image description**: mis tarkvara on peal, kuupäev
7. **Image capture destination**:
   - **Name and location**: kohalik tee, kuhu .wim-fail kirjutatakse, nt `C:\w11-tool.wim`. Tee peab olema NTFS-kettal ja seal peab olema piisavalt vaba ruumi.
   - Märgi **Upload image to WDS server**.
   - **WDS Server**: sisesta serveri nimi või IP ja vajuta **Connect**. Küsitakse kasutajanime ja parooli: kasuta WDS-i haldusõigustega kontot.
   - **Image Group**: vali eelnevalt loodud grupp.
8. Vajuta **Finish**. Algab tõmmise tegemine, mis võib võtta mitu kuni kümneid minuteid, sõltuvalt tõmmise suurusest. Viisard esmalt teeb tõmmise kohalikku .wim-faili ja seejärel laeb selle serverisse.
9. Kui viisard näitab teadet „Image captured successfully“, vajuta **Close**. Arvuti taaskäivitub.

**Märkus üleslaadimise kohta:** WDS laeb tõmmise serverisse jagatud kausta `REMINST` kaudu (see tekib WDS-i seadistamisel automaatselt), seega töötab see tavaliselt ka ilma eraldi jagatud kaustata. Laboris on kindlam teha ära jaotises 6 kirjeldatud jagatud kaust. Kui üleslaadimine ebaõnnestub (nt õiguste veaga), kontrolli järgmist:

- Kasutajal, kelle andmed **Connect** juures sisestasid, on WDS-i halduse õigused ja kirjutusõigus kaustale `RemoteInstall` (nii NTFS-i kui jagamise tasemel).
- Jagatud kaust `REMINST` on serveris olemas (`Get-SmbShare`) ja serveri tulemüür lubab SMB (TCP 445).
- Kui miski ei aita, ära märgi **Upload image to WDS server**, salvesta tõmmis näidisarvutis kohalikku .wim-faili ja lisa see hiljem käsitsi (vt jaotis 8). Teine võimalus: tee serveris eraldi jagatud kaust (nt `\\server\tõmmised`), anna sinna kirjutusõigus (laboris sobib Everyone või Authenticated Users, päris keskkonnas kitsam grupp), salvesta .wim sinna ja lisa see WDS-i käsuga **Add Install Image**.

## 8. Kontroll WDS-serveris

1. WDS-konsoolis ava **Install Images** ja seal oma grupp. Seal peaks olema uus tõmmis.
2. Paremklõps tõmmisel → **Properties**. Kontrolli nime, kirjeldust ja veendu, et tõmmis on **Enabled** (lubatud).
3. Vajadusel saad siin tõmmisele määrata ka **unattended** vastusfaili (WSIM-is tehtud `.xml`), vt eraldi õppematerjali unattended-paigaldusest.

Kui upload ebaõnnestus (nt võrguviga), jääb .wim-fail näidisarvuti kettale alles. Saad selle hiljem WDS-i käsitsi lisada: paremklõps grupil → **Add Install Image...** → vali fail.

## 9. Tõmmise paigaldamine klientidele

1. Käivita kliendiarvuti PXE kaudu (F12).
2. Vali WDS-i käivitusmenüüs tavaline käivitustõmmis **Microsoft Windows Setup (x64)** (mitte capture-tõmmis!).
3. Vali keel ja klaviatuur, sisesta WDS-i kasutaja andmed.
4. Vali paigaldustõmmis (see, mille just tegid).
5. Vali ketas ja paigalda. Pärast paigaldust läbib Windows esmakäivituse viisardi (OOBE), kuna tõmmis oli sysprepitud.
6. Arvuti nime ja domeeni liitmise saad tõmmisele automaatselt määrata unattended vastusfailiga või teha käsitsi.

## 10. Tüüpilised probleemid

| Probleem | Põhjus ja lahendus |
| --- | --- |
| Capture-viisardis pole ühtegi ketast | Arvuti pole sysprepitud või sysprep pole lõpule jõudnud. Tee sysprep uuesti. |
| Sysprep annab vea | Vaata `setuperr.log`. Sageli on põhjuseks Store'i rakendus, mis on ühele kasutajale uuendatud. Eemalda rakendus PowerShelliga (`Get-AppxPackage`, `Remove-AppxPackage`). |
| PXE-käivitus ei jõua WDS-ini | Kontrolli DHCP-d, VLAN-i, DHCP relay'd ja WDS-i PXE vastamise sätteid. |
| VM ei näe boot.wim-is kettaid | Storage-kontrolleri draiver puudub. Kasuta Proxmoxis SATA/SCSI (LSI), või lisa VirtIO draiverid boot.wim-i. |
| Windows 11 paigaldus ütleb, et arvuti ei vasta nõuetele | VM-il puudub TPM 2.0 või Secure Boot. Lisa vTPM ja UEFI või kasuta käivitustõmmisena Windows 10 boot.wim-i. |
| Capture-tõmmis ei käivitu | Käivitusrežiim (UEFI/BIOS) või arhitektuur ei klapi tõmmisega. |
| Üleslaadimine katkes | Failis on tõmmis alles kohalikul kettal. Lisa see käsitsi (vt jaotis 8). |
| Üleslaadimine serverisse ebaõnnestub (õiguste viga) | Kontrolli REMINST jagamist, kasutaja õigusi ja SMB-d (vt märkus jaotises 7). Vajadusel salvesta .wim kohalikku või eraldi jagatud kausta ja lisa WDS-i käsitsi. |

## 11. Kiirülevaade

1. Näidisarvuti valmis → **sysprep /generalize /oobe /shutdown**
2. WDS: **Boot Images → Create Capture Image** → lisa serverisse
3. WDS: **Install Images → Add Image Group**
4. Näidisarvuti PXE kaudu capture-tõmmisest → viisard → üleslaadimine gruppi
5. WDS: kontrolli tõmmist, vajadusel lisa unattended vastusfail
6. Kliendid PXE kaudu → tavaline käivitustõmmis → paigaldustõmmis
