//
//  LicenseType.swift
//  UMLicensing
//

import Foundation


/// Tipo di licenza, codificato nel 5° carattere del seriale (indice 4).
public enum licenseType: Sendable {
	case trial
	case full
	case special
	case invalid
	case gift
	case bait
	case upgrade


	/// Carattere usato nel seriale per questo tipo.
	public var char: String {
		switch self {
			case .full:     return "F"
			case .trial:    return "T"
			case .special:  return "S"
			case .gift:     return "G"
			case .bait:     return "B"
			case .upgrade:  return "U"
			case .invalid:  return ""
		}
	}


	/// Nome del tipo, salvato in `licType` e mostrato in UI.
	///
	/// ⚠️ `.upgrade` ritorna `""` di proposito: il vecchio `getLicenseTypeString`
	/// non aveva il case `.upgrade` e cadeva nel `default`, quindi tutti gli upgrade
	/// finora sono stati registrati sul server con `licType` vuoto. Mantengo il
	/// comportamento per non divergere dai dati esistenti — vedi `nameFixed`.
	public var name: String {
		switch self {
			case .full:     return "full"
			case .trial:    return "trial"
			case .special:  return "special"
			case .gift:     return "gift"
			case .bait:     return "bait"
			case .upgrade:  return ""
			case .invalid:  return ""
		}
	}


	/// Come `name`, ma con `.upgrade` corretto. Usato solo per la UI.
	public var displayName: String {
		self == .upgrade ? "upgrade" : name
	}


	/// `true` per le licenze senza scadenza, che possono saltare il controllo online.
	public var isPerpetual: Bool {
		switch self {
			case .full, .gift, .upgrade, .special:  return true
			case .trial, .bait, .invalid:           return false
		}
	}


	/// Ricava il tipo dal carattere in posizione 4 del seriale.
	public init (serialId: String) {
		let c = Compat.strUt_getChar (s: serialId, n: 4)
		switch c {
			case "F":   self = .full
			case "T":   self = .trial
			case "S":   self = .special
			case "G":   self = .gift
			case "B":   self = .bait
			case "U":   self = .upgrade
			default:    self = .invalid
		}
	}
}
