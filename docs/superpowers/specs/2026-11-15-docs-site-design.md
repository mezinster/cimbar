# CimBar documentation site — design

Date: 2026-11-15

## Intent

CimBar needs a public user guide, privacy policy and support page. The
immediate reason is the iOS app: App Store Connect needs a privacy policy URL
and a support URL for the TestFlight/App Store record, and today the only
policy is `PRIVACY_POLICY.md` on GitHub, which covers the web app and Android
but not iOS. The model is NFC Archiver's `site-docs/` (`~/nfcarchiver/site-docs`),
which the owner is happy with: copy its structure, tooling and deploy
discipline, and write CimBar's own content.

## Goals

- One MkDocs + Material source tree in `site-docs/`, built twice:
  - **`https://nfcarchiver.com/cimbar/docs/`** — the canonical copy, the one
    App Store Connect and the apps link to;
  - **`https://mezinster.github.io/cimbar/`** — a GitHub Pages mirror whose
    canonical links point back at `nfcarchiver.com/cimbar/docs/`.
- The app's five languages — `en` (root), `ru`, `uk`, `tr`, `ka` (under their
  codes) — one per `app/lib/l10n/app_*.arb`, every page in every language.
- **One privacy policy covering all three clients** (web app, Android app, iOS
  app), like NFC Archiver's single policy. Owner's decision.
- Manual, guarded deploy from `master` only, like `deploy-docs.yml` in NFC
  Archiver: dry run, S3 sync (non-HTML first, HTML last, no-cache),
  CloudFront invalidation, build-marker check on live pages, then Pages.
- CI checks every PR that touches the site (build both copies with
  `--strict`, run `check_site.py` on sources and both built trees). Deploys
  nothing.
- Infrastructure changes live in `mezinster/terraform`, as a PR there.

## Non-goals

- No App Store listing text, screenshots or store metadata for iOS.
- No developer/format documentation on the site: the specs in `docs/` and
  `spec/` stay where they are. "How it works" is a plain-language page.
- No automatic deploy on push or tag.

## Anti-goals

- The web app's deploy must never be able to delete the docs, and the docs
  deploy must never be able to delete the web app. (This is why the S3 layout
  below is not simply `cimbar/docs/`.)
- The docs site loads nothing third-party: no Google Fonts (`font: false`),
  no analytics, no CDN scripts. Search runs locally.
- No AWS account ID, role ARN or CloudFront distribution ID committed or
  printed in this public repo or its Actions logs (same hygiene as NFC
  Archiver; distribution ID from an environment secret).

## Infrastructure (terraform)

The web app deploy (`deploy-webapp.yml`) syncs `s3://<bucket>/cimbar/` with
`--delete`, one pass per file type, and its rollback restores the whole
prefix. A docs tree at `cimbar/docs/` would have its HTML deleted by every web
app deploy. So:

- **S3 prefix `cimbar-docs/`** holds the docs tree.
- **CloudFront function** (`websites/functions/directory-index.js`, the
  viewer-request function already on the distribution): before the
  directory-index logic, rewrite a URI starting with `/cimbar/docs/` to
  `/cimbar-docs/` + the rest. `/cimbar/docs` (no slash) still gets the 302 to
  `/cimbar/docs/` from the existing logic. Requests made directly to
  `/cimbar-docs/…` keep working; that is harmless (the canonical link names
  `/cimbar/docs/`).
- **IAM** (`iam/main.tf`): add `cimbar-docs` to `website_deploy_prefixes`.
  `cimbar` is already in `website_deploy_repos`.
- Invalidation uses the viewer path: `/cimbar/docs/*`.
- *My call:* the function file is shared, so the rewrite reaches every site
  in `local.sites`, not only nfcarchiver.com. No other site serves
  `/cimbar/docs/`, so no host check.

Order: the terraform PR is applied before the first docs deploy. The owner
applies terraform; I open the PR.

## The site

Pages (English titles; nav translated per language like NFC Archiver's
`nav_translations`):

