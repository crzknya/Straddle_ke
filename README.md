# Straddle

A personal iPhone tracker for **live cash-game poker**: live sessions with a timer and rebuys, all statistics in US dollars whatever currency you play in, detailed charts and reports, and reliable backups.

The app runs fully on the phone: no account, no server, no ads. The only network request is the optional “Load today’s rate” button.

> Fork of [Cammm123/Straddle](https://github.com/Cammm123/Straddle), heavily reworked: cash games only, currencies, live sessions, extended analytics, backups.

---

## Features

### Live session
- **Start live session** on the Dashboard or via the **+** button.
- Pick the venue from a list (or enter it manually), choose stakes, currency and rate, enter the buy-in, and the timer starts.
- While you play:
  - **Rebuy** in one tap (same amount as last time) or for a different amount;
  - **break**: the timer pauses;
  - edit the venue, stakes, rate, start time and notes.
- **Finish session**: enter the cash-out; duration, profit and hourly are calculated automatically.
- A bar with the timer sits above the tab bar on every tab.
- The session is saved to disk on every change, so it survives the app being closed, the phone restarting, or an update installed over the top.

### Currencies
- All statistics are **in US dollars**.
- Each session stores the **game currency** and the **rate** at the time of play.
- Amounts are entered in the game currency, and the dollar equivalent is shown next to them.
- The last currency and rate are filled in automatically. The rate can also be loaded online (open.er-api.com).
- Settings has a bulk tool that marks old sessions entered in a local currency as that currency at a chosen rate.

### Sessions and history
- Quick entry of a completed session: date, venue, stakes, game, currency, total buy-in, number of rebuys, cash-out, duration, notes.
- Venue, stakes and game are chosen from a **dropdown** (most frequent first) or entered manually.
- The venue list is managed in **Settings → Venues**.
- History has search, a filter for All / Wins / Losses, editing and deletion.

### Analytics
Filters: period (30D / 90D / YTD / 1Y / All), venue, stakes.

| Section | Contents |
|---|---|
| **Stats** | Net profit, $/hour, **BB/hour**, win rate, sessions, hours; average result/win/loss, best and worst session; **standard deviation** per session and per hour, max drawdown, distance from peak, all-time high, win/loss streaks; total and average buy-in, **ROI on buy-ins**, rebuy rate; average and longest session, sessions per week, best/worst month |
| **Charts** | Bankroll by date / session number / hours (drag a finger to read values); results by month; by day of week, time of day and session length (switchable Profit / Hourly / Win%); session result distribution; win/loss share; comparison by stakes and venue |
| **Reports** | Tables by month, year, stakes, venue, game, day of week, time of day, session length |
| **Calendar** | Each day coloured by its result; tap a day to see its sessions |

BB/hour is calculated from the stakes field: `50/100`, `$1/$2` and `100/200/400` (straddle) are understood; the big blind is the second number.

### Backup
**Settings → Backup:**
- **Save backup to Files**: a JSON file with all sessions, settings, the venue list and the running session.
- **Share backup**: send it via Telegram, Mail or AirDrop.
- **Export CSV**: for Numbers / Google Sheets.
- **Import backup**: shows what is in the file (new / updated / damaged), then **Merge** (no duplicates) or **Replace all**.

Import also accepts old `sessions.json` files, dates in any common format, and numbers written as strings. Damaged entries are skipped instead of breaking the whole import.

---

## Building without a Mac

You need a CI service that builds an **unsigned IPA**, which you then sign on the phone (for example with GBox).

### Codemagic (recommended)
1. [codemagic.io](https://codemagic.io) → sign in with GitHub → Add application → this repository.
2. The settings are picked up from [`codemagic.yaml`](codemagic.yaml) (workflow **Straddle unsigned IPA**).
3. Builds run automatically on pushes to `main`, or manually via **Start new build**.
4. Download `Straddle.ipa` from the build’s Artifacts.

The free plan includes 500 minutes a month on Mac M2; one build takes about 5 minutes.

### GitHub Actions
[`.github/workflows/main.yml`](.github/workflows/main.yml) builds the IPA and runs the tests on every push to `main`. The result is in Actions → run → Artifacts → `Straddle-unsigned`.

### Updating without losing data
- **Install the new build over the existing app, without deleting it.** Data and a running session are kept.
- Before an update, especially a risky one, make a backup: Settings → Save backup to Files.
- If you need to delete the app: backup first → delete → install → Settings → Import backup.
- Check the version in **Settings → Version**.

---

## Data storage

The files live in the app’s Documents folder (Files → On My iPhone → Straddle):

```text
sessions.json        # all sessions (array)
live-session.json    # the session currently being played, if any
```

Settings (default currency, rates, venue list, last backup date) are stored in UserDefaults and included in the backup.

Backup format:

```json
{
  "format": "straddle-backup",
  "version": 2,
  "exportedAt": 785000000,
  "sessions": [ … ],
  "preferences": { "defaultCurrency": "EUR", "rates": { "EUR": 0.92 }, "venues": [ … ] },
  "liveSession": { … }
}
```

A session stores amounts in the game currency (`buyIn`, `cashOut`) plus `currency` and `exchangeRate` (units of currency per 1 USD). Dates are seconds since 2001-01-01 (Foundation reference date).

---

## Technical details

- Swift 5.10, SwiftUI, Swift Charts, iOS 17+, iPhone, portrait orientation
- No third-party dependencies
- The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from [`project.yml`](project.yml)

```text
Straddle/
├── Analytics/   # all metrics: hourly, BB/h, std dev, drawdown, streaks, breakdowns
├── App/         # entry point, tabs, live session bar
├── Components/  # amount fields, dropdowns, currency/rate field, charts
├── Models/      # PokerSession, LiveSession, Currency
├── Services/    # SessionStore: storage, live session, settings, import/export
├── Theme/       # colours and styles
└── Views/       # Dashboard, History, Analytics, Settings, live session, forms
StraddleTests/   # analytics, storage, currencies, backups, live session
```

On a Mac:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Straddle.xcodeproj -scheme Straddle \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## License

MIT — see [LICENSE](LICENSE).
