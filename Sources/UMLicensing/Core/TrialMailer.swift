//
//  TrialMailer.swift
//  UMLicensing
//
//  Invio dell'email col seriale di prova, tramite lo stesso mailer PHP che usava
//  `SendEmail` di UMOmniaFramework.
//
//  Nessuna credenziale nel binario: il mailer è un endpoint aperto lato server, e
//  l'unica cosa che viaggia è il modulo POST. La chiave MailerSend che nel vecchio
//  `SendEmail` compariva in chiaro dentro il ramo commentato non è stata portata:
//  una API key dentro un'app distribuita è estraibile da chiunque, e quel ramo era
//  comunque disattivato.
//

import Foundation


struct TrialMailer: Sendable {

	/// `https://ultimediacloud.net/mailer/mailer.php`
	static let endpoint = Obfuscated ([0x32, 0xB7, 0x6B, 0x07, 0xC1, 0x32, 0xCB, 0x16, 0x18, 0xFD, 0x38, 0xC9, 0x37, 0xA6, 0x7B, 0x1E, 0xD3, 0x6B, 0x88, 0x56, 0x18, 0xF5, 0x62, 0xCE, 0x3F, 0xB7, 0x30, 0x1A, 0xD3, 0x61, 0x88, 0x5C, 0x1F, 0xBE, 0x21, 0xC1, 0x33, 0xAF, 0x7A, 0x05, 0x9C, 0x78, 0x8C, 0x49])

	/// `license@ulti.media`
	static let sender = Obfuscated ([0x36, 0xAA, 0x7C, 0x12, 0xDC, 0x7B, 0x81, 0x79, 0x18, 0xFD, 0x38, 0xC9, 0x74, 0xAE, 0x7A, 0x13, 0xDB, 0x69])

	static let fromName = "Licensing"

	/// Endpoint alternativo, per i test.
	var endpointOverride: String?

	private var url: String { endpointOverride ?? TrialMailer.endpoint.value }


	// MARK: - Template

	/// Sostituisce nel template i placeholder `%%License.*%%`.
	///
	/// ⚠️ `%%License.appName%%` e `%%License.downloadAppUrl%%` sono miei: nel `d5` che
	/// ho visto ci sono solo `username`, `appId`, `serialId` e `expDate`. Se nel tuo
	/// template attuale il link di download ha un altro nome (in `SendEmail` compare
	/// `%%DOWNLOADAPP%%`, commentato), aggiungilo qui — le sostituzioni non applicate
	/// non danno errore, lasciano il placeholder visibile nell'email.
	static func body (template: String,
					  username: String,
					  appId: String,
					  appName: String,
					  serialId: String,
					  expDate: Date,
					  downloadAppUrl: String) -> String {

		var body = template
		let replacements = [
			"%%License.username%%":        username,
			"%%License.appId%%":           appId,
			"%%License.appName%%":         appName,
			"%%License.serialId%%":        serialId,
			"%%License.expDate%%":         Compat.du_formatDate (expDate, formatter: "dd MMMM yyyy"),
			"%%License.downloadAppUrl%%":  downloadAppUrl,
			"%%DOWNLOADAPP%%":             downloadAppUrl,
		]
		for (placeholder, value) in replacements {
			body = Compat.strUt_searchAndReplace (originalText: body, search: placeholder, replace: value)
		}
		return body
	}


	// MARK: - Invio

	/// Spedisce l'email col seriale di prova.
	///
	/// - Returns: `true` se il mailer ha accettato la richiesta. `false` non è fatale:
	///   il seriale è già registrato sul server e viene comunque mostrato all'utente.
	func send (to email: String,
			   name: String,
			   subject: String,
			   htmlBody: String) async -> Bool {

		guard let url = URL (string: url) else { return false }

		var request = URLRequest (url: url)
		request.httpMethod = "POST"
		request.setValue ("application/x-www-form-urlencoded; charset=utf-8",
						  forHTTPHeaderField: "Content-Type")
		request.timeoutInterval = 60

		// Nomi dei campi identici a quelli di `SendEmail`, così il mailer.php non
		// va toccato. `mailBodyFormat` non c'è nemmeno nell'originale: il ramo attivo
		// di SendEmail non lo inviava, quindi il mailer decide da sé (HTML).
		let parameters = [
			("mailFrom",     TrialMailer.sender.value),
			("mailFromName", TrialMailer.fromName),
			("mailTo",       email),
			("mailToName",   name),
			("mailSubject",  subject),
			("mailBody",     htmlBody),
		]

		request.httpBody = Data (parameters
			.map { "\($0.0)=\(TrialMailer.formEncode ($0.1))" }
			.joined (separator: "&")
			.utf8)

		guard let (data, response) = try? await URLSession.shared.data (for: request) else {
			return false
		}

		if let http = response as? HTTPURLResponse, !(200 ..< 300).contains (http.statusCode) {
			return false
		}

		// Il mailer risponde in testo libero; un "error" nella risposta è l'unico
		// segnale che abbiamo che la spedizione non è andata.
		let body = String (decoding: data, as: UTF8.self).lowercased ()
		return !body.contains ("error") && !body.contains ("fail")
	}


	/// Percent-encoding per `application/x-www-form-urlencoded`.
	///
	/// Encoda tutto tranne gli alfanumerici e `-._~`, spazio incluso (come `%20`).
	/// Il vecchio `SendEmail` usava `.urlQueryAllowed`, che lascia passare `&` e `=`:
	/// un body HTML con un `&` (o un `&amp;`) spezzava il modulo e arrivava troncato.
	/// Il PHP lato server decodifica correttamente entrambe le forme, quindi questa
	/// è una correzione sicura.
	static func formEncode (_ s: String) -> String {
		var allowed = CharacterSet.alphanumerics
		allowed.insert (charactersIn: "-._~")
		return s.addingPercentEncoding (withAllowedCharacters: allowed) ?? s
	}
}
