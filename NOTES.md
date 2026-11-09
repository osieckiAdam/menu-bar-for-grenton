# Menu Bar for Grenton — uwagi do biblioteki grenton-core-swift

Menu Bar for Grenton to pierwszy test biblioteki z perspektywy jej użytkownika (apka
paska menu macOS, `from: "0.14.0"`). Tu zbieram wszystko, co w bibliotece
okazało się niewygodne, niejasne lub brakujące. Apka niczego nie obchodzi
po cichu: każde tymczasowe obejście jest opisane poniżej, a naprawy idą
przez repo biblioteki (skill `grenton-change`).

Uwagi zebrane po dodaniu rolet (2026-11-06) są gotowe jako prompt dla
sesji w repo biblioteki: [docs/library-feedback-covers.md](docs/library-feedback-covers.md)
(A7 dla dwóch typów encji, echo rolet w symulacji, `moveUp`/`moveDown`).

Podział: **błąd** / **brak w API** / **niejasność w dokumentacji**.
Status: `otwarte` / `przyjęte` (uzgodniony kształt zmiany, czeka na bibliotekę) /
`w bibliotece` (naprawione w wersji X) / `odrzucone`.

---

## Brak w API

### A1. Interfejsu z .omp nie da się zachować przez `InterfaceStore` — w bibliotece (0.13.1)

- **Co:** `InterfaceStore.save(_:)` przyjmuje tylko archiwum ZIP z Object
  Managera (parsuje je przez `ProvisioningClient.parseInterfaceArchive`).
  `ProjectFile(data:).interface()` zwraca `MobileInterfaceDTO`, który nie
  jest `Encodable`, a `save` odrzuca bajty `.omp`. Import z pliku projektu
  — reklamowany w Getting Started jako równorzędna alternatywa — nie ma
  więc „jednego poprawnego miejsca" na klucz, które biblioteka daje
  archiwum.
- **Gdzie:** `Sources/GrentonKit/InterfaceStore.swift` (`save`, `load`,
  `interface`, `system`), `Sources/GrentonProvisioning/ProjectFile.swift`.
- **Skutek w apce:** po imporcie z .omp trzeba by przy każdym starcie
  ponownie wskazywać plik albo zapisywać klucz samodzielnie (czego
  dokumentacja słusznie zabrania).
- **Propozycja:** `InterfaceStore` przechowuje też projekt: np.
  `save(project: Data, interfaceId: String?)` (zapis bajtów .omp + id
  wybranego interfejsu, walidacja przez `ProjectFile`), a `interface()` /
  `system()` czytają to, co zapisano. Alternatywa: `MobileInterfaceDTO:
  Encodable` i `save(_ interface: MobileInterfaceDTO)`.
- **Obejście tymczasowe:** import z .omp działa tylko do końca sesji
  apki; trwale zapisywane są tylko archiwum .zip i pobranie z OM.
- **Decyzja (2026-10-26):** naprawiamy w bibliotece:
  `InterfaceStore.save(project:interfaceId:)` zapisuje bajty .omp i id
  wybranego interfejsu, a `interface()` / `system()` czytają to, co
  zapisano (archiwum albo projekt).
- **W apce (2026-11-06):** `AppModel.useProject(_:interfaceId:)` woła
  `store.save(project:interfaceId:)`; `isSessionOnly` i komunikat
  „niezapisany" zniknęły.

### A2. `entity.switchable` nie da się owinąć w `Observed` — w bibliotece (0.13.1)

- **Co:** `Observed<Entity: StatefulEntity>` jest generyczny, a
  `BoundEntity.switchable` zwraca `(any SwitchableEntity)?`.
  `SwitchableEntity` nie dziedziczy po `StatefulEntity`, a egzystencjał i
  tak nie spełnia ograniczenia generycznego. Dokumentowana ścieżka
  „światła = `entity.switchable`" + „wiersz obserwuj przez `Observed`"
  się nie składa.
