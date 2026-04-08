Jah — **sinu sise-domeeni `minuleht.perenimi.local` HTTPS-i jaoks ei ole CA Web Enrollment vajalik**. Microsofti järgi on CA Web Enrollment lihtsalt **brauseripõhine** sertifikaaditellimise viis; see sobib eriti siis, kui tahad teha käsitsi interaktiivseid taotlusi või töötada stand-alone CA-ga. Enterprise CA saab sertifikaaditaotlusi vastu võtta ka **Certificates MMC snap-in’i** või **PowerShelli `Get-Certificate` cmdleti** kaudu, seega võib Web Enrollmenti täiesti välja jätta. ([Microsoft Learn][1])

Allpool ongi **ainult ilma Web Enrollmentita juhend**. 

**NB! Vali kas Powershell või GUI (Graphical User Interface) - kui alguses Powershelliga paigaldada, siis GUI vaates on asi tehtud. Seega vali üks kahest meetodist, mis moodi sa seda teha soovid.
**
---

# 1) Paigalda AD CS ainult Certification Authority rolliga

## PowerShell

```powershell
Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools
```

## GUI - Graphical User Interface ehk graafiline kasutajaliides

Server Manager → Add Roles and Features → Active Directory Certificate Services → märgi ainult **Certification Authority**.

<img width="642" height="462" alt="image" src="https://github.com/user-attachments/assets/c769b6d9-a2a3-4307-be36-014b34a240df" />


**Miks see vajalik on:** Certification Authority on see teenus, mis **allkirjastab ja väljastab** sinu sisevõrgu sertifikaadid. Kui sinu eesmärk on lihtsalt oma domeeni saitidele usaldatud HTTPS, siis sellest rollist piisab. Web Enrollment lisab ainult veebipõhise taotluslehe, mitte sertifikaadi väljastamise põhifunktsiooni. ([Microsoft Learn][1])

---

# 2) Konfigureeri CA Enterprise Root CA-ks

## PowerShell

```powershell
Install-AdcsCertificationAuthority `
  -CAType EnterpriseRootCA `
  -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
  -KeyLength 2048 `
  -HashAlgorithmName SHA256 `
  -ValidityPeriod Years `
  -ValidityPeriodUnits 5
