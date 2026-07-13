# Irrigation App TODO

## 1. Dashboard Polish

* [ ] Add a visible "last updated" timestamp for the latest successful snapshot.
* [ ] Add clearer loading/disabled feedback for manual refresh actions.
* [ ] Make timeout and network errors more user-friendly than raw exception text.

## 2. Tests

* [ ] Add focused tests for schedule field validation helpers.
* [ ] Add more JSON parsing edge-case tests for partial/degraded API payloads.

## 3. Structure

* [ ] Consider converting `part` files to normal Dart libraries if the app grows.
* [ ] Split `widgets.dart` further if repeated UI work becomes hard to navigate.

## 4. Configuration

* [ ] Show the active API base URL/status in the Configuratie screen for field debugging.
* [ ] Show app version/build information in the Configuratie screen.
