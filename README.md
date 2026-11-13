# Ikkuna

Natiivi macOS 13+ -valikkorivisovellus: ikkunamanageri ja Hammerspoonin
`app_switcher.lua`-toimintoa vastaava oikean Commandin sovellus- ja ikkunavaihtaja.
Swift + AppKit, ilman ulkoisia kirjastoja tai Hammerspoon-riippuvuutta.

## Käännös ja käyttöönotto Macilla

Tarvitset Xcoden tai Xcode Command Line Toolsin ja Swift 5.9:n tai uudemman.

```sh
cd ~/.dotfiles/hammerspoon/Ikkuna
./scripts/install.sh
```

Skripti suorittaa testit, kääntää release-version, allekirjoittaa sen paikallisesti,
asentaa sovelluksen `~/Applications/Ikkuna.app`-polkuun ja avaa sen.
Päivityksessä käynnissä oleva Ikkuna suljetaan hallitusti vasta käännöksen ja
kopioinnin onnistuttua. Asennettu versio käynnistetään automaattisesti. Jos sovellus
ei sulkeudu 10 sekunnissa, asennus keskeytyy vaihtamatta sovelluspakettia.
Jos Command Line Tools puuttuu, asenna se komennolla `xcode-select --install`.
Sovelluksen voi pelkästään kääntää komennolla `./scripts/build.sh`.

1. Sulje Hammerspoon. Ikkuna odottaa sen sulkemista, jotta pikanäppäimet eivät kilpaile.
2. Salli **Ikkuna** kohdassa Järjestelmäasetukset → Tietosuoja ja suojaus → Käyttöapu.
3. Jos valikko ilmoittaa, ettei näppäinkuuntelu käynnisty, tarkista myös
   näppäimistön tarkkailuoikeudet valikon linkistä ja käynnistä Ikkuna uudelleen.
4. Valikkoriviltä voi keskeyttää pikanäppäimet, avata asetukset ja ottaa käyttöön
   käynnistyksen kirjautumisen yhteydessä.

Asennussijainnin voi vaihtaa: `IKKUNA_INSTALL_DIR=/Applications ./scripts/install.sh`.
### Käyttöapuoikeuden säilyttäminen käännösten välillä

Oletuksen ad hoc -allekirjoitus sitoo sovelluksen identiteetin yksittäiseen
käännökseen. Käytä pysyvää allekirjoitusvarmennetta, jotta macOS voi tunnistaa
uuden käännöksen samaksi sovellukseksi.

Listaa käytettävissä olevat varmenteet:

```sh
security find-identity -v -p codesigning
```

Jos varmennetta ei ole, avaa **Avainnipun käyttö (Keychain Access)** ja valitse
Certificate Assistant → Create a Certificate. Anna nimeksi `Ikkuna Local Development`,
Identity Type: **Self Signed Root**, Certificate Type: **Code Signing**.
Säilytä varmenne ja sen yksityinen avain kirjautumisavainnipussa. Jos varmenne ei
näy yllä olevassa listassa kelvollisena, avaa sen luottamusasetukset ja salli
sen käyttö koodin allekirjoittamiseen. Paikalliseen käyttöön ei tarvita maksullista
Apple Developer -jäsenyyttä. Myös olemassa oleva Apple Development / Developer ID
-varmenne käy.

Tallenna valittu varmenne kerran sen nimellä tai listan SHA-1-tunnisteella:

```sh
./scripts/setup-signing.sh 'Ikkuna Local Development'
./scripts/install.sh
```

Skripti tallentaa varmenteen tunnisteen tiedostoon
`~/Library/Application Support/Ikkuna/signing-identity`. Tavallinen
`./scripts/install.sh` käyttää jatkossa samaa varmennetta. Puuttuva tai vanhentunut
varmenne pysäyttää allekirjoituksen; ad hoc -allekirjoitukseen ei palata hiljaisesti.
`SIGNING_IDENTITY`-ympäristömuuttuja ohittaa tallennetun asetuksen yksittäisessä
käännöksessä. `IKKUNA_SIGNING_CONFIG_DIR` voi vaihtaa asetustiedoston hakemiston.

