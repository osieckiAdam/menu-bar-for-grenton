# Prompt dla sesji w `grenton-core-swift`: uwagi z GrentonBar po roletach (2026-11-06)

Tekst poniżej (od linii poziomej) wkleja się jako polecenie w repo
`grenton-core-swift`. Źródła: GrentonBar `NOTES.md` (A5, A7, D6), pliki
`Model/LightItem.swift`, `Model/CoverItem.swift`, `Demo/DemoDriver.swift`
i testy `GrentonBarTests/LightListTests.swift`.

---

Użyj skilla `grenton-change`.

## Kontekst

Piszę GrentonBar: aplikację paska menu macOS, pierwszą aplikację zbudowaną na
`grenton-core-swift`. Pokazuje strony i sekcje interfejsu myGrenton, przełącza
światła, a od wczoraj steruje roletami `ROLLER_SHUTTER_V3` przez `CoverEntity`
(przyciski podnieś / stop / opuść, suwak lameli). Apka jest testem biblioteki
z perspektywy użytkownika: każde obejście zapisuję w jej `NOTES.md`, a naprawy
idą przez ten skill, nigdy po cichu w apce.

Wczoraj zrobiłem dwie rzeczy. Najpierw podbiłem bibliotekę z 0.12.2 do 0.14.0
i zdjąłem obejścia A1–A6 z `NOTES.md`: wszystkie działają zgodnie z CHANGELOG
0.13.1 i 0.14.0 (`Observed` dla `any SwitchableEntity`,
`DeviceDescriptor.section`, `sessionStateUpdates()`, `echoesSwitches`,
`save(project:interfaceId:)`, ikony). Potem dodałem rolety. Z tej drugiej
części zostały trzy uwagi do biblioteki i dwa drobiazgi. Zgłaszam je, bo są
tym, co każda następna aplikacja na tej bibliotece napisze od nowa, a spec
i dokumentacja powinny o tym rozstrzygać, nie apka.

Dla każdej uwagi: sklasyfikuj zmianę wg kroku 1 skilla, zaproponuj kształt API
i zapis w spec, przeprowadź przez spec → conformance → port → DocC → przykłady.
Jeśli którąś odrzucasz, napisz dlaczego i co apka ma robić zamiast tego, żebym
zaktualizował `NOTES.md`. Żadnych identyfikatorów mojej instalacji w kodzie,
fixture'ach ani commitach. Pytaj, zanim uruchomisz cokolwiek, co zmienia stan
domu.

## 1. „Wyślij i poczekaj na raport z CLU” jest potrzebne każdej encji z komendą

**Co widzę.** Komenda wraca, gdy CLU przyjmie żądanie (`resp`, spec §5.3.4);
nowy stan przychodzi później osobnym `clientReport`. Aplikacja, która chce
pokazać, czy zmiana się udała, musi sama: wziąć `updates()` **przed**
wysłaniem, wysłać, czekać z timeoutem na raport spełniający warunek,
a w międzyczasie pokazywać stan żądany (inaczej przełącznik miga, jak
w przykładzie `LightRow` z Observing State).

**Jak to odkryłem.** Napisałem to w GrentonBar dwa razy. Raz dla
`SwitchableEntity` (`LightItem.setOn`: warunek `isOn == on`), drugi raz
wczoraj dla `CoverEntity` (`CoverItem.perform`: warunek „jakikolwiek raport”,
bo roleta jedzie kilkadziesiąt sekund i potwierdzeniem jest pierwsza zmiana
`motion`, `position` albo `tilt`, nie pozycja docelowa). Kod jest niemal
identyczny, wyciągnąłem go do wspólnego helpera w apce. Ten sam wzorzec jest
w `Examples/switch-light/main.swift` jako pętla odpytująca co 200 ms.

Testy apki wykryły dwie pułapki, które helper w bibliotece powinien mieć
opisane w spec:

