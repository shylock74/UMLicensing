//
//  Alert.swift
//  UMLicensing
//

import AppKit


@MainActor
enum Alert {

	/// Come per le finestre di licenza: un alert modale creato mentre l'utente è in
	/// un'app a tutto schermo resta nella Space dell'app e non lo vede nessuno, mentre
	/// `runModal` blocca comunque il flusso. Da fuori sembra che l'app non faccia niente.
	private static func showInActiveSpace (_ alert: NSAlert) -> NSApplication.ModalResponse {
		alert.window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
		NSApp.activate (ignoringOtherApps: true)
		return alert.runModal ()
	}

	static func ok (_ message: String, _ informative: String) {
		let alert = NSAlert ()
		alert.messageText     = message
		alert.informativeText = informative
		alert.alertStyle      = .warning
		alert.addButton (withTitle: "OK")
		Diagnostics.trace ("alert: \(message) — \(informative.replacingOccurrences (of: "\n", with: " / "))")
		_ = showInActiveSpace (alert)
	}


	/// `true` se l'utente sceglie il primo pulsante.
	static func twoButtons (_ message: String,
							_ informative: String,
							first: String,
							second: String) -> Bool {
		let alert = NSAlert ()
		alert.messageText     = message
		alert.informativeText = informative
		alert.alertStyle      = .warning
		alert.addButton (withTitle: first)
		alert.addButton (withTitle: second)
		Diagnostics.trace ("alert a due pulsanti: \(message) [\(first) | \(second)]")

		let answer = showInActiveSpace (alert) == .alertFirstButtonReturn
		Diagnostics.trace ("alert: scelto \(answer ? first : second)")
		return answer
	}
}
