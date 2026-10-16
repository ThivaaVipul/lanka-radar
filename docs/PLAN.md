# Lanka Radar plan

Living document, updated as work proceeds. Last updated: 2026-10-16.
Status: **M0 to M4 merged, the `data` branch is live; M4b (Tamil titles from glyph IDs) built on `feat/tamil-ocr`. Next: M5 (app).**

A personal Android app that watches Sri Lankan official sources (gazettes, price controls, fuel, exchange rates, holidays, exam notices) and tells you when something new lands. GitHub Actions does most of the watching and the app reads what it publishes; the two sources that only answer inside Sri Lanka are read by the app itself.

## Decisions (2026-10-16, grilling session)

- **Purpose:** personal side project, built in the open. For now it is only for you: nothing is posted anywhere.
- **Content (v1):** price controls and fuel (CAA price-control gazettes, CEYPETCO fuel, LP gas), daily-life extraordinary gazettes, holidays and USD/LKR rates, exam notices.
- **USD/LKR:** the app reads CBSL's own site on the phone (the same-day official rate); the workflow keeps Frankfurter's copy as a backup.
- **Sri Lanka-only sources (decided after the first GitHub run):** CEYPETCO's fuel prices and CBSL's rate search refuse GitHub's servers abroad, so the app fetches both on the phone during its sync and makes the same items, with the same IDs, as the workflow would.
- **LP gas:** alert when Litro posts a new price-list image, and show that image. Reading the numbers comes later.
- **Moving parts:** only GitHub and the app. No Claude, Firebase, servers or other accounts.
- **Scrapers:** Python on GitHub Actions; results saved as JSON in the repo.
- **Text:** no AI. Each item uses its official headline, taken from the first page of its English and Tamil PDFs. (GitHub Models, the first choice, was retired on 30 July 2026.)
- **App:** Android (Flutter). English menus; each item shows the English headline with the Tamil one a tap away, plus the official PDF in each language that exists.
- **Alerts:** price changes, exam dates and results, holiday reminders, other daily-life gazettes and USD/LKR moves over 2% in a week. Every topic has its own on/off switch.
- **Name:** Lanka Radar. Repo `lanka-radar`, app ID `app.lankaradar`.
- **Parked:** Lanka MCP, Sinhala, public posting (Facebook Page, WhatsApp Channel), a web page.
- **Gazette groups (2026-10-16):** prices, taxes and imports; energy and utilities; wages and labour; elections. Each becomes a feed item with an alert; everything else (land title settlement, land acquisition and so on) is skipped.
- **Tamil gazette titles (2026-10-16):** Tamil PDFs come in two kinds. Bamini-encoded fonts (GP-Rasanji, Bamini, Tharmini) convert cleanly to Unicode with Open-Tamil. The rest, about 8 in 9 (election and CAA notices), use Arial Unicode MS with scrambled text maps; their Tamil is read from the glyph IDs instead, which gives the exact text (M4b). OCR was the first plan for them and turned out not to be needed.
- **Exam notices (2026-10-16):** school exams (O/L, A/L, Grade 5 scholarship, GIT), their timetables, and the department's own press releases and notices. Admission cards for institutional exams, religious and Piriven exams, recruitment exams and the monthly exam calendars are left out.

### Defaults (accepted 2026-10-16)

