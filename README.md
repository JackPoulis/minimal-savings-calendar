# Savings

A small savings tracker for your car purchase, running as a native app on **Windows** and **Android**.

- **Balance graph**: a day-by-day balance from a start date to an end date you choose. Tap any day to add, edit or delete money coming in or going out, each with a title.
- **Goal bar**: how much you have today (green), how much your upcoming entries will add by the end date (gray), and what is still missing (red).
- **Loan estimate**: the monthly payment and total interest for a loan amount, APR and term of any whole number of years (1 or more).

The app lives in [`flutter_app/`](flutter_app).

## Run the app

Needs the Flutter SDK (3.47 or newer).

```bash
cd flutter_app && flutter run -d windows
```

For Android, with a phone connected over USB debugging or an emulator running:

```bash
cd flutter_app && flutter run -d android
```

To produce an installable APK:

```bash
cd flutter_app && flutter build apk --release
```

The APK lands in `flutter_app/build/app/outputs/flutter-apk/`.

## Data

Each install keeps its own `data.json`:

- **Windows**: `%USERPROFILE%\Documents\CarBuySavings\data.json`
- **Android**: the app's private documents directory, which goes away if you uninstall the app

The file holds the entries and settings plus the sync bookkeeping described under [Sync](#sync). Saves are atomic (written to `data.json.tmp` and renamed), and all reads and writes go through [`lib/store.dart`](flutter_app/lib/store.dart).

### First-run seed

On first launch, when no `data.json` exists yet, the app copies `flutter_app/assets/seed_data.json` into place. That file holds the private starting data and is **git-ignored**, so real amounts never enter the repo or a cloned checkout. `assets/seed_data.example.json` is committed as a harmless stand-in and is used when the private seed is absent.

## Sync

Both installs work offline and keep their own `data.json`. To bring them together, press the QR button in the header on the PC and scan the code with the phone — that is the whole flow. The scan pairs the phone and syncs immediately; there is nothing else to press.

- The **PC is the hub**: it serves the sync over the local network for exactly as long as its QR window is open, and nothing is reachable once that window is closed.
- The **phone is the client**: it does the merging, so it is where conflicts are resolved.
- Entries and the settings (dates, target, loan) both sync. Edits to *different* fields of the same entry merge on their own; edits to the *same* field, or a delete on one side against an edit on the other, come up on the phone as a conflict with the two values side by side and **Keep all mine / Keep all PC's** to settle them. Cancelling changes nothing on either device.
- Nothing is written on the phone until the PC has accepted the push, and the PC applies a push whole or not at all, so a dropped connection mid-sync leaves both sides exactly as they were.
- Deletes are kept as tombstones in `data.json` (`"deleted": true`) so a deletion can travel; the app never shows them. The file also gains per-field edit times and the pairing state under `"sync"`. An older `data.json` loads unchanged.

Every sync starts with a fresh scan — the phone has no sync button and no pairing screen. The pairing itself is remembered, so re-scanning the same PC continues where the last sync left off, while a PC whose `data.json` has been wiped is recognised as a new one and receives the phone's whole history.

### Requirements and limits

- Both devices must be on the **same network**, and the PC's sync window must be open. Guest Wi-Fi and "client isolation" block it; a phone hotspot that the PC joins works.
- Windows asks to allow the app through the firewall the first time: allow it on **private networks**.
- Plain HTTP on a trusted LAN, deliberately: the per-device secret stops casual access, not eavesdropping. No cloud, no accounts, no background sync.

The design this follows, including the parts deliberately left out, is written up in [OFFLINE_FIRST_SYNC_PLAYBOOK.md](OFFLINE_FIRST_SYNC_PLAYBOOK.md).

## Tests

```bash
cd flutter_app && flutter analyze && flutter test
```

The tests cover the balance/loan maths, the stored file's round trip, the store's seeding and atomic saves, and the UI at both desktop and phone widths.

`test/sync/` covers sync on its own: the merge and conflict-resolution rules as pure functions, the hub's routes and its all-or-nothing push, QR decoding and pairing, and a phone and a PC with separate data files syncing over a real socket — union, auto-merge, every conflict answer, cancelling, a PC edit mid-sync, and an edit on the phone mid-sync.
