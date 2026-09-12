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

		Diagnostics.trace ("licensed(): appId=\(appId) appName=\(appName) appShortId=\(appShortId) "
						   + "acceptedApps=\(context.acceptedApps) previousPrefix=\(previousVersionPrefix.isEmpty ? "—" : previousVersionPrefix) "
						   + "trialExpDays=\(trialExpDays) graceDays=\(graceDays) "
						   + "serverUrl=\(serverUrl ?? "predefinito")")

		let result = await run (context)
		License.licenseValidated = result

		Diagnostics.trace ("licensed(): esito \(result)")
		return result
	}


	/// Log dettagliato di tutto lo scambio col server, risposte grezze comprese.
	///
	/// Equivale a `defaults write <bundle-id> UMLicensing.debug -bool YES`, ma si può
	/// accendere da codice prima di chiamare `licensed()`. I codici diagnostici
	/// (`UML-Exxx`) vengono stampati comunque, anche con questo a `false`.
	public static var verboseLogging: Bool {
		get { Diagnostics.forceEnabled }
		set { Diagnostics.forceEnabled = newValue }
	}


	/// Stato della licenza in forma leggibile, da allegare a una segnalazione.
	///
	/// Non tocca la rete: dice cosa c'è su questo Mac e come sta rispetto al grace
	/// period, che è la metà della risposta quando salta fuori un `UML-E3xx`/`E4xx`.
	public static func diagnosticReport (appId: String, graceDays: Int = 30) -> String {
		let store   = LicenseStore (appId: appId)
		let license = store.load ()
		let machId  = Compat.netU_getMacAddress ()
		let saved   = UMLicenseValidationCode.load ()

		let expected = UMLicenseValidationCode (appId: license.appId,
												serialNumber: license.serialId,
												machineID: license.machId)

		let last = store.lastServerCheck
		let days = last.map { Compat.du_getDeltaDate (firstDate: $0, secondDate: Date ()) }

		return """
		UMLicensing diagnostic report
		  appId              \(appId)
		  serialId           \(license.serialId.isEmpty ? "—" : license.serialId)
		  licType            \(license.licType.isEmpty ? "—" : license.licType)
		  perpetual          \(license.type.isPerpetual)
		  regDate            \(Compat.du_getDateString (license.regDate))
		  expDate            \(Compat.du_getDateString (license.expDate))
		  expired            \(license.isExpired)
		  registered         \(license.isRegistered)
		  storeError         \(license.errorMessage.isEmpty ? "—" : license.errorMessage)
		  machId (store)     \(license.machId.isEmpty ? "—" : license.machId)
		  machId (this Mac)  \(machId.isEmpty ? "— (UML-E308)" : machId)
		  validationCode     \(saved == nil ? "assente (UML-E306)" : (saved?.validationCode == expected.expectedCode () ? "corrisponde" : "non corrisponde (UML-E307)"))
		  lastServerCheck    \(last.map { Compat.du_getDateString ($0) } ?? "mai (UML-E402)")
		  giorni dall'ultimo \(days.map (String.init) ?? "—") su \(graceDays) \((days ?? 0) > graceDays ? "(UML-E401)" : "")
		"""
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

		Diagnostics.log ("avvio: \(stateSummary (license, c))")

		license = usableStoredLicense (license, c)

		// Percorso veloce: licenza perpetua già confermata dal server di recente.
		// Nessuna rete, nessuna attesa all'avvio; il rinnovo del grace period viene
		// tentato in sottofondo senza mai mostrare nulla all'utente.
		if isLocallyValid (license, c), withinGrace (c) {
			Diagnostics.trace ("run: percorso veloce — licenza locale valida e dentro il grace period")
			refreshInBackground (license, c)
			return true
		}

		// Nessuna licenza in locale: forse questa macchina è già registrata sul server
		// (reinstallazione, o utente che ha cancellato i preferences).
		if !license.isRegistered {
			Diagnostics.trace ("run: nessuna licenza in locale, provo il recupero dal server")
			if let recovered = await recoverFromServer (c) {
				license = recovered
			}
		}

		while true {
			// L'alert di conferma ha senso solo come risposta a qualcosa che l'utente
			// ha appena fatto: iniziare il trial o digitare un seriale. Chi aveva già
			// la licenza — o se l'è vista recuperare dal server dopo una reinstallazione —
			// non ha chiesto niente, e si vedrebbe annunciare un'attivazione che non
			// ha svolto. Succedeva al primo avvio dopo l'aggiornamento da UMOmniaFramework.
			var justAcquired = false

			if !license.isRegistered || license.isExpired {
				Diagnostics.trace ("run: serve una licenza "
								   + "(registrata=\(license.isRegistered) scaduta=\(license.isExpired))")

				guard let acquired = await acquire (c, startingFromSerial: license.isExpired) else {
					Diagnostics.trace ("run: l'utente ha rinunciato, esco con false")
					return false
				}
				license = acquired
				justAcquired = true
			}

			switch await confirm (license, c) {
				case .ok (let confirmed):
					Diagnostics.trace ("run: confermata dal server, serialId=\(confirmed.serialId)")
					markValidated (confirmed, c)
					if justAcquired {
						announceActivation (confirmed, appName: c.appName)
					}
					return true

				case .offline (let tolerated, let diagnosis):
					Diagnostics.trace ("run: offline, tollerato=\(tolerated) — \(diagnosis.logLine)")
					guard tolerated else {
						Alert.ok (offlineAlertTitle (diagnosis),
								  offlineAlertBody (diagnosis, c))
						return false
					}
					markValidated (license, c)
					return true

				case .rejected (let message):
					Diagnostics.trace ("run: rifiutata dal server — \"\(message)\", azzero la licenza locale")
					Alert.ok ("License", formatServerMessage (message))
					c.store.clear ()
					UMLicenseValidationCode.clear ()
					license = LicenseData ()
			}
		}
	}


	/// La licenza da cui partire, dato quello che c'è nei preferences.
	///
	/// Restituisce una licenza vuota quando il seriale salvato non appartiene a questa
	/// app: prefisso di una versione precedente non più accettata, o licenza di un altro
	/// prodotto rimasta nei preferences.
	///
	/// Senza questo filtro passava lo stesso. `isRegistered` guarda solo che il seriale
	/// ci sia e che la firma locale torni, mai il prefisso: il flusso saltava `acquire()`
	/// e andava dritto a `confirm()`, che chiedeva conferma al server — dove quel seriale
	/// esiste davvero, perché è stato venduto. L'app si sbloccava con una licenza che
	/// aveva appena smesso di accettare, e il controllo sul prefisso scattava solo quando
	/// il server non rispondeva.
	///
	/// La licenza **non** viene cancellata dai preferences: se il prefisso torna fra gli
	/// `acceptedApps` deve riprendere a funzionare da sola, senza far reinserire niente.
	static func usableStoredLicense (_ license: LicenseData, _ c: Context) -> LicenseData {
		guard license.isRegistered, !c.isSerialValid (license.serialId) else { return license }

		Diagnostics.diagnose (.serialFailsLocalCheck,
							  "avvio",
							  "\(license.serialId) non è di questa app "
							  + "(accettati: \(c.acceptedApps.joined (separator: ", "))"
							  + (c.previousVersionPrefix.isEmpty
								 ? ""
								 : ", versione precedente: \(c.previousVersionPrefix)")
							  + ") — resta nei preferences ma non vale come licenza")

		return LicenseData ()
	}


	/// Il titolo dice la verità sulla causa: "server irraggiungibile" su una risposta
	/// arrivata regolarmente ma illeggibile manda l'utente a controllare il router per
	/// un problema che è nostro.
	private static func offlineAlertTitle (_ diagnosis: UMLicensingDiagnosis) -> String {
		switch diagnosis.server {
			case .validatorMismatch, .malformedResponse, .htmlErrorPage,
				 .unreadableDate, .missingSerialField, .httpStatus:
				return "Licensing Server Problem"
			default:
				return "Cannot Reach the Licensing Server"
		}
	}


	private static func offlineAlertBody (_ diagnosis: UMLicensingDiagnosis, _ c: Context) -> String {

		// Cosa è successo lato server.
		let cause: String
		switch diagnosis.server {
			case .validatorMismatch, .malformedResponse, .htmlErrorPage,
				 .unreadableDate, .missingSerialField, .httpStatus, .emptyResponse:
				cause = "\(c.appName) could not verify your license: \(diagnosis.server.text.lowercased ())"
			default:
				cause = "\(c.appName) could not verify your license because the licensing server is unreachable."
		}

		// Perché la copia locale non è bastata a coprirlo. Il vecchio testo dava sempre
		// la colpa ai 30 giorni, anche quando il grace period non c'entrava: su un trial
		// il controllo online è obbligatorio a ogni avvio, e nessuno lo diceva.
		let reason: String
		switch diagnosis.local {
			case .graceExpired:
				reason = "It has been more than \(c.graceDays) days since the last successful check."
			case .notPerpetual:
				reason = "Trial licenses are verified online every time the app starts."
			case .validationCodeMismatch, .emptyMachId:
				reason = "This license could not be matched to this Mac offline."
			case .noValidationCode, .neverChecked:
				reason = "This license has never been confirmed on this Mac."
			case .some (let code):
				reason = code.text
			case nil:
				reason = ""
		}

		// Cosa può fare l'utente: mandarlo a controllare il firewall quando il server
		// risponde e basta è tempo suo sprecato.
		let advice: String
		switch diagnosis.server {
			case .validatorMismatch, .malformedResponse, .htmlErrorPage,
				 .unreadableDate, .missingSerialField, .httpStatus, .emptyResponse:
				advice = "This is a problem on our side. Please try again later, or contact support with the code below."
			default:
				advice = "Check your internet connection, firewall or VPN, then try again."
		}

		return [cause, reason, advice, "Error code: \(diagnosis.display)"]
			.filter { !$0.isEmpty }
			.joined (separator: "\n\n")
	}


	private static func formatServerMessage (_ message: String) -> String {
		if LicenseServer.isUnknownSerialMessage (message)
			|| message.lowercased ().contains ("invalid s/n") {
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
			Diagnostics.trace ("recoverFromServer: nessuna licenza recuperabile per machId=\(c.machId)")
			return nil
		}

		Diagnostics.trace ("recoverFromServer: recuperato serialId=\(remote.serialId)")

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
				Diagnostics.trace ("acquire: salto la scelta, vado dritto all'inserimento del seriale")
			} else {
				Diagnostics.trace ("acquire: mostro la schermata di scelta")
				choice = await LicenseWindow.show (title: c.appName,
												   size: ChooseLicenseView.windowSize,
												   closed: ChooseOutcome.quit) { finish in
					ChooseLicenseView (appName: c.appName,
									   trialExpDays: c.trialExpDays,
									   purchaseUrl: c.purchaseUrl,
									   finish: finish)
				}
			}

			Diagnostics.trace ("acquire: scelta \(choice)")

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
					Diagnostics.trace ("acquire: mostro la schermata di inserimento seriale")
					let outcome = await LicenseWindow.show (title: c.appName,
														   size: CGSize (width: 460, height: 300),
														   closed: SerialOutcome.quit) { finish in
						InsertSerialView (appName: c.appName,
										  purchaseUrl: c.purchaseUrl,
										  isSerialValid: { c.isSerialValid ($0) },
										  checkConnection: { await c.makeServer ().isReachable () },
										  lookUpSerial: { await c.makeServer ().lookUpSerial (appId: c.appId, serialId: $0) },
										  finish: finish)
					}

					switch outcome {
						case .quit:
							Diagnostics.trace ("acquire: finestra seriale chiusa senza inserire niente")
							return nil
						case .serial (let sn):
							Diagnostics.trace ("acquire: seriale inserito \(sn)")
							if let activated = await activate (sn, c) {
								return activated
							}
							Diagnostics.trace ("acquire: attivazione non riuscita, torno alla scelta")
					}
			}
		}
	}


	/// Emette un seriale di prova e lo spedisce per email. `false` se l'utente rinuncia.
	private static func issueTrial (_ c: Context) async -> Bool {

		Diagnostics.trace ("issueTrial: mostro la schermata di iscrizione al trial")

		let signupResult: TrialSignup? = await LicenseWindow.show (title: c.appName,
																   size: CGSize (width: 460, height: 320),
																   closed: nil) { finish in
			TrialSignupView (appName: c.appName,
							 trialExpDays: c.trialExpDays,
							 finish: finish)
		}

		guard let signup = signupResult else {
			Diagnostics.trace ("issueTrial: iscrizione annullata")
			return false
		}

		Diagnostics.trace ("issueTrial: iscrizione di \(signup.username) <\(signup.email)>")

		let serialId = LicenseValidator.generateSN (appShortId: c.appShortId,
													type: .trial,
													progressiveN: Int (arc4random_uniform (100_000_000)))
		let expDate = Compat.du_getDatePlusDays (date: Date (), days: c.trialExpDays)

		Diagnostics.trace ("issueTrial: generato \(serialId), scadenza \(Compat.du_getDateString (expDate))")

		do {
			try await c.makeServer ().uploadNewLicense (appId: c.appId,
														serialId: serialId,
														expDate: expDate,
														machId: c.machId,
														username: signup.username,
														email: signup.email)
		} catch {
			Diagnostics.trace ("issueTrial: caricamento sul server fallito (\(error))")
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

		Diagnostics.trace ("issueTrial: email a \(signup.email) \(sent ? "spedita" : "NON spedita")")

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

		Diagnostics.trace ("activate: verifico in locale \(serialId)")

		guard c.isSerialValid (serialId) else {
			Diagnostics.trace ("activate: \(serialId) non passa il controllo locale (prefisso o cifre)")
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
		} catch let LicenseServer.ServerError.unreachable (code) {
			Diagnostics.diagnose (code, "activate", stateSummary (license, c))
			Alert.ok ("Cannot Reach the Licensing Server",
					  """
					  \(c.appName) could not activate your serial number because the licensing \
					  server is unreachable. \(code.text)

					  Check your internet connection, firewall or VPN, then try again.

					  Error code: \(code.display)
					  """)
			return nil
		} catch let LicenseServer.ServerError.rejected (message) {
			// Il server può rifiutare perché il seriale risulta già attivato — su questo
			// stesso Mac. Succede a chi ha perso i preferences, o a chi arriva da
			// UMOmniaFramework, dove `getDataByMachId()` sovrascriveva `machId` con
			// `machId2` (license.swift:551) e quindi il valore salvato non è mai stato
			// quello vero. Se l'attivazione che il server ha in archivio è di questa
			// macchina, non c'è niente da riattivare: la adottiamo e basta.
			Diagnostics.trace ("activate: rifiutata (\"\(message)\"), controllo se è già attiva su questo Mac")
			if let adopted = await adoptExistingActivation (license, c) {
				return adopted
			}
			Alert.ok ("License", formatServerMessage (message))
			return nil
		} catch let LicenseServer.ServerError.notValidated (code) {
			Diagnostics.diagnose (code, "activate", stateSummary (license, c))
			Alert.ok ("Licensing Server Problem",
					  """
					  \(code.text)

					  This is a problem on our side. Please try again later, or contact support \
					  with the code below.

					  Error code: \(code.display)
					  """)
			return nil
		} catch {
			let code = UMLicensingCode.transport (error)
			Diagnostics.diagnose (code, "activate", "\(error)")
			Alert.ok ("License", "\(Strings.notValidated.value)\n\nError code: \(code.display)")
			return nil
		}

		Diagnostics.trace ("activate: attivazione completata, salvo la licenza in locale")
		c.store.save (license)
		c.store.lastServerCheck = Date ()
		return license
	}


	/// Riconosce un seriale che il server considera già attivato **su questa macchina**
	/// e lo riporta in locale. `nil` in ogni altro caso: il vincolo alla macchina resta,
	/// qui non si rilascia né si sposta niente.
	private static func adoptExistingActivation (_ license: LicenseData, _ c: Context) async -> LicenseData? {

		guard !c.machId.isEmpty,
			  let remote = try? await c.makeServer ().getData (appId: license.appId,
															   serialId: license.serialId),
			  Compat.machIdMatches (remote.machId, c.machId) else {
			Diagnostics.trace ("adoptExistingActivation: l'attivazione sul server non è di questo Mac")
			return nil
		}

		var adopted = remote.license
		adopted.machId = c.machId

		// `parseLicense` lascia le date di default quando il server le manda in un
		// formato che non sappiamo leggere: in quel caso teniamo quelle che avevamo
		// calcolato noi, invece di inventare una scadenza.
		if remote.expDate == nil { adopted.expDate = license.expDate }
		if remote.regDate == nil { adopted.regDate = license.regDate }
		if adopted.username.isEmpty { adopted.username = license.username }
		if adopted.email.isEmpty    { adopted.email    = license.email }
		if adopted.licType.isEmpty  { adopted.licType  = license.licType }

		// Una licenza scaduta resta scaduta: il rifiuto del server poteva essere quello.
		guard !adopted.isExpired else {
			Diagnostics.trace ("adoptExistingActivation: l'attivazione trovata è scaduta")
			return nil
		}

		Diagnostics.trace ("adoptExistingActivation: adotto l'attivazione già presente sul server")
		c.store.save (adopted)
		c.store.lastServerCheck = Date ()
		return adopted
	}


	// MARK: - Conferma

	private enum Confirmation {
		case ok (LicenseData)
		/// Il server non ha risposto in modo utilizzabile. `tolerated` dice se la copia
		/// locale copre la cosa; `diagnosis` porta i codici da mostrare quando non copre.
		case offline (tolerated: Bool, diagnosis: UMLicensingDiagnosis)
		case rejected (String)
	}


	private static func confirm (_ license: LicenseData, _ c: Context) async -> Confirmation {

		// Licenza perpetua già verificata di recente: nessun motivo di attendere la rete.
		if isLocallyValid (license, c), withinGrace (c) {
			Diagnostics.trace ("confirm: copia locale valida e recente, nessuna attesa della rete")
			refreshInBackground (license, c)
			return .ok (license)
		}

		Diagnostics.trace ("confirm: chiedo conferma al server per \(license.serialId)")

		do {
			let remote = try await c.makeServer ().getData (appId: license.appId,
															serialId: license.serialId)

			// Il seriale risulta legato a una macchina: va bene finché è questa.
			//
			// Non basta confrontarlo col `machId` salvato nei preferences: fino
			// all'ultima versione di UMOmniaFramework `getDataByMachId()` assegnava
			// `machId` due volte di fila, la seconda con il valore di `machId2`
			// (license.swift:550-551), e all'avvio salvava quella licenza in locale.
			// Sulle macchine già registrate il `machId` nei preferences è quindi vuoto,
			// mentre sul server c'è il MAC vero: confrontando solo quei due valori ogni
			// utente storico si vedeva rifiutare la licenza al primo avvio con questa
			// versione. Il vecchio codice, del resto, il confronto lo faceva solo in
			// fase di attivazione (license.swift:619), mai a ogni lancio.
			if !remote.machId.isEmpty,
			   !Compat.machIdMatches (remote.machId, c.machId),
			   !Compat.machIdMatches (remote.machId, license.machId) {
				Diagnostics.trace ("confirm: il server lega il seriale a \(remote.machId), "
								   + "questo Mac è \(c.machId) — rifiutata")
				return .rejected (Strings.serialAlreadyActivated.value)
			}

			// Il server è l'autorità sulla scadenza: un trial non si allunga
			// riportando indietro l'orologio del Mac. Ma solo quando la data che manda
			// è leggibile: se non lo è teniamo quella locale, perché dichiarare scaduta
			// una licenza sulla base di un campo che non sappiamo interpretare
			// significa bloccare fuori un cliente pagante.
			var updated = license

			// Licenza di questa macchina con un `machId` locale vuoto o scritto in un
			// altro formato: lo riallineiamo, così dal giro successivo il controllo passa
			// dal confronto diretto e `UMLicenseValidationCode` viene firmato col valore
			// giusto. Se invece il server è d'accordo col valore salvato ma non col MAC
			// attuale (scheda di rete sostituita) teniamo quello salvato: è l'unico che
			// il server riconosce.
			if !c.machId.isEmpty,
			   !Compat.machIdMatches (updated.machId, c.machId),
			   remote.machId.isEmpty || Compat.machIdMatches (remote.machId, c.machId) {
				updated.machId = c.machId
			}

			if let remoteExp = remote.expDate { updated.expDate = remoteExp }
			if let remoteReg = remote.regDate { updated.regDate = remoteReg }

			c.store.save (updated)
			c.store.lastServerCheck = Date ()

			// La scadenza vale solo per le licenze a termine, e solo se la data viene
			// davvero dal server.
			if remote.expDate != nil, updated.isExpired {
				Diagnostics.trace ("confirm: scaduta secondo il server "
								   + "(\(Compat.du_getDateString (updated.expDate)))")
				return .rejected ("Your \(updated.type.displayName) license has expired.")
			}

			Diagnostics.trace ("confirm: confermata dal server")
			return .ok (updated)

		} catch let LicenseServer.ServerError.unreachable (code) {
			return offlineOutcome (license, c, server: code)
		} catch let LicenseServer.ServerError.notValidated (code) {
			// Il server ha risposto: non è un problema di rete, ma di protocollo. Il
			// grace period vale lo stesso — non è l'utente ad avere sbagliato qualcosa.
			return offlineOutcome (license, c, server: code)
		} catch let LicenseServer.ServerError.rejected (message) {
			Diagnostics.trace ("confirm: rifiutata dal server — \"\(message)\"")
			return .rejected (message)
		} catch {
			return offlineOutcome (license, c, server: UMLicensingCode.transport (error))
		}
	}


	/// Decide se la licenza salvata basta a coprire un server che non ha risposto, e
	/// con quali codici spiegarlo se non basta.
	private static func offlineOutcome (_ license: LicenseData,
										_ c: Context,
										server: UMLicensingCode) -> Confirmation {

		let localReason = localBlockReason (license, c)
		let graceReason = localReason == nil ? graceBlockReason (c, allowNeverChecked: true) : nil
		let blocking    = localReason ?? graceReason

		var diagnosis = UMLicensingDiagnosis (server: server, local: blocking)
		diagnosis.detail = stateSummary (license, c)

		if let blocking {
			Diagnostics.diagnose (blocking, "confirm", diagnosis.detail)
		}
		Diagnostics.log ("esito offline: \(diagnosis.logLine)")

		return .offline (tolerated: blocking == nil, diagnosis: diagnosis)
	}


	// MARK: - Validazione locale

	/// La licenza salvata è integra, non scaduta, e il codice di validazione locale
	/// corrisponde a questa macchina.
	private static func isLocallyValid (_ license: LicenseData, _ c: Context) -> Bool {
		let reason = localBlockReason (license, c)
		Diagnostics.trace ("isLocallyValid: \(reason == nil ? "sì" : "no — \(reason!.display) \(reason!.text)")")
		return reason == nil
	}


	/// Perché la licenza salvata non è utilizzabile senza server. `nil` se lo è.
	///
	/// È la stessa catena di controlli di prima, spezzata in `guard` distinti per poter
	/// dire *quale* è saltato: erano tutti indistinguibili dietro un unico `false`, e
	/// l'utente si vedeva incolpare la rete anche quando la rete non c'entrava niente.
	private static func localBlockReason (_ license: LicenseData, _ c: Context) -> UMLicensingCode? {

		guard license.isRegistered else {
			// `LicenseStore.load()` azzera il seriale quando la firma locale non torna:
			// "manomessa" e "assente" arrivano qui identiche, le separa il messaggio.
			return license.errorMessage == Strings.invalidLicense.value
				? .localValidatorMismatch
				: .noLocalLicense
		}
		guard !license.isExpired                    else { return .licenseExpired }
		guard c.isSerialValid (license.serialId)    else { return .serialFailsLocalCheck }
		guard license.type.isPerpetual              else { return .notPerpetual }
		guard let saved = UMLicenseValidationCode.load () else { return .noValidationCode }

		let expected = UMLicenseValidationCode (appId: license.appId,
												serialNumber: license.serialId,
												machineID: license.machId)
		guard saved.validationCode == expected.expectedCode () else {
			// Il codice è firmato sul machId: se il MAC non è più leggibile (niente
			// interfaccia Ethernet primaria: Mac senza rete cablata, VPN che riordina
			// le interfacce) non torna più niente, ed è un caso a sé.
			return c.machId.isEmpty ? .emptyMachId : .validationCodeMismatch
		}
		return nil
	}


	/// Siamo entro la finestra in cui si può fare a meno del server.
	///
	/// - Parameter allowNeverChecked: se non c'è alcun controllo registrato (licenza
	///   arrivata da una versione precedente del package, che non salvava la data)
	///   concediamo comunque il beneficio del dubbio invece di bloccare un cliente
	///   che ha sempre funzionato.
	private static func withinGrace (_ c: Context, allowNeverChecked: Bool = false) -> Bool {
		let reason = graceBlockReason (c, allowNeverChecked: allowNeverChecked)
		Diagnostics.trace ("withinGrace: \(reason == nil ? "sì" : "no — \(reason!.display) \(reason!.text)")")
		return reason == nil
	}


	/// Perché la finestra offline non copre. `nil` se copre.
	private static func graceBlockReason (_ c: Context, allowNeverChecked: Bool) -> UMLicensingCode? {
		guard let last = c.store.lastServerCheck else {
			if allowNeverChecked {
				c.store.lastServerCheck = Date ()
				return nil
			}
			return .neverChecked
		}

		let days = Compat.du_getDeltaDate (firstDate: last, secondDate: Date ())
		guard days > c.graceDays else { return nil }

		Diagnostics.log ("grace scaduto: \(days) giorni dall'ultimo controllo (limite \(c.graceDays))")
		return .graceExpired
	}


	/// Fotografia dello stato locale, per il log e per `diagnosticReport`.
	private static func stateSummary (_ license: LicenseData, _ c: Context) -> String {
		let last = c.store.lastServerCheck
		let days = last.map { Compat.du_getDeltaDate (firstDate: $0, secondDate: Date ()) }

		return [
			"serial=\(license.serialId.isEmpty ? "—" : license.serialId)",
			"type=\(license.type.displayName.isEmpty ? "—" : license.type.displayName)",
			"perpetual=\(license.type.isPerpetual)",
			"expired=\(license.isExpired)",
			"exp=\(Compat.du_getDateString (license.expDate))",
			"machId(store)=\(license.machId.isEmpty ? "—" : license.machId)",
			"machId(mac)=\(c.machId.isEmpty ? "—" : c.machId)",
			"validationCode=\(UMLicenseValidationCode.load () == nil ? "assente" : "presente")",
			"lastCheck=\(last.map { Compat.du_getDateString ($0) } ?? "mai")",
			"giorni=\(days.map (String.init) ?? "—")/\(c.graceDays)",
		].joined (separator: " ")
	}


	/// Rinnova in sottofondo la finestra di grace, senza mai interrompere l'utente.
	/// Un fallimento qui non ha conseguenze immediate: al più, fra `graceDays` giorni
	/// il controllo online tornerà obbligatorio.
	private static func refreshInBackground (_ license: LicenseData, _ c: Context) {
		let store  = c.store
		let server = c.makeServer ()
		let appId  = license.appId
		let serial = license.serialId

		Diagnostics.trace ("refreshInBackground: rinnovo il grace period in sottofondo per \(serial)")

		Task.detached (priority: .background) {
			guard let remote = try? await server.getData (appId: appId, serialId: serial),
				  remote.serialId == serial else {
				Diagnostics.trace ("refreshInBackground: rinnovo non riuscito, resta l'ultima data buona")
				return
			}
			await MainActor.run { store.lastServerCheck = Date () }
			Diagnostics.trace ("refreshInBackground: grace period rinnovato")
		}
	}


	private static func markValidated (_ license: LicenseData, _ c: Context) {
		Diagnostics.trace ("markValidated: firmo il codice di validazione per "
						   + "\(license.serialId) su machId=\(license.machId)")

		UMLicenseValidationCode (appId: license.appId,
								 serialNumber: license.serialId,
								 machineID: license.machId).save ()
	}


	/// Conferma all'utente che l'attivazione è andata a buon fine.
	///
	/// Chiamata solo dopo `acquire()`: vedi il commento in `run()` sul perché non
	/// vada mostrata a chi la licenza ce l'aveva già.
	private static func announceActivation (_ license: LicenseData, appName: String) {
		Diagnostics.trace ("announceActivation: tipo \(license.type.name)")

		if license.type == .trial {
			let dateStr = Compat.du_formatDate (license.expDate, formatter: "dd MMMM yyyy")
			Alert.ok ("Trial License Activated",
					  "Thank you! Your trial license for \(appName) has been successfully activated and is valid until \(dateStr).")
		} else {
			Alert.ok ("License Activated",
					  "Thank you! Your serial number is correct. \(appName) is now unlocked and fully registered.")
		}
	}
}
