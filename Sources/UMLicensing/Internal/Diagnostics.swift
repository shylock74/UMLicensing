//
//  Diagnostics.swift
//  UMLicensing
//
//  Log diagnostico spento di default.
//
//  Serve quando una licenza viene rifiutata e non è chiaro perché: il formato delle
//  risposte del server è ancora un'ipotesi (vedi i `⚠️` in Compat.swift), e senza
//  vedere la risposta grezza si va a tentativi.
//
//  Attivazione, senza ricompilare:
//      defaults write <bundle-id> UMLicensing.debug -bool YES
//  oppure lanciando l'app con la variabile d'ambiente UMLICENSING_DEBUG=1.
//

import Foundation
import os


enum Diagnostics {

	private static let logger = Logger (subsystem: "media.ulti.UMLicensing", category: "licensing")

	static var isEnabled: Bool {
		UserDefaults.standard.bool (forKey: "UMLicensing.debug")
			|| ProcessInfo.processInfo.environment ["UMLICENSING_DEBUG"] == "1"
	}


	static func log (_ message: @autoclosure () -> String) {
		guard isEnabled else { return }
		let text = message ()
		logger.debug ("\(text, privacy: .public)")
		print ("[UMLicensing] \(text)")
	}


	/// Registra una risposta del server per intero.
	///
	/// Utile per capire se `encapsulateGetValue` sta leggendo il formato giusto: se i
	/// campi risultano vuoti ma la risposta non lo è, il delimitatore assunto è sbagliato.
	static func logResponse (_ action: String, _ response: String) {
		guard isEnabled else { return }
		log ("risposta a \"\(action)\" (\(response.count) caratteri):\n\(response)")
	}
}
