# UMLicensing

Serial-number licensing for macOS apps. Self-contained: no dependency on
UMOmniaFramework.

Port of the legacy `License` / `LicenseData` / `UMLicenseValidationCode` stack, with
the UI rewritten in SwiftUI and networking moved to async/await. Serial format,
validators, storage keys and server protocol are unchanged, so existing customers
keep working.

**Requirements:** macOS 14+, Swift 6.

## Installation

```swift
dependencies: [
    .package (url: "<your-repo-url>", from: "1.0.0")
]
```

```swift
.target (name: "MyApp", dependencies: ["UMLicensing"])
```

## Quick start

One call at launch:

```swift
import UMLicensing

@MainActor
func boot () async {
    let ok = await UMLicensing.licensed (appId:                 Boot.kAppIdLong,
                                         appName:               Boot.kAppName,
                                         appShortId:            Boot.kAppIdShort,
                                         previousVersionPrefix: Boot.kPreviousVersionPrefix,
                                         purchaseUrl:           Boot.purchaseUrl,
                                         downloadAppUrl:        Boot.downloadAppUrl,
                                         logoImageUrl:          Boot.logoImageUrl)
    guard ok else {
        NSApp.terminate (nil)
        return
    }
    // app starts
}
```

`licensed()` never terminates the app itself. If the user gives up it returns
`false` and the decision stays with the caller.

## What it does

| Step | Behaviour |
|---|---|
| 1. Fast path | Perpetual license confirmed by the server within `graceDays`: starts immediately, no network. Grace window is renewed silently in the background. |
| 2. Recovery | No local license: asks the server whether this machine (MAC address) is already registered. Covers reinstalls and wiped preferences. |
| 3. Acquisition | Choice window: start a trial, or enter a serial. |
| 4. Confirmation | Verifies with the server that the serial is not activated elsewhere and realigns the expiry date. Server unreachable but grace period still valid: starts anyway. |

Trial flow: name + email → serial generated and registered server-side → email sent →
the user pastes the serial, which confirms the address is reachable.

## Public API

### `UMLicensing`

`@MainActor public enum UMLicensing`

#### `licensed(...) async -> Bool`

Verifies the license, guiding the user through trial or serial entry when needed.
Returns `true` if the app may start.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `appId` | `String` | — | Long app identifier, as registered on the server. |
| `appName` | `String` | — | Human-readable name, shown in windows and email. |
| `appShortId` | `String` | — | 4-character serial prefix for this app. |
| `acceptedApps` | `[String]` | `[appShortId]` | Prefixes accepted by serial validation. Pass a longer list if the app was renamed or accepts another product's serials. |
| `previousVersionPrefix` | `String` | `""` | Previous version prefix, additionally accepted. |
| `purchaseUrl` | `String` | — | Opened by the "Buy a License" button. |
| `downloadAppUrl` | `String` | `""` | Download link embedded in the trial email. |
| `logoImageUrl` | `String` | — | App logo shown at the top of the trial email. |
| `logoImageAlt` | `String` | `""` | Logo alt text. Falls back to `appName`. |
| `mailBackgroundColor` | `NSColor` | `.umLicensingMailBackground` | Email background. |
| `mailAccentColor` | `NSColor` | `.umLicensingMailAccent` | Email borders, button and links. |
| `mailBody` | `String` | bundled template | Alternative HTML template. |
| `trialExpDays` | `Int` | `7` | Trial duration. |
| `graceDays` | `Int` | `30` | Days a license stays valid without reaching the server. Past this, an online check becomes mandatory. |
| `serverUrl` | `String?` | `nil` | Alternative endpoint. Normally left `nil`. |

#### `currentLicense(appId:) -> LicenseData`

Returns the stored license without touching the network or showing any window.

```swift
let license = UMLicensing.currentLicense (appId: Boot.kAppIdLong)
if license.type == .trial {
    showTrialBadge (until: license.expDate)
}
```

### `LicenseData`

`public struct LicenseData: Codable, Sendable, Equatable`