```

## GUI
Peale CA paigaldust tuleb sul lõpetada selle seadistamine (vt. pilti allpool)<br>
<p><img width="202" height="97" alt="image" src="https://github.com/user-attachments/assets/8ac4cf68-bfa6-44c3-be10-c509760b014c" /></p>

<p>Viisard siis alljärgnev:<br>
<img width="625" height="463" alt="image" src="https://github.com/user-attachments/assets/6b96e115-74c9-49bc-b2cc-4e44adcdf0ff" />
</p>

**Enterprise CA**<br>
<img width="625" height="463" alt="image" src="https://github.com/user-attachments/assets/f331d1c3-3555-4931-beb1-542f7fc0cb74" />

 **Root CA**<br>
<img width="625" height="463" alt="image" src="https://github.com/user-attachments/assets/637c2d3e-f865-4297-81bd-2517a110c05d" />

**Create a new private key**<br>
<img width="625" height="463" alt="image" src="https://github.com/user-attachments/assets/e16daa42-a78a-4b8c-9650-96b60c10debf" />
<img width="625" height="463" alt="image" src="https://github.com/user-attachments/assets/e3ef7e40-0ccb-4f2b-8ff5-6cc27fa3bc08" />
CA Name jätate nagu teil seal pakutakse (vt allpool)<br>
<img width="625" height="463" alt="image" src="https://github.com/user-attachments/assets/4425fa5d-71ee-4c8a-9c69-cda6d4d78445" />

<img width="625" height="463" alt="image" src="https://github.com/user-attachments/assets/8f62cacd-23c2-4b66-84ae-6cfdb48a3302" />

Confirmation aknas on näha siis vaikimisi väärtusi. Kui kõik sobib, siis vajutada **Configure**:<br>
<img width="625" height="463" alt="image" src="https://github.com/user-attachments/assets/49f86008-42b0-4020-8155-4b2a94f6c365" />

Configure AD CS wizard:

* **Enterprise CA**
* **Root CA**
* **Create a new private key**
* RSA **2048**
* SHA256
* kehtivus näiteks **5 aastat**

**Miks see vajalik on:** Enterprise CA töötab Active Directoryga koos ja võimaldab sertifikaadimallide kasutamist ning nende levitamist kogu domeenis. Microsofti dokumentatsiooni järgi on sertifikaadimallid enterprise CA keskkonnas AD-s talletatud ning uued mallid replitseeruvad domeenikontrolleritesse. ([Microsoft Learn][2])

---

# 3) Veendu, et CA saab väljastada serverisertifikaate

Kui kasutad vaikimalli, siis piisab tavaliselt **Web Server** või **SslWebServer** mallist. Kui vaja, loo sellest koopia ja kohanda.

## GUI

Server Manager aknas Tools->Certificate Authority valides saad valida sertifikaatide malle, mille alusel enda uus sertifikaat teha.
Ennem uue sertifikaadi tegemist on soovitatav teha duplikaat juba olemasolevast **Web Server** mallist kuna soovime enda veebilehele HTTPS'i sertifikaati.

Selleks siis avanevas aknas, kui oled aktiivseks teinud kausta "Certificate Templates", siis vajutad paremas aknas tühja ala peal (vt allolevat pilti) ja valid valiku **Manage**</br>
<img width="625" height="483" alt="image" src="https://github.com/user-attachments/assets/3028bcb1-e206-4694-9dc4-5cdfa27713f8" />

**Manage** valides avaneb allolev aken ning otsid sealt üles sertifikaadi malli nimega **Web server** ja parema hiireklikiga valid **Duplicate template**:
<img width="625" height="330" alt="image" src="https://github.com/user-attachments/assets/e5a13a53-b1c5-4393-b821-8f6af3d7ca92" />

Seejärel avanevas aknas annad uuele mallile nime aknas **General** ning määrad ära ka selle kestvuse (Valid period)
Meie näites anname nimeks Veebileht-GPO ning kestvuseks 5 aastat ja 6 kuud (vt allpool olevat pilti)</br>

<img width="330" height="334" alt="image" src="https://github.com/user-attachments/assets/d3e30ffb-345f-404b-8969-cbef5004fce5" /></br>

Vahelehel **Request Handling** paneme linnukese, et lubame vajadusel ka privaatvõtit eksportida (üldiselt ei ole see hea praktika, aga testimiskeskkonnas või sõltuvalt orgnisatsioonist, võib vahel see vajalik olla)</br>
<img width="330" height="455" alt="image" src="https://github.com/user-attachments/assets/891e2ade-5668-4a5f-b955-7b8077929d37" />

Samuti on vaja lisada vahekaardil **Security** kasutajagrupile **Authenticated Users** **Enroll** õigus (vt allpool olevalt pildilt)</br>
<img width="435" height="608" alt="image" src="https://github.com/user-attachments/assets/e3cacdb7-26c9-4183-9c40-a51f2556e159" />

Seejärel vajutame **OK** nuple.

Peale seda on meil võimalik nüüd taodelda uut sertfikaati nende vaikeväärtustega, mis me tegime.
Selleks siis vajutame aknas **Certificate Authority** paremal pool aknas hiire paremale klahvile 
Certification Authority → **Certificate Templates** → **New** → **Certificate Template to Issue** → vali serveri mall.</br>
<img width="625" height="433" alt="image" src="https://github.com/user-attachments/assets/b00a8bb5-bf3e-472e-a332-4b3ce9253759" />

Uues aknas on meil nüüd olemas selle uue sertifikaadi mall (meie näite puhul on selleks sertifikaadi malli nimeks **Veebileht-GPO**)</br>
<img width="480" height="306" alt="image" src="https://github.com/user-attachments/assets/c4b0815b-ac46-4f12-900d-570c0ef8e1c6" />

Valime selle ja vajutame **OK** nuple

Nüüd on meil sertifikaatide mallide loendis ka meie loodud mall nimega **Veebileht-GPO**</br>
<img width="625" height="300" alt="image" src="https://github.com/user-attachments/assets/77664122-a7f6-46bf-8321-b02218f8b705" />


**Miks see vajalik on:** CA ei väljastada mingit sertifikaati juhuslikult, vaid ainult neid, mille mall on talle välja antud. Microsofti järgi tuleb CA-le template “issue’iks” lisada, et ta saaks selle alusel sertifikaate väljastada. ([Microsoft Learn][2])

---

# 4) Küsi IIS-i serverile veebisertifikaat

## PowerShell

```powershell
Get-Certificate `
  -Template "WebServer" `
  -DnsName "minuleht.perenimi.local" `
  -CertStoreLocation "cert:\LocalMachine\My"
```

## GUI

`certlm.msc` → Personal → Certificates → **Request New Certificate** → vali **Web Server** → pane nimeks `minuleht.perenimi.local`.
<img width="850" height="353" alt="image" src="https://github.com/user-attachments/assets/e71ee0df-4f2f-43b6-8f3d-e6bd92fa2d09" />


