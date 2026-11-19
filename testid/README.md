# Terminoloogia testid (peatükk 2)

Kaks viisi peatüki 2 termineid harjutada ja kontrollida.

## 1. Interaktiivne test (iseseisvaks harjutamiseks)

[`peatykid/02-terminoloogia-test.html`](../peatykid/02-terminoloogia-test.html) — avaneb brauseris, töötab võrguühenduseta.

- Valib **100 termini pangast juhuslikult 25 küsimust** (muudetav), juhuslikus järjekorras.
- Iga küsimus: antakse selgitus, vali õige termin neljast variandist. Kohene tagasiside + näide.
- **Iga testikord = uus juhuslik komplekt.** Täpselt see, mida õpilane vajab kordamiseks.
- Eksitajad valitakse eelistatult samast teemast (usutavamad valikud).
- Lisaks „Sõnastik"-vaade kõigi terminite sirvimiseks ja otsimiseks.

Õpilased pääsevad ligi GitHub Pages lehena või faili otse avades.

## 2. Google Forms test (hindamiseks / vastuste kogumiseks)

[`terminoloogia-google-forms.gs`](terminoloogia-google-forms.gs) — Google Apps Script, mis **genereerib** automaatselt hinnatava Google Formsi quizi.

### Miks skript, mitte valmis Form?

Google Forms **ei oska ise** vastaja kohta juhuslikult valida 25 küsimust 100-st — ta oskab ainult **segada kõigi küsimuste järjekorda** (ja näitab siis kõiki). Juhusliku *alamhulga* valik tuleb teha genereerimisel. Seda skript teebki: iga käivitus loob uue vormi, kuhu on pangast juhuslikult valitud 25 küsimust.

### Kasutamine

1. Ava <https://script.google.com> → **New project**.
2. Kleebi `terminoloogia-google-forms.gs` sisu `Code.gs`-i (asenda kogu sisu).
3. Vali funktsioon **`looTerminoloogiaTest`** → **Run**. Esimesel korral küsib Google luba (**Authorize**) → luba.
4. **Execution log** näitab vormi lingid: *Muutmine* (Edit) ja *Täitmine* (Published).

Skript seab vormi quiz-režiimi (1 punkt küsimuse eest, õige vastus märgitud → automaatne hindamine), kogub vastaja e-posti ja segab 25 küsimuse järjekorra iga vastaja jaoks.

### „Igale kasutajale ja igale korrale eraldi 25"

Üks genereeritud vorm = üks juhuslik 25 komplekt; järjekord seguneb vastaja kaupa, aga **küsimuste hulk on kõigil sama**. Kui tahad, et komplekt ka *erineks*:

- **Iga eksami/tunni jaoks uus vorm** — käivita `looTerminoloogiaTest` uuesti, saad uue juhusliku 25. Lihtne ja praktiline.
- **Mitu paralleelvarianti** — käivita paar korda, jaga õpilaste vahel variandid A/B/C.
- **Tõeline „iga katse uus"** — selleks sobib ülalkirjeldatud interaktiivne HTML-test, mis valib iga avamise/kordamise peale uue 25. Forms seda vastaja kohta ei suuda.

### Häälestus

Skripti ülaosas:
- `KYSIMUSI` — mitu küsimust vormi (vaikimisi 25).
- `SEGA_JARJEKORD_VASTAJALE` — kas Forms segab küsimuste järjekorra iga vastaja jaoks (vaikimisi `true`).
- `form.setCollectEmail(true)` — eemalda rida, kui e-posti koguda ei taha.

Terminipank (`PANK`) on skripti sees ja pärineb samast allikast kui HTML-test, nii et küsimused kattuvad.