| Property | Type | Description |
|---|---|---|
| `appId` `serialId` `machId` | `String` | Identity of the license. |
| `username` `password` `email` | `String` | Registration details. |
| `regDate` `expDate` | `Date` | Registration and expiry. |
| `licType` | `String` | License type as stored server-side. |
| `errorMessage` | `String` | Non-empty when the local copy failed validation. |

| Computed | Type | Description |
|---|---|---|
| `type` | `licenseType` | Type derived from the serial. |
| `isRegistered` | `Bool` | Present and passing local validation. |
| `isExpired` | `Bool` | Past expiry. Perpetual licenses never expire. |
| `serialCounter` | `Int?` | Progressive number extracted from the serial. |

### `licenseType`

`public enum licenseType: Sendable` — `.trial` `.full` `.special` `.invalid` `.gift`
`.bait` `.upgrade`

| Member | Type | Description |
|---|---|---|
| `init(serialId:)` | — | Derives the type from character 5 of the serial. |
| `char` | `String` | Serial character: `F` `T` `S` `G` `B` `U`. |
| `name` | `String` | Value stored in `licType`. |
| `displayName` | `String` | Same, but correct for `.upgrade` — see *Deliberate quirks*. |
| `isPerpetual` | `Bool` | `true` for `.full` `.gift` `.upgrade` `.special`. |

### `UMLicenseValidationCode`

`public struct UMLicenseValidationCode: Codable, Sendable, Equatable`

Local proof that a license was verified on this machine — what allows offline
launches. The machine ID is hashed before storage, never kept in clear.

```swift
let code = UMLicenseValidationCode (appId: "com.ulti.beatmark",
                                    serialNumber: "PC20F-00000001-1234567",
                                    machineID: macAddress)
code.save ()

if let saved = UMLicenseValidationCode.load (), saved.isValid {
    // license already confirmed on this Mac
}
```

| Member | Signature | Description |
|---|---|---|
| `init` | `(appId:serialNumber:machineID:)` | `machineID` is MD5-hashed on the way in. |
| `expectedCode()` | `-> String` | Expected code for this app/serial/machine triple. |
| `isValid` | `Bool` | Stored code matches the expected one. |
| `save(defaults:)` | `(UserDefaults = .standard)` | Persists with a freshly computed code. |
| `load(defaults:)` | `-> UMLicenseValidationCode?` | Static. Reads the stored code. |

### `License` — compatibility facade

`@MainActor public enum License`

Mirrors the legacy static surface so existing app code compiles unchanged. No logic
here — it forwards to `UMLicensing`. Populated by `licensed()`.

**Read-only state:** `appId` `appName` `appShortId` `acceptedApps`
`previousVersionPrefix` `purchaseLicenseURL` `downloadAppUrl` `trialExpDays`
`licenseValidated` `username` `email`

| Method | Returns |
|---|---|
| `loadLicense()` | `LicenseData` |
| `getSerialId()` `getMachineId()` `getAppId()` | `String` |
| `isRegistered()` `isExpired()` | `Bool` |
| `getExpirationDate()` | `Date` |
| `getType()` `getCurrentLicenseType()` | `licenseType` |
| `getLicenseType(_:)` | `licenseType` from a serial |
| `getLicenseTypeChar(_:)` `getLicenseTypeString(_:)` | `String` |
| `serialToApp(_:)` | `String` — first 4 characters |
| `validateSerial(_:)` | `Bool` — local check only |
| `generateSN(appId:type:progressiveN:)` | `String` |
| `getValidator(text:)` `getSerialPrefixValidator(_:)` `getUnlockCode()` | `String` |
| `releaseLicense(appId:serialId:unlockCode:) async` | `Bool` |
| `fastReleaseLicense(serialId:) async` | `Bool` |
| `clearLicense() async` | — asks for confirmation, then releases server-side |

### `NSColor` defaults

```swift
NSColor.umLicensingMailBackground   // #0f172a
NSColor.umLicensingMailAccent       // #38bdf8
```

## Serial format

```
PC20F-00000001-1234567
└─┬─┘│ └──┬───┘ └──┬──┘
  │  │    │        └─ validator: 7 digits from md5(prefix + secret)
  │  │    └────────── progressive number, 8 digits, zero-padded
  │  └─────────────── license type (F/T/S/G/B/U)
  └────────────────── appShortId, 4 characters
```

