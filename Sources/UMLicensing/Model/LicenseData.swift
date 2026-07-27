//
//  LicenseData.swift
//  UMLicensing
//

import Foundation


/// La licenza, così com'è salvata in locale e scambiata col server.
public struct LicenseData: Codable, Sendable, Equatable {

	public var appId:         String = ""
	public var serialId:      String = ""
	public var machId:        String = ""
	public var username:      String = ""
	public var password:      String = ""
	public var email:         String = ""
	public var regDate:       Date   = Date ()
	public var expDate:       Date   = LicenseData.defaultExpDate ()
	public var licType:       String = ""
	public var errorMessage:  String = ""


	/// Scadenza di default: la stessa del vecchio `LicenseData`, 7 giorni da adesso.
	public static func defaultExpDate () -> Date {
		Compat.du_getDatePlusDays (date: Date (), days: 7)
	}


	public init () {}


	public init (appId:         String = "",
				 serialId:      String = "",
				 machId:        String = "",
				 username:      String = "",
				 password:      String = "",
				 email:         String = "",
				 regDate:       Date   = Date (),
				 expDate:       Date   = LicenseData.defaultExpDate (),
				 licType:       String = "",
				 errorMessage:  String = "") {

		self.appId        = appId
		self.serialId     = serialId
		self.machId       = machId
		self.username     = username
		self.password     = password
		self.email        = email
		self.regDate      = regDate
		self.expDate      = expDate
		self.licType      = licType
		self.errorMessage = errorMessage
	}


	/// Tipo di licenza dedotto dal seriale.
	public var type: licenseType {
		licenseType (serialId: serialId)
	}


	/// La licenza è presente e non ha errori di validazione locale.
	public var isRegistered: Bool {
		(errorMessage == "") && (serialId != "")
	}


	/// La data di scadenza è passata. Le licenze perpetue non scadono mai.
	public var isExpired: Bool {
		guard !type.isPerpetual else { return false }
		return Compat.du_getDeltaDate (firstDate: Date (), secondDate: expDate) <= 0
	}


	/// Numero progressivo estratto dal seriale (la parte fra il primo e il secondo `-`).
	public var serialCounter: Int? {
		let p = Compat.strUt_position (srcText: serialId, subString: "-", startAt: 0, recurrence: 1)
		guard p > 0 else { return nil }
		let prefix = Compat.strUt_getLeft (serialId, n: p)
		let n2 = Compat.strUt_position (srcText: serialId, subString: "-", startAt: 0, recurrence: 0) + 1
		return Int (Compat.strUt_stripLeft (prefix, n: n2))
	}
}
