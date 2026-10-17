# IIS, PHP, MySQL ja WordPressi paigaldusjuhend Windows Serveris

## Sisukord
- [IIS rolli paigaldus](#iis-rolli-paigaldus)
- [Microsoft Visual C++ käivituskeskkond](#microsoft-visual-c-käivitus-keskkond)
- [PHP paigaldus](#php-paigaldus)
- [MySQL/MariaDB paigaldus](#mysqlmariadb-paigaldus)
- [Andmebaasi loomine](#andmebaasi-loomine)
- [WordPressi paigaldus](#wordpressi-paigaldus)
- [Veebisaidi loomine](#veebisaidi-loomine)
- [SSL sertifikaat](#ssl-sertifikaat)
- [DNS kirje loomine](#dns-kirje-loomine)
- [SQL andmebaasis kirjete parandamine](#sql-andmebaasis-kirjete-parandamine)

---

## IIS rolli paigaldus

1. Käivitame **Server Manager** haldustööriista. Valime menüüst `Manage -> Add Roles And Features`. Valime serveri, millele soovime IIS-i rolli paigaldada.
2. Valime menüüst rolli **Web Server (IIS)**. Avaneb paigaldusviisard. 
3. Kindlasti jätame märgituks märkeruudu *Include management tools (if applicable)* ja vajutame **Add Features** ja seejärel **Next**. 
4. Järgnevalt avanevas *Features* dialoogiaknas vajutame **Next**. Samuti vajutame **Next** ka sellele järgnevas dialoogiaknas *Web Server Role (IIS)*.
5. Järgnevalt avanevas dialoogiaknas *Role Services* märgime lisaks juba vaikimisi märgitud valikutele ära valiku `Web Server -> Application Development -> CGI` ja vajutame **Next**.
6. Järnevalt avaneb kinnitusaken. Seal vajutame lihtsalt **Install**, pärast mida algab rolli paigaldamine ja võime juba akna sulgeda vajutades **Close**.

Kui roll on paigaldatud, tekib Server Manageri juurde tööriist **Internet Information Services (IIS) Manager**. Nagu kõiki teisi sealseid tööriistu, saab seda avada ka Start menüüst või otsingut kasutades. Avame selle.

Navigeerime IIS Manageris oma serverile ja valime saitide alt vaikimisi veebisaidi nimega **Default Web Site**. Vajutame parempoolses menüüs *Browse Website* all `Browse *:80 (http)`. Seepeale avaneb brauseris IIS veebisaidi vaikimisi avaleht.

> **Märkus:** Vaikimisi asukohaks IIS serveris asuvatel veebilehtedel on `C:\inetpub\wwwroot`

Kui vaikimisi veebileht avanes ilusti, siis keelame selle nüüd ära. Teeme IIS manageris oma **Default Web Site** peal hiire parempoolse nupuga kliki ja valime avanenud menüüs `Manage Website -> Stop`.

> **NB!** Vaikimisi ei ole IIS-il vaikimisi dokumentide all kirjas `index.php` faili. Lisame selle sinna. Vajutame IIS Manageris oma serveri peale ja seejärel avame **Default Document** menüü. Kui `index.php` puudub, siis saame selle siit lisada vajutades **Add**.

---

## Microsoft Visual C++ käivitus keskkond

Selleks, et Windowsi masinas PHP-d (ja paljusid muid rakendusi) jooksutada, tuleb kõigepealt paigaldada ka Visual C++ käivituskeskkond. Sageli on see teil juba olemas, kui olete masinat kasutanud mõnda aega, kuid kui tegu on uue masinaga, siis ei pruugi seda olla. 

Selle saab alla laadida Microsofti lehelt aadressilt:  
[https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170#visual-studio-2015-2017-2019-and-2022](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170#visual-studio-2015-2017-2019-and-2022)

Laeme selle alla ja paigaldame.

---

## PHP paigaldus

Varasemalt sai paljusid lisavõimalusi IIS-ile paigaldada läbi *Web Platform Installer* rakenduse, kuid see ei toimi enam 2022. aasta lõpust. Seetõttu tuleb meil PHP alla laadida käsitsi. Leheküljelt [https://et.wordpress.org/about/requirements/](https://et.wordpress.org/about/requirements/) näeme, et WordPressile sobib PHP versioon alates 7.4.

1. Läheme PHP kodulehele [https://windows.php.net/download#php-8.3](https://windows.php.net/download#php-8.3) ja laeme alla Windowsi versiooni. WordPressile sobib **PHP x64 Non Thread Safe** versioon. 
2. Alla laaditud `.zip` fail tuleb kõigepealt lahti pakkida ja tekkinud kaust liigutada kuhugi loogilisse asukohta, kust me selle pärast IIS-ile kätte anname. Näiteks kaust `C:\PHP` sobib hästi.
3. Järgnevalt tuleb IIS-ile öelda, kus PHP asub. Selleks on vaja alla laadida IIS-i laiendus nimega **PHP Manager 2 For IIS 10**. Selle saab laadida alla aadressilt [https://github.com/phpmanager/phpmanager](https://github.com/phpmanager/phpmanager).
4. Laadime selle alla ja paigaldame. *(Tegelikult saab ka ilma selle laienduseta, kui luua käsitsi vajalik “handler mapping” reegel, kuid see laiendus on mugav ka PHP toimimise testimiseks.)*

Nüüd tekkis IIS Manageris valik **PHP Manager**. 

Avame PHP manageri ja valime **Register New PHP version**. Näitame ette teekonna, kus asub programm `php-cgi.exe`.

Kontrollime, et PHP töötab. Selleks avame IIS Manageris PHP Manageri laienduse ja vajutame **Check phpinfo()**. Valime oma saidi ja vajutame OK. Avaneb PHP diagnostika leht. 

> **NB!** Selleks, et kontroll õnnestuks, peab veebisait olema aktiivne! Kui PHP diagnostika leht ei avane, siis kontrollige kindlasti, et Visual C++ käivituskeskkond oleks paigaldatud!

---

## MySQL/MariaDB paigaldus

Laeme alla ja installime kas **MySQL** ([https://dev.mysql.com/downloads/installer/](https://dev.mysql.com/downloads/installer/)) või **MariaDB** ([https://mariadb.com/downloads/](https://mariadb.com/downloads/)) andmebaasiserveri. Mina panen näidiseks peale MariaDB.

Andmebaasi peakasutaja on `root`. Sellele kasutajale tuleks ka panna mingisugune parool. Vaikimisi port, millel andmebaasiserver päringuid vastu võtab, on `3306`. Kui vajutame install, paigaldatakse kogu selekteeritud tarkvara, tehakse vajalikud reeglid tulemüüri jne. Kui kõik on tehtud, siis jääb üle veel vajutada **Finish**.

---

## Andmebaasi loomine

Avame MySQL andmebaasikliendi ja kirjutame sisse logimiseks `root` parooli.

Loome WordPressile andmebaasi ja anname kasutajale vajalikud õigused. Mina panen andmebaasi nimeks `wordpress`, kasutajaks `wpuser` ja parooliks `Kala1234` aga pole eriti tähtis, mis parameetreid kasutate. Oluline on, et te samad parameetrid hiljem ka oma WordPressile kätte annaksite.

> **NB!** Päris saitide puhul muidugi ärge kasutage lihtsaid ja korduvaid paroole!!!

Sisestage kliendis järgmised käsud:

```sql
create database wordpress default character set utf8 collate utf8_unicode_ci;
grant all privileges on wordpress.* to wpuser@localhost identified by "Kala1234";
flush privileges; -- Et muudetud õigused jõustuksid.
exit; -- Väljume andmebaasiserverist
```

**Veel mõned kasulikud käsud:**
- `show databases;` - Näitab andmebaase, mis on meil serveris
- `show grants;` - Näitab õigusi, mis on parasjagu sisse loginud kasutajal
- `show grants for 'kasutajanimi'@'localhost';` - Näitab õigusi, mis on käsus viidatud kasutajal

---

## WordPressi paigaldus

1. WordPressi viimase versiooni paigaldusarhiivi saab alla laadida aadressilt [https://et.wordpress.org/download/](https://et.wordpress.org/download/)
2. Laeme selle alla ja pakime selle sisu lahti kausta `c:\inetpub\wwwroot\wordpress`
3. Nüüd avame tekstiredaktori Notepad administraatori õigustes ja võtame lahti faili `wp-config-sample.php`.
4. Kõigepealt muudame andmebaasi nime, kasutaja ja parooli vastavaks nendele parameetritele, mis me enne MySQL-is käsurealt tegime.
5. Järgnevalt otsime failis üles autentimisvõtmete osa.
6. Läheme aadressile [https://api.wordpress.org/secret-key/1.1/salt/](https://api.wordpress.org/secret-key/1.1/salt/), genereerime seal uued võtmed ja paneme oma faili olemasoleva osa asemele.
7. Salvestame faili uue nimega `wp-config.php`. **NB!** Enne valime kindlasti failitüübiks *All Files*.

---

## Veebisaidi loomine

1. Navigeerime IIS manageris oma serveris saitide juurde ja vajutame **Add Website**.
2. Paneme oma saidile mingi nime. WordPressi testimiseks ja paigaldamiseks üle HTTP ühenduse piisab esialgsetest seadistustest. Hiljem aktiveerime juba ka HTTPS ühenduse ja teeme saidile DNS kirje, aga praegu sobib nii. 
3. (Meid võidakse hoiatada, et samale aadressile on juba tehtud veebiserveris sidumine, aga see on vaikimisi sait, mis on meil juba välja lülitatud.)
4. Vajutame oma saidile ja seejärel lingile, mis avab saidi meil veebilehitsejas.
5. Paigaldame WordPressi brauseris avaneva juhendi abil ja veendume, et saame sisse logida.

---

## SSL sertifikaat

Serverile ise allkirjastatud SSL sertifikaadi loomine on lihtne. 

1. Avame IIS Manageris oma serveri. 
2. Seejärel võtame lahti **Server Certificates** ja valime **Create Self-Signed Certificate**.
3. Paneme oma sertifikaadile nime. (Näiteks "kalakala", või mõni muu teile sobiv nimi).
4. Nüüd läheme IIS manageris oma saidi peale. Valime **Bindings** ja vajutame **Add**.
5. Valime tüübiks `https`. Seejärel avaneb rohkem seadeid. 
6. `IP address` valime *All Unassigned* asemel oma serveri IP. Port las jääda `443`. 
7. Host name (hosti nimi) lahtrisse kirjutame nime, millega saame edaspidi oma domeenis selle masina poole pöörduda. (Näiteks `wordpress.rkoor.lan`).
8. Lõpuks selekteerime veel rippmenüüst sertifikaadi, mille me just eelmises sammus lõime, ja vajutame **OK**.

Kui `https` seadistus on tehtud, siis võib varasema `http` seadistuse eemaldada. Vajutame *Site Bindings* all `http` peale ja seejärel valime **Remove**.

---

## DNS kirje loomine

Kuigi me eelmises sammus lisasime oma WordPressi leheküljele seadistuste alt hostinime, siis tuleb see nüüd ka DNS serveris kirjeldada. 

1. Selleks avame **DNS Manageri** haldustööriista kas Server Manageri kaudu või otsingust. 
2. Vajutame oma serveri peale ja seejärel võtame lahti **Forward Lookup Zones** seadistused.
3. *Forward Lookup Zones* alt valime oma domeeni nime. 
4. Uue kirje loomiseks teeme hiire parempoolse nupuga kliki ja valime **New Host (A or AAAA)**.
5. Nime lahtrisse kirjutame näiteks `wordpress`. Saidi FQDN (ehk täielikult kvalifitseeruv domeeninimi) on seega `wordpress.rkoor.lan`. 
6. IP aadressiks kirjutame oma serveri IP aadressi (näiteks `10.0.70.2`). 
7. Kui kõik on tehtud, vajutame **Add Host**.

---

## SQL andmebaasis kirjete parandamine

Kuna me eelnevalt juba paigaldasime WordPressi lehe, siis nüüd tuleb peale DNS kirje tegemist ja saidile HTTPS ühenduse loomist ka andmebaasis ära muuta lehekülje aadressi kirjed. Kui me seda ei tee, siis on lehekülg katki, sest kõik lingid viitavad lehekülje vanale aadressile ja samuti ei kuvata pilte.

> **Märkus:** Kõigepealt tuleb lehekülge avades hoiatus ise signeeritud sertifikaadi kohta. Lisame selle erandi ja läheme edasi leheküljele.

Avame MySQL kliendi ja muudame saidi kirjed ära, vastavalt sellele, mis sai kirjutatud DNS serverisse A kirjesse. Selle tegemiseks on mitmeid meetodeid, millest saab ülevaate näiteks järgmisel lingil: [https://wordpress.org/support/article/changing-the-site-url/](https://wordpress.org/support/article/changing-the-site-url/)

Meie teeme muudatuse otse andmebaasis. Kui andmebaas on parooli all, siis kõigepealt sisestame selle ja seejärel kirjutame järgmised käsud (vastavalt oma saidi vanale ja uuele aadressile):

```sql
use wordpress;
update wp_options set option_value = "https://wordpress.rkoor.lan" where option_value = "http://localhost";
exit;
```

Kui käsk läks läbi, siis teavitatakse meid, et 2 kirjet muudeti.

Nüüd uuesti oma saidile siirdudes saame veenduda, et lingid töötavad ja URL on õige.
