# Lanka Radar

Tells you when Sri Lankan official sources publish something new: extraordinary gazettes, price controls, fuel and LP gas prices, the USD/LKR rate, holidays and exam notices.

A GitHub Actions workflow checks the sources every hour and commits what it finds to the `data` branch as JSON. The Android app reads that JSON, keeps an offline copy and notifies you. Two sources only answer inside Sri Lanka, so the app reads those itself on the phone. No servers, no accounts.

**Status:** in development (v1), Android only, for personal use. See [docs/PLAN.md](docs/PLAN.md).

## Requirements

- Python 3.12 or newer
- Flutter 3.44 (stable channel), Dart 3.12
- JDK 17 or newer
- Android SDK

## Getting started

```bash
git clone <repo-url> lanka-radar
cd lanka-radar
python -m venv scrapers/.venv
source scrapers/.venv/bin/activate      # Windows (Git Bash): source scrapers/.venv/Scripts/activate
pip install -e "scrapers[dev]"

cd app
flutter pub get
flutter run
```

## Development

| Task | Command |
| --- | --- |
| Python format | `ruff format .` (repo root) |
| Python lint | `ruff check .` |
| Scraper tests | `pytest scrapers` |
| Release tooling tests | `pytest scripts/release` |
| Run the scrapers live | `python -m lanka_radar run --data <scratch folder>` |
| App format | `dart format lib test` (in `app/`) |
| App analyze | `flutter analyze` |
| App tests | `flutter test` |
| App debug build | `flutter build apk --debug` |
| Regenerate the database code | `dart run build_runner build` (in `app/`, after changing the drift tables) |

CI (`.github/workflows/ci.yml`) runs all of these on every push to `main` and every pull request.

## Layout

```text
scrapers/          Python package that reads the sources (runs on GitHub Actions)
app/               Flutter app, Android only
scripts/release/   works out the next version and release notes
docs/              plan
```

## Data

The scrape workflow (`.github/workflows/scrape.yml`) runs every hour and commits to the `data` branch, which never merges into `main`:

| File | What it holds |
| --- | --- |
| `latest.json` | the newest 200 feed items, newest first |
| `items/<yyyy>/<mm>/<id>.json` | every feed item, one file each |
| `months/<yyyy>-<mm>.json` | every feed item of that month, newest first: the app's history |
| `months/index.json` | each month's item count and file hash, so the app downloads only the months that changed |
| `datasets/usd-lkr.json` | Frankfurter's copy of CBSL's daily USD/LKR rate since 1 January 2026, a backup that often runs days behind |
| `datasets/holidays.json` | public holidays from 2026 on, Poya days included |
| `status.json` | each source's last run, last success and last error |
| `state/<name>.json` | the scrapers' own bookkeeping, not for the app |

Feed items are news: a gazette (fuel price revisions included), a USD/LKR move of 2% or more in a week, an exam notice. Gazettes become items only when they belong to a daily-life group: prices, taxes and imports; energy and utilities; wages and labour; elections. Exam notices become items for school exams (O/L, A/L, Grade 5 scholarship, GIT) and the department's own press releases and notices. A new Litro price list is an item too.

Each gazette item's PDFs are read once: the title on page 1 becomes the headline when the list only names the issuer, and in price gazettes (CAA orders, fuel revisions) the price table becomes key numbers. Tamil titles come from an old Bamini-encoded font, converted to Unicode with Open-Tamil, or from Arial Unicode MS, whose text in these PDFs is scrambled, so it is read from the glyph IDs instead.

CEYPETCO's fuel prices and CBSL's rate search only answer inside Sri Lanka, so the workflow (on GitHub's servers abroad) can't read them. The app reads them on the phone during its sync: the fuel prices fill its Now card (fuel price changes reach the feed as fuel revision gazettes), and the same-day USD/LKR rate makes the same rate items, with the same IDs, as the workflow's backup copy, so a copy from either side is recognized. A source that fails 3 runs in a row fails the workflow once, so GitHub emails you; after that its failures are only recorded in `status.json`, and the app flags the source.

## Git workflow

- `main` is always releasable. Work happens on short branches named `feat/...`, `fix/...`, `docs/...` or `chore/...` and lands through a pull request once CI passes.
- Pull requests are squash-merged, so each becomes one commit on `main` whose message is the PR title. Titles follow [Conventional Commits](https://www.conventionalcommits.org/), checked by `.github/workflows/pr-title.yml`.
- The `data` branch belongs to the scrape workflow. Never commit to it by hand or merge it into `main`.
- Version tags (`vX.Y.Z`) are created only by the release workflow.

## Releases

Every push to `main` that ships a change publishes a release (`.github/workflows/release.yml`). The commit types since the last tag decide the version:

| Commit type | Release |
| --- | --- |
| `fix`, `perf`, `revert` | patch (0.1.1) |
| `feat` | minor (0.2.0) |
| `feat!:` or a `BREAKING CHANGE:` footer | major (1.0.0) |
| `docs`, `chore`, `ci`, `test`, `refactor`, `style`, `build` | none |

- Only commits that change `app/` count, so scraper and tooling work never publishes an app release.
- The first release uses the version in `app/pubspec.yaml` once there is a `feat` or `fix` to ship. A pubspec version above the computed one wins, so a version can still be forced by hand.
- The Android version code is `major * 1000000 + minor * 1000 + patch`, so it always grows.
- Each release carries the signed `lanka-radar-X.Y.Z.apk` and `SHA256SUMS.txt`. Notes come from `CHANGELOG.md` when it has a section for the version, otherwise from the commits.

### Signing key (one time)

Android only installs an update signed with the same key as the installed app, so every release uses one key. Create it once and keep a backup somewhere safe:

```bash
keytool -genkeypair -v -keystore lanka-radar-upload.jks -alias upload -keyalg RSA -keysize 4096 -validity 10000
```

Then add four repository secrets (Settings > Secrets and variables > Actions):

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | output of `base64 -w0 lanka-radar-upload.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | the key password |

Until they exist, a release that is due is skipped with a warning instead of failing. For local release builds, create `app/android/key.properties` (gitignored):

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/absolute/path/to/lanka-radar-upload.jks
```

Without that file, release builds are signed with the debug key.

## Sources

Gazettes from the Department of Government Printing, fuel prices from CEYPETCO, LP gas prices from Litro, exchange rates from the Central Bank of Sri Lanka, exam notices from the Department of Examinations, recruitments from the Public Service Commission, and holidays from Google's public Sri Lanka holiday calendar. Lanka Radar is not affiliated with any of them, and every item links to the official source.

## License

MIT. See [LICENSE](LICENSE).
