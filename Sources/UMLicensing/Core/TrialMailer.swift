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

import AppKit
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

	/// Il template incluso nel package (`MailTemplate.txt`).
	///
	/// È il default per tutte le app. Chi ne vuole uno diverso passa `mailBody`
	/// a `licensed()`.
	static func defaultTemplate () -> String {
		guard let url = Bundle.module.url (forResource: "MailTemplate", withExtension: "txt"),
			  let text = try? String (contentsOf: url, encoding: .utf8) else {
			return ""
		}
		return text
	}


	/// I valori che riempiono i `%%…%%` del template.
	struct Fields: Sendable {
		var username:       String
		var appId:          String
		var appName:        String
		var serialId:       String
		var expDate:        Date
		var downloadAppUrl: String
		var logoImageUrl:   String
		var logoImageAlt:   String
		/// Componenti nella forma `15, 23, 42`: il template le usa dentro `rgb(…)`.
		var backgroundRGB:  String
		var accentRGB:      String
	}


	/// Sostituisce nel template tutti i placeholder `%%…%%`.
	///
	/// `%%BUILD%%` e `%%YEAR%%` non sono parametri: vengono da `Bundle.main` e
	/// dalla data corrente, così non c'è modo di dimenticarsi di aggiornarli.
	static func body (template: String, fields f: Fields) -> String {

		var body = template

		// Un logo con src vuoto viene disegnato dai client email come icona rotta.
		// Meglio togliere l'intero blocco che spedire un'email visibilmente difettosa.
		if f.logoImageUrl.isEmpty {
			body = removingLogoBlock (from: body)
		}

		let replacements = [
			// Nomi usati da MailTemplate.txt
			"%%License.username%%":  f.username,
			"%%License.serialId%%":  f.serialId,
			"%%License.expDate%%":   Compat.du_formatDate (f.expDate, formatter: "dd MMMM yyyy"),
			"%%APPNAME%%":           f.appName,
			"%%DOWNLOADAPP%%":       f.downloadAppUrl,
			"%%LogoImageUrl%%":      f.logoImageUrl,
			"%%LogoImageAlt%%":      f.logoImageAlt.isEmpty ? f.appName : f.logoImageAlt,
			"%%BG_RGB%%":            f.backgroundRGB,
			"%%ACCENT_RGB%%":        f.accentRGB,
			"%%BUILD%%":             currentBuild (),
			"%%YEAR%%":              currentYear (),

			// Nomi del vecchio `d5`, tenuti per i template già in circolazione.
			"%%License.appId%%":          f.appId,
			"%%License.appName%%":        f.appName,
			"%%License.downloadAppUrl%%": f.downloadAppUrl,
		]

		for (placeholder, value) in replacements {
			body = Compat.strUt_searchAndReplace (originalText: body, search: placeholder, replace: value)
		}
		return body
	}


	/// Rimuove il `<div>` che avvolge `<img src="%%LogoImageUrl%%">`.
	private static func removingLogoBlock (from template: String) -> String {
		guard let imgRange = template.range (of: "%%LogoImageUrl%%"),
			  let divStart = template.range (of: "<div", options: .backwards, range: template.startIndex ..< imgRange.lowerBound),
			  let divEnd = template.range (of: "</div>", range: imgRange.upperBound ..< template.endIndex) else {
			return template
		}
		return template.replacingCharacters (in: divStart.lowerBound ..< divEnd.upperBound, with: "")
	}


	// MARK: - Valori automatici

	/// Versione commerciale e numero di build, es. `2.1.0 (1234)`.
	///
	/// È la coppia che serve al supporto: la prima dice all'utente cosa ha comprato,
	/// la seconda identifica il binario esatto.
	static func currentBuild (bundle: Bundle = .main) -> String {
		let info = bundle.infoDictionary
		let short = info? ["CFBundleShortVersionString"] as? String ?? ""
		let build = info? ["CFBundleVersion"] as? String ?? ""

		switch (short.isEmpty, build.isEmpty) {
			case (false, false): return "\(short) (\(build))"
			case (false, true):  return short
			case (true, false):  return build
			case (true, true):   return "-"
		}
	}


	static func currentYear (date: Date = Date ()) -> String {
		Compat.du_formatDate (date, formatter: "yyyy")
	}


	/// Componenti sRGB nella forma `15, 23, 42`, pronte per finire dentro `rgb(…)`
	/// e `rgba(…, 0.7)` del template.
	///
	/// La conversione a sRGB è necessaria perché un `NSColor` preso dagli Assets può
	/// essere in un altro color space (o essere dinamico light/dark): senza conversione
	/// `redComponent` va in crash.
	@MainActor
	static func rgbComponents (_ color: NSColor) -> String {
		guard let c = color.usingColorSpace (.sRGB) else { return "0, 0, 0" }

		let r = Int ((c.redComponent   * 255).rounded ())
		let g = Int ((c.greenComponent * 255).rounded ())
		let b = Int ((c.blueComponent  * 255).rounded ())
		return "\(r), \(g), \(b)"
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
