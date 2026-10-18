# wasc passwords (browser extension + macOS desktop)

A rebranded build of [bitwarden/clients](https://github.com/bitwarden/clients), preconfigured for
the wasc self-hosted Vaultwarden at **https://passwords.wasc.me** (friends and family).

upstream_tag: desktop-v2026.10.0

- `main` mirrors upstream `main` (updated by the monthly upstream sync, see [Upstream sync](#upstream-sync)).
- `wasc` (default branch) = an upstream release tag plus the small patch described below.
- All upstream workflows are disabled in this fork; only `wasc-*.yml` run (enforced by
  `wasc-guard.yml`, see [CI](#ci)).
- Safari, Linux and Windows packaging are out of scope.

## Fixed identifiers

| What                                        | Value                                                                                                                                 |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Extension name                              | `wasc passwords`                                                                                                                      |
| Chrome/Edge/Opera extension ID              | `gdadfgkaaapapjjhoamgbmjmlhbckdho` (from the manifest `key`; the private `.pem` is kept outside the repo and must never be committed) |
| Firefox add-on ID                           | `passwords@wasc.me`                                                                                                                   |
| Native messaging host                       | `me.wasc.passwords`                                                                                                                   |
| Desktop appId / productName                 | `me.wasc.passwords.desktop` / `wasc passwords`                                                                                        |
| Desktop IPC socket dir (macOS, unsandboxed) | `~/Library/Caches/me.wasc.passwords.desktop`                                                                                          |
| Default server                              | `https://passwords.wasc.me`                                                                                                           |

## What the fork changes

Keep this list in sync with the diff (`git diff <upstream_tag> wasc -- . ':!wasc' ':!.github/workflows/wasc-*'`).

| File                                                                                                                             | Change                                                                                                                                                                                                                                                        |
| -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apps/browser/webpack/manifest.js`                                                                                               | `transformWasc()` applies `wasc/browser/manifest-overrides.json` (name, titles, `key`, gecko id, AMO data collection) after the channel transform. Top-level sections only apply when present (MV2 `browser_action` vs MV3 `action`).                         |
| `apps/browser/webpack.base.js`                                                                                                   | Copies `wasc/brand/browser/*.png` over `images/` (toolbar/action icons). In-app logos untouched.                                                                                                                                                              |
| `apps/browser/src/background/nativeMessaging.background.ts`, `apps/browser/src/platform/ipc/transports/desktop-ipc.transport.ts` | `connectNative("me.wasc.passwords")`.                                                                                                                                                                                                                         |
| `libs/common/src/platform/services/default-environment.service.ts`                                                               | `buildEnvironment()`: with nothing stored, fall back to a self-hosted environment at `https://passwords.wasc.me` instead of Bitwarden US. The region picker still works. Spec adjusted (+1 test).                                                             |
| `apps/desktop/src/main/native-messaging.main.ts`                                                                                 | Host manifest name/files/registry keys `me.wasc.passwords`, allowed Chrome origin = our ID, allowed Firefox extension `passwords@wasc.me`. Does not touch an official Bitwarden install's host manifests.                                                     |
| `apps/desktop/desktop_native/core/src/ipc/mod.rs`                                                                                | Socket dir `me.wasc.passwords.desktop` so the proxy never talks to an official Bitwarden app.                                                                                                                                                                 |
| `wasc/desktop/electron-builder.json`                                                                                             | `extends` upstream `apps/desktop/electron-builder.json`; appId, productName + `extraMetadata.productName` (own userData dir and keychain service names), GitHub publish feed, no provisioning profile, own entitlements, icon, artifact names without spaces. |
| `wasc/desktop/entitlements.mac.plist`                                                                                            | Upstream mac entitlements minus Bitwarden's team-bound `application-identifier` / `team-identifier` (they need Bitwarden's provisioning profile).                                                                                                             |
| `wasc/brand/`                                                                                                                    | Placeholder icon (`icon.svg`, `icon-rounded.svg`) and `render-icons.sh`, which renders the committed `browser/*.png` and `desktop/icon.icns`.                                                                                                                 |

### electron-builder `extends` notes (verified against app-builder-lib 26.9 source)

- `--config` and `extends` paths are resolved against the **project dir** (`apps/desktop`, the
  cwd), not against the config file. Hence `"extends": "./electron-builder.json"`, and the
  `../../wasc/...` paths for icon/entitlements.
- Objects deep-merge; a `null` value replaces (used for `mac.provisioningProfile`).
- Arrays are **concatenated** (`extraFiles`, `protocols`, `target`, ...), so the wasc config must
  not redefine arrays it wants to replace. `publish` is given as an array so it replaces the
  upstream object instead of merging into it (otherwise the upstream `url` leaks in).

## Chrome Web Store and the extension ID

The CWS rejects a manifest containing `key` and assigns the item ID itself. To keep
`gdadfgkaaapapjjhoamgbmjmlhbckdho`, make the **first** upload by hand: take
`wasc-passwords-chrome-<version>-webstore.zip` (CI artifact, manifest without `key`), add the private
key as `key.pem` at the zip root, and upload it as a new item. Later uploads (CI, API v2) use the
`-webstore.zip` without `key.pem`. If the store ends up with a different ID, add
`chrome-extension://<store-id>/` to `loadChromeIds()` in `apps/desktop/src/main/native-messaging.main.ts`.

## Known leftovers (intentionally not changed)

- In-app strings, help/web-vault links and `cloudWebVaultUrl` still say/point to Bitwarden.
- `bitwarden://` URL scheme: both the official Bitwarden desktop app and ours register it on
  every launch, so macOS hands `bitwarden://` callbacks (Duo 2FA, SSO login, ...) to whichever app
  was **launched last**. A Duo/SSO login started in one app can end up in the other. **Don't run
  both apps on the same Mac**; if you must, quit the other one before logging in.
- The SSH agent socket `~/.bitwarden-ssh-agent.sock` is shared with an official install (only
  matters if both apps are installed and the SSH agent is enabled).
- Phishing detection (premium) downloads Bitwarden's list from assets.bitwarden.com.

## Building locally

```sh
npm ci
# Browser
cd apps/browser
npm run dist:chrome     # build/ + dist/dist-chrome.zip  (MV3)
npm run dist:firefox    # build/ + dist/dist-firefox.zip (MV2)
npx web-ext lint -s build
# Desktop (macOS)
cd ../desktop/desktop_native && node build.js cross-platform --release && cd ..
npm run build
APPLE_NOTARIZE=false CSC_IDENTITY_AUTO_DISCOVERY=false CSC_NAME=- \
  npx electron-builder --config ../../wasc/desktop/electron-builder.json --mac --universal -p never -c.mac.identity=-
```

## Upstream sync

Upstream sync is **not** done by CI. A monthly T3 Code scheduled task in Nicolai's compose-services
thread (`wasc-passwords-monthly-sync-v1`, every 30 days) mirrors upstream `main` into our `main`,
merges the newest stable upstream `desktop-v*` tag into a `sync/<tag>` branch, resolves conflicts
(keeping the patch below), bumps `upstream_tag:` above, opens a PR into `wasc` (merge commit, never
squash), runs the workflow guard right after the push, runs `wasc-browser.yml` and
`wasc-desktop.yml` (release=false) on the branch and fixes build breaks, and dispatches both with
release=true after merging. No `ANTHROPIC_API_KEY` or `SYNC_TOKEN` is needed.

## CI

| Workflow           | Trigger                                | Does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------ | -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `wasc-browser.yml` | push to `wasc` (browser paths), manual | Builds Chrome + Firefox zips and a source zip. Manual run with `release` publishes `wasc-browser-v<version>` as a GitHub **prerelease** (GitHub treats the newest full release as Latest whenever none is explicitly marked, even with `--latest=false`, which would hijack the desktop update feed; prereleases never become Latest). With `publish_stores`: Chrome Web Store (API v2) if `CWS_CLIENT_ID`, `CWS_CLIENT_SECRET`, `CWS_REFRESH_TOKEN`, `CWS_EXTENSION_ID`, `CWS_PUBLISHER_ID` are set; AMO (`web-ext sign`, listed or unlisted) if `AMO_JWT_ISSUER`, `AMO_JWT_SECRET` are set. |
| `wasc-desktop.yml` | push to `wasc` (desktop paths), manual | Universal macOS DMG + zip + `latest-mac.yml`, then **launches the packaged app for 15 s** and fails on dyld/code-signature errors. Signs with `MAC_CERT_P12_BASE64` / `MAC_CERT_PASSWORD` (Developer ID Application), notarizes with `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8`. Without the cert it produces an ad-hoc signed build without hardened runtime. Manual run with `release` publishes `wasc-desktop-v<version>`: signed builds are marked **Latest** (the auto-update feed), unsigned builds are published as **prerelease** and never become Latest.                         |
| `wasc-guard.yml`   | push to `wasc`, monthly (3rd), manual  | Runs `wasc/ci/workflow-guard.sh`: disables every active workflow not named `wasc-*`, and re-enables `wasc-guard.yml` itself (keepalive, see below).                                                                                                                                                                                                                                                                                                                                                                                                                                           |

### Releases, tags and versioning

- Our release tags are `wasc-desktop-v<version>` and `wasc-browser-v<version>`. The fork also
  carries upstream's `desktop-v*` / `browser-v*` (and old bare `v*`) tags, so we never reuse those
  names. The upstream sync fetches upstream tags into `refs/upstream-tags/*`, never into
  `refs/tags/*`, so an upstream tag can never overwrite one of ours (or vice versa).
- electron-updater's GitHub provider (6.8, `allowPrerelease` off) asks
  `github.com/<repo>/releases/latest` for the Latest release's tag, then downloads
  `latest-mac.yml` from that tag; the version comes from `latest-mac.yml`, not from the tag name.
  The tag prefix therefore does not matter. What matters is that only signed desktop releases
  are full releases: browser releases and unsigned desktop builds are published as prereleases,
  because GitHub reports the newest full release as Latest when none is explicitly marked.
- Releases are created as **draft**, the assets are uploaded, then the release is published. The
  release job **fails if the release for that version already has assets** (no silent `--clobber`).
- `<version>` defaults to upstream's (`apps/desktop/src/package.json`, `apps/browser/package.json`).
  To ship a fork-only fix on the same upstream base, run the workflow manually with the
  `version` input, e.g. `2026.10.1`: desktop applies it via `-c.extraMetadata.version` (CI checks
  the bundle and `latest-mac.yml`), browser stamps it into the manifest templates for that build.
  Pick a version greater than the current release (the updater only moves forward) and lower than
  upstream's next one (e.g. `2026.10.1` after `2026.10.0`, before upstream `2026.11.0`). If
  upstream itself ships `2026.10.1`, use `2026.10.2` and so on.
- An unsigned desktop prerelease blocks its version number: to publish a signed build of the same
  version, delete the prerelease (and its tag) first, or use the next fix version.

### Workflow token and guard

- The repo's default `GITHUB_TOKEN` permission is **read** (`Settings > Actions > General`), and
  every `wasc-*` job declares its own `permissions:`. Build jobs get `contents: read`; only the
  release/store jobs and the guard (`actions: write`) get write scopes.
- `wasc/ci/workflow-guard.sh` disables every active workflow outside `wasc-*.yml`. Upstream
  workflows are registered (enabled) when a branch containing them is pushed, so the guard runs on
  every push to `wasc`, monthly, and the upstream sync runs it right after pushing a sync branch.
- **Keepalive:** GitHub disables scheduled workflows in public repos after 60 days without
  repository activity. `wasc-guard.yml` is the only scheduled wasc workflow; it runs monthly and
  calls `PUT /actions/workflows/wasc-guard.yml/enable` on itself, which resets the timer (same
  approach as the API mode of `gautamkrishnar/keepalive-workflow`, without a third-party action).
  If it ever gets disabled anyway, re-enable it in the Actions tab.

Signing details: `scripts/macos-signing-identity.js` hardcodes Bitwarden's identity when
`GITHUB_ACTIONS=true`, so electron-builder runs with `GITHUB_ACTIONS=false` and `CSC_NAME=<SHA-1 of
our Developer ID cert>`; `scripts/after-sign.js` notarizes via `APP_STORE_CONNECT_*` (mapped from
the `ASC_*` secrets).

## Updating the icon

Edit `wasc/brand/icon-rounded.svg` (and `icon.svg`, shared with passwords-ios), run
`wasc/brand/render-icons.sh` (ImageMagick 7 + python3), commit the outputs.