- **Gdzie:** `Sources/GrentonDevices/Entities.swift` (`SwitchableEntity`,
  `BoundEntity.switchable`), `Sources/GrentonSwiftUI/Observed.swift`.
- **Obejście tymczasowe:** w apce enum z trzema przypadkami
  (`Observed<ToggleEntity>`, `Observed<DimmableLightEntity>`,
  `Observed<HsbLightEntity>`) budowany przez `switch` po `BoundEntity`
  z `@unknown default`. To dokładnie ten kod, który `switchable` miało
  oszczędzić.
- **Propozycja:** `SwitchableEntity: StatefulEntity` oraz sposób
  obserwacji egzystencjału — np. `Observed` z inicjalizatorem
  `init(_ entity: any StatefulEntity)` / wariant nie-generyczny
  `ObservedEntity` dla `BoundEntity`, albo `ObservedSwitch`
  (`isOn`, `setOn`) dla `any SwitchableEntity`.
- **Decyzja (2026-10-26):** `SwitchableEntity: StatefulEntity` plus
  wariant `Observed` dla egzystencjału (`any StatefulEntity`).
- **W apce (2026-11-06):** `LightItem` trzyma `entity: BoundEntity` i jeden
  `Observed<any SwitchableEntity>`; po typie rozróżnia tylko
  `DemoDriver.report` (surowa wartość) i filtr świateł (A6).

### A3. System nie udostępnia interfejsu ani sekcji stron — w bibliotece (0.13.1)

- **Co:** układ z myGrenton (strona → nagłówek sekcji → widgety) jest
  tylko w `MobileInterfaceDTO.pages[].items`. `GrentonSystem` (i
  `SimulatedGrentonSystem`) nie trzymają DTO, a `DeviceDescriptor.page`
  (`DevicePage`) ma tylko `index` i `name` — bez sekcji. Apka, która chce
  pokazać sekcje, musi trzymać DTO obok systemu i łączyć widgety
  z urządzeniami po `descriptor.id == widget.id`.
- **Gdzie:** `Sources/GrentonDevices/GrentonSystem.swift`,
  `Sources/GrentonDevices/Descriptors.swift` (`DevicePage`),
  `Sources/GrentonKit/InterfaceStore.swift`.
- **Skutek:** wygodne `InterfaceStore.system()` nie wystarcza — apka woła
  `store.interface()` i sama tworzy `GrentonSystem(interface:)`, żeby mieć
  DTO do nagłówków. Złączenie po id widgetu nie jest nigdzie opisane jako
  kontrakt (działa, bo `DeviceDescriptor.id` to „the widget id").
- **Propozycja:** sekcja w deskryptorze (np. `DeviceDescriptor.section:
  DeviceSection?` z `id`/`title` najbliższego nagłówka powyżej) albo
  `system.pages` / `layout` z kolejnością stron, sekcji i urządzeń.
- **Decyzja (2026-10-26):** najpierw spec 0.13.0 (§6.1):
  `DeviceDescriptor.section` = najbliższy nagłówek powyżej na tej samej
  stronie (`id`, `title`), kolejność jak w interfejsie.
- **W apce (2026-11-06):** `LightListBuilder.pages(devices:physicalObjects:)`
  grupuje po `descriptor.page` i `descriptor.section`, bez DTO. Apka nadal
  tworzy `GrentonSystem(interface:)` z `store.interface()` — tylko po
  nazwę interfejsu do nagłówka menu (`MobileInterfaceDTO.name`), której
  system nie wystawia. Drobiazg, nie zgłaszam osobno.

### A4. Brak strumienia zmian stanu połączenia — w bibliotece (0.13.1)

- **Co:** stan CLU jest dostępny tylko przez `diagnostics()` /
  `sessionStates()` (async, snapshot). Pasek statusu „CLU nie odpowiada"
  musi odpytywać w pętli; encje mają `updates()`, sesje nie.
- **Gdzie:** `Sources/GrentonDevices/GrentonSystem.swift`.
- **Obejście tymczasowe:** odpytywanie `diagnostics()` co kilka sekund,
  tylko gdy menu jest otwarte.
- **Propozycja:** `system.sessionStateUpdates()` (`AsyncStream` jak
  `updates()` encji: sygnał, stan czytany z `sessionStates()`), albo
  obserwowalny stan w `GrentonSwiftUI`.
- **Decyzja (2026-10-26):** `system.sessionStateUpdates()` — sygnał
  w stylu `updates()` encji, tylko w porcie (migawka §5.4.5 bez zmian).
- **W apce (2026-11-06):** `HomeModel.statusTask` subskrybuje
  `sessionStateUpdates()` przed `start()` i czyta `diagnostics()` po każdym
  sygnale; odpytywanie zniknęło.

### A5. `GrentonSimulation` w trybie demo apki — w bibliotece (0.13.1)

- **Co:** dokumentacja każe dodawać `GrentonSimulation` tylko do targetu
  testów. Apka potrzebuje też trybu demo / podglądów SwiftUI bez sieci —
  symulacja nadaje się do tego idealnie, brakuje tylko „echa" (komenda
  nie zmienia wartości, więc demo musi samo ustawiać stan po komendzie).
