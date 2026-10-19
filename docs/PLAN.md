# Lanka Radar plan

Living document, updated as work proceeds. Last updated: 2026-10-19.
Status: **M0 to M7 built: the app is released (v0.2.0 updated over v0.1.0) and in daily use. Now: M8 (a redesign and more sources), grilled on 2026-10-19 and planned below; M8a to M8c are done; M8d (the search screen) is next.**

A personal Android app that watches Sri Lankan official sources (gazettes, price controls, fuel, exchange rates, holidays, exam notices) and tells you when something new lands. GitHub Actions does most of the watching and the app reads what it publishes; the two sources that only answer inside Sri Lanka are read by the app itself.

## Decisions (2026-10-16, grilling session)

- **Purpose:** personal side project, built in the open. For now it is only for you: nothing is posted anywhere.
- **Content (v1):** price controls and fuel (CAA price-control gazettes, CEYPETCO fuel, LP gas), daily-life extraordinary gazettes, holidays and USD/LKR rates, exam notices.
- **USD/LKR:** the app reads CBSL's own site on the phone (the same-day official rate); the workflow keeps Frankfurter's copy as a backup.
- **Sri Lanka-only sources (decided after the first GitHub run):** CEYPETCO's fuel prices and CBSL's rate search refuse GitHub's servers abroad, so the app fetches both on the phone during its sync. CBSL's same-day rate also makes the rare USD/LKR items, with the same IDs as the workflow's. Fuel makes no items on the phone (decided in the M5 grilling): fuel price changes arrive as fuel revision gazettes, which carry the old and new prices, and CEYPETCO's live prices fill the Now card.
- **LP gas:** alert when Litro posts a new price-list image, and show that image. Reading the numbers comes later.
- **Moving parts:** only GitHub and the app. No Claude, Firebase, servers or other accounts.
- **Scrapers:** Python on GitHub Actions; results saved as JSON in the repo.
- **Text:** no AI. Each item uses its official headline, taken from the first page of its English and Tamil PDFs. (GitHub Models, the first choice, was retired on 30 July 2026.)
- **App:** Android (Flutter). English menus; each item shows the English headline with the Tamil one a tap away, plus the official PDF in each language that exists. Details in the M5 decisions below.
- **Alerts:** price changes, exam dates and results, holiday reminders, other daily-life gazettes and USD/LKR moves over 2% in a week. Every topic has its own on/off switch.
- **Name:** Lanka Radar. Repo `lanka-radar`, app ID `app.lankaradar`.
- **Parked:** Lanka MCP, Sinhala, public posting (Facebook Page, WhatsApp Channel), a web page.
- **Gazette groups (2026-10-16):** prices, taxes and imports; energy and utilities; wages and labour; elections. Each becomes a feed item with an alert; everything else (land title settlement, land acquisition and so on) is skipped.
- **Tamil gazette titles (2026-10-16):** Tamil PDFs come in two kinds. Bamini-encoded fonts (GP-Rasanji, Bamini, Tharmini) convert cleanly to Unicode with Open-Tamil. The rest, about 8 in 9 (election and CAA notices), use Arial Unicode MS with scrambled text maps; their Tamil is read from the glyph IDs instead, which gives the exact text (M4b). OCR was the first plan for them and turned out not to be needed.
- **Exam notices (2026-10-16):** school exams (O/L, A/L, Grade 5 scholarship, GIT), their timetables, and the department's own press releases and notices. Admission cards for institutional exams, religious and Piriven exams, recruitment exams and the monthly exam calendars are left out.
- **App (M5 grilling, 2026-10-16):**
  - Feed card: topic and issuer with the date, the headline in up to 3 lines, and on price items the first key numbers with the price before. Titles in capitals are shown in title case (small words in lower case; acronyms, numbers and roman numerals kept); the data keeps the official text. When the English headline is only the issuer (no English PDF), the card shows the Tamil title.
  - Feed: newest first, a quiet month heading where the month changes, the date on each card. A dot marks items that arrived since the last visit; older history filling in is never marked.
  - Item screen: the English headline with the Tamil one under it, key numbers, the gazette number and dates, English and Tamil PDF buttons (Sinhala only when it is the only PDF) and the official page. PDFs open in the browser.
  - Search: English and Tamil headlines, issuer and number, over all history, offline.
  - History: a fresh install shows the newest items first and loads the rest of 2026 in the background.
  - Now card above the feed: all six CEYPETCO fuel prices, USD/LKR, the next holiday, LP gas (the price list's date) and the latest exam timetable. Tapping opens small sheets: fuel prices with the date each started and the price before; USD/LKR over the last 30 days; the year's remaining holidays with the Tamil name under each; Litro's price-list image; the exam item.
  - Refresh on opening when the last refresh is over 15 minutes old, and on pull to refresh (background sync is M6).
  - Health: nothing extra while all is well. A source with no success for a day puts a warning in the app bar, and a stale Now value shows its own date ("as of 14 Oct"). A Sources screen lists each source's last success and error.
  - Look: Zen Mode's style (Albert Sans, rounded cards, motion, dark mode following the system) with the teal accent; Tamil uses the phone's Tamil font.
- **Alerts (M6 grilling, 2026-10-16):**
  - One notification per new item, stacked under Lanka Radar, with its headline (and key numbers on price items); tapping it opens the item.
  - Switches: Prices, Exams, USD/LKR moves, Holiday reminders, and gazettes by group (Taxes and imports, Energy and utilities, Wages and labour, Elections). All start on except Elections, which is most gazettes (about 1 to 3 a day). A gazette with prices counts as Prices.
  - Fuel: a change in CEYPETCO's prices alerts right away ("Fuel prices changed: Petrol 92 399 (was 414)"; tapping opens the fuel prices). A fuel revision gazette then alerts only if its prices are new to the phone.
  - Quiet hours: a switch with adjustable start and end, 22:00 to 06:00 to begin with; anything found then waits for the first sync after the end.
  - Holiday reminders at about 19:00 the evening before every public holiday, Poya days included, with tentative dates marked and the Tamil name.
  - Battery: the Alerts screen has a row that opens the app's system settings (battery No restrictions, Autostart on Xiaomi phones), and shows when the last background sync ran.
  - Nothing alerts for a fresh install's history or while the app is open (the dots cover that). Android channels: New items, Fuel prices, Holiday reminders. The menu has Alerts, Sources and About.
- **Redesign and more sources (M8 grilling, 2026-10-19):**
  - Layout: a bottom bar with four tabs, Today, Prices, Notices and Dates; search in the top bar; the menu keeps Alerts, Sources and About. Today shows only what is new for you, the key numbers with trend arrows, the next holiday and a power cut going on in your area. The Now card and its sheets give way to the tabs.
  - Election notices never show on Today; in Notices they fold into one row a week ("Election notices (7)").
  - Look: the calm teal stays, with an icon and tint per topic, large numbers with up and down arrows (ochre for rises, teal for falls) and small trend lines.
  - Cards say what changed, made from the data where it allows ("Tuna 155g fixed at Rs 480, was 500"), otherwise the official title in up to 2 lines, then one small line with the issuer and date. The full title, the Tamil title and the PDFs are on the item page. English throughout; a Tamil-only notice shows its Tamil title.
  - Search matches what the cards show and common other spellings (O/L, timetable, dollar). It covers everything (notices, prices, dates, exams) in groups of compact rows with the match highlighted, and a group header filters to its group. Before you type: suggestion chips and the last 5 searches.
  - Features: price charts (USD/LKR, each fuel, controlled prices); Dates with holidays, long weekends and exam dates read from the timetable PDFs, with countdowns and add to calendar; a home-screen widget (Petrol 92, Diesel, USD/LKR, the next holiday); sharing as text with the official link; jobs from the Public Service Commission as a topic with its own switch; power cuts from EDLCare for the area you pick, plus your CEB account number (optional, kept on the phone) for planned cuts. Planned cuts alert at 19:00 the evening before; breakdowns in your area alert when a sync sees them, except in quiet hours, when they are dropped.
  - Market prices: the Central Bank's Daily Price Report (retail prices at Pettah, Dambulla and Narahenpita, weekdays: rice, vegetables, onions, potatoes, dhal, sugar, eggs, coconut, fish, fruit) becomes a dataset; Prices gets a Market section with a chart per item, and search finds them. No alerts, since these move every day.
  - Not now: watch words and places, water cuts (the Water Board publishes no notices), a Tamil interface, the weekly gazette's vacancies, HARTI's wholesale prices and supermarket prices (Later).
  - The workflow runs every hour, and so does the phone's background sync.

### Defaults (accepted 2026-10-16)

- Public repo under ThivaaVipul, MIT license. Scraped data is committed to a separate `data` branch, so `main` holds only code.
- Scrapers run every hour (every 3 hours until M8a). The app checks about every hour, plus pull to refresh, and stays silent from 22:00 to 06:00 (anything new arrives in the morning).
- History is loaded from 1 January 2026.
- Flutter with one Cubit per screen, like Zen Mode, and an offline copy you can search.
- GitHub Actions builds the signed APK; you install it from GitHub Releases. No Play Store.
- Each source records its last successful run. The app flags a source that has gone quiet, and GitHub emails you when a run fails.
- Nothing git-related happens without your OK at each step. Commits end with Claude's `Co-Authored-By` line (since 2026-10-16; earlier ones have none).
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
| Market prices | CBSL's Daily Price Report: `cbsl.gov.lk/en/statistics/economic-indicators/price-report` lists one PDF per weekday, `/sites/default/files/cbslweb_documents/statistics/pricerpt/price_report_YYYYMMDD_e.pdf` (older ones without the underscore before `e`). Page 2 is a table of yesterday's and today's wholesale and retail prices. | Checked 2026-10-19: loads from abroad, unlike CBSL's rate search. Text PDF made from Excel, so a table-aware reader (pdfplumber) is needed. No milk powder, bread or flour. HARTI's daily wholesale PDFs (`harti.gov.lk/daily-price.php`, many economic centres, weekends too) also load from abroad (Later). |
| Power cuts | EDLCare (`edlcare.edl.lk`, where `cebcare.ceb.lk` now redirects): a public JSON API used by its outage map, `/api/incognito/provinces`, `/areas?provinceId=`, `/outage-locations?areaId=` (breakdowns, demand management and planned cuts with start, end and customers) and `/calendar?acctNo=&from=&to=` (scheduled cuts for one account, no login). | Checked 2026-10-19: answers from Sri Lanka and from abroad. Unofficial and undocumented, so it may change; asked gently. Areas are CEB area offices, not districts. |
| Jobs | Public Service Commission (`psc.gov.lk`): recruitment announcements on its homepage, each a PDF under `/images/latest_document/psc_announcements/<year>/`, titled with the post. | Checked 2026-10-19 from Sri Lanka. Covers PSC recruitments only; the weekly gazette's "Posts - Vacant" is the full list (Later). The Water Board's interruptions page has had no notices since 2022, so water cuts are out. |
| Exam notices | Department of Examinations JSON: `doenets.lk/cms/api/resources?isEnabled=1&rowCount=N&type=NEWS` for news and `type=EXCA` for the exam calendar (timetables and monthly calendars), with titles in English, Sinhala and Tamil (real Tamil) and one PDF per language. The calendar is PDFs, not dates. | The homepage refuses plain HTTP (403), but the JSON answered, from servers abroad too. Results are per-candidate lookups, so alerts cover "results released" notices only. |

## Design

**Repo layout (`main`)**

- `scrapers/`: Python 3.12 package, one module per source. A shared HTTP client (retries, polite user agent, a pause between pages, never downloads a known PDF twice). From M4: PDF text through pdfplumber, with pdfminer for the glyph IDs of Arial Unicode Tamil. No OCR: every gazette so far has a text layer. Tests run on saved fixtures, not live sites.
- `app/`: Flutter, Android only.
- `scripts/release/`: works out the next version and the release notes (Python, standard library only, with tests).
- `.github/workflows/`: `scrape.yml` (every hour, commits to `data`), `ci.yml` (Python and Flutter checks), `release.yml` (signed APK to GitHub Releases), `pr-title.yml` (Conventional Commit titles).
- `ruff.toml` at the root holds the Python lint and format settings for both `scrapers/` and `scripts/`.

**Data branch (`data`)**

- `items/<yyyy>/<mm>/<id>.json`: one file per feed item. Feed items are news: a gazette (fuel price revisions included), a new LP gas price list, a USD/LKR move of 2% or more in a week, an exam notice. IDs are stable, e.g. `gazette-2510-36`, `gas-litro-2026-10-06`, `rates-usd-lkr-2026-06-08`, `exam-2468`.
- `latest.json`: the newest 200 items, small enough to fetch on every sync. It changes only when items do.
- `months/<yyyy-mm>.json` (from M5): every item published in that month, for the app's history and so that later fixes to older items (a Tamil title found by a re-read) reach the phone. `months/index.json` lists each month with its item count and a hash of its file, so the app downloads only the months that changed.
- `datasets/<name>.json`: values for the "now" strip and reminders: `usd-lkr` (Frankfurter's copy of the daily rate since 1 January 2026, a backup for the phone's same-day CBSL rate) and `holidays` (public holidays from 2026 on). Fuel prices live on the phone, which reads them itself.
- `state/<name>.json`: the scrapers' own bookkeeping, not for the app (e.g. the gazette action ID and the newest gazette seen).
- `status.json`: when the last run happened, and per source the last run, last success, last error and failures in a row. A source that fails 3 runs in a row fails the workflow once (one email); later failures are only recorded, and the app flags the source.
- Item fields: `id`, `source`, `topic` (`prices`, `gazettes`, `rates`, `holidays`, `exams`), `issuer`, `headline` (en, ta), `keyNumbers`, `published`, `effective`, `links` (pdf_en, pdf_ta, pdf_si, image, page), `data` (structured values, e.g. a gazette's number and group), `alert`.
- The app reads `raw.githubusercontent.com/ThivaaVipul/lanka-radar/data/...`: public, no token.

**Headlines (from M4)**

- Each gazette item's English and Tamil PDFs are read once (`pdfs.py`), 40 gazettes a run at most, newest first; while a backlog remains, runs read the list back to January so older items come into view. Results are cached in `state/gazette-pdfs.json` and read again only when a gazette's files change. A broken PDF is recorded and not retried.
- Page 1's title is the bold, capitals or larger block right after the masthead (which ends with the last line of 13.5 pt or more), skipping a reference line above it (DGC/A877/PL305., Order No.: 97).
- English headline: the list's description when it names a subject ("Ministry of Energy - Revise the Fuel Price"), otherwise the PDF title, otherwise the description. Tamil headline: the Tamil PDF's title, only when its text is trusted (see the decision above).
- Price tables (a header naming a price column) become key numbers; a table with a current and a revised price (fuel revisions) gives the revised price with the current one as before. A price table also puts the item under Prices. Labels drop Latin names in brackets, and a sentence about a pack becomes its first quantity ("Tuna 155g").
- The group rules are checked again against the PDF title, so a routine notice listed only by its issuer (a weekly customs exchange-rate notice) is dropped.

**App**

- Screens: Home (the Now card, topic chips and the feed), Item, Search, Sources and About, with a plain `Navigator` like Zen Mode. Topic chips: All, Prices, Gazettes, Exams, Rates (holidays are not feed items).
- Data: drift (SQLite) holds the items, each as its JSON plus the columns to sort, filter and search by. Search is a LIKE over a lower-case text of the English and Tamil headlines, issuer and number: with about 500 items a year a scan is instant, and it matches Tamil too. A refresh reads `months/index.json` and downloads only the months that changed, newest first, plus `datasets/holidays.json`, `datasets/usd-lkr.json` and `status.json`; ETags keep unchanged files from downloading again.
- Headlines: title case for words in capitals is applied on screen only. A card shows the Tamil headline when the English one is only the issuer.
- Phone-side sources, in the same refresh: CEYPETCO's active fuel prices (one row per product, no history) and CBSL's rate search, which only answer inside Sri Lanka. The app keeps each fuel product's price history and the daily rate. A fuel price's "before" comes from that history, otherwise from the latest fuel revision gazette; until CEYPETCO first answers, the fuel part of the Now card shows that gazette's prices with its date. From M6, CBSL's rates also make `rates-usd-lkr-<date>` items exactly as the workflow does from Frankfurter, so both sides merge by ID and a big move alerts the same day; if CBSL can't be reached, the rate falls back to `datasets/usd-lkr.json`.
- Holidays: Tamil names come from a small table in the app; a name missing from it stays English only.
- Health: `status.json` for the workflow's sources, and the app's own record for CEYPETCO and CBSL.
- The app declares the INTERNET permission in its main manifest (release builds have none yet), in M5.
- Alerts screen (M6): the switches, quiet hours, a battery row and the last background sync. Notifications are posted per item into three channels (New items, Fuel prices, Holiday reminders); a tap opens the item, the fuel prices or the holidays.
- Background sync (M6): WorkManager about every hour (every 3 hours until M8a) on any network runs the same refresh as opening the app (month files, datasets, status, CEYPETCO, CBSL), then notifies for items first seen in that sync that are on, recent (published in the last 14 days) and outside quiet hours; held items go out after quiet hours. Nothing is posted while the app is in front.
- Holiday reminders (M6): inexact local notifications at about 19:00 the evening before (no exact-alarm permission), scheduled again after each refresh of `datasets/holidays.json`.
- The notification permission is asked once, after the first sync (M6).

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
- [x] A glyph not in the table yet keeps its line untrusted and is recorded with the reading (`unknown_glyphs`), so the table can grow; two more were added after the first full runs (8077 and 8088)
- OCR not needed; moved to Later in case a Tamil PDF in another font shows up

### M5: App

Five pull requests, each with its tests:

- [x] M5a, workflow: monthly item files and their index (`months/`), written from the stored items on every run
- [x] M5b, app foundation: Zen Mode's theme with teal and Albert Sans, the drift database, the refresh (index, changed months, datasets, status, ETags), the INTERNET permission; Home is a plain list of headlines until M5c
- [x] M5c, feed and item: Home feed with month headings, cards, title case, new-item dots, topic chips and pull to refresh; the item screen with PDF buttons; search
- [x] M5d, Now card: CEYPETCO fuel and CBSL rates read on the phone with local history (tests on the saved M1 responses), the detail sheets, holidays with Tamil names, LP gas and the exam timetable; the phone's own USD/LKR move items moved to M6
- [x] M5e, health and finish: Sources and About screens, stale warnings, empty and error states; checked on a real phone

### M6: Alerts

Three pull requests, each with its tests:

- [x] M6a, background alerts: WorkManager sync about every 3 hours (the app's refresh in the background), a notification per new item with the default switches, the permission asked once after the first sync, nothing for history or while the app is open
- [x] M6b, Alerts screen: the switches (gazettes by group), quiet hours with adjustable times and held alerts, the battery row and the last background sync; Alerts in the menu
- [x] M6c, the phone's own alerts: CEYPETCO fuel changes (and fuel gazettes only when new), `rates-usd-lkr-<date>` items from CBSL's same-day rates (the workflow's IDs, kept through the month files' refresh), holiday reminders at 19:00 the evening before

### M7: Releases and field test

- [x] Create the signing key and add the four repository secrets (you, once; README has the steps)
- [x] First release installed from GitHub Releases (v0.1.0), and an update installs over it (v0.2.0)
- [x] An app icon: a radar sweep, as an adaptive icon with a themed-icon layer, and the same radar as the notification icon
- [ ] Two weeks of daily use; tune topics and alerts

### M8: Redesign and more sources

Nine pull requests, each its own release:

- [x] M8a, search fix and hourly: search matches what the cards show (topic, price labels, "gazette 2509/31") and common other spellings; the workflow and the phone's background sync run every hour
- [x] M8b, layout: the Today, Prices, Notices and Dates tabs, the new cards, election notices folded
- [x] M8c, jobs: the Public Service Commission's recruitments as a topic, with an alert switch
- [ ] M8d, search screen: one search over notices, prices, dates and exams, grouped, with suggestions and recent searches
- [ ] M8e, price charts: USD/LKR, each fuel, controlled prices
- [ ] M8f, market prices: the Central Bank's daily retail prices as a dataset, a Market section in Prices with charts, searchable
- [ ] M8g, Dates: holidays, long weekends, exam dates read from the timetable PDFs, countdowns, add to calendar
- [ ] M8h, power cuts: EDLCare by area and account, reminders for planned cuts, alerts for breakdowns
- [ ] M8i, a home-screen widget and sharing

## Open questions

None right now.

## Later

- Lanka MCP on the same data
- Sinhala headlines (the official Sinhala PDFs make this easy)
- AI summaries, if headlines turn out not to be enough (a small model inside the workflow, or a free API key)
- Public channels (Facebook Page, WhatsApp Channel) and a web page
- LP gas prices read from Litro's image
- HARTI's daily wholesale prices from the economic centres; supermarket prices (Keells, Cargills, Glomark), if a fair way to read them turns up
- Weekly gazettes (their vacancies first), Acts and Bills; water interruptions, if the Water Board starts publishing them; Laugfs gas
- OCR (Tesseract, on GitHub's servers) for Tamil PDFs in a font the reader doesn't know, if one shows up
- Search inside the gazettes' text (the workflow would keep each PDF's text)
- An in-app PDF viewer that keeps offline copies

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
| 2026-10-16 | M4b merged (PR #7). Its first run on GitHub gave a Tamil title to all 35 gazettes read so far that have a Tamil PDF; 32 feed items carry one (the other 3 are customs notices dropped as routine). |
| 2026-10-16 | M5 grilled; the decisions are under "App (M5 grilling)". Fuel price changes now come only from fuel revision gazettes, which carry the old and new prices; CEYPETCO, which gives only each product's active price, fills the Now card instead of making items, so a change shows (and later alerts) once. History reaches the app as monthly item files with an index, so later fixes to older items reach the phone too. M5 is split into five pull requests, M5a to M5e. |
| 2026-10-16 | M5a merged (PR #8): the `data` branch has month files for January to October (408 items). The first price table to come in (CAA canned fish, 2504/86) showed long labels with Latin names that cut off before the pack size, so labels now drop bracketed Latin names and keep the net weight ("Tuna 155g"). Two Tamil notices had no title because of two glyphs not yet in the table (the shapes of tuu and puu); they were added, and an unknown glyph is now recorded with the reading. Reader version 3 reads the affected PDFs again once. |
| 2026-10-16 | M5b: drift 2.34 with SQLite bundled by the `sqlite3` package's build hooks, so tests run on any desktop with no extra setup. Each item is stored as its JSON plus columns to sort, filter and search by, and keeps the time the phone first saw it (for M5c's new-item dots). Search is a LIKE over a lower-case search column instead of the trigram index first planned: about 500 items a year scan instantly, and it matches Tamil too. A refresh reads the month index and downloads only changed months; a refresh that fails part way keeps what it stored and asks for the index again next time. The generated drift code is committed. |
| 2026-10-16 | M5c: the feed has cards (topic and issuer, date, headline in up to 3 lines, up to 3 key numbers with the price before), month headings, topic chips, new-item dots (items first seen after the feed was last left and published within 14 days, so history filling in is never marked) and search as you type. Two display rules came from the real data: a headline that starts with its issuer's name ("Department of Census and Statistics - The Census Ordinance") drops it, since the card's top line names the issuer; and a gazette with neither an English nor a Tamil title shows its number ("Gazette 2509/28"). Fuel labels shorten to their common names ("Lanka Petrol 92 Octane" reads "Petrol 92"). Links open in the browser through url_launcher. |
| 2026-10-16 | M5d: the Now card. The phone reads CEYPETCO's active prices and CBSL's rate search itself (both checked live from Sri Lanka), keeps a price history per fuel and the daily rates, and records each source's last run, success and error for the Sources screen (M5e). A fuel price's "before" comes from the phone's history or, on a fresh install, from the latest fuel revision gazette; until CEYPETCO first answers, the fuel prices come from that gazette, marked "as of" its date. USD/LKR falls back to the workflow's copy when CBSL hasn't answered. Holiday names in Tamil come from a table bundled with the app (`assets/holidays_ta.json`). The phone making its own USD/LKR move items moved to M6, where same-day alerts need them. |
| 2026-10-16 | M5e: a Sources screen (menu) lists what GitHub reads, with the workflow's last run, and what the phone reads, each with its last success and last error. A source with no success for a day, or a workflow that hasn't run for a day, puts a warning in the app bar that opens it. About has the version (package_info_plus), a line on where the data comes from, the source code and the licenses. M5 is complete apart from this pull request. |
| 2026-10-16 | M6 grilled; the decisions are under "Alerts (M6 grilling)". One notification per item; gazette switches by group with election notices off by default; fuel changes alert from CEYPETCO the day they happen, and a fuel gazette only if its prices are new to the phone; adjustable quiet hours; holiday reminders at 19:00 the evening before; a battery row for Xiaomi's background limits. M6 is split into three pull requests, M6a to M6c. |
| 2026-10-16 | M6a: the background sync runs in its own Flutter engine with its own database connection, so the database uses write-ahead logging and a 10 second busy timeout, and the feed reads its items again when the app comes back. The app marks itself in front while the feed is on screen; a mark older than 12 hours counts as gone, for an app that was stopped without leaving. The first background run comes a full period after install, since opening the app has just refreshed. Notifications go out one per item in a group with a summary, IDs from the item ID so a re-sent item replaces its own; a tap opens the item, also when it starts the app. On a phone, the sync ran in the background in about 5 seconds. |
| 2026-10-16 | M6b: an Alerts screen (in the menu) with the switches in two groups (topics, and gazettes by group), quiet hours (on, 22:00 to 06:00, times picked on a 24-hour clock like the rest of the app) and a Battery row that opens the app's page in Android's settings and shows when the background sync last ran, in the warning colour after 12 hours. A row at the top says when notifications are off and opens their settings. Android's settings pages open through a small method channel in MainActivity rather than a package. A background sync in quiet hours keeps the IDs of what would have alerted; the first sync after them posts those whose switch is still on, and opening the app drops them, since the feed marks them new. Each sync records when it started, even if its refresh then fails. The Holiday reminders switch comes with the reminders in M6c. |
| 2026-10-19 | M6c: a sync compares CEYPETCO's prices before and after its refresh and posts one "Fuel prices changed" notification (Prices switch, its own channel, a later change replaces it, a tap opens the fuel prices); a fuel gazette whose prices equal the phone's latest CEYPETCO prices doesn't alert. The phone makes the workflow's `rates-usd-lkr-<date>` items with the same rule and fields (checked against the workflow's 2026-05-22 item), from CBSL's rates plus the workflow's `datasets/usd-lkr.json` (its rate wins where both have a day), only for days after that file's last day. They are filed under the month `phone`, which no month file replaces; the workflow's copy of the same ID takes over and keeps when the phone first saw it, and phone items are dropped once the workflow's rates cover their day. Holiday reminders are scheduled again after every refresh and on the switch: inexact, 19:00 Sri Lanka time the evening before, every holiday in the dataset, through a boot receiver so they survive a restart; `proguard-rules.pro` keeps the notification plugin's Gson models for release builds (to check on the first release). Quiet hours hold a fuel change like an item. |
| 2026-10-19 | M7: the release workflow had skipped every due release for want of the signing key. The key was made (PKCS12, alias `upload`, valid to 2054, kept outside the repo with a backup) and its four secrets added; Release run by hand published v0.1.0 (a 61 MB APK with code for three CPU types), installed from GitHub Releases after removing the debug build, which has another key. The release build keeps the notification plugin's classes (checked in the APK) and schedules the holiday reminders. The app icon followed: a white radar sweep on the app's teal, drawn as vectors (adaptive icon with a themed-icon layer, PNGs for Android 7), and the same radar as the status bar icon, kept from the resource shrinker by `res/raw/keep.xml`. |
| 2026-10-19 | M8 grilled; the decisions are under "Redesign and more sources (M8 grilling)". Search was missing what the cards show: on the 420 items, `diesel` and `tuna` found nothing (they are only in price labels), `timetable` and `o/l` found nothing (the titles say "Time Table" and "Ordinary Level"), and `gazette` found nothing (the topic wasn't searched). M8a indexes the topic, the price labels long and short and "gazette <number>", adds other spellings for common words, and works the search text out again for stored items (schema 4). GitHub ran the 3-hourly scrape about 5 times a day, 18 minutes to almost 3 hours late, so the workflow now runs every hour, and so does the phone's sync, through WorkManager's update policy so phones with the app move to it. Sources checked for M8: EDLCare for power cuts (usable), the PSC for jobs (usable), the Water Board (no notices), CBSL's Daily Price Report for market prices (usable, added as M8f), HARTI (usable, Later) and supermarket sites (outlet-bound, likely against their terms). |
| 2026-10-19 | M8b: a bottom bar with Today, Prices, Notices and Dates in place of the one feed and the Now card. Today has four tiles (Petrol 92, Diesel, USD/LKR with its move over a week, the next holiday) and the items new since the last visit, or the latest 5, never election notices. Prices lists each fuel with its price before and an arrow (ochre up, teal down), USD/LKR's last week, Litro's list and the latest price orders; Dates the year's holidays and the school exam notices. Notices keeps the topic chips and month headings and folds each week's election notices into one row that opens in place. Cards became a topic badge (an icon in an ochre, teal or plain circle), a title saying what changed where the data allows ("Petrol 92 down to Rs 399, and 1 more", "O/L 2026 timetable", short exam names, the act an order is made under dropped), and one line with the issuer and date; notifications use the same title. A fuel or holiday notification now opens the Prices or Dates tab instead of a sheet. |
| 2026-10-19 | M8c: a `jobs` source reads the Public Service Commission's homepage (`psc.gov.lk/index.php?lang=en`, which loads from abroad: checked from 5 countries), whose latest announcements are PDFs named with their upload time in Unix seconds and titled with the post. Recruitments and calls for applications become `jobs-psc-<seconds>` items in a new `jobs` topic; transfer and appeal decisions are left out. A live run found 2 for 2026. The app has a Jobs chip and icon, a Jobs alert switch (on), and finds them by "job" (and recruitments by "vacancy"; election notices, which fill council vacancies, are not jobs). The homepage keeps only the latest few, so older recruitments aren't backfilled. |
