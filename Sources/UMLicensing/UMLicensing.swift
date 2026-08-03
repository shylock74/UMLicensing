//
//  UMLicensing.swift
//  UMLicensing
//
//  Punto di ingresso del package. Una sola chiamata all'avvio dell'app:
//
//      @main struct MyApp: App {
//          ...
//          guard await UMLicensing.licensed (appId:      Boot.kAppIdLong,
//                                            appName:    Boot.kAppName,
//                                            appShortId: Boot.kAppIdShort,
//                                            ...) else {
//              NSApp.terminate (nil)
//              return
//          }
//
//  `licensed()` non termina mai l'app da sé: se l'utente rinuncia ritorna `false`
//  e la decisione resta al chiamante.
//

import AppKit
import Foundation


@MainActor
public enum UMLicensing {

	// MARK: - API

	/// Verifica la licenza, guidando l'utente attraverso trial o inserimento seriale
	/// se necessario.
	///
	/// - Parameters:
	///   - appId: identificativo lungo dell'app, quello registrato sul server.
	///   - appName: nome leggibile, mostrato nelle finestre.
	///   - appShortId: prefisso a 4 caratteri dei seriali di questa app.
	///   - acceptedApps: prefissi accettati da `validateSerial`. Se vuoto, viene usato
	///     `[appShortId]`. Passa una lista più lunga se l'app ha cambiato nome o se
	///     accetti i seriali di un altro prodotto.
	///   - previousVersionPrefix: prefisso della versione precedente, accettato in più.
	///   - purchaseUrl: pagina di acquisto, aperta dal pulsante "Buy a License".
	///   - downloadAppUrl: link di download inserito nell'email del trial.
	///   - logoImageUrl: logo dell'app mostrato in cima all'email del trial.
	///   - logoImageAlt: testo alternativo del logo. Se vuoto viene usato `appName`.
	///   - mailBackgroundColor: colore di fondo dell'email.
	///   - mailAccentColor: colore dei dettagli dell'email (bordi, pulsante, link).
	///   - mailBody: template HTML alternativo. Se vuoto viene usato `MailTemplate.txt`
	///     incluso nel package.
	///   - trialExpDays: durata del periodo di prova.
	///   - graceDays: per quanti giorni la licenza resta valida senza riuscire a
	///     contattare il server. Oltre questa soglia il controllo online torna obbligatorio.
	///   - serverUrl: endpoint alternativo. Normalmente si lascia `nil`.
	///
	/// - Returns: `true` se l'app può partire.
	@discardableResult
	public static func licensed (appId:                  String,
								 appName:               String,
								 appShortId:            String,
								 acceptedApps:          [String] = [],
								 previousVersionPrefix: String = "",
								 purchaseUrl:           String,
								 downloadAppUrl:        String = "",
								 logoImageUrl:          String,
								 logoImageAlt:          String = "",
								 mailBackgroundColor:   NSColor = .umLicensingMailBackground,
								 mailAccentColor:       NSColor = .umLicensingMailAccent,
								 mailBody:              String = "",
								 trialExpDays:          Int = 7,
								 graceDays:             Int = 30,
								 serverUrl:             String? = nil) async -> Bool {

		let context = Context (appId:                 appId,
							   appName:               appName,
							   appShortId:            appShortId,
							   acceptedApps:          acceptedApps.isEmpty ? [appShortId] : acceptedApps,
							   previousVersionPrefix: previousVersionPrefix,
							   purchaseUrl:           purchaseUrl,
							   downloadAppUrl:        downloadAppUrl,
							   logoImageUrl:          logoImageUrl,
							   logoImageAlt:          logoImageAlt,
							   // I colori vengono risolti subito in componenti sRGB:
							   // `NSColor` non è `Sendable` e non può viaggiare nel Context.
							   backgroundRGB:         TrialMailer.rgbComponents (mailBackgroundColor),
							   accentRGB:             TrialMailer.rgbComponents (mailAccentColor),
							   mailBody:              mailBody.isEmpty ? TrialMailer.defaultTemplate () : mailBody,
							   trialExpDays:          trialExpDays,
							   graceDays:             graceDays,
							   serverUrl:             serverUrl)

		License.configure (context)

		let result = await run (context)
		License.licenseValidated = result
		return result
	}


	/// La licenza attualmente salvata, senza toccare la rete né mostrare finestre.
	public static func currentLicense (appId: String) -> LicenseData {
		LicenseStore (appId: appId).load ()
	}


	// MARK: - Contesto