Myönnä käyttöapuoikeus ensimmäisen uudella varmenteella allekirjoitetun asennuksen
jälkeen vielä kerran. Jos vanha lupa ei toimi, poista vanha Ikkuna-rivi
käyttöapuasetuksista ja lisää asennettu sovellus uudelleen. Käynnistä jatkossa
sovellus samasta asennuspolusta ja säilytä sama varmenne. Varmennetta vaihdettaessa
tai macOS:n nollatessa oikeudet lupa voidaan joutua myöntämään uudelleen.

Paluu vanhaan toteutukseen: lopeta Ikkuna valikkoriviltä ja käynnistä Hammerspoon.
Vanhoja Lua-tiedostoja tai niiden asetuksia ei muuteta.

## Pikanäppäimet

Hyper tarkoittaa yhdistelmää **⌃⌥⇧⌘**.
Nuolinäppäinten macOS:n lisäämä Fn-lippu ohitetaan pikanäppäinten vertailussa,
jotta esimerkiksi ⌃⌥ + ← / → tunnistetaan myös Fn-lipun sisältävistä tapahtumista.

| Näppäimet | Toiminto |
| --- | --- |
| ⌃⌥ + ← / → | Vasen / oikea puolikas |
| ⌃⌥ + U / I / J / K | Ylävasen / yläoikea / alavasen / alaoikea neljännes |
| ⌃⌥ + C | Keskelle, vuorotellen 50 % ja 75 % leveys toistuvilla painalluksilla |
| ⌃⌥ + Return | Suurenna |
| ⌃⌥ + Delete | Palauta suurennusta edeltävä koko |
| ⌃⌥ + 0 | Älykäs kahden palstan jako, ikkunat pinotaan palstoihin |
| ⌃⌥ + + / − | Kasvata / pienennä; pitkä painallus säätää jatkuvasti |
| ⇧⌃⌘ + + / − | Kasvata / pienennä korkeutta ja mukauta kiinni olevat naapurit; pohjassa pitäminen säätää jatkuvasti |
| ⇧⌃⌥ + + / − | Sama pystysuuntainen koonsäätö |
| ⌃⌥⇧ + ← / → | Täytä koko korkeus vapaaseen tilaan naapureiden välissä |
| ⌃⌥⇧ + U / I / J / K | Täytä ylä- tai alarivin vapaa tila |
| ⌥ + H / J / K / L | Vaihda ikkunaan vasemmalla / alhaalla / ylhäällä / oikealla |
| ⌃⌥⌘ + ← / → | Siirrä viereiselle näytölle suhteellinen koko ja paikka säilyttäen |
| Hyper + Tab | Vaihda seuraavan näytön päällimmäiseen ikkunaan |
| Hyper + M | Keskitä hiiri aktiiviseen ikkunaan |
| Hyper + J | Hae ikkuna ja yritä lisätä se nykyiseen Stage Manager -ryhmään |
| Hyper + S | Pakota paikalliset pikanäppäimet ruudunjaon / VM:n aikana |
| Hyper + R | Lataa asetukset uudelleen |
| Oikea ⌘ + kirjain tai numero | Vaihda käynnissä olevaan sovellukseen |
| Oikea ⌘ + oikea ⌥ + kirjain tai numero | Vaihda aktiivisen stagen ikkunaan otsikon alkukirjaimella |
| Oikea ⌘ + oikea ⌥ + Tab | Selaa aktiivisen stagen kaikki ikkunat |

Sovellusvaihtajan lista näkyy, kun oikea Command on pohjassa. Sama kirjain selaa
samalla kirjaimella alkavat sovellukset. Vain viimeinen vapautushetkellä aktiivinen
sovellus saa käyttöpisteen, ja usein valitut sovellukset näkyvät ensin.

Stage Managerissa ⌥ H/J/K/L säilyttää suuntanavigoinnin. Nykyisen ryhmän
päällekkäiset ikkunat ovat mukana. Jos suunnasta tai vastareunalta ei löydy
kohdetta, samalle akselille osuvat ryhmän ikkunat ovat valittavissa varavalinnalla.
Ikkunalistaa ei avata.

