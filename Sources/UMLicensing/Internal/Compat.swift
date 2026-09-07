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
//  Tutte le funzioni qui dentro sono state riscontrate sui sorgenti originali
//  (`UMOmniaFramework/License/license.swift`, `UMFoundation/.../stringUtils.swift`,
//  `dateUtils.swift`, `netUtils.swift`, `encapsulate.swift`): dove il commento cita
//  l'originale, è perché il comportamento è stato copiato da lì e non va "migliorato".
//

import Foundation
import CryptoKit
import IOKit


enum Compat {

	// MARK: - Hash

	/// MD5 in esadecimale minuscolo, senza separatori.
	///
	/// L'originale usa `CC_MD5` e formatta ogni byte con `%02x`: qui cambia solo
	/// l'implementazione, non l'output.
	static func racId_md5 (_ s: String) -> String {
		let digest = Insecure.MD5.hash (data: Data (s.utf8))
		return digest.map { String (format: "%02x", $0) }.joined ()
	}


	/// Estrae le sole cifre da `s` finché non raggiunge lunghezza `l`.
	///
	/// Usata per generare il validator numerico a 7 cifre dei seriali e l'unlock code
	/// a 10 cifre. Se le cifre non bastano l'originale si richiama ricorsivamente su
	/// `s`, cioè riparte dalle stesse cifre: qui il ciclo fa la stessa cosa.
	///
	/// Se in `s` non c'è nemmeno una cifra l'originale restituisce stringa vuota, non
	/// una stringa di zeri: il chiamante deve poter distinguere i due casi.
	static func racId_getNumbersToLength (s: String, l: Int) -> String {
		guard !s.isEmpty, l > 0 else { return "" }

		let digits = s.filter { $0.isNumber }
		guard !digits.isEmpty else { return "" }

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
	/// Il formato è `<label>valore</label>`, come in `encapsulateLabelStart/End`.
	static func encapsulateGetValue (srcText: String, label: String) -> String {
		strUt_getInnerText (srcText: srcText,
							prevText: "<\(label)>",
							succText: "</\(label)>")
	}


	// MARK: - Date

	/// Data in formato server: `dd/MM/yyyy`, senza orario.
	///
	/// È il formato dell'originale (`dateUtils.du_getDateString`) e non è negoziabile:
	/// entra nel validator della copia locale della licenza e in quello di `activate`,
	/// quindi un formato diverso rende illeggibili tutte le licenze già emesse e fa
	/// rifiutare le attivazioni dal server.
	///
	/// Da non confondere con `LicenseRemoteData.getDateFromServerString`, che legge
	/// `yyyy-MM-dd`: quella è l'API di amministrazione, non è questo percorso.
	static func du_getDateString (_ date: Date) -> String {
		legacyDateFormatter.string (from: date)
	}


	/// La stessa data in `yyyy-MM-dd`.
	///
	/// Serve solo a riconoscere le licenze firmate dalle prime versioni di questo
	/// package, che usavano per errore il formato ISO. Vedi `LicenseStore.load()`.
	static func du_getDateStringISO (_ date: Date) -> String {
		isoDateFormatter.string (from: date)
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


	/// Interpreta una data ricevuta dal server (`dd/MM/yyyy`).
	///
	/// Conserva la firma non opzionale dell'originale, ma per decidere se una licenza
	/// è scaduta usa `du_parseServerDate`: qui una stringa illeggibile diventa l'anno 0,
	/// cioè una data nel passato, e farebbe risultare scaduta qualunque licenza.
	static func du_createDateFormStandardString (_ s: String) -> Date {
		du_parseServerDate (s) ?? du_createDate (d: 1, m: 1, y: 2100)
	}


	/// Interpreta una data del server, `nil` se il formato non è riconoscibile.
	///
	/// L'originale leggeva a offset fissi e su una stringa fuori formato faceva
	/// `Int(...)!`, cioè crash, oppure anno 0 — una data remota nel passato, con la
	/// licenza appena attivata già scaduta. Distinguere "data assente", "data
	/// illeggibile" e "data valida" è ciò che evita quel fallimento silenzioso.
	static func du_parseServerDate (_ s: String) -> Date? {
		let trimmed = s.trimmingCharacters (in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }

		// Percorso nativo, quello di `du_createDateFormStandardString`: giorno in
		// `[0,2)`, mese in `[3,5)`, anno nelle ultime 4 cifre, cioè `dd/MM/yyyy`.
		if let date = parseLegacyStyle (trimmed) { return date }

		// Il backend di amministrazione risponde invece in `yyyy-MM-dd`.
		if let date = parseISOStyle (trimmed) { return date }

		// Formati alternativi visti in giro sui backend classic ASP/PHP a seconda
		// della locale del server.
		for format in ["dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy HH:mm",
					   "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "yyyy/MM/dd",
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


	/// `dd/MM/yyyy` letto agli offset fissi dell'originale, così accetta anche i
	/// separatori diversi dalla barra (`27-07-2026`, `27.07.2026`) esattamente come lui.
	private static func parseLegacyStyle (_ s: String) -> Date? {
		guard let d = Int (strUt_getLeft (s, n: 2)),
			  let m = Int (strUt_getSubString (srcString: s, startAt: 3, endAt: 5)),
			  let y = Int (strUt_getRight (s, n: 4)),
			  (1 ... 31).contains (d),
			  (1 ... 12).contains (m) else {
			return nil
		}

		let date = du_createDate (d: d, m: m, y: y)
		return isPlausible (date) ? date : nil
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


	/// Il formato dell'originale. Non cambiarlo: vedi `du_getDateString`.
	private static let legacyDateFormatter: DateFormatter = {
		let df = DateFormatter ()
		df.locale = Locale (identifier: "en_US_POSIX")
		df.dateFormat = "dd/MM/yyyy"
		return df
	} ()


	/// Usato solo per riconoscere le firme sbagliate delle prime versioni del package.
	private static let isoDateFormatter: DateFormatter = {
		let df = DateFormatter ()
		df.locale = Locale (identifier: "en_US_POSIX")
		df.dateFormat = "yyyy-MM-dd"
		return df
	} ()


	// MARK: - Rete

	/// Percent-encoding dei parametri in query string.
	///
	/// L'originale partiva da `.urlHostAllowed`, che lascia passare in chiaro `&` e `=`:
	/// un valore che li contenesse spezzava la query. Qui il set è ristretto, così il
	/// server riceve comunque il valore esatto una volta decodificato.
	///
	/// Il `+` va codificato a mano: percent-encoding lo considera già valido, ma chi
	/// legge la query lo interpreta come uno spazio — ed è il motivo per cui una email
	/// come `nome+tag@x.com` arrivava mutilata.
	static func netU_percEnc (_ s: String) -> String {
		let allowed = CharacterSet (charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
									+ "abcdefghijklmnopqrstuvwxyz"
									+ "0123456789-._~")
		return s.addingPercentEncoding (withAllowedCharacters: allowed) ?? s
	}


	/// MAC address dell'interfaccia di rete primaria, usato come `machId`:
	/// `aa:bb:cc:dd:ee:ff`, esadecimale minuscolo, come `netU_getMacAddress()`.
	///
	/// `machId` identifica la macchina sul server: qualunque differenza di formato fa
	/// risultare ogni utente già attivato su un'altra macchina, con conseguente
	/// "Serial number already activated".
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

		var mac: String?
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

			// L'originale non si ferma alla prima interfaccia: sovrascrive a ogni giro
			// e restituisce l'ULTIMA che risponde. Su un Mac con più di una interfaccia
			// primaria (Thunderbolt bridge, adattatori USB-Ethernet) fermarsi alla prima
			// darebbe un machId diverso da quello con cui l'utente è registrato.
			mac = data.map { String (format: "%02x", $0) }.joined (separator: ":")
		}
		return mac
	}
}
