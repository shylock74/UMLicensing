//
//  UMLicensingTests.swift
//  UMLicensing
//
//  Questi test bloccano le assunzioni che ho dovuto dedurre dal vecchio codice
//  invece di leggerle nel sorgente di UMOmniaFramework. Se un'assunzione è
//  sbagliata, va corretta in `Compat.swift` e questi test devono continuare a
//  passare con i valori reali.
//

import Foundation
import XCTest
@testable import UMLicensing


// MARK: - Formato dei seriali

final class SerialTests: XCTestCase {

	/// Un seriale generato deve superare la propria validazione. Se questo test
	/// fallisce, `racId_getNumbersToLength` o `strUt_position` non si comportano
	/// come l'originale.
	func testGenerateSNRoundTrip () {
		for type in [licenseType.full, .trial, .gift, .special, .bait, .upgrade] {
			let sn = LicenseValidator.generateSN (appShortId: "PC20", type: type, progressiveN: 42)

			XCTAssertTrue (LicenseValidator.validateSerial (sn,
														   acceptedApps: ["PC20"],
														   previousVersionPrefix: ""),
						   "seriale \(sn) di tipo \(type) rifiutato")
			XCTAssertEqual (licenseType (serialId: sn), type)
		}
	}


	func testSerialFormat () {
		let sn = LicenseValidator.generateSN (appShortId: "PC20", type: .full, progressiveN: 1)

		XCTAssertTrue (sn.hasPrefix ("PC20F-00000001-"))
		XCTAssertEqual (sn.count, 22)

		let parts = sn.split (separator: "-").map (String.init)
		XCTAssertEqual (parts.count, 3)
		XCTAssertEqual (parts [1].count, 8)
		XCTAssertEqual (parts [2].count, 7)
		XCTAssertTrue (parts [2].allSatisfy (\.isNumber))
	}


	func testSerialOfAnotherAppIsRejected () {
		let sn = LicenseValidator.generateSN (appShortId: "PC20", type: .full, progressiveN: 7)

		XCTAssertFalse (LicenseValidator.validateSerial (sn,
														acceptedApps: ["XX99"],
														previousVersionPrefix: ""))
	}


	func testPreviousVersionPrefixIsAccepted () {
		let sn = LicenseValidator.generateSN (appShortId: "PC19", type: .full, progressiveN: 7)

		XCTAssertTrue (LicenseValidator.validateSerial (sn,
													   acceptedApps: ["PC20"],
													   previousVersionPrefix: "PC19"))
	}


	func testTamperedValidatorIsRejected () {
		var sn = LicenseValidator.generateSN (appShortId: "PC20", type: .full, progressiveN: 7)
		sn = String (sn.dropLast ()) + (sn.hasSuffix ("0") ? "1" : "0")

		XCTAssertFalse (LicenseValidator.validateSerial (sn,
														acceptedApps: ["PC20"],
														previousVersionPrefix: ""))
	}


	func testSerialCounterIsReadBack () {
		var license = LicenseData ()
		license.serialId = LicenseValidator.generateSN (appShortId: "PC20", type: .full, progressiveN: 12345)

		XCTAssertEqual (license.serialCounter, 12345)
	}


	/// Nessuno di questi deve far crashare la validazione: arrivano da un campo di
	/// testo in cui l'utente può scrivere qualsiasi cosa.
	func testMalformedInputDoesNotCrash () {
		for input in ["", "-", "--", "PC20F", "PC20F-", "PC20F-00000001", "????-????-????", "PC20F--"] {
			XCTAssertFalse (LicenseValidator.validateSerial (input,
															acceptedApps: ["PC20"],
															previousVersionPrefix: ""),
							"input \"\(input)\" accettato")
		}
	}
}


// MARK: - Helper dedotti

final class CompatTests: XCTestCase {

