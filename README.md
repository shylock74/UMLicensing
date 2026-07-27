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

## Not ported

Out of scope by design: Control Panel window, upgrade flow requiring the previous
serial, bait licenses, `LicenseRemote` (administration API), `UMIntegrityCheck`.

## Open assumptions

Five behaviours were inferred from the legacy call sites rather than read from the
original UMOmniaFramework sources. All are marked `⚠️` in code.

| Assumption | Location | Risk if wrong |
|---|---|---|
| `racId_md5` returns lowercase hex | `Internal/Compat.swift` | No validator matches; all existing licenses rejected |
| `du_getDateString` format (with or without time) | `Internal/Compat.swift` | Wrong `activate` and local-copy validators |
| `encapsulateGetValue` uses `<label>…</label>` | `Internal/Compat.swift` | Every server response reads empty |
| `prefs_setValueDate` stores a native `Date` | `Internal/LicenseStore.swift` | Dates misread, existing users de-registered |
| `netU_getMacAddress` format | `Internal/Compat.swift` | "Serial number already activated" for everyone |

The licensing server URL currently points at `https://alexraccuglia.net/license/license.asp`,
the only endpoint appearing in clear in the legacy code. Confirm it matches the
obfuscated `serverUrl` before shipping.

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
