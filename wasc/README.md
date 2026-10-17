# wasc passwords (browser extension + macOS desktop)

A rebranded build of [bitwarden/clients](https://github.com/bitwarden/clients), preconfigured for
the wasc self-hosted Vaultwarden at **https://passwords.wasc.me** (friends and family).

upstream_tag: desktop-v2026.10.0

- `main` mirrors upstream `main` (updated by `wasc-sync.yml`).
- `wasc` (default branch) = an upstream release tag plus the small patch described below.
- All upstream workflows are disabled in this fork; only `wasc-*.yml` run.
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

## Known leftovers (intentionally not changed)

- In-app strings, help/web-vault links and `cloudWebVaultUrl` still say/point to Bitwarden.
- `bitwarden://` URL scheme and the SSH agent socket `~/.bitwarden-ssh-agent.sock` are shared with
  an official install (only matters if both apps are installed and the SSH agent is enabled).
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
  npx electron-builder --config ../../wasc/desktop/electron-builder.json --mac --universal -p never -c.mac.identity=null
```

## CI

| Workflow           | Trigger                                | Does                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ------------------ | -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `wasc-browser.yml` | push to `wasc` (browser paths), manual | Builds Chrome + Firefox zips and a source zip. Manual run with `release` attaches them to release `browser-v<version>` (created with `--latest=false`, so the desktop updater ignores it). With `publish_stores`: Chrome Web Store (API v2) if `CWS_CLIENT_ID`, `CWS_CLIENT_SECRET`, `CWS_REFRESH_TOKEN`, `CWS_EXTENSION_ID`, `CWS_PUBLISHER_ID` are set; AMO (`web-ext sign`, listed or unlisted) if `AMO_JWT_ISSUER`, `AMO_JWT_SECRET` are set.              |
| `wasc-desktop.yml` | push to `wasc` (desktop paths), manual | Universal macOS DMG + zip + `latest-mac.yml`. Signs with `MAC_CERT_P12_BASE64` / `MAC_CERT_PASSWORD` (Developer ID Application), notarizes with `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8`. Without the cert it produces an unsigned build. Manual run with `release` publishes `desktop-v<version>` and marks it **Latest** (electron-updater's GitHub provider reads `latest-mac.yml` from the Latest release; auto-update only works for signed builds). |
| `wasc-sync.yml`    | quarterly (1 Jan/Apr/Jul/Oct), manual  | Re-disables non-wasc workflows, mirrors upstream `main`, merges the newest stable `desktop-v*` tag into `sync/<tag>`, lets `claude-code-action` (`ANTHROPIC_API_KEY`) resolve conflicts, opens a PR into `wasc` and dispatches both build workflows on it. Needs `SYNC_TOKEN` (PAT with contents, pull requests, workflows, actions) to push upstream workflow-file changes.                                                                                   |

Signing details: `scripts/macos-signing-identity.js` hardcodes Bitwarden's identity when
`GITHUB_ACTIONS=true`, so electron-builder runs with `GITHUB_ACTIONS=false` and `CSC_NAME=<SHA-1 of
our Developer ID cert>`; `scripts/after-sign.js` notarizes via `APP_STORE_CONNECT_*` (mapped from
the `ASC_*` secrets).

## Updating the icon

Edit `wasc/brand/icon-rounded.svg` (and `icon.svg`, shared with passwords-ios), run
`wasc/brand/render-icons.sh` (ImageMagick 7 + python3), commit the outputs.