	/// `validateSerial` chiama `strUt_position(recurrence: 1)` e si aspetta il
	/// SECONDO trattino: la ricorrenza è 0-based.
	func testPositionCountsOccurrencesFromZero () {
		let s = "PC20F-00000001-1234567"

		XCTAssertEqual (Compat.strUt_position (srcText: s, subString: "-", startAt: 0, recurrence: 0), 5)
		XCTAssertEqual (Compat.strUt_position (srcText: s, subString: "-", startAt: 0, recurrence: 1), 14)
		XCTAssertEqual (Compat.strUt_position (srcText: s, subString: "-", startAt: 0, recurrence: 2), -1)
		XCTAssertEqual (Compat.strUt_position (srcText: s, subString: "@", startAt: 0, recurrence: 0), -1)
	}


	func testPadN () {
		XCTAssertEqual (Compat.strUt_padN (n: 1, padN: 8), "00000001")
		XCTAssertEqual (Compat.strUt_padN (n: 12345678, padN: 8), "12345678")
		XCTAssertEqual (Compat.strUt_padN (n: 123456789, padN: 8), "123456789")
	}


	func testGetNumbersToLength () {
		XCTAssertEqual (Compat.racId_getNumbersToLength (s: "a1b2c3d4e5f6", l: 4), "1234")
		XCTAssertEqual (Compat.racId_getNumbersToLength (s: Compat.racId_md5 ("PC20F-00000001"), l: 7).count, 7)

		// Poche cifre: l'originale ricicla le stesse finché non arriva a lunghezza.
		XCTAssertEqual (Compat.racId_getNumbersToLength (s: "a1b2", l: 5), "12121")

		// Nessuna cifra: stringa vuota, non una stringa di zeri.
		XCTAssertEqual (Compat.racId_getNumbersToLength (s: "abcdef", l: 4), "")
		XCTAssertEqual (Compat.racId_getNumbersToLength (s: "", l: 4), "")
	}


	/// ⚠️ Ipotesi: MD5 in hex minuscolo. Se `racId_md5` usava hex maiuscolo questo
	/// test va aggiornato E ogni licenza esistente smette di validare.
	func testMD5IsLowercaseHex () {
		XCTAssertEqual (Compat.racId_md5 ("abc"), "900150983cd24fb0d6963f7d28e17f72")
		XCTAssertEqual (Compat.racId_md5 (""), "d41d8cd98f00b204e9800998ecf8427e")
	}


	func testSubStringMatchesServerDateParsing () {
		let s = "2026-07-27 10:15:00"

		XCTAssertEqual (Compat.strUt_getSubString (srcString: s, startAt: 0, endAt: 4), "2026")
		XCTAssertEqual (Compat.strUt_getSubString (srcString: s, startAt: 5, endAt: 7), "07")
		XCTAssertEqual (Compat.strUt_getSubString (srcString: s, startAt: 8, endAt: 10), "27")
	}


	/// ⚠️ Ipotesi sul formato di risposta del server.
	func testEncapsulateGetValue () {
		let response = "<errorCode>0</errorCode><data><serialId>PC20F-00000001-1234567</serialId></data>"

		XCTAssertEqual (Compat.encapsulateGetValue (srcText: response, label: "errorCode"), "0")

		let data = Compat.encapsulateGetValue (srcText: response, label: "data")
		XCTAssertEqual (Compat.encapsulateGetValue (srcText: data, label: "serialId"), "PC20F-00000001-1234567")
		XCTAssertEqual (Compat.encapsulateGetValue (srcText: response, label: "assente"), "")

		let errResponse = "<errorCode>1</errorCode><errorMessage>Invalid S/N</errorMessage>"
		XCTAssertEqual (Compat.encapsulateGetValue (srcText: errResponse, label: "errorCode"), "1")
		XCTAssertEqual (Compat.encapsulateGetValue (srcText: errResponse, label: "errorMessage"), "Invalid S/N")
	}


	func testDeltaDateIsSigned () {
		let today = Date ()

		XCTAssertEqual (Compat.du_getDeltaDate (firstDate: today,
												secondDate: Compat.du_getDatePlusDays (date: today, days: 5)), 5)
		XCTAssertEqual (Compat.du_getDeltaDate (firstDate: today,
												secondDate: Compat.du_getDatePlusDays (date: today, days: -3)), -3)
	}


