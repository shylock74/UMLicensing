//
//  Compat.swift
//  UMLicensing
//
//  Reimplementazione autonoma degli helper che il vecchio codice prendeva da
//  UMOmniaFramework. Ogni funzione deve produrre output IDENTICO all'originale:
//  entrano tutte nel calcolo dei validator MD5 e nelle chiavi di storage, quindi
//  una singola differenza (maiuscole, padding, formato data) invalida le licenze
//  già emesse e fa rifiutare le richieste dal server.
//
//  ⚠️ = ipotesi da verificare contro il sorgente originale di UMOmniaFramework.
//

import Foundation
import CryptoKit
import IOKit


enum Compat {

	// MARK: - Hash

	/// MD5 in esadecimale.
	///
	/// ⚠️ Assumo hex **minuscolo** senza separatori: è l'output di `CC_MD5` formattato
	/// con `%02x`, la convenzione più comune. Se `racId_md5` usa `%02X` (maiuscolo)
	/// ogni validator cambia e nessuna licenza esistente passa più.
	static func racId_md5 (_ s: String) -> String {
		let digest = Insecure.MD5.hash (data: Data (s.utf8))
		return digest.map { String (format: "%02x", $0) }.joined ()
	}


	/// Estrae le sole cifre da `s` finché non raggiunge lunghezza `l`.
	///
	/// Usata per generare il validator numerico a 7 cifre dei seriali e l'unlock code
	/// a 10 cifre. Un hash MD5 (32 hex) contiene in media ~12 cifre, quindi per `l = 10`
	/// bastano quasi sempre; per sicurezza, se le cifre finiscono prima, l'originale
	/// deve pur fare qualcosa.
	///
	/// ⚠️ Il fallback quando le cifre non bastano è la mia ipotesi (riparte dall'inizio
	/// dell'hash finché non completa). L'alternativa plausibile è il padding con "0".
	static func racId_getNumbersToLength (s: String, l: Int) -> String {
		let digits = s.filter { $0.isNumber }
		guard digits.count < l else {
			return String (digits.prefix (l))
		}
		guard !digits.isEmpty else { return String (repeating: "0", count: l) }

		var result = digits
		while result.count < l {
			result += digits
		}
		return String (result.prefix (l))
	}


	// MARK: - Stringhe

	static func strUt_length (_ s: String) -> Int {
		s.count
	}


	/// Carattere in posizione `n` (0-based), stringa vuota se fuori range.
	static func strUt_getChar (s: String, n: Int) -> String {
		guard n >= 0, n < s.count else { return "" }
		return String (Array (s) [n])
	}


	/// I primi `n` caratteri.
	static func strUt_getLeft (_ s: String, n: Int) -> String {
		guard n > 0 else { return "" }
		return String (s.prefix (n))
	}


	/// Gli ultimi `n` caratteri.
	static func strUt_getRight (_ s: String, n: Int) -> String {
		guard n > 0 else { return "" }
		return String (s.suffix (n))
	}


	/// `s` senza i primi `n` caratteri.
	static func strUt_stripLeft (_ s: String, n: Int) -> String {
		guard n > 0 else { return s }
		return String (s.dropFirst (n))
	}


	/// `s` senza gli ultimi `n` caratteri.
	static func strUt_stripRight (_ s: String, n: Int) -> String {
		guard n > 0 else { return s }
		return String (s.dropLast (n))
	}


	/// Sottostringa `[startAt, endAt)`, 0-based.
	static func strUt_getSubString (srcString: String, startAt: Int, endAt: Int) -> String {
		let chars = Array (srcString)
		guard startAt >= 0, startAt < chars.count, endAt > startAt else { return "" }
		return String (chars [startAt ..< min (endAt, chars.count)])
	}


	/// Posizione (0-based) della `recurrence`-esima occorrenza di `subString`,
	/// cercando da `startAt`. `-1` se non trovata.
	///
	/// `recurrence` è 0-based: `0` = prima occorrenza, `1` = seconda. Dedotto da
	/// `validateSerial`, che con `recurrence: 1` sul seriale `AB12F-00000001-1234567`
	/// deve ottenere 14, cioè il secondo trattino.
	static func strUt_position (srcText: String, subString: String, startAt: Int, recurrence: Int) -> Int {
		guard !subString.isEmpty else { return -1 }
		let chars = Array (srcText)
		let needle = Array (subString)
		guard startAt >= 0, chars.count >= needle.count else { return -1 }

		var found = -1
		var i = startAt
		while i <= chars.count - needle.count {
			if Array (chars [i ..< i + needle.count]) == needle {
				found += 1
				if found == recurrence { return i }
				i += needle.count
			} else {
				i += 1
			}
		}
		return -1
	}


