Õppematerjal kausta ümbersuunamise (Folder Redirection) seadistamiseks Windowsi domeenis, tuginedes Woshub-i juhendile https://woshub.com/enable-folder-redirection-with-gpo/.

---

# ÕPPEMATERJAL: Folder Redirection seadistamine Group Policy (GPO) abil

## 1. Sissejuhatus

**Folder Redirection** (kausta ümbersuunamine) võimaldab kasutaja profiili kaustad (nt *Desktop, Documents, Pictures*) salvestada lokaalse arvuti asemel failiserveri jagatud võrgukausta.

**Peamised eelised:**

* **Andmete turvalisus:** Kasutaja failidest tehakse varukoopiaid tsentraalselt serveris.
* **Mobiilsus:** Kasutaja failid on kättesaadavad igast domeeni arvutist, kuhu ta sisse logib.
* **Kiirus:** Võrreldes *Roaming Profiles* lahendusega on sisselogimine kiirem, sest andmeid ei kopeerita iga kord edasi-tagasi.

---

## 2. Etapp: Failiserveri ja õiguste ettevalmistamine

Enne poliitika loomist peab serveris olema koht, kuhu andmed salvestatakse.

### 2.1. Loo turvagrupp

Loo Active Directorys grupp OU KASUTAJAD alla (nt `RedirectFolders`), kuhu kuuluvad kasutajad, kellele ümbersuunamist rakendatakse.

### 2.2. Loo jagatud kaust (Shared Folder)

1. Loo serveris kaust (nt `F:\RedirFolder`).
2. Jaga see võrgus: **Advanced Sharing** -> **Permissions** -> Anna *Authenticated Users* grupile **Full Control**.

### 2.3. Seadista NTFS õigused (Kriitiline samm!)

See tagab, et kasutajad pääsevad ligi ainult enda failidele.

1. Vali kausta Properties -> **Security** -> **Advanced**.
2. **Disable Inheritance** (lülita pärilus välja) ja vali "Convert...".
3. Eemalda tavakasutajad (*Users*) ja veendu, et jääksid:
* **SYSTEM** – Full Control
* **Administrators** – Full Control
* **CREATOR OWNER** – Full Control (ainult alamkaustadele)
<img width="370" height="382" alt="image" src="https://github.com/user-attachments/assets/4b257c24-19b7-4301-ae0d-ac3b6650e51e" />


4. Lisa oma loodud grupp (`RedirectFolders`) ja anna neile õigus **"This folder only"**: *List folder, Read attributes, Create folders*.

> **Ekraanitõmmis viide:** Vaata artiklist jaotist *"create shared folder for redirected user's profiles"*, kus on näha täpsed linnukesed NTFS õiguste tabelis.
<img width="500" height="303" alt="image" src="https://github.com/user-attachments/assets/b365e75c-6b2a-4858-acac-ee2dc3d9bd3e" />

---
Määra **Full Control** õigused grupile **Authenticated Users** võrgujagamise seadetes (**Sharing** –> **Advanced Sharing** -> **Permissions**).

<img width="250" height="250" alt="image" src="https://github.com/user-attachments/assets/fb9f7872-b435-4dd4-ae56-275a44e9180e" />

---

## 3. Etapp: Group Policy seadistamine

1. Ava **Group Policy Management** (`gpmc.msc`).
2. Loo uus GPO (nt `KaustadeYmbersuunamine`) ja lingi see vastava OU-ga.
3. **Security Filtering:** Eemalda *Authenticated Users* ja lisa oma grupp `RedirectFolders`.

### 3.1. Poliitika muutmine (Edit GPO)

Liigu: **User Configuration** -> **Policies** -> **Windows Settings** -> **Folder Redirection**.

**Näide: Documents kausta suunamine:**

1. Paremklõps **Documents** -> **Properties**.
2. **Setting:** Vali *Basic – Redirect everyone’s folder to the same location*.
3. **Target folder location:** *Create a folder for each user under the root path*.
4. **Root Path:** Sisesta serveri tee, nt `\\AD1\RedirFoler`.

> **Ekraanitõmmis viide:** Otsi artiklist pilti *"Enable user Folder Redirection in Windows via GPO"*. See näitab, kuidas Root Path peab välja nägema.
<img width="450" height="344" alt="image" src="https://github.com/user-attachments/assets/8e812b3c-8f57-4a9f-adba-2b458555d333" />

---

## 4. Etapp: Seaded (Settings) vahekaart

Olulised valikud **Settings** saki all:

* **Grant the user exclusive rights:** Kui see on märgitud, on ainult kasutajal juurdepääs. Kui soovid, et administraatorid ka faile näeksid, võta linnuke ära (eeldusel, et seadistasid NTFS õigused 2. etapis õigesti).
* **Move the contents of Documents to the new location:** Soovitatav sisse lülitada, et kasutaja praegused failid liiguksid automaatselt serverisse.

---

## 5. Kontrollimine

1. Logi kasutaja arvutisse sisse.
2. Tee Documents kaustal paremklõps -> **Properties** -> **Location**.
3. Seal peaks olema kirjas serveri võrgutee (nt `\\AD1\RedirFoler\kasutajanimi\Documents`).

> **Ekraanitõmmis viide:** Vaata artikli lõpus olevat pilti *"Deploy Folder Redirection in Windows 11"*, mis kinnitab, et asukoht on muutunud võrguteeks.

---

### Oluline nõuanne: "Trusted Sites"

Et vältida turvahoiatusi (Windows Security Warning) failide avamisel serverist, lisa failiserver GPO abil **Local Intranet** tsooni:

* ***Computer Configuration -> Administrative Templates -> Windows Components -> Internet Explorer -> Internet Control Panel -> Security Page -> Site to Zone Assignment List***.
* Väärtus: `\\serveri-nimi` ja Zone: `1`.

---

*See materjal on mõeldud süsteemiadministraatoritele kasutajaandmete tsentraliseerimiseks.*