Hyper + J avaa hakukentän ja ikkunalistan. Viimeksi käytetty tarjolla oleva ikkuna
on valittuna. Haku kohdistuu sovelluksen nimeen ja ikkunan otsikkoon; nuolinäppäimet
vaihtavat valintaa, Enter lisää ja Esc sulkee. Historia kertyy Ikkunan käynnissä
ollessa 300 ms:n välein. Näkyvät ikkunat, pienennetyt ikkunat ja koko näytön ikkunat
jätetään pois. Listaa selaamalla ei aktivoida kohdeikkunaa.

**Stage Manager -liittäminen on kokeellinen ja vaatii käyttötestin Macilla.**
Toteutus etsii WindowManagerin käyttöapupuusta täsmälleen ikkunan otsikkoa vastaavan
yksiselitteisen kohteen, joka tarjoaa `AXAddToStage`-toiminnon, ja kutsuu sitä suoraan.
Jos otsikko ei vastaa, kohdetta haetaan sovelluksen yksiselitteisesti tunnistetun
CG-pienoiskuvan ja käyttöapupainikkeen päällekkäisen sijainnin perusteella.
Pelkkää sovelluksen prosessia käytetään tunnistamiseen vain, jos sillä on yksi
pienentämätön AX-ikkuna ja yksi näkyvä CG-kohde.
Toiminto on epävirallinen ja macOS-versiosta riippuva. Sivupalkin täytyy
olla näkyvissä. Samannimisiä tai tyhjäotsikkoisia ikkunoita ei käsitellä. macOS-version
käyttöapupuu tai ryhmitelty pienoiskuva voi estää tunnistamisen. Liittämisen jälkeen
tarkistetaan, että lähtö- ja kohdeikkuna näkyvät täysikokoisina; tämä ei yksin todista
ryhmän jäsenyyttä. Epäonnistuminen näkyy kuittaukseen asti virheikkunassa, jonka
Kopioi virhe -painikkeella saa tarkemmat hakutiedot talteen. Kohdetta ei aktivoida varakeinona.
Onnistuneen yrityksen jälkeen alkuperäinen ikkuna kohdistetaan uudelleen.

Ikkunavaihdin näyttää aktiivisen stagen kaikkien sovellusten ikkunat samalla näytöllä,
myös toistensa peittämät ikkunat. Pienennetyt ikkunat, muiden stagejen pienoiskuvat
ja muiden Spaces-työpöytien ikkunat jätetään pois. Ilman Stage Manageria lista
kattaa nykyisen työpöydän ikkunat samalla näytöllä.
Otsikon alkukirjain vaihtaa ikkunaan ja Tab selaa kaikki listan ikkunat.
Lista päivitetään uudelleen 200 ms:n jälkeen.
Vasen Command ja Commandin yhdistelmät Controlin, Shiftin tai Fn:n kanssa
säilyttävät tavallisen toimintansa. Jos kirjaimelle ei löydy kohdetta,
näppäin välitetään sovellukselle. Ikkunahaun yhteydessä tämä tapahtuu haun jälkeen.

## Asetukset

Asetukset luodaan ensimmäisellä käynnistyksellä tiedostoon
`~/Library/Application Support/Ikkuna/config.json`. Avaa se valikkoriviltä.
Vain muutettavat kentät tarvitsee määritellä; puuttuvat käyttävät oletuksia.
Virheellisiä asetuksia ei oteta käyttöön, ja virhe näytetään käyttäjälle.

```json
{
  "windowGap": 4,
  "stageManagerLeftInset": 160,
  "stageManagerRightInset": 360,
  "appKeys": { "com.apple.finder": "0", "Firefox": "b" },
  "ignoredApps": ["Finder"]
}
```

Sovellusnimet ja bundle ID:t eivät erottele kirjainkokoa. `appKeys` ohittaa
poissulkemisen, bundle ID ohittaa nimen ja määritelty näppäin varataan pois muiden
sovellusten oletusalkukirjaimilta. Samalle näppäimelle voi määritellä monta sovellusta.
`appKeys` ja `ignoredApps` korvaavat vastaavan oletuslistan kokonaan.

Hammerspoonin `local_config.lua` ei lataudu automaattisesti. Vastaavuudet ovat:

| Hammerspoon | Ikkuna |
| --- | --- |
| WINDOW_GAP | windowGap |
| STAGE_MANAGER_STRIP_WIDTH | stageManagerLeftInset |
| STAGE_MANAGER_RIGHT_INSET | stageManagerRightInset |
| RCMD_APP_KEYS | appKeys |
| RCMD_IGNORED_APPS | ignoredApps |

Muut kentät: `captureBundleIDs` (oletuksena Screen Sharing ja Parallelsin prosessit)
sekä `parallelsExcludedTitles` (`Control Center`, `Preferences`, `About Parallels`).
Näissä ikkunoissa pikanäppäimet jäävät paikallisiksi. Muiden VM-ikkunoiden sekä
ruudunjaon aikana ne välitetään eteenpäin. Parallelsin otsikkotarkistus tehdään
taustalla 300 ms välein. Sovelluksen vaihtuessa läpivienti huomioidaan heti;
Parallelsin sisäiseen ikkunanvaihtoon voi liittyä tämä tarkistusviive.

## Rakenne

| Moduuli | Vastuu |
| --- | --- |
| `IkkunaCore/Geometry.swift` | Ikkunaruudukot, peittyminen, suuntanavigointi, täyttö, näyttösiirrot ja koonsäädön suunnitelma |
| `IkkunaCore/AppRules.swift` | Vaihtajan näppäinvaraukset, poissulkeminen ja selaus |
| `Ikkuna/Accessibility.swift` | AX-kutsut, CG-ikkunalista, koordinaatistot ja Firefox-otsikot |
| `Ikkuna/WindowEngine.swift` | Ikkunakomennot, paluumuisti, suurennushistoria ja pitkä koonsäätö |
| `Ikkuna/Hotkeys.swift` | Näppäinkuuntelu, oikean/vasemman muokkausnäppäimen erottelu ja läpivienti |
| `Ikkuna/AppSwitcher.swift` | Sovellus- ja ikkunavaihtajan tila sekä tallentuvat käyttöpisteet |
| `Ikkuna/Overlay.swift` | Vaihtajalista ja tilaviestit, ilman kohdistuksen kaappaamista |
| `Ikkuna/Configuration.swift` | Validoidut asetukset ja atominen tilan tallennus |
| `Ikkuna/App.swift` | Valikkorivi, käyttöoikeudet, kirjautumiskäynnistys ja moduulien kytkentä |

Näistä ikkunageometria ja vaihtajan säännöt ovat erillinen Swift-kirjasto ilman
AppKit-riippuvuutta. Näppäinkuuntelija ei tee Accessibility-kutsuja. Ikkunoiden
käsittely tehdään yhdessä sarjallisessa työjonossa, ja CG-ikkunatiedot haetaan
suoraan prosessissa. Koonsäätö pitää osallistujat ja laskennalliset mitat muistissa,
säilyttää palstojen välit ja rajoittaa kutistuvien ikkunoiden leveyden 200 pisteeseen.
Sekä asettelukomennot että jatkuva koonsäätö poistavat sovelluksen
`AXEnhancedUserInterface`-tilan väliaikaisesti käytöstä animaation estämiseksi,
jos tila oli päällä. Tila palautetaan muutoksen jälkeen; Firefoxin otsikkohaku säilyy.
Koonsäätö päättyy näppäimen tai muokkausnäppäinten vapautuessa, keskeytyksessä,
nukkumaan mennessä tai näppäinkuuntelun häiriössä.

Stage Managerin kanssa toistuvat asettelut vuorottelevat varattua aluetta
kunnioittavan ja koko työalueen kattavan asettelun välillä. Ilman Stage Manageria
asettelut pysyvät samoina. Työpöytätilassa yli puoliksi muiden ikkunoiden alle
peittyneet ikkunat ohitetaan; peittävä pinta-ala lasketaan päällekkäisyyksiä
kahdesti laskematta. Stage Managerissa aktiivisen ryhmän päällekkäiset ikkunat
säilyvät navigoitavina.

## Testaus ja rajat

```sh
swift test
./scripts/build.sh
```

Geometrialle ja vaihtajan säännöille on 28 XCTest-testiä. Ne kattavat myös
negatiiviset näyttökoordinaatit, peittymisen, paluumuistin kulmarajan,
molempien palstojen yhteisen koonsäädön ja näppäinvarausten etusijajärjestyksen.
Macilla `build.sh` vaatii testien ja release-käännöksen onnistumisen ennen
sovelluspaketin tekemistä.