	/// Regressione: una data del server in un formato non previsto veniva letta come
	/// anno 0 — cioè una data nel passato — e faceva risultare scaduta una licenza
	/// appena attivata. Ora una stringa illeggibile è `nil`, non una data finta.
	func testUnreadableServerDateIsNilNotYearZero () {
		for input in ["27/07/2026 10:15", "July 27, 2026", "", "   ", "abc",
					  "0000-00-00", "null", "-", "20260727"] {
			let parsed = Compat.du_parseServerDate (input)

			if let parsed {
				XCTAssertTrue (Compat.isPlausible (parsed),
							   "\"\(input)\" interpretata come data implausibile: \(parsed)")
			}
		}
	}


	/// I formati che il backend può realisticamente restituire devono dare tutti
	/// il 27 luglio 2026.
	func testServerDateFormatsAreUnderstood () {
		let expected = Compat.du_createDate (d: 27, m: 7, y: 2026)

		for input in ["2026-07-27", "2026-07-27 10:15:00", "2026/07/27",
					  "27/07/2026", "27-07-2026"] {
			XCTAssertEqual (Compat.du_parseServerDate (input), expected,
							"formato non riconosciuto: \"\(input)\"")
		}
	}


	/// Il caso che produceva il bug: `Int("27/0") ?? 0` dava anno 0, cioè una data
	/// remotissima nel passato, e la licenza risultava scaduta.
	func testNonISODateIsNotReadAsYearZero () {
		let date = Compat.du_createDateFormStandardString ("31/12/2030")

		XCTAssertTrue (Compat.isPlausible (date))
		XCTAssertGreaterThan (date, Date (), "una scadenza 2030 non può risultare già passata")
	}


	/// Una licenza a termine con scadenza futura non deve risultare scaduta solo
	/// perché il server ha risposto in un formato inatteso.
	func testTrialWithFutureRemoteDateIsNotExpired () {
		var license = LicenseData ()
		license.serialId = LicenseValidator.generateSN (appShortId: "PC20", type: .trial, progressiveN: 1)
		license.expDate  = Compat.du_createDateFormStandardString ("31/12/2030")

		XCTAssertFalse (license.isExpired)
	}


	/// Il formato che entra nei validator. Se questo test cambia, cambia anche la
	/// firma di ogni licenza già emessa: non "aggiustarlo", è il contratto col vecchio
	/// `du_getDateString`.
	func testDateStringIsLegacyDayFirstFormat () {
		let date = Compat.du_createDate (d: 27, m: 7, y: 2026)

		XCTAssertEqual (Compat.du_getDateString (date), "27/07/2026")
		XCTAssertEqual (Compat.du_createDateFormStandardString (Compat.du_getDateString (date)), date)
	}


	/// L'unlock code dettato al supporto non passa da md5: le cifre escono direttamente
	/// dalla concatenazione, come in `License.getUnlockCode()`.
	func testUnlockCodeMatchesLegacyFormula () {
		var license = LicenseData ()
		license.appId    = "FCP SRT Importer 2"
		license.serialId = "SI20F-00000123-1234567"
		license.machId   = "aa:bb:cc:dd:ee:ff"

		let expected = Compat.racId_getNumbersToLength (s: license.appId + license.serialId
													   + license.machId + "53r141",
													   l: 10)
		XCTAssertEqual (LicenseValidator.unlockCode (for: license), expected)
		XCTAssertEqual (LicenseValidator.unlockCode (for: license).count, 10)
	}