- **Gdzie:** `Sources/GrentonSimulation/SimulatedGrentonSystem.swift`,
  artykuł Testing Your App.
- **Obejście tymczasowe:** apka linkuje `GrentonSimulation` i po każdej
  komendzie ustawia wartość sama (`simulation.set`).
- **Propozycja:** dopuścić w dokumentacji użycie w podglądach / trybie
  demo; opcja `echoCommands: true`, która po komendzie on/off ustawia
  stan tak, jak zrobiłby to CLU.
- **Decyzja (2026-10-26):** dokumentacja dopuści podglądy / tryb demo.
  `echoCommands` tylko dla on/off (`turnOn`/`turnOff`/`setOn`) — dla
  termostatu czy rolety „jak zrobiłby CLU" byłoby zgadywaniem; echo musi
  mieć testy, żeby symulacja nie kłamała.
- **W apce (2026-11-06):** `SimulatedGrentonSystem(interface:echoesSwitches: true)`;
  `DemoDriver.echo` zniknęło, `report` zostało do stanu początkowego
  i „włącznika ściennego". Rolety w demo będą potrzebowały własnej
  symulacji ruchu (echo tylko dla on/off — zgodnie z decyzją).

### A6. Ikona widgetu ginie przy dekodowaniu — nie da się odróżnić światła od pompy — w bibliotece (0.14.0)