Toteutusympäristö on Linux ilman Swift-työkaluketjua ja macOS SDK:ta.
**Swift-käännöstä, XCTest-testejä ja macOS:n käyttötestejä ei ole ajettu tässä
ympäristössä.** Mukana olevat testit eivät yksin varmista macOS-integraatiota.
Ensimmäisellä Mac-käynnistyksellä tarkista erityisesti:

- Puolikkaat, neljännekset, suurennus ja palautus.
- Suuntavaihto, reunalta kierto ja vastakkaisen suunnan paluumuisti.
- Koonsäädön lyhyt ja pitkä painallus sekä vapautus kesken säädön.
- Oikean Commandin valikko, samaan alkukirjaimeen osuvat sovellukset ja mukautetut näppäimet.
- Nopea oikea Command + oikea Option + kirjain, Tab ja saman stagen eri sovellusten päällekkäiset ikkunat.
- Useat näytöt, Stage Manager, Spaces ja Parallelsin läpivienti.

Muiden sovellusten Accessibility-tuki ja niiden omat minimikoot rajoittavat
ikkunoiden ohjausta. Spaces-vaihdot riippuvat myös macOS:n Mission Control
-asetuksista. Suorituskykyeroa Hammerspooniin ei ole vielä mitattu.

CG-ikkunat ja AX-ikkunat yhdistetään omistajaprosessin ja geometrian perusteella,
käyttämättä yksityisiä ikkuna-ID-rajapintoja. Epäselvä kohde jätetään käsittelemättä.
Täsmälleen samankokoiset ja samassa kohdassa olevat saman sovelluksen ikkunat
voivat siksi jäädä suuntanavigoinnin tai yhteiskoonsäädön ulkopuolelle;
otsikkoperusteinen `app_switcher` käyttää suoraan AX-ikkunoita.
Stage Managerin pienoiskuvat hylätään, jos niiden CG-mitat eivät vastaa AX-mittoja.
Animaation aikana oikeakin ikkuna voi hetkellisesti jäädä haun ulkopuolelle.

Lokit löytyvät Console-sovelluksesta alijärjestelmällä `fi.iiro.Ikkuna`:

```sh
log stream --predicate 'subsystem == "fi.iiro.Ikkuna"' --level debug
```

Tämä versio sisältää ikkunamanagerin ja `app_switcher`-toiminnon.
Pomodoro, tallennettavat layoutit, Parallelsin erilliset ohjauskomennot sekä
rcmd:n HTTP/WebSocket-palvelin eivät kuulu tähän versioon.

## Muistissa oleva diagnostiikkaloki

Valikkorivin **Diagnostiikkaloki…** avaa päivittyvän lokin, jonka voi kopioida
tai tyhjentää. Viimeiset 300 merkintää säilytetään vain prosessin muistissa;
sovelluksen lopettaminen tai päivittäminen tyhjentää lokin.

Koonsäädöstä tallennetaan suunta, kasvatus/pienennys, näyttöalue, osallistujien
ikkuna-ID:t ja prosessit, alkuperäiset mitat, pyydetyt ja toteutuneet mitat,
AX-kutsujen onnistuminen sekä mittojen poikkeamat. Ikkunoiden otsikoita ei
sisällytetä koonsäädön merkintöihin. Aikaleima on sekunteja koneen käynnistyksestä.
Toteutuneen koon lukeminen voi osua sovelluksen viivästettyyn päivitykseen;
yksittäinen poikkeama ei siksi vielä todista minimikokorajoitusta.

Toista koonsäätöongelma ja avaa sen jälkeen loki ennen uudelleenkäynnistystä.
Valitse **Kopioi loki** ja liitä teksti virheraporttiin. Koonsäätö asettaa koon uudelleen sijainnin siirron jälkeen ja tarkistaa koko
ryhmän toteutuneet mitat. Jos sovellus ei hyväksy mittoja, säätö keskeytetään ja
edellinen asettelu yritetään palauttaa kaikille osallistujille. Palautusyritykset
ja niiden onnistuminen näkyvät lokissa.
