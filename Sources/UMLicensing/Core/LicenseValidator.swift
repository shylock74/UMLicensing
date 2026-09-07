//
//  LicenseValidator.swift
//  UMLicensing
//
//  Generazione e verifica dei seriali. Formato:
//
//      AB12F-00000001-1234567
//      └─┬─┘│ └──┬───┘ └──┬──┘
//        │  │    │        └─ validator: 7 cifre estratte da md5(prefix + segreto)
//        │  │    └────────── progressivo, 8 cifre con zeri davanti
//        │  └─────────────── tipo licenza (F/T/S/G/B/U)
//        └────────────────── appShortId, 4 caratteri
//
//  Tutto qui dentro deve restare bit-compatibile col vecchio `License`: questi
//  numeri sono già stampati sulle ricevute dei clienti.
//

import Foundation


enum LicenseValidator {

	/// `License.getValidator(text:)` — l'hash usato per firmare ogni scambio col server
	/// e la copia locale della licenza.
	static func hash (_ text: String) -> String {
		Compat.racId_md5 (text + Strings.validatorSuffix.value)
	}


	/// I primi 4 caratteri del seriale, cioè l'app a cui appartiene.
	static func serialToApp (_ s: String) -> String {
		Compat.strUt_getLeft (s, n: 4)
	}


	/// Le 7 cifre di controllo che chiudono il seriale.
	static func serialPrefixValidator (_ prefix: String) -> String {
		Compat.racId_getNumbersToLength (s: hash (prefix), l: 7)
	}


	/// Costruisce un seriale valido.
	static func generateSN (appShortId: String, type: licenseType, progressiveN: Int) -> String {
		let prefix = appShortId + type.char + "-" + Compat.strUt_padN (n: progressiveN, padN: 8)
		return prefix + "-" + serialPrefixValidator (prefix)
	}


	/// Verifica che il seriale appartenga a una delle app accettate e che le cifre di
	/// controllo tornino. È una verifica puramente locale: non dice se il seriale
	/// esiste sul server o se è già stato attivato altrove.
	static func validateSerial (_ s: String,
								acceptedApps: [String],
								previousVersionPrefix: String) -> Bool {

		let appStr = serialToApp (s)

		var accepted = acceptedApps.contains (appStr)
		if !previousVersionPrefix.isEmpty,
		   appStr == Compat.strUt_getLeft (previousVersionPrefix, n: 4) {
			accepted = true
		}
		guard accepted else { return false }

		let l = Compat.strUt_length (s)
		let p = Compat.strUt_position (srcText: s, subString: "-", startAt: 0, recurrence: 1)
		guard p > 0, l - p - 1 > 0 else { return false }

		let prefix    = Compat.strUt_getLeft (s, n: p)
		let validator = Compat.strUt_getRight (s, n: l - p - 1)
		return serialPrefixValidator (prefix) == validator
	}


	// MARK: - Validator della copia locale

	/// Il testo firmato per rilevare manomissioni della licenza nei preferences.
	/// L'ordine dei campi e la doppia presenza di `serialId` sono quelli originali:
	/// cambiarli invaliderebbe le licenze già salvate.
	static func validatorText (for d: LicenseData) -> String {
		d.appId + d.serialId + d.machId + d.username + d.password + d.serialId
			+ Compat.du_getDateString (d.regDate)
			+ Compat.du_getDateString (d.expDate)
			+ d.licType
	}


	static func validator (for d: LicenseData) -> String {
		hash (validatorText (for: d))
	}


	/// La firma che producevano le prime versioni di questo package, quando
	/// `du_getDateString` restituiva `yyyy-MM-dd` invece del `dd/MM/yyyy` originale.
	///
	/// Serve solo a `LicenseStore.load()` per riconoscere — e riscrivere — le licenze
	/// salvate da quelle build, invece di dichiararle manomesse.
	static func isoValidator (for d: LicenseData) -> String {
		hash (d.appId + d.serialId + d.machId + d.username + d.password + d.serialId
			  + Compat.du_getDateStringISO (d.regDate)
			  + Compat.du_getDateStringISO (d.expDate)
			  + d.licType)
	}


	// MARK: - Unlock

	/// Codice che l'utente detta al supporto per sbloccare un seriale rimasto legato
	/// a una macchina che non ha più.
	///
	/// Niente md5: l'originale estrae le cifre direttamente dalla concatenazione. Il
	/// tool del supporto (SNGenerator) calcola così, quindi passare dall'hash
	/// produrrebbe codici che non combaciano con quelli dettati al cliente.
	static func unlockCode (for d: LicenseData) -> String {
		let s = d.appId + d.serialId + d.machId + Strings.unlockSuffix.value
		return Compat.racId_getNumbersToLength (s: s, l: 10)
	}


	/// Codice di rilascio rapido: md5 triplo del seriale.
	static func fastUnlockCode (serialId: String) -> String {
		Compat.racId_md5 (Compat.racId_md5 (Compat.racId_md5 (serialId)))
	}
}