	struct Context: Sendable {
		let appId:                 String
		let appName:               String
		let appShortId:            String
		let acceptedApps:          [String]
		let previousVersionPrefix: String
		let purchaseUrl:           String
		let downloadAppUrl:        String
		let logoImageUrl:          String
		let logoImageAlt:          String
		let backgroundRGB:         String
		let accentRGB:             String
		let mailBody:              String
		let trialExpDays:          Int
		let graceDays:             Int
		let serverUrl:             String?

		var machId: String { Compat.netU_getMacAddress () }

		var store: LicenseStore { LicenseStore (appId: appId) }

		func makeServer () -> LicenseServer { LicenseServer (baseUrl: serverUrl) }

		func isSerialValid (_ s: String) -> Bool {
			LicenseValidator.validateSerial (s,
											 acceptedApps: acceptedApps,
											 previousVersionPrefix: previousVersionPrefix)
		}
	}


	// MARK: - Flusso

	private static func run (_ c: Context) async -> Bool {

		var license = c.store.load ()

		// Percorso veloce: licenza perpetua già confermata dal server di recente.
		// Nessuna rete, nessuna attesa all'avvio; il rinnovo del grace period viene
		// tentato in sottofondo senza mai mostrare nulla all'utente.
		if isLocallyValid (license, c), withinGrace (c) {
			refreshInBackground (license, c)
			return true
		}

		// Nessuna licenza in locale: forse questa macchina è già registrata sul server
		// (reinstallazione, o utente che ha cancellato i preferences).
		if !license.isRegistered {
			if let recovered = await recoverFromServer (c) {
				license = recovered
			}
		}

		while true {
			if !license.isRegistered || license.isExpired {
				guard let acquired = await acquire (c, startingFromSerial: license.isExpired) else {
					return false
				}
				license = acquired
			}

			switch await confirm (license, c) {
				case .ok (let confirmed):
					markValidated (confirmed, c)
					announceTrialExpiry (confirmed)
					return true

				case .offline (let tolerated):
					guard tolerated else {
						Alert.ok ("Cannot Reach the Licensing Server",
								  """
								  \(c.appName) could not verify your license because the licensing \
								  server is unreachable, and it has been more than \(c.graceDays) days \
								  since the last successful check.

								  Check your internet connection, firewall or VPN, then try again.
								  """)
						return false
					}
					markValidated (license, c)
					return true

				case .rejected (let message):
					Alert.ok ("License", formatServerMessage (message))
					c.store.clear ()
					UMLicenseValidationCode.clear ()
					license = LicenseData ()
			}
		}
	}


	private static func formatServerMessage (_ message: String) -> String {
		let lower = message.lowercased ()
		if lower.contains ("doesn't exist") || lower.contains ("does not exist") || lower.contains ("invalid s/n") {
			return "\(Strings.invalidSN.value).\n\(Strings.checkIfYouTypedCorrectly.value)."
		}
		return message.isEmpty ? Strings.invalidLicense.value : message
	}


	// MARK: - Recupero dal server

	private static func recoverFromServer (_ c: Context) async -> LicenseData? {
		let server = c.makeServer ()
		guard let remote = try? await server.getDataByMachId (appId: c.appId, machId: c.machId),
			  !remote.serialId.isEmpty,
			  c.isSerialValid (remote.serialId) else {
			return nil
		}

		var license = remote.license
		license.machId = c.machId
		c.store.save (license)
		c.store.lastServerCheck = Date ()
		return license
	}


	// MARK: - Acquisizione di una licenza

	/// Guida l'utente fino a ottenere una licenza. `nil` se rinuncia.
	///
	/// - Parameter startingFromSerial: salta la schermata di scelta e va dritto
	///   all'inserimento del seriale. Usato quando il trial è scaduto: riproporre
	///   "Start Free Trial" a chi l'ha già consumato sarebbe solo confusionario.
	private static func acquire (_ c: Context, startingFromSerial: Bool) async -> LicenseData? {

		var skipChoice = startingFromSerial

		while true {
			let choice: ChooseOutcome

			if skipChoice {
				choice = .insertSerial
				skipChoice = false
			} else {
				choice = await LicenseWindow.show (title: c.appName,
												   size: CGSize (width: 460, height: 340),
												   closed: ChooseOutcome.quit) { finish in
					ChooseLicenseView (appName: c.appName,
									   trialExpDays: c.trialExpDays,
									   purchaseUrl: c.purchaseUrl,
									   finish: finish)
				}
			}

			switch choice {
				case .quit:
					return nil

				case .startTrial:
					if await issueTrial (c) {
						// Il seriale è stato spedito per email: l'utente lo incolla,
						// e così confermiamo che l'indirizzo è raggiungibile davvero.
						skipChoice = true
					}

				case .insertSerial:
					let outcome = await LicenseWindow.show (title: c.appName,
														   size: CGSize (width: 460, height: 300),
														   closed: SerialOutcome.quit) { finish in
						InsertSerialView (appName: c.appName,
										  purchaseUrl: c.purchaseUrl,
										  isSerialValid: { c.isSerialValid ($0) },
										  checkConnection: { await c.makeServer ().isReachable () },
										  finish: finish)
					}

					switch outcome {
						case .quit:
							return nil
						case .serial (let sn):
							if let activated = await activate (sn, c) {
								return activated
							}
					}
			}
		}
	}