	/// Una licenza salvata da una build che firmava in `yyyy-MM-dd` deve essere
	/// riconosciuta e riscritta con la firma legacy, non dichiarata manomessa.
	func testIsoSignedLicenseIsMigratedNotRejected () {
		let defaults = UserDefaults (suiteName: "UMLicensingTests.isoMigration")!
		defaults.removePersistentDomain (forName: "UMLicensingTests.isoMigration")

		var license = LicenseData ()
		license.appId    = "FCP SRT Importer 2"
		license.serialId = LicenseValidator.generateSN (appShortId: "SI20", type: .full, progressiveN: 123)
		license.machId   = "aa:bb:cc:dd:ee:ff"
		license.username = "Alex"
		license.password = "PASSWORD"
		license.email    = "alex@example.com"
		license.regDate  = Compat.du_createDate (d: 1, m: 3, y: 2024)
		license.expDate  = Compat.du_createDate (d: 1, m: 1, y: 2100)
		license.licType  = "full"

		let store = LicenseStore (appId: license.appId, defaults: defaults)
		store.save (license)
		// Sovrascriviamo la firma con quella sbagliata delle prime build.
		defaults.set (LicenseValidator.isoValidator (for: license), forKey: "license..validator")

		let loaded = store.load ()
		XCTAssertEqual (loaded.serialId, license.serialId, "la licenza non deve essere scartata")
		XCTAssertTrue (loaded.errorMessage.isEmpty)

		// E la firma sui preferences ora è quella legacy.
		XCTAssertEqual (defaults.string (forKey: "license..validator"),
						LicenseValidator.validator (for: license))

		defaults.removePersistentDomain (forName: "UMLicensingTests.isoMigration")
	}
}


// MARK: - Offuscamento

final class ObfuscationTests: XCTestCase {

	func testKnownStringsDecodeCorrectly () {
		XCTAssertEqual (Strings.validatorSuffix.value, "l1c3n53!")
		XCTAssertEqual (Strings.unlockSuffix.value, "53r141")
		XCTAssertEqual (Strings.validationCodeSuffix.value, "1òàùéP*'ì1c3n53!")
		XCTAssertEqual (Strings.invalidSN.value, "Invalid S/N")
		XCTAssertEqual (Strings.notRegistered.value, "Not registered.")
		XCTAssertEqual (Strings.notValidated.value, "Not validate.")
		XCTAssertEqual (Strings.invalidLicense.value, "Invalid License")
		XCTAssertEqual (Strings.checkIfYouTypedCorrectly.value, "Check if you typed correctly")
		XCTAssertEqual (Strings.serialAlreadyActivated.value, "Serial number already activated.")
		XCTAssertEqual (Strings.trialLicenseExpires.value, "Trial License expires: ")
	}


	func testRoundTripHandlesNonASCII () {
		for s in ["", "a", "https://example.com/x.asp?a=1&b=2", "àèìòù €", String (repeating: "x", count: 200)] {
			XCTAssertEqual (Obfuscated (Obfuscated.encode (s)).value, s)
		}
	}


	/// Stampa i byte da incollare in `Strings.swift`. Non è una verifica: è il modo
	/// di produrre le costanti senza lasciare i literal in chiaro nel binario.
	func testEmitBytesUtility () throws {
		try XCTSkipUnless (ProcessInfo.processInfo.environment ["UMLICENSING_EMIT"] == "1",
						   "utility: eseguire con UMLICENSING_EMIT=1")

		for s in ["Not registered.", "Invalid License"] {
			let bytes = Obfuscated.encode (s).map { String (format: "0x%02X", $0) }.joined (separator: ", ")
			print ("\(s) -> [\(bytes)]")
		}
	}
}


// MARK: - Storage

final class StoreTests: XCTestCase {

	private func makeDefaults () -> UserDefaults {
		UserDefaults (suiteName: "UMLicensingTests.\(UUID ().uuidString)")!
	}


	func testSaveAndLoadRoundTrip () {
		let store = LicenseStore (appId: "com.ulti.test", defaults: makeDefaults ())

		var license = LicenseData ()
		license.appId    = "com.ulti.test"
		license.serialId = LicenseValidator.generateSN (appShortId: "PC20", type: .full, progressiveN: 1)
		license.machId   = "aa:bb:cc:dd:ee:ff"
		license.username = "Alex"
		license.email    = "alex@example.com"
		license.licType  = "full"

		store.save (license)
		let loaded = store.load ()

		XCTAssertTrue (loaded.isRegistered)
		XCTAssertEqual (loaded.serialId, license.serialId)
		XCTAssertEqual (loaded.email, "alex@example.com")
		XCTAssertEqual (loaded.errorMessage, "")
	}