- komenda, która nic nie zmienia (`open()` na otwartej rolecie, `setOn(true)`
  na włączonym świetle) często **nie daje żadnego raportu**, więc helper musi
  zwrócić `true` od razu, gdy warunek jest spełniony już przed wysłaniem;
- gdy użytkownik klika szybko, nowsza komenda musi przejąć stan „żądany”,
  a starsza po timeoucie nie może go skasować.

**Propozycja.** Jeden helper w `GrentonDevices`, mniej więcej:

```swift
extension StatefulEntity {
    /// Subscribes to `updates()`, runs `command`, then waits until `condition`
    /// holds or `timeout` passes. `true` at once when it already holds.
    func perform(
        _ command: () async throws -> Void,
        confirmedWhen condition: @Sendable () -> Bool,
        within timeout: Duration
    ) async throws -> Bool
}
```

plus nakładki: `SwitchableEntity.setOn(_:confirmingWithin:)` oraz dla
`CoverEntity` warianty `open/close/stop/setTilt(…, reportingWithin:)`
z warunkiem „pierwszy raport”. Spec: nowy punkt w §6 „intent z
potwierdzeniem” (subskrypcja przed wysłaniem, `true`/`false`/błąd, zasada dla
komendy bez zmiany). Przykład `switch-light` skrócić do tego API. W Observing
State poprawić `LightRow`: pokazywać stan żądany do raportu (to jest moje D6).

## 2. Symulacja nie echo-uje rolet; tryb demo pisze to sam

**Co widzę.** `SimulatedGrentonSystem(interface:echoesSwitches:)` odbija tylko
on/off. Decyzja z października brzmiała: echo dla termostatu czy rolety byłoby
zgadywaniem.

**Jak to odkryłem.** Tryb demo GrentonBar (podglądy SwiftUI i `-GrentonBarDemo
YES`) musiał dostać własny symulator rolety: po komendzie `state` 1 lub 2,
potem `position` co 10 jednostek co 300 ms, na końcu `state` 0; `stop()` →
`state` 0; `setTilt(t)` → surowa wartość lameli `Int(90 − 0.9·t)` ze spec
§6.3.8. To 30 linii, które będzie miała każda apka z podglądami rolet.
Przy okazji musiałem dojść do formuły lameli i surowych kluczy
(`descriptor.motionState`, `descriptor.position`, `descriptor.tilt?.position`)
ze źródeł, bo Testing Your App o nich nie mówi.

**Propozycja.** Nie proszę o fizykę ruchu. Proszę o rozważenie
**minimalnego, deterministycznego** echa dla rolet: po `setPosition(p)` →
`position = p`, `state = 0` (bez ruchu w czasie); po `setTilt(t)` → surowa
wartość lameli wg formuły ze spec; po `stop()` → `state = 0`. Nazwa np.
`echoesCovers:` albo ogólniejsze `echoes: [.switches, .covers]`. Jeśli zostaje
„tylko on/off”, dopisz w Testing Your App akapit „demo mode for shutters”
z listą surowych kluczy i formułą lameli, żeby apki nie czytały tego ze
źródeł.

## 3. `open()`/`close()` to `setPosition`; `moveUpAction`/`moveDownAction` leżą odłogiem

**Co widzę.** Spec §6.3.8 mapuje `open()` → `setPosition("100")`, `close()` →
`setPosition("0")`, a `moveUpAction` / `moveDownAction` zostawia „out of scope
for v1”, choć DTO je trzyma i są polami wymaganymi w §3.5. myGrenton pod
strzałkami używa właśnie ich.

**Jak to odkryłem.** Projektując przyciski ▲ ▼ w apce czytałem §6.3.8 obok
`RollerShutterV3ObjectDTO` i fixture'u z `Tests/GrentonDevicesTests`. Nie mam
pewności, czy `setPosition(100)` i `moveUp()` zachowują się tak samo na
sprzęcie: roleta bez skalibrowanego czasu przejazdu, `reversePosition`,
blokada. Na żywo jeszcze tego nie sprawdziłem.

