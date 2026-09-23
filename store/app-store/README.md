# App Store listing

Source of truth for AIPedometer's App Store product page (app `6778799265`), in the canonical
layout of `asc metadata` (asc 5.4), the same layout as the studio's other apps.
`AIPedometerTests/Constants/StoreListingTests.swift` pins the in-app Privacy Policy and Support
links to these URLs, the App Store Connect field limits, the Terms of Use link and the price.

| Path | Holds |
|---|---|
| `app-info/<locale>.json` | name, subtitle, privacy policy URL |
| `version/<version>/<locale>.json` | description, keywords, promotional text, marketing and support URLs |
| `pricing.json` | base territory and price point (BRA, R$ 1,99 → proceeds R$ 1,48) |

The version folder must equal `MARKETING_VERSION` in `project.yml`: a version bump renames it,
or the unit tests fail. Categories, App Privacy answers and review notes are in
[`docs/appstore/metadata/`](../../docs/appstore/metadata/).

Links go to AIPedometer's own pages on conhecendotudo.com.br (`/pt/apps/privacidade/aipedometer/`,
`/en/apps/privacy/aipedometer/` and the matching `suporte`/`support` pages), not the website-wide
policy, which covers website forms the app does not have.

## Validating

```bash
asc metadata validate --dir store/app-store --check-urls --subscription-app --output table
```

## Applying

These are writes to App Store Connect; run them only with the owner's approval. The App Store
version must exist in App Store Connect first (the draft there is still 1.0.4).

```bash
V=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
asc metadata plan  --app 6778799265 --version "$V" --platform IOS --dir store/app-store
asc metadata approve --review-dir .asc/metadata/review --all   # after reading the plan
asc metadata apply --app 6778799265 --version "$V" --platform IOS --dir store/app-store \
  --review-dir .asc/metadata/review --confirm
asc pricing schedule create --app 6778799265 \
  --price-point "$(python3 -c 'import json;print(json.load(open("store/app-store/pricing.json"))["pricePointId"])')" \
  --base-territory BRA --start-date "$(date +%F)"
asc pricing availability create --app 6778799265 --territory BRA --available true \
  --available-in-new-territories true
asc pricing availability edit --app 6778799265 --all-territories --available true
```

A paid app needs the Paid Applications agreement, tax and banking active in App Store Connect
(Business); the price schedule cannot be created without them.
