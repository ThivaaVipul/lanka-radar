# Lanka Radar

Personal Android app that tells you when Sri Lankan official sources publish something new. Python scrapers run on GitHub Actions and commit JSON to the `data` branch; the Flutter app reads it. Progress and decisions are in `docs/PLAN.md`: tick items as they land and log design changes there.

## Commands

```bash
# Python, from the repo root with scrapers/.venv active
pip install -e "scrapers[dev]"
ruff format .                 # CI fails on unformatted code
ruff check .
pytest scrapers
pytest scripts/release

# App, from app/
flutter pub get
dart format lib test          # CI fails on unformatted code
flutter analyze               # strict mode, must be clean
flutter test
flutter build apk --debug
```

Scraper tests live in `scrapers/tests/` and run on saved fixtures in `scrapers/tests/fixtures/`, never on live sites. Dart tests mirror `lib/` under `app/test/`.

## Architecture rules

- Only GitHub and the app. No servers, accounts, Firebase, analytics, crash reporting or AI services.
- Scrapers write only to the `data` branch, through the scrape workflow. `main` holds code only.
- One module per source in `scrapers/src/lanka_radar/sources/`. Shared code (HTTP client, item model, writer) lives in the package, not in the source modules.
- Be polite to government sites: a user agent that names the project, retries with backoff, never re-download a PDF already seen.
- Item IDs are stable and built from the source's own IDs. Changing the ID scheme needs a log entry in the plan.
- The app reads only `raw.githubusercontent.com/ThivaaVipul/lanka-radar/data/...`. No tokens or keys in the app.
- Notifications are local, from a WorkManager sync. No push service.

## Git workflow and releases

- Branches `feat/...`, `fix/...`, `docs/...`, `chore/...` off `main`; a pull request, CI green, then squash merge with a Conventional Commit title.
- The commit type decides the release (README, Releases): `feat` is minor, `fix`/`perf`/`revert` patch, `!` or `BREAKING CHANGE:` major, everything else none. Pick the type honestly.
- Never commit to `data`, never create `v*` tags by hand, and never change the version in `app/pubspec.yaml` unless asked to force one.
- Release logic lives in `scripts/release/` (Python, standard library only). Change it test-first in `scripts/release/test_version.py`.

## Constraints

- Fully free: public repo, GitHub-hosted standard runners, no paid services, nothing that needs a card.
- Android only.
- Add a package (pip or pub) only in the change that first uses it.
- Declare an Android permission only in the change that uses it.
- Check versions and APIs against current docs (Context7) before adding or upgrading a dependency or a GitHub Action.

## Conventions

- Python 3.12+, type hints on public functions, ruff for format and lint (`ruff.toml` at the root), pytest.
- Flutter: app shell in `lib/app/`, shared code in `lib/core/`, feature-first folders (`lib/features/<feature>/`), one Cubit per screen (Bloc only when events need it), package imports, `Equatable` state.
- UI: Material 3, minimal and calm, short labels, no explanatory paragraphs on screens.
- Plain ASCII punctuation in code, comments, docs and commits: no em or en dashes, arrows, smart quotes or emoji.
- Line endings are LF (enforced by `.gitattributes`).
- Commits: small, imperative subject, no `Co-Authored-By` trailer. Never commit or push without asking.
- Git identity is `ThivaaVipul` with the GitHub noreply email (`114325514+ThivaaVipul@users.noreply.github.com`), set in this repo's git config. The repo is public, so no personal email in commits or files. Don't use `gh` or browser tools for GitHub.