`validateSerial` is a local check: it confirms the prefix is accepted and the check
digits match. It says nothing about whether the serial exists server-side or is
already activated elsewhere.

## Trial email

Template: `Sources/UMLicensing/MailTemplate.txt`, bundled as a package resource.
Apps wanting a different email pass their own HTML in `mailBody`.

| Placeholder | Source |
|---|---|
| `%%License.username%%` | name entered in the trial window |
| `%%License.serialId%%` | generated serial |
| `%%License.expDate%%` | expiry, formatted `27 July 2026` |
| `%%APPNAME%%` | `appName` |
| `%%DOWNLOADAPP%%` | `downloadAppUrl` |
| `%%LogoImageUrl%%` | `logoImageUrl` |
| `%%LogoImageAlt%%` | `logoImageAlt`, or `appName` when empty |
| `%%BG_RGB%%` | `mailBackgroundColor` as `15, 23, 42` |
| `%%ACCENT_RGB%%` | `mailAccentColor` as `56, 189, 248` |
| `%%BUILD%%` | automatic: `CFBundleShortVersionString (CFBundleVersion)` |
| `%%YEAR%%` | automatic: current year |

`%%License.appId%%`, `%%License.appName%%` and `%%License.downloadAppUrl%%` — the
legacy `d5` names — remain recognised for templates already in circulation.

An empty `logoImageUrl` removes the whole `<img>` block: an empty `src` renders as a
broken-image icon in most email clients.

Adding a placeholder to the template means adding it to `TrialMailer.body`. The test
`testRealTemplateHasNoLeftoverPlaceholders` fails if one is missed.

Delivery goes through `https://ultimediacloud.net/mailer/mailer.php` with the same
fields as the legacy `SendEmail` (`mailFrom`, `mailFromName`, `mailTo`, `mailToName`,
`mailSubject`, `mailBody`). No credentials ship in the binary.

## Backward compatibility

Deliberately preserved:

- **Serial format** and validator algorithm.
- **Storage keys** `license..serialId` and friends — double dot included. Already
  registered users do not lose their license.
- **Server protocol** — same actions, same MD5 validators.
- **Date format `dd/MM/yyyy`** (`Compat.du_getDateString`). It goes into the local
  copy's validator and into the `activate` validator, so it is the format of every
  license already in the field. Do not "modernise" it to ISO.
- **Unlock code without MD5** — `racId_getNumbersToLength(appId + serialId + machId +
  secret, 10)`, digits taken straight from the concatenation, matching what SNGenerator
  gives support.
- **MAC address = the last matching primary interface**, not the first. The legacy
  loop overwrote its result on every iteration; on a Mac with more than one primary
  Ethernet interface, picking the first yields a different `machId` and the server
  answers "Serial number already activated".

### Deliberate quirks

`licenseType.name` returns `""` for `.upgrade`. The original
`getLicenseTypeString` had no `.upgrade` case and fell through to `default`, so every
upgrade on the server carries an empty `licType`. Behaviour kept to avoid diverging
from existing data; `displayName` returns `"upgrade"` for UI use.

### Intentional fixes

- `clearLicense()` built its keys as `"license\(infix).appId"`, missing the dot after
  `license`, so it deleted keys that never existed and left the license in place. Now
  removed for real.
- The mailer used `.urlQueryAllowed` percent-encoding, which lets `&` and `=` through:
  an HTML body containing a link with a query string broke the POST form and arrived
  truncated. Now fully form-encoded.
- `netU_percEnc` was based on `.urlHostAllowed`, which also lets `&` and `=` through,
  so a value containing either split the query. Now restricted to unreserved
  characters, `+` included — the legacy code special-cased `+` for the same reason:
  left as-is it reaches the server as a space, and an address like `name+tag@x.com`
  no longer matches the validator computed on it.

### Migration from the first releases of this package

Versions before this one signed the stored license with the dates in `yyyy-MM-dd`
instead of the original `dd/MM/yyyy`, so on a machine that had run one of them
`LicenseStore.load()` would find a signature that no longer matches and report the
license as tampered with. `load()` now recognises that older signature, accepts the
license, and rewrites it with the correct one — no user is de-registered, and no
network round trip is needed. See `LicenseValidator.isoValidator`.