- **Co:** `entity.switchable` (a dokumentacja nazywa to „lights and
  switches") obejmuje każdy `ON_OFF`: lampy, ale też gniazdka, pompy,
  zawory, odkurzacz, grzanie i przełączniki wirtualne (np. blokady
  czujników). Jedyny sygnał „to jest światło" to ikona,
  którą Object Manager zapisuje w komponencie (`image`: `bulb`,
  `plafond`, `ceiling_lamp_7`, `wall_lamp_1`, … vs `valve`,
  `power_socket`, `vacuum_robot_4`, `floor_heating`). U autora
  ~100 komponentów `ON_OFF`, ~40 różnych ikon. Biblioteka odrzuca to pole
  już w DTO: `ButtonBistableComponentDTO` / `ButtonBistableV2ComponentDTO`
  nie mają `image` (choć `LedButtonComponentDTO` i komponenty rolet je
  mają), a `ToggleDescriptor` / `DimmableLightDescriptor` nie mają ikony.
- **Gdzie:** `Sources/GrentonModel/DTO/Components.swift`
  (komponenty bistabilne), `Sources/GrentonDevices/Descriptors.swift`
  (deskryptory encji), spec §3.5 (pola komponentów) i §6.1/§6.3.
- **Skutek w apce:** pierwszy żywy test pokazał jako światła m.in.
  zawór, pompę i całą stronę przełączników wirtualnych.
  Wymaganie „na start same światła" jest niewykonalne przez API.
- **Obejście tymczasowe:** brak — apka nadal pokazuje wszystko, co
  `switchable` (czytanie surowego `data.json` z archiwum byłoby
  powieleniem parsera biblioteki).
- **Propozycja:** (1) `image` w DTO komponentów bistabilnych
  i `icon: String?` w deskryptorach encji (ikona komponentu, a dla
  widgetów z ikoną na poziomie widgetu — ta), tak jak dziś robi to
  myGrenton; (2) do decyzji: czy klasyfikacja „ikona → światło" ma być
  w bibliotece (np. `ToggleDescriptor.appearsAsLight` albo
  `DeviceKind.light` dla `ON_OFF` z ikoną oświetlenia — reguła w spec),
  czy w apce (wtedy biblioteka daje tylko surową ikonę). Ściemniacze
  i `LED` są światłem zawsze.
- **Decyzja biblioteki (0.14.0):** surowa ikona (`BoundEntity.icon`,
  `DeviceDescriptor.icon`), klasyfikacja po stronie apki; Controlling
  Devices „Lights only" pokazuje filtr po fragmentach `lamp`, `bulb`,
  `plafond`, `light`.
- **W apce (2026-11-06):** `LightItem.isLight` przepuszczało `toggle` tylko
  z ikoną z listy z dokumentacji (`lamp`, `bulb`, `plafond`, `light`).
- **Na żywo (2026-11-08) ta reguła zawiodła.** W instalacji autora
  przełączniki `ON_OFF` mają 41 różnych ikon; 59 ma ikonę lampy, 42 nie.
  Wśród tych 42 mniej więcej połowa to światła: instalator dobierał ikonę
  po **miejscu** (kinkiety z ikoną `sofa`, `tv`, `bookcase`, `mirror`;
  sufity z `garden_table`, `door_1`, `personal_computer`; lampki schodowe
  ze `stairs`; „oświetlenie nocne” z `crescent_moon_1`; linia LED z `led`).
  Allowlista z artykułu „Lights only” ukryła je wszystkie; użytkownik
  zauważył brak świateł w salonie.
- **W apce (2026-11-08):** filtr odwrócony na **blocklistę**: przełącznik
  jest światłem, chyba że ikona jest jednoznacznie nieoświetleniowa
  (`LightItem.nonLightIcons`: `power_socket`, `socket`, `power`, `valve`,
  `floor_heating`, `ac`, `door`, `gate`, `garage`; prefiksy `vacuum_robot`,
  `pump`, `boiler`, `heating`). Pokazanie pompy jako światła jest tańsze
  niż ukrycie światła. Nazwy ikon są dopasowywane w całości, bo `door`
  to otwieranie bramy, a `door_1` to lampa przed wejściem.
- **Do biblioteki:** przykład w „Lights only” powinien ostrzegać, że ikona
  koduje miejsce równie często co typ, i pokazywać blocklistę zamiast
  allowlisty (zob. `docs/library-feedback-covers.md`, pkt 4).

### A7. Brak „wyślij i poczekaj na potwierdzenie z CLU" — otwarte

- **Co:** komenda zwraca, gdy CLU przyjął żądanie; nowy stan przychodzi
  osobnym raportem. Każdy klient, który chce wiedzieć, czy zmiana się
  udała, musi sam subskrybować `updates()` przed komendą i czekać
  z timeoutem. Przykład `switch-light` robi to pętlą odpytującą `isOn`
  co 200 ms przez 5 s; Menu Bar for Grenton — taskiem na `updates()` z timeoutem
  (`LightItem.setOn`, ~25 linii), dodatkowo przez `switch` po typie,
  bo `any SwitchableEntity` nie ma `updates()` (A2).
- **Gdzie:** `Sources/GrentonDevices/Entities.swift`,
  `Examples/switch-light/main.swift`.
- **Propozycja:** np. `SwitchableEntity.setOn(_:confirmingWithin:) async
  throws -> Bool` (subskrypcja przed wysłaniem, `true` gdy raport
  potwierdzi stan), albo ogólne `entity.waitUntil(timeout:_:)`. Przykład
  `switch-light` by się skrócił.

---

## Niejasność w dokumentacji

### D1. macOS: uśpienie, wybudzenie, apka paska menu — w bibliotece (0.13.1)

- „Running on Apple Platforms" opisuje cykl życia tylko dla iOS (tło /
  pierwszy plan). Brak wskazówek dla Maca: co z subskrypcjami po
  uśpieniu, czy `stop()`/`start()` przy każdym otwarciu menu jest
  w porządku (koszt `start()`, ile trwa do pierwszych wartości przy
  ~200 kluczach), czy wolno je wołać często.
