//
//  LicenseWindow.swift
//  UMLicensing
//
//  Presenta una schermata SwiftUI in una finestra e attende la scelta dell'utente,
//  così il flusso di licenza si scrive come codice lineare invece che come catena
//  di callback fra view controller (il vecchio d3 → d4 → d5 → d8 → d13 → d14).
//

import AppKit
import SwiftUI


@MainActor
enum LicenseWindow {

	/// Mostra `content` e sospende finché l'utente non produce un risultato.
	///
	/// Se l'utente chiude la finestra dal pulsante rosso, il risultato è `closed`:
	/// una finestra di licenza chiusa deve valere come rinuncia, non lasciare il
	/// flusso appeso per sempre.
	static func show<R: Sendable, V: View> (title: String,
											size: CGSize,
											closed: R,
											@ViewBuilder content: (@escaping @MainActor (R) -> Void) -> V) async -> R {

		let host = WindowHost<R> (closedResult: closed)
		let view = content { [host] result in host.finish (result) }

		return await withCheckedContinuation { continuation in
			host.begin (title: title, size: size, view: view, continuation: continuation)
		}
	}
}


/// Tiene insieme finestra e continuation, garantendo un solo `resume`.
@MainActor
private final class WindowHost<R: Sendable>: NSObject, NSWindowDelegate {

	private var window: NSWindow?
	private var continuation: CheckedContinuation<R, Never>?
	private let closedResult: R
	private var strongSelf: WindowHost?


	init (closedResult: R) {
		self.closedResult = closedResult
	}


	func begin (title: String,
				size: CGSize,
				view: some View,
				continuation: CheckedContinuation<R, Never>) {

		self.continuation = continuation
		self.strongSelf   = self          // la finestra è l'unica cosa che ci tiene vivi

		let window = NSWindow (contentRect: NSRect (origin: .zero, size: size),
							   styleMask: [.titled, .closable],
							   backing: .buffered,
							   defer: false)
		window.title            = title
		window.contentView      = NSHostingView (rootView: view)
		window.delegate         = self
		window.isReleasedWhenClosed = false
		window.center ()
		window.level            = .floating

		self.window = window

		NSApp.activate (ignoringOtherApps: true)
		window.makeKeyAndOrderFront (nil)
	}


	func finish (_ result: R) {
		guard let continuation else { return }
		self.continuation = nil

		window?.delegate = nil
		window?.close ()
		window = nil

		continuation.resume (returning: result)
		strongSelf = nil
	}


	nonisolated func windowWillClose (_ notification: Notification) {
		MainActor.assumeIsolated {
			finish (closedResult)
		}
	}
}
