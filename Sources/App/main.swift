import AppKit

// Focusing the search field would otherwise make AppKit spawn an "AutoFill (Clipboard Win)"
// helper process to offer passwords and contacts. Nothing here can be autofilled, so opt out.
UserDefaults.standard.register(defaults: ["NSAutoFillHeuristicsEnabled": false])

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