**Propozycja.** Rozstrzygnąć w spec, z adnotacją Δ, jeśli zostaje jak jest.
Jeśli równoważności nie da się uzasadnić, dodać do `CoverDescriptor`
opcjonalne `moveUpAction` / `moveDownAction` i intencje `moveUp()` /
`moveDown()` (no-op bez akcji, jak `stop()`), a w Controlling Devices
napisać, kiedy używać których. Powiedz mi, co obserwować na żywo (np.
`position` i `state` po `moveUp()` na rolecie bez kalibracji), to sprawdzę
na swojej instalacji i wrócę z wynikiem do CHANGELOG.

## 4. Przykład „Lights only” (allowlista ikon lamp) ukrywa prawdziwe światła

**Co widzę.** Controlling Devices po 0.14.0 pokazuje filtr: przełącznik jest
światłem, gdy ikona zawiera `lamp`, `bulb`, `plafond` lub `light`. Wdrożyłem
go dosłownie.

**Jak to odkryłem.** Po dwóch dniach użytkownik zgłosił, że z salonu zniknęła
część świateł. Policzyłem ikony przełączników `ON_OFF` w swoim interfejsie:
41 różnych nazw, 59 przełączników z ikoną lampy, 42 bez. Z tych 42 około
połowa to światła, bo instalator dobierał ikonę po **miejscu**, nie po
urządzeniu: kinkiety mają `sofa`, `tv`, `bookcase`, `mirror`; sufity
`garden_table`, `door_1`, `personal_computer`; lampki schodowe `stairs`;
oświetlenie nocne `crescent_moon_1`; linia LED na przekaźniku ma `led`.
Jednocześnie `door` (bez sufiksu) to przycisk otwierania bramy, więc nawet
dopasowanie po fragmencie nazwy nie działa.

**Co zrobiłem w apce.** Odwróciłem regułę na blocklistę: przełącznik jest
światłem, chyba że ikona jest jednoznacznie czymś innym (`power_socket`,
`socket`, `power`, `valve`, `floor_heating`, `ac`, `door`, `gate`, `garage`,
prefiksy `vacuum_robot`, `pump`, `boiler`, `heating`), dopasowanie całej
nazwy. Pokazanie pompy jako światła jest tańsze niż ukrycie światła.

**Propozycja.** W „Lights only” zamienić przykład na blocklistę i dodać
jedno ostrzeżenie: nazwa ikony w Object Managerze koduje miejsce równie
często co typ urządzenia, więc nie ma listy słów, która wybierze światła;
apka powinna domyślnie pokazywać wszystkie przełączniki i dać użytkownikowi
ukryć te, których nie chce. Jeśli w spec jest miejsce na katalog ikon
Object Managera (A6 wspominało o ~40 nazwach), ta obserwacja powinna tam
trafić jako powód, dla którego biblioteka nie klasyfikuje.

## Drobiazgi

- **`GrentonSystem` nie wystawia nazwy interfejsu** (`MobileInterfaceDTO.name`).
  Po 0.13.1 apka nie potrzebuje już DTO do sekcji, ale nadal trzyma je obok
  systemu wyłącznie po tytuł do nagłówka menu. Jedno zdanie w artykule „the
  interface beside the system” albo `GrentonSystem.name`.
- **`GrentonValue.int` przyjmuje `Int64`.** Pisząc symulator rolety w demo
  trzy razy dostałem „Cannot convert value of type 'Int' to expected argument
  type 'Int64'” przy `simulation.set(ref, to: .int(position))`, bo `position`
  w `CoverEntity` jest `Int`. Wygodny inicjalizator albo statyczna funkcja
  przyjmująca `Int` (np. `GrentonValue.int(_ value: Int)`) oszczędzi tego
  każdemu, kto ustawia wartości z API encji z powrotem w symulacji.