**Miks see vajalik on:** sertifikaat peab vastama sellele nimele, mida brauser kasutab. `Get-Certificate` suudab taotluse saata enrollment serverisse ning väljastatud sertifikaadi kohe masinapoodi paigaldada. ([Microsoft Learn][3])

---

# 5) Seo sertifikaat IIS saidiga HTTPS bindingus

## GUI

IIS Manager → sinu sait → **Bindings…** → Add:

* Type: **https**
* Port: **443**
* Hostname: `minuleht.perenimi.local`
* SSL certificate: vali just saadud sertifikaat

## PowerShell

```powershell
Import-Module WebAdministration

New-WebBinding -Name "minuleht" -Protocol https -Port 443 -HostHeader "minuleht.perenimi.local"
```

**Miks see vajalik on:** IIS valib sissetuleva päringu järgi õige saidi ja sertifikaadi hostinime ning pordi alusel. SNI lubab sama IP ja pordi peal mitut HTTPS saiti, kui neid vaja peaks olema. ([Microsoft Learn][4])

---

# 6) Ekspordi CA juursertifikaat

## PowerShell

```cmd
certutil -ca.cert C:\temp\rootCA.cer
```

**Miks see vajalik on:** klient ei pea usaldama serverisertifikaati otse; ta peab usaldama CA-d, mis selle allkirjastas. Selleks on vaja CA juursertifikaat kliendile kätte toimetada. ([Microsoft Learn][5])

---

# 7) Jaga CA usaldus kliendimasinatele GPO kaudu

## GUI

Group Policy Management → uus GPO näiteks `Trust-Internal-CA` → Edit:

`Computer Configuration → Policies → Windows Settings → Security Settings → Public Key Policies → Trusted Root Certification Authorities → Import`

Impordi sinna `rootCA.cer`.

**Miks see vajalik on:** Microsofti järgi saab Active Directory domeenis usaldatavaid root-sertifikaate Windowsi seadmetele jagada **Group Policy** kaudu. GPO tuleb siduda domeeni, saidi või OU-ga, kus vastavad arvutid asuvad. ([Microsoft Learn][5])

---

# 8) Seo GPO õigesse OU-sse või domeenile

## GUI

Group Policy Management → linki GPO domeenile või sellele OU-le, kus klientarvutid asuvad.

**Miks see vajalik on:** GPO toimib ainult nendele objektidele, millega ta on seotud. Kui linki pole, ei jõua usaldusjuur klientideni. ([Microsoft Learn][5])

---

# 9) Rakenda poliitika kliendis

## CMD

```cmd
gpupdate /force
```

## Kontroll

`certlm.msc` → **Trusted Root Certification Authorities**

**Miks see vajalik on:** pärast poliitika uuendamist peab CA juursertifikaat olema kliendi masinapoes, muidu brauser ei usalda HTTPS ühendust. ([Microsoft Learn][5])

---

# 10) Testi lehte

Ava kliendis:

```text
https://minuleht.perenimi.local
```

**Miks see vajalik on:** kui DNS, sertifikaadi nimi, IIS binding ja GPO usaldus on õiged, avaneb sait ilma sertifikaadiveata. IIS kontrollib päringus hostinime ja kasutab sobivat sertifikaati; brauser kontrollib omakorda usaldusahelat. ([Microsoft Learn][4])

---

## Kokkuvõte

**Web Enrollmenti võib julgelt välja jätta**, kui eesmärk on oma domeenis olevate saitide jaoks CA-st sertifikaate väljastada ja usaldus GPO kaudu klientidele levitada. See teeb lahenduse lihtsamaks: **CA + sertifikaadimall + GPO + IIS HTTPS binding** on kogu vajalik ahel. Web Enrollment on lisamugavus käsitsi brauseripõhiseks taotlemiseks, mitte nõue sisevõrgu HTTPS jaoks. ([Microsoft Learn][1])

[1]: https://learn.microsoft.com/en-us/windows-server/identity/ad-cs/certificate-authority-web-enrollment "Certification Authority Web Enrollment | Microsoft Learn"
[2]: https://learn.microsoft.com/en-us/windows-server/identity/ad-cs/manage-certificate-templates "Manage certificate templates in Windows Server | Microsoft Learn"
[3]: https://learn.microsoft.com/en-us/powershell/module/pki/get-certificate?view=windowsserver2025-ps "Get-Certificate (pki) | Microsoft Learn"
[4]: https://learn.microsoft.com/en-us/iis/configuration/system.applicationhost/sites/site/bindings/binding "Binding &lt;binding&gt; | Microsoft Learn"
[5]: https://learn.microsoft.com/en-us/windows-server/identity/ad-cs/distribute-certificates-group-policy "Distribute certificates to Windows devices by using Group Policy | Microsoft Learn"