- **Pomiar na żywo (2026-10-26, wstępny):** Menu Bar for Grenton woła `start()`
  przy każdym otwarciu menu i `stop()` minutę po zamknięciu. Czas do
  pokazania stanów jest krótki („niewiele”), a ponowne otwarcie po
  `stop()` łączy się bez problemu. Obserwacja trwa (dłuższe użycie,
  uśpienie Maca). Jeśli się utrzyma, to dobry materiał do akapitu „On
  a Mac” w artykule: `start()` przy otwarciu UI, `stop()` z opóźnieniem
  po zamknięciu.
- **Artykuł (0.13.1, „macOS: sleep, wake and menu-bar apps”)** mówi
  inaczej niż pomiar: system uruchomić raz i zostawić (ping na CLU co
  kilka sekund), nie zatrzymywać przy każdym zamknięciu menu; po
  uśpieniu sesja sama przechodzi w `degraded` i wraca.
- **W apce (2026-11-06):** zgodnie z artykułem — `start()` przy pierwszym
  otwarciu menu, bez `stop()` do wyjścia z aplikacji (`HomeModel.stopDelay`
  zniknął). Start leniwy, nie przy uruchomieniu: testy jednostkowe hostuje
  apka i nie mogą łączyć się z domem.

### D2. Sandbox macOS: które uprawnienia — częściowo rozstrzygnięte

- Artykuł wymienia tylko `com.apple.security.network.client`. Nie mówi,
  czy push z CLU (przychodzący datagram na ten sam socket) wystarcza
  z samym `network.client`, ani czy `AnySourceUdpSocketFactory`
  (nasłuch z dowolnego źródła) nie wymaga `network.server`.
- **Sprawdzone na żywo (2026-10-26):** w sandboksowanej apce z samym
  `network.client` i domyślnym `NetworkUdpSocketFactory` push działa:
  przełączenie fizycznym włącznikiem pojawia się w otwartym menu.
  Warto to napisać w artykule wprost („`network.client` wystarcza, także
  na pushe z CLU”).
- **Nadal otwarte:** `AnySourceUdpSocketFactory` w sandboksie (Menu Bar for Grenton
  go nie używa).

### D3. `InterfaceStore.system()` vs. potrzeba DTO — w bibliotece (0.13.1, „the interface beside the system”)

- Getting Started pokazuje `InterfaceStore().system()` jako drogę
  startu, ale każda apka, która chce czegoś więcej niż płaskiej listy
  encji (sekcje, nazwy stron interfejsu, ikony), potrzebuje DTO
  (patrz A3). Warto pokazać wariant `store.interface()` +
  `GrentonSystem(interface:)` i powiedzieć, kiedy go użyć.

### D4. Ręczny data.json: format nagłówka, typy komponentów, ciche pomijanie — w bibliotece (0.13.1, „the smallest data.json”)

- `SectionHeaderDTO` jest udokumentowany, ale nie to, skąd bierze się
  `label` (pierwszy `components[].label` widgetu `HEADER`). Przy pisaniu
  syntetycznego `data.json` do testów apki trzeba było to wyczytać ze
  źródła `PageDTO.init(from:)`. Testing Your App zachęca do ręcznego
  `data.json`, ale nie podaje minimalnego przykładu (klucz, CLU, strona,
  `ON_OFF`, `HEADER`).
