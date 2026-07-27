//
//  Obfuscated.swift
//  UMLicensing
//
//  Sostituisce Splhash. Le stringhe sensibili (URL del server, chiavi dei validator,
//  messaggi) non compaiono in chiaro nel binario: `strings UMLicensing` non le trova.
//
//  Non è crittografia — la chiave è nel binario, quindi chi disassembla arriva alla
//  stringa. Serve solo ad alzare il costo dell'ispezione banale, come faceva Splhash.
//

import Foundation


/// Stringa offuscata con XOR + chiave ciclica, decodificata a runtime al primo accesso.
struct Obfuscated: Sendable {

	private let bytes: [UInt8]

	init (_ bytes: [UInt8]) {
		self.bytes = bytes
	}

	/// La stringa in chiaro.
	var value: String {
		String (decoding: Obfuscated.xor (bytes), as: UTF8.self)
	}

	/// Codifica una stringa in chiaro nell'array di byte da incollare nel sorgente.
	/// Usata solo dal tool di supporto, mai a runtime.
	static func encode (_ s: String) -> [UInt8] {
		xor (Array (s.utf8))
	}

	private static func xor (_ input: [UInt8]) -> [UInt8] {
		let k = key
		return input.enumerated ().map { $0.element ^ k [$0.offset % k.count] }
	}

	/// La chiave è assemblata a pezzi per non finire nel binario come una sequenza unica.
	private static var key: [UInt8] {
		[0x5A, 0xC3, 0x1F, 0x77] + [0xB2, 0x08, 0xE4, 0x39] + [0x6D, 0x91, 0x4C, 0xA0]
	}
}


extension Obfuscated: ExpressibleByStringLiteral {
	/// Comodità per i test e per il codice non sensibile.
	init (stringLiteral value: String) {
		self.init (Obfuscated.encode (value))
	}
}
