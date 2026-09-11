//
//  UMLicensingCode.swift
//  UMLicensing
//
//  Codici diagnostici. Esistono perché l'alert "Cannot Reach the Licensing Server"
//  è ambiguo: scatta sia quando la rete manca davvero, sia quando il server risponde
//  ma in un formato che non sappiamo leggere, sia quando la licenza locale non è
//  utilizzabile offline. Tre cause diversissime, un solo messaggio — e l'utente che
//  scrive al supporto può solo dire "non funziona".
//
//  Ogni codice compare nell'alert come `UML-Exxx`, così il testo che l'utente
//  fotografa basta a capire cosa è successo senza chiedergli di attivare i log.
//

import Foundation


public enum UMLicensingCode: String, Sendable {

	// MARK: - Trasporto (1xx): il server non ha risposto

	/// L'URL costruito non è valido: baseUrl sbagliato o query non codificabile.
	case badUrl                 = "E101"
	/// Nessuna connessione a internet.
	case noInternet             = "E102"
	/// La richiesta è scaduta prima della risposta (server lento, o filtrata in silenzio).
	case timeout                = "E103"
	/// Il nome host non si risolve: DNS, o un blocco a livello di risolutore.
	case dnsFailure             = "E104"
	/// Host raggiunto ma connessione rifiutata: server giù, o porta chiusa da un firewall.
	case cannotConnect          = "E105"
	/// Handshake TLS fallito: certificato scaduto, proxy che ispeziona il traffico, data di sistema sbagliata.
	case tlsFailure             = "E106"
	/// Altro errore di rete: il dettaglio esatto finisce nel log.
	case networkOther           = "E107"
	/// Il server ha risposto con uno stato HTTP fuori da 2xx (404, 500, pagina di cortesia dell'hosting).
	case httpStatus             = "E108"
	/// Risposta vuota: connessione riuscita, corpo di zero byte.
	case emptyResponse          = "E109"


	// MARK: - Protocollo (2xx): il server ha risposto, ma la risposta non è utilizzabile

	/// Il campo `validator` non corrisponde all'md5 del blocco `data`: risposta non autentica,
	/// oppure il backend firma con un segreto/formato diverso.
	case validatorMismatch      = "E201"
	/// Risposta non vuota ma senza i tag attesi: il delimitatore che assume
	/// `encapsulateGetValue` non è quello che usa il backend.
	case malformedResponse      = "E202"
	/// La risposta è HTML o un errore PHP, non il formato della licenza.
	case htmlErrorPage          = "E203"
	/// Le date arrivate dal server non sono in un formato leggibile.
	case unreadableDate         = "E204"
	/// Risposta formalmente valida ma senza `serialId` né `errorMessage`.
	case missingSerialField     = "E205"


	// MARK: - Stato locale (3xx): perché la licenza salvata non copre l'offline

	/// Nei preferences non c'è nessuna licenza.
	case noLocalLicense         = "E301"
	/// La licenza salvata c'è ma la firma locale non torna: preferences manomessi o corrotti.
	case localValidatorMismatch = "E302"
	/// La licenza è scaduta secondo la data salvata.
	case licenseExpired         = "E303"
	/// Il seriale non supera la verifica locale: cifre di controllo o prefisso app sbagliati.
	case serialFailsLocalCheck  = "E304"
	/// Licenza non perpetua (trial o bait): per definizione va verificata online a ogni avvio.
	case notPerpetual           = "E305"
	/// Manca `UMLicenseValidationCode`: questa licenza non è mai stata confermata su questo Mac.
	case noValidationCode       = "E306"
	/// Il codice di validazione salvato non corrisponde: il machId è cambiato dopo l'ultima conferma.
	case validationCodeMismatch = "E307"
	/// Il MAC dell'interfaccia primaria non è leggibile: `machId` vuoto, ogni confronto fallisce.
	case emptyMachId            = "E308"


	// MARK: - Grace period (4xx)

	/// Sono passati più giorni del consentito dall'ultimo controllo riuscito.
	case graceExpired           = "E401"
	/// Non risulta nessun controllo riuscito registrato.
	case neverChecked           = "E402"


