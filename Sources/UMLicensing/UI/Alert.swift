//
//  Alert.swift
//  UMLicensing
//

import AppKit


@MainActor
enum Alert {

	static func ok (_ message: String, _ informative: String) {
		let alert = NSAlert ()
		alert.messageText     = message
		alert.informativeText = informative
		alert.alertStyle      = .warning
		alert.addButton (withTitle: "OK")
		NSApp.activate (ignoringOtherApps: true)
		alert.runModal ()
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
		NSApp.activate (ignoringOtherApps: true)
		return alert.runModal () == .alertFirstButtonReturn
	}
}