	/// Emette un seriale di prova e lo spedisce per email. `false` se l'utente rinuncia.
	private static func issueTrial (_ c: Context) async -> Bool {

		let signupResult: TrialSignup? = await LicenseWindow.show (title: c.appName,
																   size: CGSize (width: 460, height: 320),
																   closed: nil) { finish in
			TrialSignupView (appName: c.appName,
							 trialExpDays: c.trialExpDays,
							 finish: finish)
		}

		guard let signup = signupResult else { return false }

		let serialId = LicenseValidator.generateSN (appShortId: c.appShortId,
													type: .trial,
													progressiveN: Int (arc4random_uniform (100_000_000)))
		let expDate = Compat.du_getDatePlusDays (date: Date (), days: c.trialExpDays)

		do {
			try await c.makeServer ().uploadNewLicense (appId: c.appId,
														serialId: serialId,
														expDate: expDate,
														machId: c.machId,
														username: signup.username,
														email: signup.email)
		} catch {
			Alert.ok ("Cannot Create the Trial License",
					  """
					  \(c.appName) could not reach the licensing server to create your trial.

					  Check your internet connection, firewall or VPN, then try again.
					  """)
			return false
		}

		// Ricordiamo i dati: al momento dell'attivazione servono per intestare la licenza.
		UserDefaults.standard.set (signup.username, forKey: "License.temp.username")
		UserDefaults.standard.set (signup.email,    forKey: "License.temp.email")

		let body = TrialMailer.body (template: c.mailBody,
									 fields: TrialMailer.Fields (username: signup.username,
																 appId: c.appId,
																 appName: c.appName,
																 serialId: serialId,
																 expDate: expDate,
																 downloadAppUrl: c.downloadAppUrl,
																 logoImageUrl: c.logoImageUrl,
																 logoImageAlt: c.logoImageAlt,
																 backgroundRGB: c.backgroundRGB,
																 accentRGB: c.accentRGB))

		let sent = await TrialMailer ().send (to: signup.email,
											  name: signup.username,
											  subject: "\(c.appName) Trial Serial Number",
											  htmlBody: body)

		if sent {
			Alert.ok ("Trial Serial Number Sent",
					  """
					  We sent your trial serial number to \(signup.email).

					  If it doesn't arrive within a few minutes, check your spam folder.
					  """)
		} else {
			Alert.ok ("Trial Serial Number Ready",
					  """
					  Your trial serial number is ready and has been sent to \(signup.email).

					  If you don't receive it within a few minutes, check your spam folder.
					  """)
		}
		return true
	}


	/// Attiva un seriale su questa macchina. `nil` se l'attivazione non riesce.
	private static func activate (_ serialId: String, _ c: Context) async -> LicenseData? {

		guard c.isSerialValid (serialId) else {
			Alert.ok (Strings.invalidSN.value, Strings.checkIfYouTypedCorrectly.value)
			return nil
		}

		let defaults = UserDefaults.standard
		var license = LicenseData ()
		license.appId    = c.appId
		license.serialId = serialId
		license.machId   = c.machId
		license.licType  = licenseType (serialId: serialId).name
		license.username = defaults.string (forKey: "License.temp.username") ?? "USERNAME"
		license.password = "PASSWORD"
		license.email    = defaults.string (forKey: "License.temp.email") ?? "EMAIL"
		license.regDate  = Date ()
		license.expDate  = licenseType (serialId: serialId).isPerpetual
			? Compat.du_createDate (d: 1, m: 1, y: 2100)
			: Compat.du_getDatePlusDays (date: Date (), days: c.trialExpDays)

		do {
			try await c.makeServer ().activate (license)
		} catch LicenseServer.ServerError.unreachable {
			Alert.ok ("Cannot Reach the Licensing Server",
					  """
					  \(c.appName) could not activate your serial number because the licensing \
					  server is unreachable.

					  Check your internet connection, firewall or VPN, then try again.
					  """)
			return nil
		} catch let LicenseServer.ServerError.rejected (message) {
			Alert.ok ("License", formatServerMessage (message))
			return nil
		} catch {
			Alert.ok ("License", Strings.notValidated.value)
			return nil
		}

		c.store.save (license)
		c.store.lastServerCheck = Date ()
		return license
	}


