//
//  MailColors.swift
//  UMLicensing
//
//  Colori di default dell'email del trial, allineati al resto di MailTemplate.txt:
//  il template ha testo chiaro (#e5e7eb) su fondo scuro, e il pulsante di download
//  scrive in #0b1120 sopra il colore d'accento — quindi l'accento deve restare
//  abbastanza chiaro da reggere quel testo scuro.
//

import AppKit


public extension NSColor {

	/// Fondo dell'email: `#0f172a`, lo slate scuro su cui il template è disegnato.
	static let umLicensingMailBackground = NSColor (srgbRed: 15  / 255,
													green:   23  / 255,
													blue:    42  / 255,
													alpha:   1)

	/// Accento dell'email: `#38bdf8`, usato per bordi, link e pulsante di download.
	static let umLicensingMailAccent = NSColor (srgbRed: 56  / 255,
												green:   189 / 255,
												blue:    248 / 255,
												alpha:   1)
}