	/// Le chiavi devono restare quelle del vecchio `License`, doppio punto incluso:
	/// è lì che si trova la licenza sulle macchine degli utenti già registrati.
	func testLegacyKeys () {
		let defaults = makeDefaults ()
		let store = LicenseStore (appId: "com.ulti.test", defaults: defaults)

		var license = LicenseData ()
		license.appId    = "com.ulti.test"
		license.serialId = "PC20F-00000001-1234567"
		store.save (license)

		XCTAssertEqual (defaults.string (forKey: "license..appId"), "com.ulti.test")
		XCTAssertEqual (defaults.string (forKey: "license..serialId"), "PC20F-00000001-1234567")
		XCTAssertNotNil (defaults.string (forKey: "license..validator"))
	}


	func testNewSystemKeysIncludeAppId () {
		let defaults = makeDefaults ()
		let store = LicenseStore (appId: "com.ulti.test", newSystem: true, defaults: defaults)

		var license = LicenseData ()
		license.appId    = "com.ulti.test"
		license.serialId = "PC20F-00000001-1234567"
		store.save (license)

		XCTAssertEqual (defaults.string (forKey: "license..com.ulti.test.appId"), "com.ulti.test")
	}


	/// L'attacco più banale: allungare la scadenza del trial modificando i preferences.
	func testTamperedExpiryIsRejected () {
		let defaults = makeDefaults ()
		let store = LicenseStore (appId: "com.ulti.test", defaults: defaults)

		var license = LicenseData ()
		license.appId    = "com.ulti.test"
		license.serialId = LicenseValidator.generateSN (appShortId: "PC20", type: .trial, progressiveN: 1)
		store.save (license)

		defaults.set (Compat.du_getDatePlusDays (date: Date (), days: 3650), forKey: "license..expDate")

		let loaded = store.load ()
		XCTAssertFalse (loaded.isRegistered)
		XCTAssertEqual (loaded.serialId, "")
	}


	func testClearRemovesTheLicense () {
		let defaults = makeDefaults ()
		let store = LicenseStore (appId: "com.ulti.test", defaults: defaults)

		var license = LicenseData ()
		license.appId    = "com.ulti.test"
		license.serialId = "PC20F-00000001-1234567"
		store.save (license)
		store.clear ()

		XCTAssertNil (defaults.string (forKey: "license..serialId"))
		XCTAssertFalse (store.load ().isRegistered)
	}


	func testPerpetualLicenseNeverExpires () {
		var license = LicenseData ()
		license.appId    = "com.ulti.test"
		license.serialId = LicenseValidator.generateSN (appShortId: "PC20", type: .full, progressiveN: 1)
		license.expDate  = Compat.du_getDatePlusDays (date: Date (), days: -1000)

		XCTAssertFalse (license.isExpired)
	}


	func testTrialExpires () {
		var license = LicenseData ()
		license.serialId = LicenseValidator.generateSN (appShortId: "PC20", type: .trial, progressiveN: 1)
		license.expDate  = Compat.du_getDatePlusDays (date: Date (), days: -1)

		XCTAssertTrue (license.isExpired)
	}
}


// MARK: - Codice di validazione

final class ValidationCodeTests: XCTestCase {

	func testCodeIsBoundToMachine () {
		let a = UMLicenseValidationCode (appId: "app", serialNumber: "PC20F-00000001-1234567", machineID: "aa:bb")
		let b = UMLicenseValidationCode (appId: "app", serialNumber: "PC20F-00000001-1234567", machineID: "cc:dd")

		XCTAssertNotEqual (a.expectedCode (), b.expectedCode ())
	}


	func testMachineIdIsNeverStoredInClear () {
		let code = UMLicenseValidationCode (appId: "app", serialNumber: "sn", machineID: "aa:bb:cc:dd:ee:ff")

		XCTAssertNotEqual (code.machineID, "aa:bb:cc:dd:ee:ff")
		XCTAssertEqual (code.machineID, Compat.racId_md5 ("aa:bb:cc:dd:ee:ff"))
	}


