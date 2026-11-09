# GrentonBar

Aplikacja paska menu macOS (14+): światła i rolety domu Grenton pogrupowane
jak w myGrenton — strona → sekcja z nagłówka → urządzenie. Światła
(przełączniki z ikoną lampy, ściemniacze, LED) włącza się i wyłącza; rolety
(`ROLLER_SHUTTER_V3`) podnosi, zatrzymuje i opuszcza, a po kliknięciu
wiersza ustawia lamele suwakiem. Pierwszy test biblioteki
[grenton-core-swift](https://github.com/osieckiAdam/grenton-core-swift)
z perspektywy użytkownika; uwagi do biblioteki: [NOTES.md](NOTES.md).

## Uruchomienie

1. Otwórz `GrentonBar.xcodeproj` w Xcode i uruchom schemat `GrentonBar`.
2. Schemat ma włączony argument `-GrentonBarDemo YES`: menu pokazuje
   syntetyczny dom demo na `SimulatedGrentonSystem`, bez sieci. W menu
   „…” → Demo: przełączenie światła „z włącznika", awaria CLU.
3. Na żywo: Product → Scheme → Edit Scheme → Run → Arguments, odznacz
   `-GrentonBarDemo YES`. Przy pierwszym połączeniu macOS zapyta o dostęp
   do sieci lokalnej — działa tylko dla podpisanego `.app` uruchomionego
   z Xcode/Findera.

Połączenie z CLU startuje przy pierwszym otwarciu menu i trwa do wyjścia
z aplikacji (`stop()` przy zamykaniu), zgodnie z zaleceniem biblioteki dla
aplikacji na Macu.

## Interfejs i klucz

Interfejs mobilny (archiwum `.zip` z Object Managera, pobranie z OM
przez adres + PIN albo plik projektu `.omp`) zawiera klucz AES CLU.
Archiwum trzyma wyłącznie `InterfaceStore` biblioteki (Application
Support aplikacji). `*.zip` i `*.omp` są w `.gitignore`; w repo są tylko
syntetyczne interfejsy (`GrentonBar/Demo/demo-interface.json`,
`GrentonBarTests/Fixtures/test-interface.json`).

## Rozwój

- Projekt generuje [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  z `project.yml`: po dodaniu lub usunięciu pliku `xcodegen generate`.
- Testy: `xcodebuild test -scheme GrentonBar -destination 'platform=macOS'`
  (model listy, statusy, syntetyczne interfejsy — bez sieci).
- Podgląd bez klikania w pasek menu:
  `TEST_RUNNER_SNAPSHOT_DIR=/jakiś/katalog xcodebuild test -scheme GrentonBar -destination 'platform=macOS' -only-testing:GrentonBarTests/Snapshots`
  zapisuje PNG menu i okna importu.