	// MARK: - Presentazione

	/// Il codice come va mostrato all'utente.
	public var display: String { "UML-" + rawValue }


	/// Spiegazione in una riga. Inglese come il resto della UI.
	public var text: String {
		switch self {
			case .badUrl:                   return "The licensing endpoint URL is not valid."
			case .noInternet:               return "No internet connection."
			case .timeout:                  return "The licensing server did not answer in time."
			case .dnsFailure:               return "The licensing server name could not be resolved."
			case .cannotConnect:            return "The licensing server refused the connection."
			case .tlsFailure:               return "The secure connection to the licensing server failed."
			case .networkOther:             return "The connection to the licensing server failed."
			case .httpStatus:               return "The licensing server answered with an HTTP error."
			case .emptyResponse:            return "The licensing server answered with an empty response."
			case .validatorMismatch:        return "The licensing server answer is not signed as expected."
			case .malformedResponse:        return "The licensing server answer is in an unexpected format."
			case .htmlErrorPage:            return "The licensing server returned a web page instead of a license."
			case .unreadableDate:           return "The licensing server sent dates in an unknown format."
			case .missingSerialField:       return "The licensing server answer contains no serial number."
			case .noLocalLicense:           return "No license is stored on this Mac."
			case .localValidatorMismatch:   return "The stored license signature does not match."
			case .licenseExpired:           return "The stored license is expired."
			case .serialFailsLocalCheck:    return "The stored serial number does not pass the local check."
			case .notPerpetual:             return "Trial licenses must be verified online at every launch."
			case .noValidationCode:         return "This license has never been confirmed on this Mac."
			case .validationCodeMismatch:   return "The stored confirmation does not match this Mac."
			case .emptyMachId:              return "The primary network interface could not be identified."
			case .graceExpired:             return "Too long since the last successful check."
			case .neverChecked:             return "No successful check has ever been recorded."
		}
	}


	/// Traduce un errore di `URLSession` nel codice corrispondente.
	static func transport (_ error: Error) -> UMLicensingCode {
		guard let urlError = error as? URLError else { return .networkOther }

		switch urlError.code {
			case .notConnectedToInternet, .networkConnectionLost,
				 .internationalRoamingOff, .dataNotAllowed:
				return .noInternet
			case .timedOut:
				return .timeout
			case .cannotFindHost, .dnsLookupFailed:
				return .dnsFailure
			case .cannotConnectToHost, .resourceUnavailable, .badServerResponse:
				return .cannotConnect
			case .secureConnectionFailed, .serverCertificateHasBadDate,
				 .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
				 .serverCertificateNotYetValid, .clientCertificateRejected,
				 .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection:
				return .tlsFailure
			default:
				return .networkOther
		}
	}
}


/// Perché la licenza non ha potuto essere confermata, in due parti: cosa è andato
/// storto con il server e — se la copia locale non ha potuto sopperire — perché.
///
/// Tenerle separate è il punto: "server irraggiungibile" da solo non spiega niente,
/// visto che con una licenza full confermata di recente l'app parte lo stesso.
public struct UMLicensingDiagnosis: Sendable {

	/// Cosa è successo parlando col server.
	public var server: UMLicensingCode

	/// Perché la licenza salvata non basta a coprire l'assenza di risposta.
	/// `nil` quando la copre: in quel caso l'utente non vede niente.
	public var local: UMLicensingCode?

	/// Dettaglio libero per il log (stato HTTP, messaggio di sistema, giorni trascorsi).
	public var detail: String = ""


	public init (server: UMLicensingCode, local: UMLicensingCode? = nil, detail: String = "") {
		self.server = server
		self.local  = local
		self.detail = detail
	}


	/// I codici da mostrare nell'alert: `UML-E102 / UML-E305`.
	public var display: String {
		guard let local else { return server.display }
		return "\(server.display) / \(local.display)"
	}


	/// Riga completa per il log.
	public var logLine: String {
		var line = "\(display) — \(server.text)"
		if let local { line += " \(local.text)" }
		if !detail.isEmpty { line += " [\(detail)]" }
		return line
	}
}
