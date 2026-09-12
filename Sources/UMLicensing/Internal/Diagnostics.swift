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
//  `trace` è la terza via: esce sempre nelle build Debug e sparisce del tutto in Release,
//  perché il compilatore non ne vede nemmeno la chiamata. Serve a seguire il flusso mentre
//  si sviluppa senza doversi ricordare di accendere un flag.
//

import Foundation
import os


enum Diagnostics {

	private static let logger = Logger (subsystem: "media.ulti.UMLicensing", category: "licensing")

	/// Attivazione da codice, per chi non vuole passare da `defaults write`:
	/// `UMLicensing.verboseLogging = true` prima di chiamare `licensed()`.
	nonisolated(unsafe) static var forceEnabled = false

	/// In Debug il log dettagliato è acceso e basta: chi sta sviluppando vuole vedere
	/// lo scambio col server senza prima ricordarsi di un flag. In Release resta spento
	/// finché non lo si accende esplicitamente.
	static let isDebugBuild: Bool = {
		#if DEBUG
		return true
		#else
		return false
		#endif
	} ()


	static var isEnabled: Bool {
		isDebugBuild
			|| forceEnabled
			|| UserDefaults.standard.bool (forKey: "UMLicensing.debug")
			|| ProcessInfo.processInfo.environment ["UMLICENSING_DEBUG"] == "1"
	}


	static func log (_ message: @autoclosure () -> String) {
		guard isEnabled else { return }
		emit (message ())
	}


	/// Traccia di un'operazione, visibile solo nelle build Debug.
	///
	/// A differenza di `log` non guarda nessun flag: in Debug si vuole vedere cosa succede
	/// senza preparare niente. In Release l'intero corpo — e il costo di comporre la
	/// stringa — non esiste, quindi si può chiamare anche nei percorsi caldi.
	static func trace (_ message: @autoclosure () -> String) {
		#if DEBUG
		emit (message ())
		#endif
	}


	/// Scrive su `os.Logger` e su stdout.
	///
	/// `fflush` non è decorativo: quando stdout non è un terminale — la console di Xcode,
	/// o un log rediretto su file — è bufferizzato a blocchi, e le ultime righe prima di
	/// un blocco o di una `terminate` non arrivano mai. Proprio le righe che servono.
	private static func emit (_ text: String) {
		logger.debug ("\(text, privacy: .public)")
		print ("[UMLicensing] \(text)")
		fflush (stdout)
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
		fflush (stdout)

		guard isEnabled, !detail.isEmpty else { return }
		log ("\(code.display) dettaglio: \(detail)")
	}
}
