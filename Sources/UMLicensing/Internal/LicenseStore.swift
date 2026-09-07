//
//  LicenseStore.swift
//  UMLicensing
//
//  Persistenza locale della licenza. Le chiavi sono IDENTICHE a quelle del vecchio
//  `License` — doppio punto incluso — perché sulle macchine degli utenti già
//  registrati la licenza è salvata lì: cambiarle equivale a de-registrare tutti.
//

import Foundation


/// `@unchecked` per via di `UserDefaults`, che non è dichiarato `Sendable` ma è
/// documentato come thread-safe. Lo store non ha altro stato mutabile.
struct LicenseStore: @unchecked Sendable {

	/// `true` per il nuovo schema di chiavi con l'appId nell'infisso.
	/// Il vecchio `License.newSystem` era `false` di default, quindi l'infisso è vuoto
	/// e le chiavi reali sono `license..appId`, `license..serialId`, ...
	let newSystem: Bool
	let appId: String

	private let defaults: UserDefaults

	init (appId: String, newSystem: Bool = false, defaults: UserDefaults = .standard) {
		self.appId     = appId
		self.newSystem = newSystem
		self.defaults  = defaults
	}


	/// Riproduce `License.licenseInfix()`.
	private var infix: String {
		newSystem ? ".\(appId)" : ""
	}


	private func key (_ field: String) -> String {
		"license.\(infix).\(field)"
	}


	// MARK: - Lettura

	/// Carica la licenza e ne verifica il validator locale.
	///
	/// Replica `License.loadLicense()`: se il validator non torna, il seriale viene
	/// azzerato e viene riportato l'errore, così una licenza manomessa a mano nei
	/// preferences non passa.
	func load () -> LicenseData {
		var data = LicenseData ()
		data.appId    = defaults.string (forKey: key ("appId")) ?? ""
		data.serialId = defaults.string (forKey: key ("serialId")) ?? ""

		guard !data.appId.isEmpty, !data.serialId.isEmpty else {
			data.errorMessage = Strings.notRegistered.value
			return data
		}

		data.machId   = defaults.string (forKey: key ("machId")) ?? ""
		data.password = defaults.string (forKey: key ("password")) ?? ""
		data.username = defaults.string (forKey: key ("username")) ?? ""
		data.email    = defaults.string (forKey: key ("email")) ?? ""
		data.regDate  = date (forKey: key ("regDate")) ?? Date ()
		data.expDate  = date (forKey: key ("expDate")) ?? Date ()
		data.licType  = defaults.string (forKey: key ("licType")) ?? ""

		let stored = defaults.string (forKey: key ("validator")) ?? ""
		if stored != LicenseValidator.validator (for: data) {
			// Le prime versioni di questo package firmavano le date in `yyyy-MM-dd`
			// invece del `dd/MM/yyyy` originale: chi ha girato una di quelle build ha
			// nei preferences una firma che non torna più. Se è quella, la licenza è
			// autentica: la accettiamo e riscriviamo subito la firma giusta, così il
			// giro successivo passa dal percorso normale.
			guard stored == LicenseValidator.isoValidator (for: data) else {
				data.errorMessage = Strings.invalidLicense.value
				data.serialId = ""
				return data
			}
			save (data)
		}
		return data
	}


	// MARK: - Scrittura

	/// Replica `License.saveLicense()`. Con `invalidate` scrive un validator che non
	/// corrisponde ai dati, rendendo la licenza illeggibile senza cancellarla.
	func save (_ data: LicenseData, invalidate: Bool = false) {
		defaults.set (data.appId,    forKey: key ("appId"))
		defaults.set (data.serialId, forKey: key ("serialId"))
		defaults.set (data.machId,   forKey: key ("machId"))
		defaults.set (data.password, forKey: key ("password"))
		defaults.set (data.username, forKey: key ("username"))
		defaults.set (data.email,    forKey: key ("email"))
		setDate (data.regDate, forKey: key ("regDate"))
		setDate (data.expDate, forKey: key ("expDate"))
		defaults.set (data.licType,  forKey: key ("licType"))

		let validatorText = invalidate ? "" : LicenseValidator.validatorText (for: data)
		defaults.set (LicenseValidator.hash (validatorText), forKey: key ("validator"))
	}


	/// Rimuove ogni traccia della licenza.
	///
	/// ⚠️ Il vecchio `clearLicense()` costruiva le chiavi con `"license\(infix).appId"`
	/// — senza il punto dopo `license` — quindi cancellava chiavi che non esistevano e
	/// la licenza in realtà restava nei preferences. Qui uso le chiavi giuste, così
	/// la rimozione funziona davvero. Se dipendevi da quel comportamento, dimmelo.
	func clear () {
		for field in ["appId", "serialId", "machId", "machId2", "password",
					  "username", "email", "regDate", "expDate", "licType", "validator"] {
			defaults.removeObject (forKey: key (field))
		}
	}


	// MARK: - Date

	/// `prefs_setValueDate` / `prefs_getValueDate` fanno `UserDefaults.set(value:)` e
	/// `object(forKey:) as! Date`: un `Date` nativo. La lettura da stringa resta solo
	/// come rete di sicurezza per preferences scritti a mano.
	private func date (forKey k: String) -> Date? {
		if let d = defaults.object (forKey: k) as? Date { return d }
		if let s = defaults.string (forKey: k) { return Compat.du_createDateFormStandardString (s) }
		return nil
	}


	private func setDate (_ date: Date, forKey k: String) {
		defaults.set (date, forKey: k)
	}


	// MARK: - Grace period

	/// Ultima volta che il server ha confermato la licenza. Serve al grace period offline.
	var lastServerCheck: Date? {
		get { defaults.object (forKey: key ("lastServerCheck")) as? Date }
		nonmutating set { defaults.set (newValue, forKey: key ("lastServerCheck")) }
	}
}