	static func strUt_searchAndReplace (originalText: String, search: String, replace: String) -> String {
		originalText.replacingOccurrences (of: search, with: replace)
	}


	/// `n` come stringa, allineata a destra e riempita di zeri fino a `padN` cifre.
	static func strUt_padN (n: Int, padN: Int) -> String {
		let s = String (n)
		guard s.count < padN else { return s }
		return String (repeating: "0", count: padN - s.count) + s
	}


	/// Testo racchiuso fra `prevText` e `succText`, vuoto se non trovato.
	static func strUt_getInnerText (srcText: String, prevText: String, succText: String) -> String {
		guard let start = srcText.range (of: prevText) else { return "" }
		let rest = srcText [start.upperBound...]
		guard let end = rest.range (of: succText) else { return "" }
		return String (rest [..<end.lowerBound])
	}


	// MARK: - Protocollo di risposta del server

	/// Estrae il valore di un campo dalla risposta del server.
	///
	/// ⚠️ Assumo il formato `<label>valore</label>`. Se il server usa un delimitatore
	/// diverso (`[label]...[/label]`, `label={...}`, ecc.) va corretto qui: da questa
	/// funzione dipendono `errorCode`, `data`, `validator`, `released`, quindi
	/// sbagliarla significa che ogni attivazione fallisce silenziosamente.
	static func encapsulateGetValue (srcText: String, label: String) -> String {
		strUt_getInnerText (srcText: srcText,
							prevText: "<\(label)>",
							succText: "</\(label)>")
	}


	// MARK: - Date

	/// Data in formato server.
	///
	/// ⚠️ `LicenseRemoteData.getDateFromServerString` legge anno da `[0,4)`, mese da
	/// `[5,7)`, giorno da `[8,10)`, quindi il prefisso è certo: `yyyy-MM-dd`. Resta da
	/// confermare se `du_getDateString` accoda anche l'orario (`HH:mm:ss`) — il server
	/// riceve questa stringa in `expDate`, e nel validator di `activate` ci finisce
	/// dentro, quindi la differenza conta.
	static func du_getDateString (_ date: Date) -> String {
		serverDateFormatter.string (from: date)
	}


	static func du_formatDate (_ date: Date, formatter: String) -> String {
		let df = DateFormatter ()
		df.locale = Locale (identifier: "en_US_POSIX")
		df.dateFormat = formatter
		return df.string (from: date)
	}


	static func du_createDate (d: Int, m: Int, y: Int) -> Date {
		var components = DateComponents ()
		components.year = y
		components.month = m
		components.day = d
		return calendar.date (from: components) ?? Date ()
	}


	/// Interpreta una data ricevuta dal server (`yyyy-MM-dd`, con o senza orario).
	///
	/// Conserva la firma non opzionale dell'originale, ma per decidere se una licenza
	/// è scaduta usa `du_parseServerDate`: qui una stringa illeggibile diventa l'anno 0,
	/// cioè una data nel passato, e farebbe risultare scaduta qualunque licenza.
	static func du_createDateFormStandardString (_ s: String) -> Date {
		du_parseServerDate (s) ?? du_createDate (d: 1, m: 1, y: 2100)
	}


