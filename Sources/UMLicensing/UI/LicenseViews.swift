//
//  LicenseViews.swift
//  UMLicensing
//
//  Le tre schermate del flusso di licenza, equivalenti ai vecchi d3, d4 e d8.
//
//  I pulsanti sono tutti `UMUICapsuleButton`: le finestre di licenza sono la prima
//  cosa che l'utente vede dell'app, e con i pulsanti di sistema stonavano col resto
//  delle interfacce. Azione primaria in `.accent`, tutto il resto in `.gray`.
//

import SwiftUI
import UMUIControls


// MARK: - d3: scelta iniziale

/// Cosa ha scelto l'utente nella schermata iniziale.
enum ChooseOutcome: Sendable {
	case startTrial
	case insertSerial
	case quit
}


struct ChooseLicenseView: View {

	let appName: String
	let trialExpDays: Int
	let purchaseUrl: String
	let finish: @MainActor (ChooseOutcome) -> Void

	var body: some View {
		VStack (spacing: 24) {

			LicenseHeader (appName: appName, subtitle: "This copy is not registered yet.")

			VStack (alignment: .leading, spacing: 18) {
				ChoiceRow (title: "Start Free Trial",
						   detail: "\(trialExpDays) days, full features. We'll email you the serial number.") {
					finish (.startTrial)
				}

				ChoiceRow (title: "I Have a Serial Number",
						   detail: "Enter the serial number you received when you purchased.") {
					finish (.insertSerial)
				}
			}
			.frame (maxWidth: .infinity, alignment: .leading)

			HStack {
				UMUICapsuleButton ("Buy a License", style: .gray, size: .normal) { open (purchaseUrl) }

				Spacer ()

				UMUICapsuleButton ("Quit", style: .gray, size: .normal) { finish (.quit) }
					.keyboardShortcut (.cancelAction)
			}
		}
		.padding (28)
		.frame (width: 460)
	}
}


// MARK: - d4: nome ed email per il trial

/// Dati raccolti per emettere il trial, o `nil` se l'utente torna indietro.
struct TrialSignup: Sendable {
	var username: String
	var email: String
}


struct TrialSignupView: View {

	let appName: String
	let trialExpDays: Int
	let finish: @MainActor (TrialSignup?) -> Void

	@State private var username = ""
	@State private var email = ""
	@State private var confirming = false
	@State private var error: String?

	private var expiryText: String {
		Compat.du_formatDate (Compat.du_getDatePlusDays (date: Date (), days: trialExpDays),
							  formatter: "dd MMMM yyyy")
	}

	var body: some View {
		VStack (alignment: .leading, spacing: 20) {

			LicenseHeader (appName: appName,
						   subtitle: "Your trial will expire on \(expiryText).")

			VStack (alignment: .leading, spacing: 10) {
				LabeledField (label: "Name",  text: $username)
				LabeledField (label: "Email", text: $email)
			}

			if let error {
				Label (error, systemImage: "exclamationmark.triangle.fill")
					.foregroundStyle (.red)
					.font (.callout)
			}

			// L'email è l'unico modo che l'utente ha di riavere il seriale:
			// una conferma esplicita costa poco e evita gran parte delle richieste di supporto.
			if confirming {
				Text ("""
					The serial number will be sent to **\(email)**.
					If it doesn't arrive within a few minutes, check your spam folder.
					""")
					.font (.callout)
					.foregroundStyle (.secondary)
					.fixedSize (horizontal: false, vertical: true)
			}

			HStack {
				UMUICapsuleButton ("Back", style: .gray, size: .normal) { finish (nil) }
					.keyboardShortcut (.cancelAction)

				Spacer ()

				if confirming {
					UMUICapsuleButton ("Let Me Check Again", style: .gray, size: .normal) {
						confirming = false
					}

					UMUICapsuleButton ("Yes, That's My Email", style: .accent, size: .normal) {
						finish (TrialSignup (username: username, email: email))
					}
					.keyboardShortcut (.defaultAction)
				} else {
					UMUICapsuleButton ("Continue", style: .accent, size: .normal) { validate () }
						.keyboardShortcut (.defaultAction)
				}
			}
		}
		.padding (28)
		.frame (width: 460)
	}


