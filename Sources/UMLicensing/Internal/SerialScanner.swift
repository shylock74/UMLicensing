//
//  SerialScanner.swift
//  UMLicensing
//

import AppKit
import Foundation


enum SerialScanner {

	/// Il vecchio codice aveva due regex in disaccordo fra loro (`[0-9]{7}-[0-9]{8}`
	/// in `snRegex`, `[0-9]{8}-[0-9]{7}` in `foundSNs`). Quella giusta è la seconda:
	/// `generateSN` produce 8 cifre di progressivo e 7 di validator.
	///
	/// Il prefisso è `[A-Z0-9]{4}` invece di `[A-Z]{2}[0-9]{2}`: alcuni appShortId
	/// potrebbero non seguire quello schema, e una regex troppo stretta farebbe fallire
	/// il Paste senza spiegare perché.
	private static let pattern = "[A-Z0-9]{4}[A-Z]-[0-9]{8}-[0-9]{7}"


	/// Tutti i seriali distinti presenti nel testo, nell'ordine in cui compaiono.
	static func serials (in text: String) -> [String] {
		let upper = text.uppercased ()
		guard let regex = try? NSRegularExpression (pattern: pattern) else { return [] }

		let range = NSRange (upper.startIndex ..< upper.endIndex, in: upper)
		var found: [String] = []

		for match in regex.matches (in: upper, range: range) {
			guard let r = Range (match.range, in: upper) else { continue }
			let s = String (upper [r])
			if !found.contains (s) { found.append (s) }
		}
		return found
	}


	/// Il primo seriale trovato negli appunti, se c'è.
	@MainActor
	static func serialInClipboard () -> String? {
		guard let text = NSPasteboard.general.string (forType: .string) else { return nil }
		return serials (in: text).first
	}
}


enum EmailValidator {

	/// Stessa regex del vecchio `validateEmail`.
	static func isValid (_ email: String) -> Bool {
		let format = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
		return NSPredicate (format: "SELF MATCHES %@", format).evaluate (with: email)
	}
}