- Public repo under ThivaaVipul, MIT license. Scraped data is committed to a separate `data` branch, so `main` holds only code.
- Scrapers run every 3 hours. The app checks about every 3 hours, plus pull to refresh, and stays silent from 22:00 to 06:00 (anything new arrives in the morning).
- History is loaded from 1 January 2026.
- Flutter with one Cubit per screen, like Zen Mode, and an offline copy you can search.
- GitHub Actions builds the signed APK; you install it from GitHub Releases. No Play Store.
- Each source records its last successful run. The app flags a source that has gone quiet, and GitHub emails you when a run fails.
- Nothing git-related happens without your OK at each step. Commits have no `Co-Authored-By` trailer.
- Git identity `ThivaaVipul` with the GitHub noreply email only (set in this repo's git config, since the repo is public); no `gh` or browser tools for GitHub.
- Versions and APIs are checked against current docs (Context7) before a dependency or GitHub Action is added or upgraded.

### Git workflow and releases (2026-10-16)

- Conventional Commits. Work on `feat/...`, `fix/...`, `docs/...` or `chore/...` branches, open a pull request, and squash-merge it once CI is green. A workflow checks that PR titles are Conventional Commits.
- Every push to `main` that ships a change publishes a release. The version comes from the commits since the last `v*` tag: `feat` is minor, `fix`, `perf` and `revert` are patch, `!` or `BREAKING CHANGE:` is major. Other types don't release.
- The first release is `app/pubspec.yaml`'s 0.1.0, once a `feat` or `fix` lands. A higher pubspec version wins, so a version can be forced by hand.
- Android version code: `major * 1000000 + minor * 1000 + patch`.
- Each release has the signed APK and `SHA256SUMS.txt`. One signing key, kept in four repository secrets; until they exist, a due release is skipped with a warning.
- The `data` branch belongs to the scrape workflow, and `v*` tags come only from the release workflow.

## Sources (checked live on 2026-10-16)

| Source | How to read it | Notes |
| --- | --- | --- |
| Extraordinary gazettes | `documents.gov.lk/web/extra_gazettes` is a Next.js page whose table loads through a server action, `TableDataAction`. A plain POST to the page with its `next-action` ID and the body `[{"apiEndpoint": ".../extra-gazette/get-all", "page": N, "limit": 100, ...}]` answers with JSON: number, date, descriptions, and the PDF file per language. PDFs download from `/api/content-file-proxy?file=/extra-gazette-content/<file>.pdf`. No browser needed. | The action ID is defined in one of the site's scripts as `createServerReference("<id>", ..., "TableDataAction")`, so a rebuild that changes it is found again automatically. 2,249 gazettes in 2026 up to mid-October; 91 numbers are listed twice (merged by number); 72 have no PDF; the "Tamil" description is English text. Loads from servers abroad. |
| CAA price controls | Same list, issuer "Consumer Affairs Authority" (e.g. 2509/31, 7 Oct 2026). | Prices are in the PDF text. |
| Fuel | CEYPETCO JSON: `api.ceypetco.gov.lk/api/admin/fuel-prices/active?limit=100` (product, price in LKR, effective date). Read by the app on the phone. | Only answers inside Sri Lanka: connections from every foreign test server failed (USA, Germany, Singapore and more). |
| LP gas | Litro: `litrogas.com/price-list/` shows the list as one image whose file name carries the date (e.g. `Price-List-06.10.2026.webp`). | A new file name means new prices. The full-size image is the shortest URL (resized copies end in e.g. `-300x374`). v1 shows the image; reading the numbers comes later. |
| USD/LKR | CBSL's rate search: a plain form POST to `cbsl.gov.lk/cbsl_custom/exrates/exrates_results.php` (`chk_cur[]=USD~US Dollar`, `txtStart`, `txtEnd`) returns a table of daily rates; read by the app on the phone. The workflow keeps Frankfurter's copy, `api.frankfurter.dev/v2/rates?providers=CBSL&base=USD&quotes=LKR&from=...&to=...`, as a backup. | CBSL's results page answers 403 to most servers abroad (the USA, Spain, Israel, Kazakhstan). Frankfurter's copy was a week behind (latest 2026-10-09 on 2026-10-16) but has the same numbers. |
| Holidays | Google's public Sri Lanka holiday calendar (ICS feed, no key). | Has Poya days, but also observances like Mother's Day, so only events marked "Public holiday" are kept; tentative dates are flagged. The Tamil calendar (`ta.lk`) still has English names, so Tamil holiday names come from the app (M5). |
| Exam notices | Department of Examinations JSON: `doenets.lk/cms/api/resources?isEnabled=1&rowCount=N&type=NEWS` for news and `type=EXCA` for the exam calendar (timetables and monthly calendars), with titles in English, Sinhala and Tamil (real Tamil) and one PDF per language. The calendar is PDFs, not dates. | The homepage refuses plain HTTP (403), but the JSON answered, from servers abroad too. Results are per-candidate lookups, so alerts cover "results released" notices only. |

## Design

**Repo layout (`main`)**

- `scrapers/`: Python 3.12 package, one module per source. A shared HTTP client (retries, polite user agent, a pause between pages, never downloads a known PDF twice). From M4: PDF text through pdfplumber, with pdfminer for the glyph IDs of Arial Unicode Tamil. No OCR: every gazette so far has a text layer. Tests run on saved fixtures, not live sites.
- `app/`: Flutter, Android only.
- `scripts/release/`: works out the next version and the release notes (Python, standard library only, with tests).
- `.github/workflows/`: `scrape.yml` (every 3 hours, commits to `data`), `ci.yml` (Python and Flutter checks), `release.yml` (signed APK to GitHub Releases), `pr-title.yml` (Conventional Commit titles).
- `ruff.toml` at the root holds the Python lint and format settings for both `scrapers/` and `scripts/`.

**Data branch (`data`)**

- `items/<yyyy>/<mm>/<id>.json`: one file per feed item. Feed items are news: a fuel price change, a USD/LKR move of 2% or more in a week, a gazette, an exam notice. IDs are stable, e.g. `gazette-2510-36`, `fuel-2026-09-30`, `rates-usd-lkr-2026-06-08`, `exam-2468`.
- `latest.json`: the newest 200 items, small enough to fetch on every sync. It changes only when items do.
- `datasets/<name>.json`: values for the "now" strip and reminders: `usd-lkr` (Frankfurter's copy of the daily rate since 1 January 2026, a backup for the phone's same-day CBSL rate) and `holidays` (public holidays from 2026 on). Fuel prices live on the phone, which reads them itself.
- `state/<name>.json`: the scrapers' own bookkeeping, not for the app (e.g. the gazette action ID and the newest gazette seen).
- `status.json`: when the last run happened, and per source the last run, last success, last error and failures in a row. A source that fails 3 runs in a row fails the workflow once (one email); later failures are only recorded, and the app flags the source.
- Item fields: `id`, `source`, `topic` (`prices`, `gazettes`, `rates`, `holidays`, `exams`), `issuer`, `headline` (en, ta), `keyNumbers`, `published`, `effective`, `links` (pdf_en, pdf_ta, pdf_si, image, page), `data` (structured values, e.g. old and new fuel price), `alert`.
- The app reads `raw.githubusercontent.com/ThivaaVipul/lanka-radar/data/...`: public, no token.

**Headlines (from M4)**

- Each gazette item's English and Tamil PDFs are read once (`pdfs.py`), 40 gazettes a run at most, newest first; while a backlog remains, runs read the list back to January so older items come into view. Results are cached in `state/gazette-pdfs.json` and read again only when a gazette's files change. A broken PDF is recorded and not retried.
- Page 1's title is the bold, capitals or larger block right after the masthead (which ends with the last line of 13.5 pt or more), skipping a reference line above it (DGC/A877/PL305., Order No.: 97).
- English headline: the list's description when it names a subject ("Ministry of Energy - Revise the Fuel Price"), otherwise the PDF title, otherwise the description. Tamil headline: the Tamil PDF's title, only when its text is trusted (see the decision above).
- Price tables (a header naming a price column) become key numbers; a table with a current and a revised price (fuel revisions) gives the revised price with the current one as before. A price table also puts the item under Prices.
- The group rules are checked again against the PDF title, so a routine notice listed only by its issuer (a weekly customs exchange-rate notice) is dropped.

**App**

- Home: a "now" strip (fuel prices, USD/LKR, next holiday, the latest exam timetable) above the feed, with topic chips.
- Item: English headline, Tamil a tap away, key numbers where the source has them, the PDF in English or Tamil.
- Settings: an alert switch per topic, quiet hours, source health.
- Sync: WorkManager about every 3 hours on any network. It compares `latest.json` with the local database (drift, with full-text search) and notifies for new alert items, outside quiet hours only.
- Phone-side sources, in the same sync: CEYPETCO's fuel feed and CBSL's rate search, which only answer inside Sri Lanka. The app keeps the fuel price history and the daily rate locally and makes `fuel-<date>` and `rates-usd-lkr-<date>` items exactly as the workflow did, so items from either side merge by ID. If CBSL can't be reached, the "now" rate falls back to `datasets/usd-lkr.json`.
- Holiday reminders: local notifications scheduled for the evening before (inexact, so no exact-alarm permission).
- The notification permission is asked once, after the first sync.

## Milestones

Each milestone ends with ruff, pytest, `flutter analyze` and `flutter test` passing, plus a debug APK build once the app exists.

### M0: Project setup

- [x] README, CLAUDE.md, this plan, MIT license, LF line endings, editorconfig
- [x] Python tooling (ruff, pytest) and the Flutter project (Android only, `app.lankaradar`, strict analyzer)
- [x] CI workflow
- [x] Git workflow and automatic releases: `scripts/release/` with tests, `release.yml`, `pr-title.yml`, release signing from `android/key.properties` with a debug key fallback
- [x] Git repo, published as the public `ThivaaVipul/lanka-radar`; the first CI run passed

### M1: Pipeline and easy sources

- [x] Item schema, JSON writer, `latest.json`, `datasets/`, `status.json`
- [x] Scrape workflow that commits to the `data` branch (creates the branch on its first run)
- [x] Fuel (CEYPETCO), USD/LKR (CBSL's search form, Frankfurter as fallback), holidays (ICS, filtered); checked live into a scratch folder
- [x] Keep the schedule alive: each run re-enables the workflow through the API, since data commits don't count as activity on `main`
- [x] First run on GitHub created and filled the `data` branch; it showed that CEYPETCO and CBSL refuse GitHub's servers
- [x] Fuel and CBSL left the workflow (the app reads them, M5); USD/LKR on GitHub is Frankfurter only; `status.json` drops removed sources

### M2: Gazettes

- [x] Reader for the extraordinary gazette list through the site's `TableDataAction` (plain HTTP, 100 a page, a pause between pages); no Playwright needed
- [x] The action ID is found again in the site's scripts after a rebuild, and kept in `state/gazettes.json`
- [x] Copies of one gazette merged by number (PDFs combined, fuller description kept); an answer without data is retried
- [x] Daily-life groups matched on the issuer: prices, taxes and imports (weekly customs exchange-rate notices skipped); energy and utilities; wages and labour; elections. Any gazette mentioning a price goes to the Prices topic (CAA orders, fuel price revisions, the monthly consumer price index)
- [x] History from 1 January 2026: 393 items in a 31-second first run; later runs read one page
- PDF download and text moved to M4, where their text is first used

### M3: Exams and LP gas

- [x] Exam notices from the news feed and timetables from the exam calendar: school exams and the department's notices (12 items in 2026), with the Tamil titles
- [x] Litro: a new price-list image, spotted by its dated file name, becomes a Prices item linking the full-size image

### M4: Headlines and topics

- [x] PDF download (English and Tamil where they exist) for gazette items, 40 a run, newest first, with the backlog read on later runs
- [x] Title block from page 1; English titles found in 37 of 37 English PDFs in a live run
- [x] Tamil titles from Bamini-encoded fonts (Open-Tamil); scrambled Arial Unicode text is never used (M4b reads it from the glyph IDs)
- [x] Price tables read into key numbers: CAA orders (canned fish, bottled water) and fuel revisions (with the price before)
- [x] Routine notices caught by their PDF title are dropped (weekly customs exchange rates)

### M4b: Tamil titles from glyph IDs

- [x] Arial Unicode MS Tamil read from the glyph IDs, since the PDFs' own text maps are scrambled, and put back in reading order; titles for all 24 such PDFs of the first M4 run, checked by eye against the page images
- [x] Bold drawn as a second, outline-only copy is skipped (one copy was set 4 points off its text) and marks the line bold
- [x] A line is trusted only when every glyph is known and every vowel sign follows a letter
- [x] Older readings without a Tamil title get their Tamil PDF read once more; English PDFs aren't downloaded again
- OCR not needed; moved to Later in case a Tamil PDF in another font shows up

### M5: App

- [ ] Feed from `latest.json`, local database with search, item screen, PDF links
- [ ] History for a fresh install: `latest.json` holds only the newest 200 items (about three months of gazettes), so the workflow adds monthly item files for the app to backfill from
- [ ] Phone-side sources: fuel (CEYPETCO) and USD/LKR (CBSL), with local history and the same item IDs as the workflow; tests on saved responses (the M1 fixtures are in git history)
- [ ] "Now" strip, topic chips, pull to refresh, source health

### M6: Alerts

- [ ] Background sync about every 3 hours, notifications for new alert items
- [ ] Per-topic switches, quiet hours 22:00 to 06:00
- [ ] Holiday reminders the evening before

### M7: Releases and field test

- [ ] Create the signing key and add the four repository secrets (you, once; README has the steps)
- [ ] First release installed from GitHub Releases, and an update installs over it
- [ ] Two weeks of daily use; tune topics and alerts

## Open questions

None right now.

## Later

- Lanka MCP on the same data
- Sinhala headlines (the official Sinhala PDFs make this easy)
- AI summaries, if headlines turn out not to be enough (a small model inside the workflow, or a free API key)
- Public channels (Facebook Page, WhatsApp Channel) and a web page
- LP gas prices read from Litro's image
- Exam dates read from the timetable PDFs, for a "next exam" in the now strip
- Weekly gazettes, Acts and Bills; water and power interruptions; Laugfs gas
- OCR (Tesseract, on GitHub's servers) for Tamil PDFs in a font the reader doesn't know, if one shows up

## Log

| Date | Change |
| --- | --- |
| 2026-10-16 | Design settled in a grilling session; plan created. Sources checked live: the gazette site was rebuilt (old links 404), and CEYPETCO and the exam site have JSON feeds. |
| 2026-10-16 | USD/LKR comes from CBSL's own site first, since Frankfurter's CBSL series lagged a week. LP gas alerts on a new Litro price-list image; reading the numbers moved to Later. |
| 2026-10-16 | GitHub Models was retired on 30 July 2026, so v1 has no AI: items use the official headlines from their English and Tamil PDFs. M4 became "Headlines and topics". |
| 2026-10-16 | M0 built; all checks pass locally and the debug APK builds. Added the git workflow and automatic releases, ported from TaskPulse to Python so the repo needs no Node. Action versions checked with Context7: checkout v7, setup-python v7, setup-java v6, flutter-action v2. Release signing moved into M0; M7 keeps creating the key and the first release. |
| 2026-10-16 | Repo published as public. Its git identity uses the GitHub noreply email, so no personal email is in the history. |
| 2026-10-16 | M1: current values (fuel prices, USD/LKR, holidays) live in `datasets/`; feed items are only for news. Fuel keeps a per-product price history so each change shows the price before it. USD/LKR makes an item only for a 2% move in a week, at most one a week. A first live run found 3 fuel items and 3 rate moves (May and June 2026) and 53 holidays. |
| 2026-10-16 | Only commits that change `app/` count toward app releases, so scraper and tooling work never publishes an empty app. |
| 2026-10-16 | GitHub pauses schedules after 60 days without activity on the default branch, and `data` commits don't count, so the scrape workflow re-enables itself through the API on every run. |
| 2026-10-16 | First GitHub run: CEYPETCO refused the connection and CBSL's rate search answered 403. Tests from servers in 8 countries (check-host.net) showed CEYPETCO only answers inside Sri Lanka and CBSL refuses most servers abroad, while the gazette list, the exam JSON, Litro and Google all load. Decision: the app reads fuel and CBSL on the phone; the workflow keeps Frankfurter's rates as a backup with the same item IDs. This resolves the runner-IP question for exams. |
| 2026-10-16 | CI on `main` failed once in the debug APK build with no app change (it passed minutes earlier on the PR), most likely a download hiccup. Workflows now pin `ubuntu-24.04` (`ubuntu-latest` moves to Ubuntu 26 on 19 October 2026) and cache Gradle downloads. |
| 2026-10-16 | M2: the gazette table's server action answers with JSON (PDF file names included), so the reader is a plain POST instead of Playwright; its ID is found again in the site's scripts after a rebuild. Gazette groups chosen: prices, taxes and imports; energy and utilities; wages and labour; elections (390 of 2,157 gazettes in 2026). PDF download moved to M4. Two live-run bugs fixed: `splitlines()` cut rows at characters like U+2028 inside descriptions, and a brief answer without data is now retried. |
| 2026-10-16 | M3: exam notices from the CMS news feed plus timetables from its exam calendar (type `EXCA`), chosen as school exams and the department's notices; these items are the first with real Tamil headlines. The calendar holds PDFs rather than dates, so "next exam date" in the now strip became "the latest exam timetable", and reading dates from the PDFs moved to Later. Litro's price list became an item, keyed by the date in the image's file name. |
| 2026-10-16 | M4: gazette PDFs read with pdfplumber. English gazettes have a fixed masthead followed by a bold or capitals title block; English titles were found in 37 of 37 PDFs. Tamil PDFs use either Bamini-encoded fonts (converted with Open-Tamil; Latin runs inside them kept as they are) or Arial Unicode with scrambled text, which turned out to be about 8 in 9 rather than the half first estimated, so Tamil OCR became its own step (M4b). Price tables from CAA orders and fuel revisions became key numbers. The group rules now also run on the PDF title, which drops weekly customs exchange-rate notices listed only as "Sri Lanka Customs". |
| 2026-10-16 | M4 merged (PR #6). Its first run on GitHub read 40 gazettes in under 3 minutes: English titles for all 37 with an English PDF. The only Bamini Tamil PDFs were 3 customs notices, dropped as routine, so no feed item had a Tamil headline yet. The state saved before M4 had no backlog count, so that run looked at only the last 3 weeks; it left 3 gazettes waiting, which switches the next runs to the whole year. |
| 2026-10-16 | M4b: the scrambled Arial Unicode Tamil turned out to be readable without OCR. These PDFs keep Arial Unicode MS's glyph IDs, and that font's glyph order never changed, so the Tamil comes from the glyph IDs: letters and signs through the font's own cmap (found in a copy one PDF embeds), ligatures as seen in 24 PDFs, signs drawn left of their letter moved after it, and look-alike glyphs fixed (aa drawn for ra before i). All 24 Tamil PDFs of the first M4 run got their titles, checked by eye against the rendered pages, and the titles of 40 English and Bamini PDFs are unchanged. Decision: decode instead of OCR, which moved to Later. Bold drawn as an outline copy is skipped, and a bold paragraph after a larger title ends the title. |
