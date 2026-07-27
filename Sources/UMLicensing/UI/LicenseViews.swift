//
//  LicenseViews.swift
//  UMLicensing
//
//  Le tre schermate del flusso di licenza, equivalenti ai vecchi d3, d4 e d8.
//

import SwiftUI


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

			VStack (spacing: 12) {
				Button {
					finish (.startTrial)
				} label: {
					ChoiceLabel (title: "Start Free Trial",
								 detail: "\(trialExpDays) days, full features. We'll email you the serial number.")
				}

				Button {
					finish (.insertSerial)
				} label: {
					ChoiceLabel (title: "I Have a Serial Number",
								 detail: "Enter the serial number you received when you purchased.")
				}
			}
			.buttonStyle (.plain)

			HStack {
				Button ("Buy a License") { open (purchaseUrl) }
					.buttonStyle (.link)

				Spacer ()

				Button ("Quit") { finish (.quit) }
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
				Button ("Back") { finish (nil) }
					.keyboardShortcut (.cancelAction)

				Spacer ()

				if confirming {
					Button ("Let Me Check Again") { confirming = false }
					Button ("Yes, That's My Email") {
						finish (TrialSignup (username: username, email: email))
					}
					.keyboardShortcut (.defaultAction)
				} else {
					Button ("Continue") { validate () }
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
	let finish: @MainActor (SerialOutcome) -> Void

	@State private var serial = ""
	@State private var connected: Bool?

	private var trimmed: String {
		serial.uppercased ().trimmingCharacters (in: .whitespacesAndNewlines)
	}

	private var valid: Bool {
		isSerialValid (trimmed)
	}

	var body: some View {
		VStack (alignment: .leading, spacing: 20) {

			LicenseHeader (appName: appName,
						   subtitle: "Enter a valid \(appName) serial number.")

			HStack (spacing: 8) {
				TextField ("XXXXX-00000000-0000000", text: $serial)
					.textFieldStyle (.roundedBorder)
					.font (.system (.body, design: .monospaced))
					.onSubmit { if valid { finish (.serial (trimmed)) } }

				Button ("Paste") {
					if let clip = SerialScanner.serialInClipboard () { serial = clip }
				}
			}

			HStack (spacing: 6) {
				Image (systemName: valid ? "checkmark.circle.fill" : "xmark.circle.fill")
				Text (valid ? "Serial number valid" : "Serial number not valid")
			}
			.font (.callout)
			.foregroundStyle (trimmed.isEmpty ? .secondary : (valid ? Color.green : Color.red))
			.opacity (trimmed.isEmpty ? 0.6 : 1)

			ConnectionIndicator (connected: connected)

			HStack {
				Button ("Buy a License") { open (purchaseUrl) }
					.buttonStyle (.link)

				Spacer ()

				Button ("Quit") { finish (.quit) }
					.keyboardShortcut (.cancelAction)

				Button ("OK") { finish (.serial (trimmed)) }
					.keyboardShortcut (.defaultAction)
					.disabled (!valid)
			}
		}
		.padding (28)
		.frame (width: 460)
		.onAppear {
			// Se il seriale è già negli appunti (arrivato via email) risparmiamo
			// all'utente la digitazione, che su 22 caratteri è la fonte di errore principale.
			if let clip = SerialScanner.serialInClipboard () { serial = clip }
		}
		.task {
			while !Task.isCancelled {
				connected = await checkConnection ()
				try? await Task.sleep (for: .seconds (5))
			}
		}
	}
}


// MARK: - Pezzi comuni

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


private struct ChoiceLabel: View {
	let title: String
	let detail: String

	var body: some View {
		VStack (alignment: .leading, spacing: 3) {
			Text (title).font (.headline)
			Text (detail).font (.callout).foregroundStyle (.secondary)
				.fixedSize (horizontal: false, vertical: true)
		}
		.frame (maxWidth: .infinity, alignment: .leading)
		.padding (14)
		.background (.quaternary.opacity (0.5), in: RoundedRectangle (cornerRadius: 10))
		.contentShape (RoundedRectangle (cornerRadius: 10))
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


@MainActor
private func open (_ urlString: String) {
	guard let url = URL (string: urlString) else { return }
	NSWorkspace.shared.open (url)
}