	func testEmptyCodeIsInvalid () {
		let code = UMLicenseValidationCode (appId: "app", serialNumber: "sn", machineID: "mach")

		XCTAssertFalse (code.isValid)
	}
}


// MARK: - Identificativo macchina

final class MachineIdTests: XCTestCase {

	/// ⚠️ Il `machId` decide se un utente già attivato viene riconosciuto. Questo test
	/// verifica solo che ne esca uno stabile e ben formato: confronta il valore
	/// stampato con quello di `netU_getMacAddress()` sulla stessa macchina prima di
	/// spedire il package in produzione.
	func testMacAddressIsStableAndWellFormed () {
		let mac = Compat.netU_getMacAddress ()
		print ("netU_getMacAddress() -> \(mac)")

		XCTAssertFalse (mac.isEmpty, "nessun MAC address: ogni attivazione userebbe machId vuoto")
		XCTAssertEqual (mac.split (separator: ":").count, 6, "formato inatteso: \(mac)")
		XCTAssertEqual (mac, Compat.netU_getMacAddress (), "il MAC deve essere stabile fra due letture")
	}
}


// MARK: - Scansione dei seriali

final class ScannerTests: XCTestCase {

	func testFindsSerialsInFreeText () {
		let sn = LicenseValidator.generateSN (appShortId: "PC20", type: .full, progressiveN: 3)
		let text = "Ciao Alex,\nil tuo numero di serie è \(sn)\nGrazie!"

		XCTAssertEqual (SerialScanner.serials (in: text), [sn])
	}


	func testDeduplicates () {
		let sn = LicenseValidator.generateSN (appShortId: "PC20", type: .full, progressiveN: 3)

		XCTAssertEqual (SerialScanner.serials (in: "\(sn) \(sn)").count, 1)
	}


	func testNoFalsePositives () {
		XCTAssertTrue (SerialScanner.serials (in: "2026-07-27 10:15:22 nessun seriale qui").isEmpty)
	}
}


// MARK: - Email

final class EmailTests: XCTestCase {

	func testValidAddresses () {
		for email in ["a@b.co", "alex.raccuglia+test@ulti.media", "x_1@sub.domain.org"] {
			XCTAssertTrue (EmailValidator.isValid (email), "\(email) rifiutato")
		}
	}


	func testInvalidAddresses () {
		for email in ["", "alex", "alex@", "@ulti.media", "alex@ulti", "alex @ulti.media"] {
			XCTAssertFalse (EmailValidator.isValid (email), "\(email) accettato")
		}
	}


	private func makeFields (logoImageUrl: String = "https://ulti.media/logo.png",
							 logoImageAlt: String = "") -> TrialMailer.Fields {
		TrialMailer.Fields (username: "Alex",
							appId: "com.ulti.test",
							appName: "BeatMark X",
							serialId: "PC20T-00000001-1234567",
							expDate: Date (),
							downloadAppUrl: "https://ulti.media/download",
							logoImageUrl: logoImageUrl,
							logoImageAlt: logoImageAlt,
							backgroundRGB: "15, 23, 42",
							accentRGB: "56, 189, 248")
	}


	func testTemplatePlaceholdersAreReplaced () {
		let template = """
			Ciao %%License.username%%, ecco il seriale per %%License.appName%%:
			%%License.serialId%% (scade il %%License.expDate%%)
			Download: %%License.downloadAppUrl%%
			"""

		let body = TrialMailer.body (template: template, fields: makeFields ())

		XCTAssertFalse (body.contains ("%%"))
		XCTAssertTrue (body.contains ("Alex"))
		XCTAssertTrue (body.contains ("BeatMark X"))
		XCTAssertTrue (body.contains ("PC20T-00000001-1234567"))
		XCTAssertTrue (body.contains ("https://ulti.media/download"))
	}


	/// Il template incluso nel package dev'essere caricabile e non vuoto: se la
	/// dichiarazione della risorsa in Package.swift salta, l'email parte vuota.
	func testDefaultTemplateIsBundled () {
		let template = TrialMailer.defaultTemplate ()

		XCTAssertFalse (template.isEmpty, "MailTemplate.txt non trovato in Bundle.module")
		XCTAssertTrue (template.contains ("%%License.serialId%%"))
	}