- **Pułapka, która faktycznie się zdarzyła:** w syntetycznym fixture
  `ON_OFF_DOUBLE` miał komponenty `BUTTON_BISTABLE` zamiast
  `BUTTON_BISTABLE_V2`. Widget został po cichu pominięty (trafił tylko do
  `interface.skippedWidgets`), a brak świateł wyszedł dopiero w teście
  modelu. Zgodnie ze spec §3.6 to poprawne zachowanie dla danych z OM,
  ale przy ręcznie pisanych fixture'ach przydałoby się zdanie w Testing
  Your App („sprawdź `interface.skippedWidgets.isEmpty` w teście
  fixture'u") i tabela typów komponentów per widget w DocC (dziś jest
  tylko w spec, `grenton-core-design.md` §3).
- **W apce:** test `demoAndTestInterfacesSkipNoWidget` pilnuje obu
  syntetycznych interfejsów.

### D5. `GrentonSimulation` w projekcie Xcode: podwójne klasy — otwarte

- **Co:** Testing Your App każe dodać `GrentonSimulation` do targetu
  testów. W projekcie Xcode z testami hostowanymi w apce (domyślny
  szablon) apka linkuje `GrentonKit`, a testy `GrentonSimulation`; gdy ten
  sam produkt trafia do dwóch targetów, Xcode buduje go jako dynamiczny
  `PackageProduct.framework` z własną kopią `GrentonDevices`. Wynik
  w logu testów: `Class _TtC14GrentonDevices13GrentonSystem is
  implemented in both … This may cause spurious casting failures` — dla
  każdej klasy encji. Testy przechodziły, ale `as?` / `Observable` na
  zdublowanych typach to proszenie się o kłopoty.
- **Gdzie:** artykuł Testing Your App (przykład jest dla `Package.swift`,
  gdzie problemu nie ma — `swift test` nie ma aplikacji-hosta).
- **W apce:** `GrentonSimulation` linkuje tylko apka (tryb demo), test
  target dostaje moduł od hosta (`project.yml`, komentarz przy
  zależnościach). Apka bez trybu demo musiałaby albo wyłączyć hosta
  testów, albo linkować symulację do apki.
- **Propozycja:** akapit „In an Xcode project" w Testing Your App: testy
  hostowane → symulacja w targecie apki (np. tylko Debug) albo testy bez
  hosta; ewentualnie rozważyć, czy `GrentonSimulation` nie powinien
  wystawiać się z `GrentonKit`-owego grafu tak, by nie ciągnąć drugiej
  kopii `GrentonDevices`.

### D6. Przykład `LightRow` w Observing State miga przełącznikiem — otwarte

- **Co:** sekcja „In SwiftUI" pokazuje `Toggle` z
  `Binding(get: { light.value.isOn == true }, set: { … setOn … })`.
  Na żywo: po kliknięciu przełącznik przeskakuje, natychmiast wraca (bo
  `get` czyta stan sprzed raportu), a po ~ułamku sekundy znów
  przeskakuje, gdy CLU zgłosi nowy stan. Dokładnie to zobaczył autor
  w pierwszej wersji Menu Bar for Grenton, napisanej wg tego przykładu.
- **Gdzie:** `GrentonDevices.docc/ObservingState.md` („In SwiftUI"),
  `GrentonSwiftUI.docc/GrentonSwiftUI.md`.
- **W apce:** stan optymistyczny — `LightItem.pendingOn` pokazuje
  żądany stan do potwierdzenia (A7), po błędzie lub 3 s bez
  potwierdzenia wraca stan z CLU i komunikat w stopce.
- **Propozycja:** przykład z `@State var pending: Bool?` (albo z helperem
  z A7) i zdanie, że raport przychodzi po komendzie, więc UI powinno
  pokazać żądany stan od razu.

---

## Błąd

(na razie brak)
