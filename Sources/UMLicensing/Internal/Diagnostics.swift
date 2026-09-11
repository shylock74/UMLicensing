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
//  oppure lanciando l'app con la variabile d'ambiente UMLICENSING_DEBUG=1,
//  oppure da codice con `UMLicensing.verboseLogging = true`.
//
//  I codici diagnostici (`diagnose`) fanno eccezione e vengono sempre stampati: senza,
//  di un problema in campo non resta traccia da nessuna parte.
//

import Foundation
import os


enum Diagnostics {

	private static let logger = Logger (subsystem: "media.ulti.UMLicensing", category: "licensing")

	/// Attivazione da codice, per chi non vuole passare da `defaults write`:
	/// `UMLicensing.verboseLogging = true` prima di chiamare `licensed()`.
	nonisolated(unsafe) static var forceEnabled = false

	static var isEnabled: Bool {
		forceEnabled
			|| UserDefaults.standard.bool (forKey: "UMLicensing.debug")
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
	static func logResponse (_ action: String, _ response: String, status: Int = 0) {
		guard isEnabled else { return }
		let http = status == 0 ? "" : " HTTP \(status)"
		log ("risposta a \"\(action)\"\(http) (\(response.count) caratteri):\n\(response)")
	}


	/// Registra un codice diagnostico.
	///
	/// A differenza di `log`, questo esce **sempre** su `os.Logger`: il codice è la sola
	/// cosa che si riesce a farsi dire da un utente al telefono, e chiedergli prima di
	/// attivare il debug e riprodurre il problema non è realistico. Il dettaglio — che
	/// può contenere la risposta grezza — resta invece dietro il flag.
	static func diagnose (_ code: UMLicensingCode, _ action: String, _ detail: String = "") {
		logger.error ("\(code.display, privacy: .public) \(action, privacy: .public): \(code.text, privacy: .public)")
		print ("[UMLicensing] \(code.display) \(action): \(code.text)")

		guard isEnabled, !detail.isEmpty else { return }
		log ("\(code.display) dettaglio: \(detail)")
	}
}
