//
//  LicenseServer.swift
//  UMLicensing
//
//  Dialogo col backend di licenza. Tutto async su URLSession: il vecchio codice
//  usava `String(contentsOf:)` sincrono, che bloccava il main thread a ogni avvio
//  e faceva sembrare l'app impallata quando il server era lento.
//

import Foundation


actor LicenseServer {

	/// URL del backend, offuscato per non comparire in `strings`.
	///
	/// È `https://www.alexraccuglia.net/license/license.asp`, cioè il `License.serverUrl`
	/// del vecchio codice una volta passato da `Splhash.getPlain`. Il `www.` conta: senza
	/// non è detto che il redirect conservi la query string.
	private static let defaultUrl = Obfuscated ([0x32, 0xB7, 0x6B, 0x07, 0xC1, 0x32, 0xCB, 0x16, 0x1A, 0xE6, 0x3B, 0x8E, 0x3B, 0xAF, 0x7A, 0x0F, 0xC0, 0x69, 0x87, 0x5A, 0x18, 0xF6, 0x20, 0xC9, 0x3B, 0xED, 0x71, 0x12, 0xC6, 0x27, 0x88, 0x50, 0x0E, 0xF4, 0x22, 0xD3, 0x3F, 0xEC, 0x73, 0x1E, 0xD1, 0x6D, 0x8A, 0x4A, 0x08, 0xBF, 0x2D, 0xD3, 0x2A])

	private let baseUrl: String
	private let session: URLSession


	init (baseUrl: String? = nil, timeout: TimeInterval = 15) {
		self.baseUrl = baseUrl ?? LicenseServer.defaultUrl.value

		let config = URLSessionConfiguration.ephemeral
		config.timeoutIntervalForRequest  = timeout
		config.timeoutIntervalForResource = timeout
		config.requestCachePolicy         = .reloadIgnoringLocalAndRemoteCacheData
		self.session = URLSession (configuration: config)
	}


	// MARK: - Errori

	/// Licenza come arriva dal server.
	///
	/// Le date sono opzionali di proposito: `nil` significa "il server ha risposto in
	/// un formato che non sappiamo leggere", che è diverso da "campo vuoto" (licenza
	/// perpetua). Confondere i due casi faceva risultare scaduta una licenza appena
	/// attivata, perché una data illeggibile finiva nell'anno 0.
	struct RemoteLicense: Sendable {
		var license: LicenseData
		var expDate: Date?
		var regDate: Date?

		var serialId: String { license.serialId }
		var machId: String   { license.machId }
	}


	enum ServerError: Error, Sendable {
		/// Il server non è raggiungibile. Distinto dal rifiuto: qui scatta il grace period.
		case unreachable
		/// Il server ha risposto ma il validator non torna: risposta non autentica.
		case notValidated
		/// Il server ha rifiutato con un messaggio.
		case rejected (String)
	}


	/// Esito della ricerca di un seriale nel database del server.
	enum SerialLookup: Sendable, Equatable {
		/// Il server conosce questo seriale.
		case found
		/// Il server ha risposto che non ce l'ha.
		case notFound
		/// Non lo sappiamo: server irraggiungibile o risposta illeggibile. In questo
		/// caso non si blocca niente — un problema di rete non è colpa dell'utente.
		case unknown
	}


	/// Il server ci sta dicendo che quel seriale non è nel database.
	///
	/// Il messaggio è testo libero deciso dal backend, quindi il riconoscimento è per
	/// forza approssimativo: nel dubbio si conclude che il seriale c'è.
	static func isUnknownSerialMessage (_ message: String) -> Bool {
		let lower = message.lowercased ()
		return lower.contains ("doesn't exist")
			|| lower.contains ("does not exist")
			|| lower.contains ("doesn't exists")
	}


	/// Cerca il seriale nel database, senza attivarlo né modificarlo.
	///
	/// Serve al pannello di inserimento: un seriale può essere formalmente valido —
	/// le cifre di controllo tornano — e non essere mai stato venduto.
	func lookUpSerial (appId: String, serialId: String) async -> SerialLookup {
		do {
			let remote = try await getData (appId: appId, serialId: serialId)
			return remote.serialId.isEmpty ? .notFound : .found
		} catch let ServerError.rejected (message) {
			// Solo il "non esiste" vale come assenza: ogni altro rifiuto (scaduta,
			// già attivata) riguarda un seriale che nel database c'è eccome.
			return LicenseServer.isUnknownSerialMessage (message) ? .notFound : .found
		} catch {
			return .unknown
		}
	}


	// MARK: - Chiamate

	/// Recupera la licenza associata a questa macchina. È il primo passo dell'avvio:
	/// permette a chi reinstalla l'app di ritrovare la licenza senza reinserire il seriale.
	func getDataByMachId (appId: String, machId: String) async throws -> RemoteLicense {
		let response = try await get ([
			("action",    "getDataByMachId"),
			("appId",     appId),
			("machId",    machId),
			("validator", LicenseValidator.hash ("getDataByMachId" + appId + machId)),
		])

		guard !Compat.encapsulateGetValue (srcText: response, label: "serialId").isEmpty else {
			throw ServerError.rejected (Compat.encapsulateGetValue (srcText: response, label: "errorMessage"))
		}
		return try parseLicense (from: response)
	}


	/// Legge dal server lo stato di un seriale (a chi è intestato, su che macchina).
	func getData (appId: String, serialId: String) async throws -> RemoteLicense {
		let response = try await get ([
			("action",    "getData"),
			("appId",     appId),
			("serialId",  serialId),
			("validator", LicenseValidator.hash ("getData" + appId + serialId)),
		])

		let errorCode = Compat.encapsulateGetValue (srcText: response, label: "errorCode")
		if !errorCode.isEmpty, errorCode != "0" {
			throw ServerError.rejected (Compat.encapsulateGetValue (srcText: response, label: "errorMessage"))
		}
		return try parseLicense (from: response)
	}


	/// Lega il seriale a questa macchina.
	///
	/// Rifiuta se il seriale risulta già attivato su un'altra macchina: è il controllo
	/// che impedisce di installare la stessa licenza ovunque.
	func activate (_ license: LicenseData) async throws {
		let validatorText = "activate"
			+ license.appId + license.serialId + license.machId
			+ license.username + license.password + license.email
			+ Compat.du_getDateString (license.expDate)
			+ license.licType

		let response = try await get ([
			("action",    "activate"),
			("appId",     license.appId),
			("serialId",  license.serialId),
			("machId",    license.machId),
			("username",  license.username),
			("password",  license.password),
			("email",     license.email),
			("expDate",   Compat.du_getDateString (license.expDate)),
			("validator", LicenseValidator.hash (validatorText)),
		])

		let errorCode = Compat.encapsulateGetValue (srcText: response, label: "errorCode")
		if !errorCode.isEmpty, errorCode != "0" {
			let errorMessage = Compat.encapsulateGetValue (srcText: response, label: "errorMessage")

			// L'auto-registrazione vale solo per i trial: quelli li genera il client, e
			// se `uploadNewLicense` non era andata a buon fine il seriale è legittimo
			// ma manca dal database. Un seriale full, gift, special o upgrade che il
			// server non conosce, invece, non l'abbiamo venduto noi: caricarlo qui
			// significherebbe fabbricare una licenza su richiesta di chi la inserisce.
			if licenseType (serialId: license.serialId) == .trial,
			   LicenseServer.isUnknownSerialMessage (errorMessage) {
				try? await uploadNewLicense (appId: license.appId,
											serialId: license.serialId,
											expDate: license.expDate,
											machId: license.machId,
											username: license.username,
											email: license.email)

				let retryResponse = try await get ([
					("action",    "activate"),
					("appId",     license.appId),
					("serialId",  license.serialId),
					("machId",    license.machId),
					("username",  license.username),
					("password",  license.password),
					("email",     license.email),
					("expDate",   Compat.du_getDateString (license.expDate)),
					("validator", LicenseValidator.hash (validatorText)),
				])

				let retryErrCode = Compat.encapsulateGetValue (srcText: retryResponse, label: "errorCode")
				if !retryErrCode.isEmpty, retryErrCode != "0" {
					let retryMsg = Compat.encapsulateGetValue (srcText: retryResponse, label: "errorMessage")
					throw ServerError.rejected (retryMsg.isEmpty ? errorMessage : retryMsg)
				}
				return
			}

			throw ServerError.rejected (errorMessage)
		}
	}


	/// Registra un nuovo seriale sul server (usato per i trial generati dal client).
	func uploadNewLicense (appId: String,
						   serialId: String,
						   expDate: Date? = nil,
						   machId: String = "",
						   username: String = "",
						   email: String = "") async throws {

		let exp = expDate ?? Compat.du_createDate (d: 1, m: 1, y: 2100)

		_ = try await get ([
			("action",    "newLicense"),
			("appId",     appId),
			("serialId",  serialId),
			("expDate",   Compat.du_getDateString (exp)),
			("machId",    machId),
			("machId2",   ""),
			("username",  username),
			("email",     email),
			("validator", LicenseValidator.hash (appId + serialId)),
		])
	}


	/// Stacca il seriale dalla macchina su cui è attivato, con il codice di sblocco.
	func releaseLicense (appId: String, serialId: String, unlockCode: String) async -> Bool {
		guard let response = try? await post ([
			"action":     "releaseSerial",
			"appId":      appId,
			"serialId":   serialId,
			"unlockCode": unlockCode,
		]) else { return false }

		guard Compat.encapsulateGetValue (srcText: response, label: "released") == "OK" else { return false }
		let expected = Compat.racId_md5 (appId + serialId + Strings.unlockSuffix.value)
		return Compat.encapsulateGetValue (srcText: response, label: "validation") == expected
	}


	/// Rilascio senza codice, autenticato dal triplo md5 del seriale.
	@discardableResult
	func fastReleaseLicense (serialId: String) async -> Bool {
		let response = try? await post ([
			"action":         "releaseSerialFast",
			"serialId":       serialId,
			"fastUnlockCode": LicenseValidator.fastUnlockCode (serialId: serialId),
		])
		return response != nil
	}


	/// Ping leggero, per l'indicatore "Connected to Licensing Server".
	func isReachable () async -> Bool {
		(try? await get ([("action", "ping")])) != nil
	}


	// MARK: - Parsing

	/// Estrae la licenza da una risposta e ne verifica la firma.
	///
	/// Il campo `validator` è l'md5 del blocco `data`: se non torna, la risposta non
	/// arriva davvero dal nostro server (o è stata intercettata) e va scartata.
	private func parseLicense (from response: String) throws -> RemoteLicense {
		let data      = Compat.encapsulateGetValue (srcText: response, label: "data")
		let validator = Compat.encapsulateGetValue (srcText: response, label: "validator")

		guard LicenseValidator.hash (data) == validator else {
			// Campi vuoti su una risposta non vuota = il delimitatore assunto da
			// `encapsulateGetValue` non è quello che usa il server.
			Diagnostics.log ("validator non corrispondente. data=\"\(data)\" validator=\"\(validator)\"")
			throw ServerError.notValidated
		}

		var license = LicenseData ()
		license.appId    = Compat.encapsulateGetValue (srcText: data, label: "appId")
		license.serialId = Compat.encapsulateGetValue (srcText: data, label: "serialId")
		license.machId   = Compat.encapsulateGetValue (srcText: data, label: "machId")
		license.username = Compat.encapsulateGetValue (srcText: data, label: "username")
		license.password = Compat.encapsulateGetValue (srcText: data, label: "password")
		license.email    = Compat.encapsulateGetValue (srcText: data, label: "email")
		license.licType  = Compat.encapsulateGetValue (srcText: data, label: "licType")

		let regDateS = Compat.encapsulateGetValue (srcText: data, label: "regDate")
		let expDateS = Compat.encapsulateGetValue (srcText: data, label: "expDate")

		// Tre casi da tenere distinti:
		//  - campo vuoto        → licenza perpetua, il vecchio codice usava 1/1/2100
		//  - data leggibile     → la usiamo
		//  - data illeggibile   → `nil`: il server ha risposto in un formato che non
		//                         conosciamo e NON possiamo inventare una scadenza,
		//                         altrimenti una licenza appena attivata risulta scaduta.
		let parsedExp = expDateS.isEmpty ? Compat.du_createDate (d: 1, m: 1, y: 2100)
										 : Compat.du_parseServerDate (expDateS)
		let parsedReg = regDateS.isEmpty ? Compat.du_createDate (d: 1, m: 1, y: 2100)
										 : Compat.du_parseServerDate (regDateS)

		if let parsedExp { license.expDate = parsedExp }
		if let parsedReg { license.regDate = parsedReg }

		if parsedExp == nil {
			Diagnostics.log ("expDate illeggibile dal server: \"\(expDateS)\" — mantengo la scadenza locale")
		}

		return RemoteLicense (license: license, expDate: parsedExp, regDate: parsedReg)
	}


	// MARK: - Trasporto

	private func get (_ params: [(String, String)]) async throws -> String {
		// Query costruita a mano, come `netU_getGetUrl`: `URLComponents` lascia in
		// chiaro il `+`, che il server rilegge come spazio. Una email tipo
		// `nome+tag@x.com` arriverebbe diversa da quella su cui è calcolato il validator.
		let query = params
			.map { "\($0.0)=\(Compat.netU_percEnc ($0.1))" }
			.joined (separator: "&")

		guard let url = URL (string: baseUrl + "?" + query) else {
			throw ServerError.unreachable
		}

		Diagnostics.log ("GET \(params.first?.1 ?? "?") -> \(url.absoluteString)")

		do {
			let (data, _) = try await session.data (from: url)
			let response = String (decoding: data, as: UTF8.self)
			Diagnostics.logResponse (params.first?.1 ?? "?", response)
			return response
		} catch {
			Diagnostics.log ("GET fallita: \(error.localizedDescription)")
			throw ServerError.unreachable
		}
	}


	private func post (_ params: [String: String]) async throws -> String {
		guard let url = URL (string: baseUrl) else { throw ServerError.unreachable }

		var request = URLRequest (url: url)
		request.httpMethod = "POST"
		request.setValue ("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
		request.httpBody = Data (params
			.map { "\(Compat.netU_percEnc ($0.key))=\(Compat.netU_percEnc ($0.value))" }
			.joined (separator: "&")
			.utf8)

		do {
			let (data, _) = try await session.data (for: request)
			let response = String (decoding: data, as: UTF8.self)
				.replacingOccurrences (of: "<br>", with: "")
			Diagnostics.logResponse (params ["action"] ?? "?", response)
			return response
		} catch {
			Diagnostics.log ("POST fallita: \(error.localizedDescription)")
			throw ServerError.unreachable
		}
	}
}
