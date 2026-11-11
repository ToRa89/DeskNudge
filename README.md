# DeskNudge

Menüleisten-App für macOS 26, die einen LINAK-Schreibtisch über Bluetooth LE steuert und ans Aufstehen erinnert.

Nach einer einstellbaren Sitzzeit erscheint oben rechts eine Karte mit „Fahren“ und „Ablehnen“. „Fahren“ bringt den Tisch auf den Steh-Favoriten, nach der Stehzeit läuft es umgekehrt. Dazu kommen drei Favoriten mit Höheneingabe in cm und eine manuelle Fahrt, bei der der Tisch nur fährt, solange der Pfeil gedrückt ist.

## Bauen

```bash
./build.sh            # Tests, Release-Build, build/DeskNudge.app
./build.sh --install  # zusätzlich nach ~/Applications kopieren
```

Die LINAK-App vorher beenden, sie belegt sonst die Bluetooth-Verbindung zum Tisch.

## Aufbau

- `Sources/DeskCore`: Protokoll-Codec, Fahrlogik und Erinnerungslogik ohne UI, mit Unit-Tests
- `Sources/DeskNudge`: CoreBluetooth-Anbindung und SwiftUI-Oberfläche

Die GATT-UUIDs stammen aus dem LINAK-SDK der offiziellen Desk-Control-App. Das Fahrverhalten folgt den bekannten Open-Source-Steuerungen für LINAK-Tische.
