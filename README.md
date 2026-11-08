# Easy Dice Thrower

A configurable Flutter dice tray for e-ink screens. Create a tray for your game, roll individual dice, and keep the results on screen without animations.

- Numeric dice, including custom side counts.
- Žoldnéři dice: 1–3 blank, 4–5 one sword, 6 two swords.
- Custom text dice: one physical face per line, including repeated labels and blank faces.
- Editable presets and named sets. Every die can be added, changed, duplicated or removed, including d20 dice.
- Automatic local saving of the current tray, last results and named sets.
- Tap or click to roll one die; swipe left or right anywhere on the tray to roll all dice. Enter/Space rolls a focused die.
- A checkmark and roll counter change contrast after every roll, including repeated faces. Pressing a die immediately highlights its outline.
- Text outcomes have a **Full result** action for reading long labels without rolling again.
- Czech and English, with a remembered language preference or device language selection.

The standalone [dice_thrower](https://github.com/jiri-one/dice_thrower) Dart library generates the rolls. The app pins its Git revision and maps physical faces to their presentation.

## Local web preview

Tested with Flutter 3.47.9 and Dart 3.13.7.

```sh
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8767
```

Open http://localhost:8767 in a browser. A fresh web tray starts with two regular d6 dice; the `zoldneri.jiri.one` entry starts with the editable Mercenaries / Žoldnéři preset. Use **Add dice**, **Edit**, and **Sets** to configure it. The globe button chooses the interface language; by default the app follows the device or browser, falling back to English for unsupported languages. Custom names and text faces stay exactly as entered.

For custom text dice, each line represents one equally likely physical face. Repeat a label to give that outcome more faces; an empty line or `—` represents a blank face. Leading and trailing empty lines also count, and the editor shows the physical-face and blank-face totals. Numeric dice support 2–1,000,000 sides, text dice 2–100 faces, and the tray holds up to 100 dice.

## Static web build

```sh
flutter build web --release --no-web-resources-cdn
python3 -m http.server 8767 --bind 127.0.0.1 --directory build/web
```

Rendering resources and artwork are bundled locally. State is kept in this browser for this origin, so a different port or browser has a separate tray. Named sets save the selection of dice; loading one starts fresh rolls. Switching sets after editing or rolling asks for confirmation. Clearing browser storage also clears the saved trays.

If stored data cannot be loaded, automatic saving stops to protect it. Use **Try loading again** to recover it. **Replace saved data** asks for confirmation before replacing the unread data with the current tray.

## Mobile web and hosting

The web app adapts to portrait and landscape phone windows, tablets and desktop screens. On iPhone, open it in Safari and choose **Share → Add to Home Screen**. On Android, use the browser's **Install app** or **Add to Home screen** command. The manifest and home-screen icons let it open in a separate app window where the browser supports this. Loading the web app requires a connection; offline startup is not provided.

Source code, Android and web builds, tests, and deployment live in one GitHub repository. The workflow in `.github/workflows/deploy.yml` analyzes and tests the app, builds `build/web`, then deploys it to one Cloudflare Worker serving only static assets. Both custom domains serve that same deployment. No application server is needed.

Two entry domains use the same application:

| Entry | Fresh tray |
| --- | --- |
| `easy-dice-thrower.jiri.one` | Two numeric d6 dice |
| `zoldneri.jiri.one` | One d20 and three mercenary d6 dice |

These are initial presets only. Each domain remembers its own edited tray, results, sets and preferences in browser storage. Reopening a domain restores that state. The native app starts with Mercenaries.

To set up hosting:

1. Create the GitHub environment `cloudflare`, restricted to deployments from `main`, with secrets `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN`. Deployments need **Account → Workers Scripts → Edit** for the intended account. Keep credentials out of source files.
2. Push to `main` or run **Web deployment** manually on `main`. Wrangler creates or updates the assets-only Worker `easy-dice-thrower` using `wrangler.jsonc`.
3. Attach `easy-dice-thrower.jiri.one` and `zoldneri.jiri.one` as Custom Domains of that Worker. Cloudflare manages their DNS records and certificates. These bindings are configured once, outside the deployment workflow.

The public `workers.dev` address and preview URLs are disabled. Each deployment replaces the asset version for both custom domains together; `wrangler rollback VERSION_ID` restores an earlier version.

The web build uses `/` as its base path because both domains serve the app at their root. Each address stays in the browser's address bar, allowing the app to select the matching initial preset. No redirect or separate deployment repository is required.

See [Cloudflare's custom-domain setup](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/), [deployment from GitHub Actions](https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/) and [WebKit's home-screen web app support](https://webkit.org/blog/13878/).

## Android

The Android app uses the same tray and keeps its state locally on the phone. Its name is **Easy Dice Thrower** and its application ID is `one.jiri.easy_dice_thrower`.

```sh
flutter build apk --debug
```

Release builds use a separate persistent signing key in the ignored `private/` directory. Keep this key and its password backed up to preserve the ability to install updates over the existing app.

```sh
mkdir -p private
keytool -genkeypair -keystore private/android-release.jks -alias easy-dice-thrower -keyalg RSA -keysize 3072 -validity 10000
```

Create `private/android-signing.properties` with `storePassword`, `keyPassword` and `keyAlias` properties matching the key. Then build and install:

```sh
flutter build apk --release
adb -s DEVICE_ID install -r build/app/outputs/flutter-apk/app-release.apk
```

Without these private signing files a release build is unsigned. Debug builds use Android's development key. The release app needs no internet permission; its dice engine and artwork work offline. Android startup stays white even when the phone uses dark mode. Modern system bars use dark symbols on white; older Android navigation bars retain a black background so their light buttons remain visible.

## Portrait and landscape

Portrait mode keeps only the tray name and a menu button above the dice. The menu opens adding, editing, sets, saving, language, orientation and help, then closes when an action is chosen. Dice use the remaining screen space so the starting four-dice tray fits without scrolling on phone screens. Editing adds a Done button for returning to the uncluttered tray.

Short landscape windows use a compact toolbar and size the dice to fill the available space. The starting four-dice tray fits in one row; smaller sets grow to use the height. Names wrap in full, and the help button opens the gesture instructions. Larger trays remain scrollable. Resizing preserves the dice and their results.

The native Android/iOS UI includes an orientation picker with fixed **Portrait** and **Landscape** modes. Portrait is the default; the choice is remembered across sessions and set changes. Each mode requests one specific direction rather than allowing sensor-based flips. A failed request is shown in the app and can be retried from the picker.

The web and desktop versions adapt to the window size and do not offer the phone orientation lock. Browser support for locking the device orientation is limited, and mobile operating systems can override locks on large displays. The native requests are covered by platform-channel tests; physical phone verification follows the APK build.

## Checks

```sh
flutter analyze
flutter test
```

The tests cover face mapping, editable trays, repeated rolls, persistence, pending-roll cancellation, keyboard and swipe input, and narrow layouts with enlarged system text.

## Artwork

The framed mercenary faces in `assets/mercenary/` were supplied by the author of the Žoldnéři rules.

## Translations

The officially maintained languages are Czech and English. Translations use Flutter's standard ARB format: readable JSON with ICU placeholders and plural forms. No PO/MO toolchain is required.

- `lib/l10n/app_en.arb` is the template, including context and placeholder metadata.
- `lib/l10n/app_cs.arb` contains the Czech translation.
- `l10n.yaml` configures generation. Dart files under `lib/l10n/generated/` are generated automatically and kept out of Git.

To add a community translation:

1. Copy `app_en.arb` to `app_<locale>.arb`, using a valid locale supported by Flutter's Material localizations, and update `@@locale`.
2. Translate message values and set `languageName` to the language's own name. Keep message keys, placeholders such as `{count}`, and ICU syntax unchanged.
3. Run `flutter gen-l10n`, then `flutter test` and rebuild the app. The supported locale list and language picker are generated from the catalogs; adding a catalog requires no Dart changes.

`flutter pub get` and normal Flutter builds also generate the localization code. User-defined set names, die aliases and face text are data rather than translation messages. Built-in presets and automatic labels use stable identities so switching languages preserves the tray and its results.
