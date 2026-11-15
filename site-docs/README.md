# CimBar documentation site

The user guide, privacy policy and support page, in the app's five languages,
built with MkDocs + Material (modelled on NFC Archiver's `site-docs/`). One
source tree is built twice:

- **`nfcarchiver.com/cimbar/docs/`**: the canonical copy, the one App Store
  Connect and the apps link to (`/cimbar/docs/privacy/`, `/cimbar/docs/support/`);
- **`mezinster.github.io/cimbar/`**: a GitHub Pages mirror whose canonical
  links point back at `nfcarchiver.com/cimbar/docs/`.

English lives at the root, every other language under its code
(`/cimbar/docs/ru/privacy/`). The language list comes from the app's
`app/lib/l10n/app_*.arb` files.

## Where it is stored

The main copy is uploaded to the bucket prefix **`cimbar-docs/`**, not
`cimbar/docs/`: the web app's deploy syncs `cimbar/` with `--delete` and would
delete the docs. CloudFront's viewer-request function (in the terraform repo,
`websites/functions/directory-index.js`) serves `/cimbar/docs/…` from
`cimbar-docs/…`, and the deploy role may write that prefix (`iam/main.tf`).

## Preview

```bash
cd site-docs
python3 -m venv .venv && . .venv/bin/activate
pip install --require-hashes -r requirements.txt
mkdocs serve
```

## Build

Both copies, from `site-docs/`, exactly as CI and the deploy build them:

```bash
DOCS_BUILD_SHA=$(git rev-parse HEAD) mkdocs build --strict -d site/main
DOCS_BUILD_SHA=$(git rev-parse HEAD) DOCS_SITE_URL=https://mezinster.github.io/cimbar/ \
  mkdocs build --strict -d site/pages
```

`DOCS_BUILD_SHA` is stamped into every page as
`<meta name="cimbar-docs-build" content="…">`; the deploy checks the live pages
for it.

## Checks

From the repository root:

```bash
python site-docs/check_site.py                     # sources: locales, page parity, contact
python site-docs/check_site.py --built site-docs/site/main  --base /cimbar/docs/ --sha "$(git rev-parse HEAD)"
python site-docs/check_site.py --built site-docs/site/pages --base /cimbar/ --forbid /cimbar/docs/ --sha "$(git rev-parse HEAD)"
```

The built-tree check fails on any link that starts with `/` but not with that
copy's own base path. The Pages base `/cimbar/` contains the main copy's
`/cimbar/docs/`, so the Pages check also forbids that. CI (*Build docs* in
`ci.yml`) runs all of this on every push and PR; it deploys nothing.

## Writing pages

- Quote UI labels exactly as the apps show them: `app/lib/l10n/app_<lang>.arb`
  for the mobile app, `web-app/i18n.js` for the web app.
- Every page exists in every language (`check_site.py` enforces it); a new
  page also needs a `nav` entry and a `nav_translations` line per language in
  `mkdocs.yml`.
- The privacy policy covers the web app, Android and iPhone in one page. The
  English text is authoritative; each translation links to it. When the app
  gains a permission, a plugin, storage or any network use, update the policy
  (and its date) in every language **and deploy the docs before the release**
  that carries the change.
- Call the format CimBar-XL and credit sz3's libcimbar as the inspiration; never
  "CimBar v2" or "successor" (root `CLAUDE.md`, Interoperability).

## Deploy

Manual only, from `master`. Dry run first:

```bash
gh workflow run deploy-docs.yml --ref master -f dry_run=true   # print the S3 plan, upload nothing
gh workflow run deploy-docs.yml --ref master                   # deploy
```

`deploy-docs.yml` builds and checks both copies, syncs the main copy to
`s3://<bucket>/cimbar-docs/` (non-HTML first, HTML last with `no-cache`),
invalidates `/cimbar/docs/*`, and checks that the live pages carry this
commit's build marker. Only then does it deploy the Pages mirror and check it
the same way.

The deploy refuses any S3 prefix other than exactly `cimbar-docs/`, or one equal
to the web app's prefix: `sync --delete` would otherwise delete a neighbouring
site. The dry run also fails if any planned key falls outside the target prefix.

## Roll back

Re-dispatch the workflow from a known good commit. The workflow (and the
`production` and `github-pages` environments) accept only `master`, so that
means: revert the bad change on `master`, then deploy again.

```bash
git revert <bad-commit>   # via a PR to master
gh workflow run deploy-docs.yml --ref master
```

## Configuration

Set in the `production` environment (the Pages URL is fixed in the workflow).

| Name | Kind | Meaning |
|---|---|---|
| `S3_DOCS_PREFIX` | variable | `cimbar-docs/`: the key prefix the site is synced to |
| `DOCS_BASE_URL` | variable | `https://nfcarchiver.com/cimbar/docs/`: where the deploy verifies the live site |
| `S3_BUCKET` | variable | bucket serving `nfcarchiver.com` (shared with the web app) |
| `S3_PREFIX` | variable | the web app's prefix (`cimbar/`); the docs prefix must differ from it |
| `AWS_REGION` | variable | region of the bucket |
| `CLOUDFRONT_DISTRIBUTION_ID` | secret | distribution serving the domain; an environment secret, so it is masked and never appears in the logs (the web app's workflow still reads a variable of the same name) |
| `AWS_DEPLOY_ROLE_ARN` | secret | role assumed via GitHub OIDC; there are no stored AWS keys |

GitHub Pages must be set to deploy from **GitHub Actions**, and the
`github-pages` environment limited to `master`. The deploy role's permissions
are managed outside this repository.