	/// Interpreta una data del server, `nil` se il formato non è riconoscibile.
	///
	/// L'originale leggeva a offset fissi assumendo `yyyy-MM-dd`: qualunque altro
	/// formato produceva `Int("27/0") ?? 0`, cioè anno 0. Una licenza appena attivata
	/// risultava così immediatamente scaduta. Distinguere "data assente", "data
	/// illeggibile" e "data valida" è ciò che evita quel fallimento silenzioso.
	static func du_parseServerDate (_ s: String) -> Date? {
		let trimmed = s.trimmingCharacters (in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }

		// Percorso nativo: `yyyy-MM-dd` eventualmente seguito da un orario.
		if let date = parseISOStyle (trimmed) { return date }

		// Formati alternativi visti in giro sui backend classic ASP/PHP a seconda
		// della locale del server.
		for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "yyyy/MM/dd",
					   "dd-MM-yyyy", "dd/MM/yyyy", "MM/dd/yyyy",
					   "M/d/yyyy", "d/M/yyyy"] {
			let df = DateFormatter ()
			df.locale = Locale (identifier: "en_US_POSIX")
			df.calendar = calendar
			df.dateFormat = format
			if let date = df.date (from: trimmed), isPlausible (date) {
				return date
			}
		}
		return nil
	}


	private static func parseISOStyle (_ s: String) -> Date? {
		let y = Int (strUt_getSubString (srcString: s, startAt: 0, endAt: 4))
		let m = Int (strUt_getSubString (srcString: s, startAt: 5, endAt: 7))
		let d = Int (strUt_getSubString (srcString: s, startAt: 8, endAt: 10))

		guard let y, let m, let d,
			  strUt_getChar (s: s, n: 4) == "-",
			  (1 ... 12).contains (m),
			  (1 ... 31).contains (d) else {
			return nil
		}

		let date = du_createDate (d: d, m: m, y: y)
		return isPlausible (date) ? date : nil
	}


	/// Filtro di sanità: una data di licenza sta fra il 2000 e il 2200. Fuori da lì
	/// è quasi certamente il risultato di un parsing andato storto.
	static func isPlausible (_ date: Date) -> Bool {
		let year = calendar.component (.year, from: date)
		return (2000 ... 2200).contains (year)
	}


	static func du_getDatePlusDays (date: Date, days: Int) -> Date {
		calendar.date (byAdding: .day, value: days, to: date) ?? date
	}


	/// Giorni interi da `firstDate` a `secondDate`. Negativo se `secondDate` è passata.
	static func du_getDeltaDate (firstDate: Date, secondDate: Date) -> Int {
		calendar.dateComponents ([.day],
								 from: calendar.startOfDay (for: firstDate),
								 to: calendar.startOfDay (for: secondDate)).day ?? 0
	}


	private static let calendar: Calendar = {
		var c = Calendar (identifier: .gregorian)
		c.locale = Locale (identifier: "en_US_POSIX")
		return c
	} ()


	private static let serverDateFormatter: DateFormatter = {
		let df = DateFormatter ()
		df.locale = Locale (identifier: "en_US_POSIX")
		df.dateFormat = "yyyy-MM-dd"      // ⚠️ verificare se serve " HH:mm:ss"
		return df
	} ()


	// MARK: - Rete

	/// Percent-encoding dei parametri in query string.
	static func netU_percEnc (_ s: String) -> String {
		s.addingPercentEncoding (withAllowedCharacters: .alphanumerics) ?? s
	}


	/// MAC address dell'interfaccia di rete primaria, usato come `machId`.
	///
	/// ⚠️ Questo è il punto più delicato del port: `machId` identifica la macchina
	/// sul server. Se il formato differisce da quello di `netU_getMacAddress()`
	/// (maiuscolo/minuscolo, separatore `:` o `-`, presenza dei due punti) ogni utente
	/// già attivato risulta su una macchina diversa e si vede rifiutare la licenza con
	/// "Serial number already activated". Qui assumo `aa:bb:cc:dd:ee:ff` minuscolo.
	static func netU_getMacAddress () -> String {
		guard let mac = primaryMACAddress () else { return "" }
		return mac
	}


	private static func primaryMACAddress () -> String? {
		let matching = IOServiceMatching ("IOEthernetInterface") as NSMutableDictionary
		matching [kIOPropertyMatchKey] = ["IOPrimaryInterface": true] as NSDictionary

		var iterator: io_iterator_t = 0
		guard IOServiceGetMatchingServices (kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
			return nil
		}
		defer { IOObjectRelease (iterator) }

		var service = IOIteratorNext (iterator)
		while service != 0 {
			defer {
				IOObjectRelease (service)
				service = IOIteratorNext (iterator)
			}

			var parent: io_object_t = 0
			guard IORegistryEntryGetParentEntry (service, kIOServicePlane, &parent) == KERN_SUCCESS else {
				continue
			}
			defer { IOObjectRelease (parent) }

			guard let data = IORegistryEntryCreateCFProperty (parent,
															 "IOMACAddress" as CFString,
															 kCFAllocatorDefault,
															 0)?.takeRetainedValue () as? Data,
				  data.count == 6 else {
				continue
			}

			return data.map { String (format: "%02x", $0) }.joined (separator: ":")
		}
		return nil
	}
}
