# Straddle

Straddle is a privacy-first, local-only iPhone app for tracking cash-game poker sessions, profit, bankroll trends, and performance analytics.

<p align="center">
  <img src="docs/images/straddle-showcase.png" alt="Straddle dashboard, session history, and analytics displayed in restrained iPhone frames" width="100%">
</p>

<p align="center"><em>Real SwiftUI screens rendered with synthetic demonstration sessions. No personal poker data is shown.</em></p>

## Interface

<p align="center">
  <img src="docs/images/dashboard-framed.png" alt="Straddle dashboard with cumulative profit trend" width="31%">
  &nbsp;
  <img src="docs/images/history-framed.png" alt="Straddle searchable poker session history" width="31%">
  &nbsp;
  <img src="docs/images/analytics-framed.png" alt="Straddle poker performance analytics" width="31%">
</p>

## Features

- Cash-game session tracking with a venue dropdown (saved venues are managed in Settings)
- **Live sessions**: start a timer, add rebuys/add-ons, take breaks, finish with cash-out — the session is saved automatically and survives app restarts
- **Multi-currency**: each session keeps its game currency and the rate you entered (1 USD = X); every statistic is shown in US dollars
- **Backup & restore** (Settings tab): save to Files, share via Telegram/Mail/AirDrop, CSV export, import with merge/replace preview
- Fast entry for date, game, stakes, venue, buy-in, cash-out, and duration
- Cumulative profit chart and all-time dashboard
- Hourly rate, total hours, session count, win rate, average win/loss, and best/worst sessions
- Charts: bankroll by date/sessions/hours, monthly results, day of week, time of day, session length, result distribution, win/loss, stakes and venue comparisons
- Stats: BB/hour, standard deviation per session and per hour, max drawdown, streaks, ROI on buy-ins, rebuy rate
- Reports by month, year, stakes, venue, game; results calendar; filters by period, venue and stakes
- Stakes, venue and game performance breakdowns, max drawdown, current streak
- Searchable, editable session history
- Premium near-black interface with restrained electric-purple and cyan accents

## Privacy and architecture

Straddle is a self-contained native iOS app. It has no server, account system, advertising, or analytics SDK. The only network request is the optional "Load today's rate" button, which fetches public USD exchange rates from open.er-api.com.

Session data is encoded as JSON and stored only inside the app's Documents folder (visible in Files → On My iPhone → Straddle). Calculations and charts are produced locally on the phone. Standard iPhone backups may include the app container depending on the user's backup settings, but Straddle does not implement cloud synchronization or its own backup service.

Deleting the app deletes its local data. Before reinstalling, use Settings → Save backup to Files, then Settings → Import backup after installing. Installing a new build over the existing app keeps the data.

## Technology

- Swift 5.10
- SwiftUI
- Swift Charts
- Foundation and Combine
- XcodeGen
- iOS 17.0+

There are no third-party runtime dependencies.

## Repository layout

```text
Straddle/
├── Analytics/       # Metrics, trends, ROI, and breakdown calculations
├── App/             # SwiftUI application entry point and root navigation
├── Components/      # Shared UI components
├── Models/          # Codable poker-session model
├── Resources/       # Asset catalog and app icon
├── Services/        # Local JSON persistence
├── Theme/           # Colors and shared visual styling
└── Views/           # Dashboard, history, analytics, and session forms
StraddleTests/       # Analytics and persistence tests
project.yml          # XcodeGen project definition
```

## Prerequisites

- A Mac with Xcode installed
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- An iOS 17+ simulator, or an iPhone configured for development
- An Apple Developer team for physical-device signing

Install XcodeGen with Homebrew:

```bash
brew install xcodegen
```

## Build and test

```bash
git clone https://github.com/Cammm123/Straddle.git
cd Straddle
xcodegen generate
xcrun simctl list devices available
xcodebuild -project Straddle.xcodeproj -scheme Straddle \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Choose an available simulator name if `iPhone 17` is not installed.

You can also open the generated project:

```bash
open Straddle.xcodeproj
```

## Configure signing for your own device

The checked-in Apple Team ID and bundle identifiers are public application identifiers, not credentials. Forks should replace Cameron's values in `project.yml`:

- `DEVELOPMENT_TEAM`
- `bundleIdPrefix`
- `PRODUCT_BUNDLE_IDENTIFIER` for `Straddle`
- `PRODUCT_BUNDLE_IDENTIFIER` for `StraddleTests`

Use bundle identifiers registered to your own Apple Developer account, regenerate the project, select your connected iPhone as the destination, and run the `Straddle` scheme from Xcode.

```bash
xcodegen generate
```

The generated `Straddle.xcodeproj` is a local build artifact and is intentionally not committed.

## Data storage

The app stores sessions in its Documents directory (older builds used Application Support and are migrated automatically):

```text
sessions.json        # array of sessions
live-session.json    # the session currently being played, if any
```

Backups use a versioned wrapper (`{"format":"straddle-backup","version":2,"sessions":[…],"preferences":{…}}`). Import also accepts a bare `sessions.json` array, ISO-8601 or numeric dates, numbers written as strings, and skips damaged entries instead of failing.

Writes are atomic. Dates use Foundation's reference-date representation so save/load round trips preserve exact values.

## Tests

The test suite covers:

- Core profit and hourly-rate calculations
- Cumulative trends and time-range filtering
- Venue and game breakdowns
- Empty analytics behavior
- Session save, reload, update, and deletion

Run it with the `xcodebuild` command above or from Xcode's Test navigator.

## License

Straddle is available under the [MIT License](LICENSE).