| Page | File | Content |
|---|---|---|
| Home | `index.md` | What CimBar does in a paragraph, the three clients, links to the rest |
| Get the app | `get.md` | Web app link; Android via F-Droid and GitHub releases (and that the two are signed differently and can't upgrade each other); iPhone via TestFlight (public link if/when one exists, otherwise "coming") |
| Send a file or text | `send.md` | Send tab / web Send: pick a file or type text, optional passphrase, Present vs Share GIF, repair frames in plain words ("keep the animation playing; the receiver can miss frames") |
| Receive | `receive.md` | Live scan (recommended), photo capture (single-frame only in the apps), GIF import / share into the app; the web app's photo accumulation; where decoded files go (Files tab; Open / Save / Share) |
| Encryption | `encryption.md` | AES-256-GCM, PBKDF2, passphrase never stored, lost passphrase = lost file, auto-detected on receive |
| How it works | `how-it-works.md` | Plain-language CimBar-XL: coloured shapes, frames, error correction, repair frames, compression. Credits sz3's libcimbar as the inspiration, never "CimBar v2" or "successor" (see root CLAUDE.md, Interoperability) |
| Troubleshooting | `troubleshooting.md` | Scanner can't lock on (distance, glare, screen brightness), progress stalls, "wrong file" prompt, passphrase failures, old v1 GIFs don't decode, file too large |
| Privacy policy | `privacy.md` | See below |
| Support | `support.md` | Contact: support@nfcarchiver.com (owner's decision) and GitHub issues, what to include (device, OS version, app version, which client, what happened); never send file contents or passphrases |

Facts must come from the code and the existing docs (root and `app/`
CLAUDE.md, README, CHANGELOG), not from memory.

### Privacy policy content

Based on `PRIVACY_POLICY.md`, extended to iOS and re-checked against the code:

- Collects nothing; no analytics, crash reports, identifiers, ads.
- **Web app:** runs locally; stores only `cimbar.lang` in localStorage; loads
  Google Fonts (verify in `web-app/index.html` at write time — it does today);
  static S3/CloudFront hosting with standard access logs.
- **Android:** camera only (stripped plugin permissions), no internet
  permission; frames decoded in memory; debug capture exception; files in
  private storage until Open/Save/Share; prefs stored locally.
- **iPhone:** camera (`NSCameraUsageDescription`); photo library add-only if
  declared (verify `Info.plist`); the microphone string exists only because a
  camera plugin links audio APIs — the app never asks for it; Share
  extension hands files to the app through the App Group container; privacy
  manifest declares no tracking and no collected data; no network use.
- Encryption, third-party services, children, changes, open source, contact
  (support@nfcarchiver.com).
- A "This website" section like NFC Archiver's.

`PRIVACY_POLICY.md` becomes a short pointer to the published policy (the
site is the single source), and the app's About link
(`app/lib/features/settings/settings_screen.dart`) points at
`https://nfcarchiver.com/cimbar/docs/privacy/` — but only in a change merged
**after** the first docs deploy, so the link never 404s. Same for the web
app's privacy link if it has one.

## Tooling (copied from NFC Archiver, adapted)

- `site-docs/mkdocs.yml`, `requirements.in` / hash-pinned `requirements.txt`
  (same Material/i18n versions as NFC Archiver), `overrides/main.html`
  (build marker + canonical link to `https://nfcarchiver.com/cimbar/docs/`),
  `docs/assets/stylesheets/extra.css` with CimBar's colours (the web app's
  accent/bg tokens), favicon/logo from the existing generated icons.
- Build marker meta name: `cimbar-docs-build`.
- `check_site.py`: locales match the ARBs, every page exists in every
  language, contact address present, and on built trees: marker present with
  the SHA, no root-relative link outside the copy's base path
  (`/cimbar/docs/` for main, `/cimbar/` for Pages).
- `site-docs/README.md` — preview, build, checks, deploy, rollback,
  configuration table.
- CI: a `build-docs` job in `.github/workflows/ci.yml`, path-filtered to
  `site-docs/**` and the workflow itself.
- `deploy-docs.yml`: NFC Archiver's workflow with: prefix guard requiring
  exactly `cimbar-docs/` and differing from `S3_PREFIX` (`cimbar/`);
  invalidation path `/cimbar/docs/*` (not derived from the S3 prefix);
  verification against `DOCS_BASE_URL` = `https://nfcarchiver.com/cimbar/docs/`
  for `/`, `privacy/`, `support/`, `ru/privacy/`; Pages URL
  `https://mezinster.github.io/cimbar/`.
- Production environment variables to add: `S3_DOCS_PREFIX=cimbar-docs/`,
  `DOCS_BASE_URL`; secret `CLOUDFRONT_DISTRIBUTION_ID`. *My call:* the web
  app workflow reads a **variable** of the same name (unmasked); the docs
  workflow reads an environment **secret** holding the same value, as NFC
  Archiver does, and the web app workflow is left alone (out of scope).
- GitHub Pages enabled with source "GitHub Actions"; a `github-pages`
  environment restricted to `master`.
- Root `CLAUDE.md` gets a "Docs site" section like NFC Archiver's.

## Translations

I write English first, then translate into ru, uk, tr, ka, keeping the app's
own terminology (take UI labels from the ARB files so the docs say exactly
what the buttons say).

## Left to the builder

Page wording, section order inside pages, admonitions, CSS details, the exact
`check_site.py` checks beyond the ones above.
