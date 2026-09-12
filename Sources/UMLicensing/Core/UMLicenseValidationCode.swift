//
//  UMLicenseValidationCode.swift
//  UMLicensing
//
//  Prova locale che questa licenza è già stata validata su questa macchina.
//  È ciò che permette di avviare l'app senza rete: se il codice torna, la licenza
//  è stata confermata dal server in passato e non è stata copiata altrove
//  (il machId entra nell'hash).
//

import Foundation


public struct UMLicenseValidationCode: Codable, Sendable, Equatable {

	static let defaultsKey = "UMLVC"

	public var appId:           String
	public var serialNumber:    String
	public var machineID:       String
	public var validationCode:  String


	public init (appId: String, serialNumber: String, machineID: String) {
		self.appId          = appId
		self.serialNumber   = serialNumber
		self.machineID      = Compat.racId_md5 (machineID)   // il machId non viene mai salvato in chiaro
		self.validationCode = ""
	}


	/// Il codice atteso per questa terna app/seriale/macchina.
	public func expectedCode () -> String {
		Compat.racId_md5 (appId + "/" + serialNumber + "//" + machineID + "///" + Strings.validationCodeSuffix.value)
	}


	public var isValid: Bool {
		!validationCode.isEmpty && expectedCode () == validationCode
	}


	// MARK: - Persistenza

	public func save (defaults: UserDefaults = .standard) {
		var copy = self
		copy.validationCode = expectedCode ()

		Diagnostics.trace ("validationCode.save: \(copy.validationCode) "
						   + "(serial \(serialNumber), machId \(machineID))")

		guard let json = try? JSONEncoder ().encode (copy) else {
			Diagnostics.trace ("validationCode.save: codifica JSON fallita, non salvo niente")
			return
		}
		defaults.set (String (decoding: json, as: UTF8.self), forKey: UMLicenseValidationCode.defaultsKey)
	}


	public static func load (defaults: UserDefaults = .standard) -> UMLicenseValidationCode? {
		guard let s = defaults.string (forKey: defaultsKey), !s.isEmpty else {
			Diagnostics.trace ("validationCode.load: assente")
			return nil
		}

		let decoded = try? JSONDecoder ().decode (UMLicenseValidationCode.self, from: Data (s.utf8))
		Diagnostics.trace ("validationCode.load: \(decoded?.validationCode ?? "illeggibile")")
		return decoded
	}


	static func clear (defaults: UserDefaults = .standard) {
		Diagnostics.trace ("validationCode.clear: rimosso")
		defaults.removeObject (forKey: defaultsKey)
	}
}