	/// Il test che conta: sul template vero non deve restare NESSUN `%%…%%`.
	/// Se aggiungi un placeholder al template e ti dimentichi di gestirlo qui,
	/// questo test fallisce prima che l'email parta rotta.
	func testRealTemplateHasNoLeftoverPlaceholders () {
		let body = TrialMailer.body (template: TrialMailer.defaultTemplate (),
									 fields: makeFields ())

		XCTAssertFalse (body.contains ("%%"), "placeholder non sostituiti: \(leftovers (in: body))")
	}


	func testRealTemplateContainsAllValues () {
		let body = TrialMailer.body (template: TrialMailer.defaultTemplate (),
									 fields: makeFields ())

		XCTAssertTrue (body.contains ("Alex"))
		XCTAssertTrue (body.contains ("BeatMark X"))
		XCTAssertTrue (body.contains ("PC20T-00000001-1234567"))
		XCTAssertTrue (body.contains ("https://ulti.media/download"))
		XCTAssertTrue (body.contains ("https://ulti.media/logo.png"))
		XCTAssertTrue (body.contains ("rgb(15, 23, 42)"))
		XCTAssertTrue (body.contains ("rgb(56, 189, 248)"))
		XCTAssertTrue (body.contains ("rgba(56, 189, 248, 0.7)"))
	}


	/// Senza logo il blocco `<img>` sparisce, invece di lasciare un `src=""` che i
	/// client email disegnano come icona rotta.
	func testEmptyLogoRemovesTheImageBlock () {
		let body = TrialMailer.body (template: TrialMailer.defaultTemplate (),
									 fields: makeFields (logoImageUrl: ""))

		XCTAssertFalse (body.contains ("%%"))
		XCTAssertFalse (body.contains ("src=\"\""))
		XCTAssertFalse (body.contains ("LogoImageAlt"))
		// Il logo Ulti.Media nel footer non c'entra e deve restare.
		XCTAssertTrue (body.contains ("ultimedia_logo.anim.gif"))
	}


	func testLogoAltFallsBackToAppName () {
		let body = TrialMailer.body (template: TrialMailer.defaultTemplate (),
									 fields: makeFields (logoImageAlt: ""))

		XCTAssertTrue (body.contains ("alt=\"BeatMark X\""))
	}


	func testLogoAltIsUsedWhenGiven () {
		let body = TrialMailer.body (template: TrialMailer.defaultTemplate (),
									 fields: makeFields (logoImageAlt: "BeatMark logo"))

		XCTAssertTrue (body.contains ("alt=\"BeatMark logo\""))
	}


	func testCurrentYear () {
		let date = Compat.du_createDate (d: 27, m: 7, y: 2026)

		XCTAssertEqual (TrialMailer.currentYear (date: date), "2026")
	}


	func testCurrentBuildCombinesVersionAndBuild () {
		// Bundle.main durante i test è il runner, quindi verifico solo che produca
		// qualcosa di sensato invece di una stringa vuota nell'email.
		let build = TrialMailer.currentBuild ()

		XCTAssertFalse (build.isEmpty)
		XCTAssertFalse (build.contains ("%%"))
	}


	@MainActor
	func testRGBComponents () {
		XCTAssertEqual (TrialMailer.rgbComponents (.umLicensingMailBackground), "15, 23, 42")
		XCTAssertEqual (TrialMailer.rgbComponents (.umLicensingMailAccent), "56, 189, 248")
		XCTAssertEqual (TrialMailer.rgbComponents (NSColor (srgbRed: 1, green: 0, blue: 0, alpha: 1)), "255, 0, 0")
	}


	/// Un colore preso dagli Assets può essere in un color space diverso o dinamico:
	/// senza `usingColorSpace(.sRGB)` leggere `redComponent` va in crash.
	@MainActor
	func testRGBComponentsHandlesNonSRGBColors () {
		XCTAssertEqual (TrialMailer.rgbComponents (.white), "255, 255, 255")
		XCTAssertEqual (TrialMailer.rgbComponents (.black), "0, 0, 0")
		XCTAssertFalse (TrialMailer.rgbComponents (.controlAccentColor).isEmpty)
	}