	// MARK: - Conferma

	private enum Confirmation {
		case ok (LicenseData)
		/// Server irraggiungibile. `tolerated` dice se il grace period copre la cosa.
		case offline (tolerated: Bool)
		case rejected (String)
	}


	private static func confirm (_ license: LicenseData, _ c: Context) async -> Confirmation {

		// Licenza perpetua già verificata di recente: nessun motivo di attendere la rete.
		if isLocallyValid (license, c), withinGrace (c) {
			refreshInBackground (license, c)
			return .ok (license)
		}

		do {
			let remote = try await c.makeServer ().getData (appId: license.appId,
															serialId: license.serialId)

			if !remote.machId.isEmpty, remote.machId != license.machId {
				return .rejected (Strings.serialAlreadyActivated.value)
			}

			// Il server è l'autorità sulla scadenza: un trial non si allunga
			// riportando indietro l'orologio del Mac. Ma solo quando la data che manda
			// è leggibile: se non lo è teniamo quella locale, perché dichiarare scaduta
			// una licenza sulla base di un campo che non sappiamo interpretare
			// significa bloccare fuori un cliente pagante.
			var updated = license
			if let remoteExp = remote.expDate { updated.expDate = remoteExp }
			if let remoteReg = remote.regDate { updated.regDate = remoteReg }

			c.store.save (updated)
			c.store.lastServerCheck = Date ()

			// La scadenza vale solo per le licenze a termine, e solo se la data viene
			// davvero dal server.
			if remote.expDate != nil, updated.isExpired {
				return .rejected ("Your \(updated.type.displayName) license has expired.")
			}
			return .ok (updated)

		} catch LicenseServer.ServerError.unreachable {
			return .offline (tolerated: isLocallyValid (license, c) && withinGrace (c, allowNeverChecked: true))
		} catch let LicenseServer.ServerError.rejected (message) {
			return .rejected (message)
		} catch {
			return .offline (tolerated: isLocallyValid (license, c) && withinGrace (c, allowNeverChecked: true))
		}
	}


	// MARK: - Validazione locale

	/// La licenza salvata è integra, non scaduta, e il codice di validazione locale
	/// corrisponde a questa macchina.
	private static func isLocallyValid (_ license: LicenseData, _ c: Context) -> Bool {
		guard license.isRegistered,
			  !license.isExpired,
			  c.isSerialValid (license.serialId),
			  license.type.isPerpetual else {
			return false
		}

		guard let saved = UMLicenseValidationCode.load () else { return false }
		let expected = UMLicenseValidationCode (appId: license.appId,
												serialNumber: license.serialId,
												machineID: license.machId)
		return saved.validationCode == expected.expectedCode ()
	}


	/// Siamo entro la finestra in cui si può fare a meno del server.
	///
	/// - Parameter allowNeverChecked: se non c'è alcun controllo registrato (licenza
	///   arrivata da una versione precedente del package, che non salvava la data)
	///   concediamo comunque il beneficio del dubbio invece di bloccare un cliente
	///   che ha sempre funzionato.
	private static func withinGrace (_ c: Context, allowNeverChecked: Bool = false) -> Bool {
		guard let last = c.store.lastServerCheck else {
			if allowNeverChecked { c.store.lastServerCheck = Date () }
			return allowNeverChecked
		}
		return Compat.du_getDeltaDate (firstDate: last, secondDate: Date ()) <= c.graceDays
	}


	/// Rinnova in sottofondo la finestra di grace, senza mai interrompere l'utente.
	/// Un fallimento qui non ha conseguenze immediate: al più, fra `graceDays` giorni
	/// il controllo online tornerà obbligatorio.
	private static func refreshInBackground (_ license: LicenseData, _ c: Context) {
		let store  = c.store
		let server = c.makeServer ()
		let appId  = license.appId
		let serial = license.serialId

		Task.detached (priority: .background) {
			guard let remote = try? await server.getData (appId: appId, serialId: serial),
				  remote.serialId == serial else { return }
			await MainActor.run { store.lastServerCheck = Date () }
		}
	}


	private static func markValidated (_ license: LicenseData, _ c: Context) {
		UMLicenseValidationCode (appId: license.appId,
								 serialNumber: license.serialId,
								 machineID: license.machId).save ()
	}


	private static func announceTrialExpiry (_ license: LicenseData) {
		guard license.type == .trial else { return }
		Alert.ok ("License",
				  Strings.trialLicenseExpires.value
					+ Compat.du_formatDate (license.expDate, formatter: "dd MMMM yyyy"))
	}
}