	private func validate () {
		let name  = username.trimmingCharacters (in: .whitespacesAndNewlines)
		let mail  = email.trimmingCharacters (in: .whitespacesAndNewlines)

		if name.isEmpty                     { error = "Please enter your name."; return }
		if mail.isEmpty                     { error = "Please enter your email."; return }
		if !EmailValidator.isValid (mail)   { error = "That doesn't look like a valid email address."; return }

		username   = name
		email      = mail
		error      = nil
		confirming = true
	}
}


// MARK: - d8: inserimento seriale

/// Esito della schermata del seriale.
enum SerialOutcome: Sendable {
	case serial (String)
	case quit
}


struct InsertSerialView: View {

	let appName: String
	let purchaseUrl: String
	let isSerialValid: @Sendable (String) -> Bool
	let checkConnection: @Sendable () async -> Bool
	/// Cerca il seriale nel database del server. Le cifre di controllo dicono solo che
	/// il seriale è ben formato, non che esista davvero.
	let lookUpSerial: @Sendable (String) async -> LicenseServer.SerialLookup
	let finish: @MainActor (SerialOutcome) -> Void

	@State private var serial = ""
	@State private var connected: Bool?
	@State private var lookup: LicenseServer.SerialLookup?
	@State private var checking = false

	private var trimmed: String {
		serial.uppercased ().trimmingCharacters (in: .whitespacesAndNewlines)
	}

	private var valid: Bool {
		isSerialValid (trimmed)
	}

	/// I trial se li genera il client e li carica lui sul server: se uno non risulta nel
	/// database può essere semplicemente un caricamento fallito, e `activate()` lo
	/// registra da sé. Per tutti gli altri tipi un seriale assente non è mai stato
	/// venduto, quindi non deve poter proseguire.
	private var isTrial: Bool {
		licenseType (serialId: trimmed) == .trial
	}

	private var notInDatabase: Bool {
		valid && !isTrial && lookup == .notFound
	}

	var body: some View {
		VStack (alignment: .leading, spacing: 20) {

			LicenseHeader (appName: appName,
						   subtitle: "Enter a valid \(appName) serial number.")

			HStack (spacing: 8) {
				TextField ("XXXXX-00000000-0000000", text: $serial)
					.textFieldStyle (.roundedBorder)
					.font (.system (.body, design: .monospaced))
					.onSubmit { if valid, !checking, !notInDatabase { finish (.serial (trimmed)) } }

				UMUICapsuleButton ("Paste", style: .gray, size: .normal) {
					if let clip = SerialScanner.serialInClipboard () { serial = clip }
				}
			}

			SerialStatus (state: statusState)

			ConnectionIndicator (connected: connected)

			HStack {
				UMUICapsuleButton ("Buy a License", style: .gray, size: .normal) { open (purchaseUrl) }

				Spacer ()

				UMUICapsuleButton ("Quit", style: .gray, size: .normal) { finish (.quit) }
					.keyboardShortcut (.cancelAction)

				UMUICapsuleButton ("OK", style: .accent, size: .normal) { finish (.serial (trimmed)) }
					.keyboardShortcut (.defaultAction)
					.capsuleEnabled (valid && !checking && !notInDatabase)
			}
		}
		.padding (28)
		.frame (width: 460)
		.onAppear {
			// Se il seriale è già negli appunti (arrivato via email) risparmiamo
			// all'utente la digitazione, che su 22 caratteri è la fonte di errore principale.
			if let clip = SerialScanner.serialInClipboard () { serial = clip }
		}
		.task (id: trimmed) {
			lookup   = nil
			checking = false
			guard valid else { return }

			// Mezzo secondo di attesa: senza, il server viene interrogato a ogni tasto
			// premuto mentre l'utente digita il seriale.
			// `Task.sleep (for:)` richiede macOS 13: qui si resta sulla variante in
			// nanosecondi, disponibile da macOS 10.15, perché il package deve linkare
			// anche nelle app ancora ferme a Big Sur.
			try? await Task.sleep (nanoseconds: 500_000_000)
			guard !Task.isCancelled else { return }

			checking = true
			let result = await lookUpSerial (trimmed)
			guard !Task.isCancelled else { return }

			lookup   = result
			checking = false
		}
		.task {
			while !Task.isCancelled {
				connected = await checkConnection ()
				try? await Task.sleep (nanoseconds: 5_000_000_000)
			}
		}
	}