## Not ported

Out of scope by design: Control Panel window, upgrade flow requiring the previous
serial, bait licenses, `LicenseRemote` (administration API), `UMIntegrityCheck`.

## Checked against the original

The behaviours that decide whether an existing license still validates were read off
the UMOmniaFramework sources, not guessed:

| Behaviour | Original | Status |
|---|---|---|
| `racId_md5` | `CC_MD5` formatted `%02x` — lowercase hex | matches |
| `du_getDateString` | `dd/MM/yyyy`, no time | fixed — was ISO |
| `du_createDateFormStandardString` | day `[0,2)`, month `[3,5)`, year = last 4 | fixed — read ISO first |
| `encapsulateGetValue` | `<label>…</label>` | matches |
| `prefs_setValueDate` | native `Date` in `UserDefaults` | matches |
| `netU_getMacAddress` | lowercase hex, `:` separated, **last** primary interface | fixed — took the first |
| `getUnlockCode` | no MD5 around the concatenation | fixed — had one |
| `racId_getNumbersToLength` | `""` when the source has no digits | fixed — returned zeros |
| Server URL | `https://www.alexraccuglia.net/license/license.asp` | fixed — `www.` was missing |
| Validator secret | `l1c3n53!` | matches |
| Unlock secret | `53r141` | matches |
| `UMLicenseValidationCode` secret and JSON shape | `1òàùéP*'ì1c3n53!`, same key `UMLVC` | matches |

The server URL is the legacy `License.serverUrl` run through `Splhash.getPlain`.

### Fixed User-Agent

Requests go out as `UMLicensing/1.0`, not as the default URLSession agent
(`<AppName>/<version> CFNetwork/… Darwin/…`). Aruba's application firewall answers
`HTTP 999 — AW Special Error` when the app name contains a word it considers suspicious:
"Disc Scanner" was blocked on account of "scanner", and the app saw it as an unreachable
server (`UML-E108`). A fixed agent keeps the product name out of the request, so no app
can lock itself out because of what it is called.

## Diagnostics and logging

Three levels, from quietest to loudest:

| | When it prints | What it covers |
|---|---|---|
| `Diagnostics.diagnose` | always, any build | one line per `UML-Exxx`, the code a user can read out over the phone |
| `Diagnostics.log` | Debug builds, or when the flag is on | server exchange, raw responses, offline reasoning |
| `Diagnostics.trace` | Debug builds only — compiled out of Release | every step: preferences read and written, each HTTP call and its result, parsed license fields, windows shown and how they were dismissed, validation-code signing |

In a Debug build everything is on with nothing to configure. In Release, turn the middle
level on with `UMLicensing.verboseLogging = true`, `UMLICENSING_DEBUG=1`, or
`defaults write <bundle-id> UMLicensing.debug -bool YES`; `trace` does not exist there at
all, so its cost is zero.

Output goes to `os.Logger` (subsystem `media.ulti.UMLicensing`) **and** stdout, flushed
line by line — a buffered stdout would swallow exactly the lines you need when the app
blocks or terminates.

Debug traces print license fields as they are, raw server responses included: they only
exist in builds that never reach users.

## Testing

```bash
swift test
```

If `xcode-select` points at the Command Line Tools, XCTest is unavailable — select a
full Xcode for the run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Two utility tests are skipped unless explicitly enabled:

```bash
UMLICENSING_PREVIEW=/tmp/mail.html swift test --filter testWritePreviewUtility
UMLICENSING_EMIT=1 swift test --filter testEmitBytesUtility
```

The first renders the trial email to a file for visual inspection. The second emits
obfuscated byte arrays for `Strings.swift`.

## Project layout

```
Sources/UMLicensing/
├── UMLicensing.swift          Entry point: licensed(), flow orchestration
├── MailTemplate.txt           Bundled trial email template
├── Model/                     LicenseData, licenseType
├── Core/                      Validator, server client, mailer, validation code
├── Internal/                  Compat helpers, storage, obfuscation, scanner
├── UI/                        SwiftUI windows, alerts, mail colours
└── Compat/License.swift       Legacy static facade
```
