# UMLicensing

Licensing per app macOS, autonomo: nessuna dipendenza da UMOmniaFramework.
Port del vecchio `License` + `LicenseData` + `UMLicenseValidationCode`, con la UI
riscritta in SwiftUI e la rete in async/await.

macOS 14+, Swift 6.

## Uso

```swift
@MainActor
func boot () async {
    let ok = await UMLicensing.licensed (appId:                 Boot.kAppIdLong,
                                         appName:               Boot.kAppName,
                                         appShortId:            Boot.kAppIdShort,
                                         acceptedApps:          [Boot.kAppIdShort],
                                         previousVersionPrefix: Boot.kPreviousVersionPrefix,
                                         purchaseUrl:           Boot.purchaseUrl,
                                         downloadAppUrl:        Boot.downloadAppUrl,
                                         mailBody:              Boot.trialMailBody,
                                         trialExpDays:          7,
                                         graceDays:             30)
    guard ok else {
        NSApp.terminate (nil)
        return
    }
    // l'app parte
}
```

`licensed()` non termina mai l'app da sé: se l'utente rinuncia ritorna `false`.

## Cosa fa

1. **Percorso veloce** — licenza perpetua già confermata dal server negli ultimi
   `graceDays` giorni: parte subito, senza rete. Il rinnovo della finestra di grace
   avviene in sottofondo, senza mostrare niente.
2. **Recupero** — nessuna licenza in locale: chiede al server se questa macchina
   (MAC address) è già registrata. Copre reinstallazioni e preferences cancellati.
3. **Acquisizione** — schermata di scelta: trial o seriale.
   - *Trial*: nome + email, genera il seriale, lo registra sul server, manda l'email,
     poi l'utente lo incolla (così l'indirizzo risulta verificato).
   - *Seriale*: validazione locale, poi attivazione sul server.
4. **Conferma** — controlla su server che il seriale non sia attivato altrove e
   riallinea la scadenza. Server irraggiungibile e grace period ancora valido:
   si parte lo stesso.

## Compatibilità col sistema esistente

Mantenute intenzionalmente identiche:

- **Formato dei seriali** `APPT-NNNNNNNN-VVVVVVV` e algoritmo del validator.
- **Chiavi di storage** `license..serialId` ecc., doppio punto incluso. Gli utenti
  già registrati non perdono la licenza.
- **Protocollo server** — stesse `action`, stessi validator MD5.
- **`licenseType.name` per `.upgrade` ritorna `""`** — replica un bug dell'originale,
  vedi il commento in `LicenseType.swift`.

## Da completare

Il port è funzionante ma tre punti sono ipotesi finché non arrivano i sorgenti
originali. Sono tutti marcati `⚠️` nel codice:

| Cosa | Dove | Rischio se sbagliata |
|---|---|---|
| `racId_md5` in hex minuscolo | `Internal/Compat.swift` | Nessun validator torna, licenze esistenti tutte rifiutate |
| Formato di `du_getDateString` (con o senza orario) | `Internal/Compat.swift` | Validator di `activate` e della copia locale sbagliati |
| Formato di `encapsulateGetValue` (`<label>…</label>`) | `Internal/Compat.swift` | Ogni risposta del server letta vuota |
| `prefs_setValueDate` salva un `Date` nativo | `Internal/LicenseStore.swift` | Date rilette male, utenti esistenti de-registrati |
| Formato di `netU_getMacAddress` | `Internal/Compat.swift` | "Serial number already activated" per tutti |
| URL del server (da `cleanSplhash`) | `Core/LicenseServer.swift` | Nessuna chiamata arriva a destinazione |
| Nome del placeholder del link di download | `Core/TrialMailer.swift` | Placeholder visibile nell'email |

L'invio email è invece completo: `TrialMailer` posta su
`https://ultimediacloud.net/mailer/mailer.php` con gli stessi campi di `SendEmail`
(`mailFrom`, `mailFromName`, `mailTo`, `mailToName`, `mailSubject`, `mailBody`).
La chiave MailerSend che compariva in chiaro nel ramo commentato di `SendEmail` non
è stata portata: una API key dentro un'app distribuita è estraibile da chiunque.

## Fuori perimetro

Non portati, per scelta: Control Panel, flusso di upgrade con seriale precedente,
licenze bait, `LicenseRemote` (API di amministrazione), `UMIntegrityCheck`.

## Test

```bash
DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test
```

`DEVELOPER_DIR` serve perché `xcode-select` su questa macchina punta ai Command Line
Tools, che non includono XCTest.
