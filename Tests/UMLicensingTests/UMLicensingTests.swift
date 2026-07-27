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


	func testGetNumbersToLengthAlwaysReturnsRequestedLength () {
		XCTAssertEqual (Compat.racId_getNumbersToLength (s: "a1b2c3d4e5f6", l: 4), "1234")
		XCTAssertEqual (Compat.racId_getNumbersToLength (s: "abcdef", l: 4).count, 4)
		XCTAssertEqual (Compat.racId_getNumbersToLength (s: Compat.racId_md5 ("PC20F-00000001"), l: 7).count, 7)
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
	}


	func testDeltaDateIsSigned () {
		let today = Date ()

		XCTAssertEqual (Compat.du_getDeltaDate (firstDate: today,
												secondDate: Compat.du_getDatePlusDays (date: today, days: 5)), 5)
		XCTAssertEqual (Compat.du_getDeltaDate (firstDate: today,
												secondDate: Compat.du_getDatePlusDays (date: today, days: -3)), -3)
	}


	func testDateStringRoundTrip () {
		let date = Compat.du_createDate (d: 27, m: 7, y: 2026)
		let s = Compat.du_getDateString (date)

		XCTAssertTrue (s.hasPrefix ("2026-07-27"), "formato inatteso: \(s)")
		XCTAssertEqual (Compat.du_createDateFormStandardString (s), date)
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


	func testTemplatePlaceholdersAreReplaced () {
		let template = """
			Ciao %%License.username%%, ecco il seriale per %%License.appName%%:
			%%License.serialId%% (scade il %%License.expDate%%)
			Download: %%License.downloadAppUrl%%
			"""

		let body = TrialMailer.body (template: template,
									 username: "Alex",
									 appId: "com.ulti.test",
									 appName: "BeatMark X",
									 serialId: "PC20T-00000001-1234567",
									 expDate: Date (),
									 downloadAppUrl: "https://ulti.media/download")

		XCTAssertFalse (body.contains ("%%"))
		XCTAssertTrue (body.contains ("Alex"))
		XCTAssertTrue (body.contains ("BeatMark X"))
		XCTAssertTrue (body.contains ("PC20T-00000001-1234567"))
		XCTAssertTrue (body.contains ("https://ulti.media/download"))
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