	/// Scrive l'email renderizzata su file, per guardarla in un browser.
	/// Non è una verifica: `UMLICENSING_PREVIEW=/percorso/mail.html swift test`.
	func testWritePreviewUtility () throws {
		let path = ProcessInfo.processInfo.environment ["UMLICENSING_PREVIEW"] ?? ""
		try XCTSkipIf (path.isEmpty, "utility: eseguire con UMLICENSING_PREVIEW=/percorso/mail.html")

		let body = TrialMailer.body (template: TrialMailer.defaultTemplate (),
									 fields: makeFields ())
		try body.write (toFile: path, atomically: true, encoding: .utf8)
		print ("preview scritta in \(path)")
	}


	private func leftovers (in body: String) -> [String] {
		guard let regex = try? NSRegularExpression (pattern: "%%[^%]+%%") else { return [] }
		let range = NSRange (body.startIndex ..< body.endIndex, in: body)
		return regex.matches (in: body, range: range).compactMap {
			Range ($0.range, in: body).map { String (body [$0]) }
		}
	}


	func testMailerEndpointAndSender () {
		XCTAssertEqual (TrialMailer.endpoint.value, "https://ultimediacloud.net/mailer/mailer.php")
		XCTAssertEqual (TrialMailer.sender.value, "license@ulti.media")
	}


	/// Il motivo per cui non uso `.urlQueryAllowed` come faceva `SendEmail`: un body
	/// HTML contiene quasi sempre `&` (negli URL con query, o come `&amp;`), e lasciarlo
	/// passare non codificato spezza il modulo POST facendo arrivare l'email troncata.
	func testFormEncodingProtectsHTMLBodies () {
		let html = "<a href=\"https://ulti.media/dl?app=beatmark&v=2\">Download</a> R&D"
		let encoded = TrialMailer.formEncode (html)

		XCTAssertFalse (encoded.contains ("&"))
		XCTAssertFalse (encoded.contains ("="))
		XCTAssertFalse (encoded.contains (" "))
		XCTAssertEqual (encoded.removingPercentEncoding, html)
	}


	func testFormEncodingHandlesAccents () {
		let s = "Cordiali saluti, à è ì ò ù"

		XCTAssertEqual (TrialMailer.formEncode (s).removingPercentEncoding, s)
	}
}


// MARK: - Identificativo macchina

final class MachIdTests: XCTestCase {

	/// Lo stesso MAC scritto in modi diversi resta la stessa macchina. È il confronto
	/// da cui dipende "Serial number already activated".
	func testSameMacInDifferentFormatsMatches () {
		XCTAssertTrue (Compat.machIdMatches ("aa:bb:cc:dd:ee:ff", "AA:BB:CC:DD:EE:FF"))
		XCTAssertTrue (Compat.machIdMatches ("aa:bb:cc:dd:ee:ff", "aabbccddeeff"))
		XCTAssertTrue (Compat.machIdMatches ("aa-bb-cc-dd-ee-ff", "aa:bb:cc:dd:ee:ff"))
	}


	func testDifferentMacsDoNotMatch () {
		XCTAssertFalse (Compat.machIdMatches ("aa:bb:cc:dd:ee:ff", "aa:bb:cc:dd:ee:00"))
	}


	/// Un `machId` vuoto è "sconosciuto", non "uguale": è il valore che le macchine
	/// registrate con UMOmniaFramework hanno nei preferences, e non deve autorizzare
	/// niente da solo.
	func testEmptyMachIdNeverMatches () {
		XCTAssertFalse (Compat.machIdMatches ("", ""))
		XCTAssertFalse (Compat.machIdMatches ("", "aa:bb:cc:dd:ee:ff"))
		XCTAssertFalse (Compat.machIdMatches ("aa:bb:cc:dd:ee:ff", ""))
	}
}
