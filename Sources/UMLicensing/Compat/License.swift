//
//  License.swift
//  UMLicensing
//
//  Facciata di compatibilità: espone la stessa superficie statica del vecchio
//  `License` di UMOmniaFramework, così il codice già scritto nelle app
//  (`License.getSerialId()`, `License.getType()`, `License.isRegistered()`, ...)
//  continua a compilare senza modifiche.
//
//  Il motore vero è `UMLicensing`. Qui non c'è logica, solo inoltro.
//

import Foundation


@MainActor
public enum License {

	// MARK: - Stato

	public private(set) static var appId:                  String = ""
	public private(set) static var appName:                String = ""
	public private(set) static var appShortId:             String = ""
	public private(set) static var acceptedApps:           [String] = []
	public private(set) static var previousVersionPrefix:  String = ""
	public private(set) static var purchaseLicenseURL:     String = ""
	public private(set) static var downloadAppUrl:         String = ""
	public private(set) static var trialExpDays:           Int = 7

	/// `true` dopo un `UMLicensing.licensed()` andato a buon fine.
	public internal(set) static var licenseValidated = false

	/// Nome ed email inseriti per il trial, se l'utente li ha forniti.
	public static var username: String { UserDefaults.standard.string (forKey: "License.temp.username") ?? "" }
	public static var email:    String { UserDefaults.standard.string (forKey: "License.temp.email") ?? "" }


	static func configure (_ c: UMLicensing.Context) {
		appId                 = c.appId
		appName               = c.appName
		appShortId            = c.appShortId
		acceptedApps          = c.acceptedApps
		previousVersionPrefix = c.previousVersionPrefix
		purchaseLicenseURL    = c.purchaseUrl
		downloadAppUrl        = c.downloadAppUrl
		trialExpDays          = c.trialExpDays
	}


	// MARK: - Lettura della licenza

	public static func loadLicense () -> LicenseData {
		LicenseStore (appId: appId).load ()
	}

	public static func getSerialId () -> String   { loadLicense ().serialId }
	public static func getMachineId () -> String  { loadLicense ().machId }
	public static func getAppId () -> String      { loadLicense ().appId }
	public static func isRegistered () -> Bool    { loadLicense ().isRegistered }
	public static func isExpired () -> Bool       { loadLicense ().isExpired }
	public static func getExpirationDate () -> Date { loadLicense ().expDate }
	public static func getType () -> licenseType  { loadLicense ().type }
	public static func getCurrentLicenseType () -> licenseType { getType () }


	// MARK: - Seriali

	public static func getLicenseType (_ s: String) -> licenseType {
		licenseType (serialId: s)
	}

	public static func getLicenseTypeChar (_ l: licenseType) -> String { l.char }

	public static func getLicenseTypeString (_ l: licenseType) -> String { l.name }

	public static func serialToApp (_ s: String) -> String {
		LicenseValidator.serialToApp (s)
	}

	public static func validateSerial (_ s: String) -> Bool {
		LicenseValidator.validateSerial (s,
										 acceptedApps: acceptedApps,
										 previousVersionPrefix: previousVersionPrefix)
	}

	public static func generateSN (appId: String, type: licenseType, progressiveN: Int) -> String {
		LicenseValidator.generateSN (appShortId: appId, type: type, progressiveN: progressiveN)
	}

	public static func getValidator (text: String) -> String {
		LicenseValidator.hash (text)
	}

	public static func getSerialPrefixValidator (_ prefix: String) -> String {
		LicenseValidator.serialPrefixValidator (prefix)
	}

	public static func getUnlockCode () -> String {
		LicenseValidator.unlockCode (for: loadLicense ())
	}


	// MARK: - Rilascio

	/// Stacca la licenza da questa macchina, con il codice fornito dal supporto.
	public static func releaseLicense (appId: String,
									   serialId: String,
									   unlockCode: String) async -> Bool {
		await LicenseServer ().releaseLicense (appId: appId,
											   serialId: serialId,
											   unlockCode: unlockCode)
	}

	/// Rilascio rapido, senza codice.
	@discardableResult
	public static func fastReleaseLicense (serialId: String) async -> Bool {
		await LicenseServer ().fastReleaseLicense (serialId: serialId)
	}

	/// Rimuove la licenza da questo Mac dopo conferma dell'utente, rilasciandola
	/// anche sul server così può essere riattivata altrove.
	public static func clearLicense () async {
		guard Alert.twoButtons ("Warning!",
								"Remove your license from this computer?",
								first: "Remove",
								second: "Cancel") else { return }

		let serialId = loadLicense ().serialId
		LicenseStore (appId: appId).clear ()
		UMLicenseValidationCode.clear ()
		licenseValidated = false

		if !serialId.isEmpty {
			await fastReleaseLicense (serialId: serialId)
		}
	}
}
