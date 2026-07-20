import Cocoa

// The app has a manual entry point rather than @NSApplicationMain, so the
// Info.plist NSPrincipalClass key is never consulted. Touching `shared` through
// SkimApplication first is what actually decides the class: +sharedApplication
// allocates the receiver class the first time it is called, so this line — and
// only this line — makes NSApp a SkimApplication. Nothing may reference
// NSApplication.shared before it.
let app = SkimApplication.shared
assert(app is SkimApplication, "NSApp must be SkimApplication for Double-tap Option interception")

let delegate = AppDelegate()
app.delegate = delegate
app.run()