	private var statusState: SerialStatus.State {
		if trimmed.isEmpty          { return .empty }
		if !valid                   { return .malformed }
		if checking                 { return .checking }
		if notInDatabase            { return .notInDatabase }
		return .ok
	}
}


// MARK: - Pezzi comuni

/// La riga sotto il campo del seriale. Distingue tre cose che l'utente confonde
/// facilmente: seriale scritto male, seriale ben scritto ma sconosciuto al server,
/// seriale buono.
private struct SerialStatus: View {

	enum State {
		case empty
		case malformed
		case checking
		case notInDatabase
		case ok
	}

	let state: State

	var body: some View {
		VStack (alignment: .leading, spacing: 2) {
			HStack (spacing: 6) {
				Image (systemName: icon)
				Text (text)
			}
			.font (.callout)
			.foregroundStyle (color)

			if state == .notInDatabase {
				Text ("This serial number is not in the licensing database.")
					.font (.caption)
					.foregroundStyle (.secondary)
			}
		}
		.opacity (state == .empty ? 0.6 : 1)
		.frame (maxWidth: .infinity, alignment: .leading)
	}


	private var icon: String {
		switch state {
			case .empty, .malformed:  return "xmark.circle.fill"
			case .checking:           return "ellipsis.circle"
			case .notInDatabase:      return "exclamationmark.triangle.fill"
			case .ok:                 return "checkmark.circle.fill"
		}
	}


	private var text: String {
		switch state {
			case .empty, .malformed:  return "Serial number not valid"
			case .checking:           return "Checking the serial number…"
			case .notInDatabase:      return "Errore: DNF ⚠️"
			case .ok:                 return "Serial number valid"
		}
	}


	private var color: Color {
		switch state {
			case .empty, .checking:          return .secondary
			case .malformed, .notInDatabase: return .red
			case .ok:                        return .green
		}
	}
}


private struct LicenseHeader: View {
	let appName: String
	let subtitle: String

	var body: some View {
		VStack (alignment: .leading, spacing: 4) {
			Text (appName)
				.font (.title2.weight (.semibold))
			Text (subtitle)
				.foregroundStyle (.secondary)
				.fixedSize (horizontal: false, vertical: true)
		}
		.frame (maxWidth: .infinity, alignment: .leading)
	}
}


/// Una delle due scelte della prima schermata: il pulsante, e sotto la riga che
/// spiega cosa succede premendolo.
private struct ChoiceRow: View {
	let title: String
	let detail: String
	let action: @MainActor () -> Void

	var body: some View {
		VStack (alignment: .leading, spacing: 6) {
			UMUICapsuleButton (title, style: .accent, size: .normal) { action () }

			Text (detail)
				.font (.callout)
				.foregroundStyle (.secondary)
				.fixedSize (horizontal: false, vertical: true)
		}
		.frame (maxWidth: .infinity, alignment: .leading)
	}
}


private struct LabeledField: View {
	let label: String
	@Binding var text: String

	var body: some View {
		HStack {
			Text (label)
				.frame (width: 60, alignment: .trailing)
				.foregroundStyle (.secondary)
			TextField ("", text: $text)
				.textFieldStyle (.roundedBorder)
		}
	}
}


private struct ConnectionIndicator: View {
	let connected: Bool?

	var body: some View {
		HStack (spacing: 6) {
			Circle ()
				.fill (connected == true ? Color.green : (connected == nil ? Color.secondary : Color.red))
				.frame (width: 7, height: 7)
			Text (connected == true
				  ? "Connected to licensing server"
				  : (connected == nil ? "Checking licensing server…" : "Not connected to licensing server"))
		}
		.font (.caption)
		.foregroundStyle (.secondary)
	}
}


private extension View {

	/// `UMUICapsuleButton` disegna sé stesso con un `ButtonStyle` proprio, e SwiftUI
	/// non lo attenua quando è disabilitato: senza questo, "OK" resterebbe acceso e
	/// invitante anche quando premerlo non fa niente.
	func capsuleEnabled (_ enabled: Bool) -> some View {
		self
			.disabled (!enabled)
			.saturation (enabled ? 1 : 0)
			.opacity (enabled ? 1 : 0.45)
	}
}


@MainActor
private func open (_ urlString: String) {
	guard let url = URL (string: urlString) else { return }
	NSWorkspace.shared.open (url)
}
