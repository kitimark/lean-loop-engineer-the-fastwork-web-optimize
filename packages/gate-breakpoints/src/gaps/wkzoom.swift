// macOS system WebKit host for the gaps lane (the same WebCore and WebPageMac.mm as Safari on this Mac; Safari itself is
// never opened). Loads a URL in an off-screen WKWebView of a given size with a given pageZoom and then exits; the page
// reports its own facts by POST, so this host reads nothing back.
// usage: wkzoom <url> <widthPx> <heightPx> <pageZoom> <lifetimeSeconds>
import Cocoa
import WebKit

let a = CommandLine.arguments
guard a.count == 6, let url = URL(string: a[1]), let w = Double(a[2]), let h = Double(a[3]), let zoom = Double(a[4]), let life = Double(a[5]) else {
  FileHandle.standardError.write("usage: wkzoom <url> <w> <h> <pageZoom> <seconds>\n".data(using: .utf8)!)
  exit(2)
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: w, height: h), configuration: WKWebViewConfiguration())
web.pageZoom = zoom
// A borderless window far off-screen gives the view a layout; it is never ordered front, so nothing appears.
let win = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: w, height: h), styleMask: [.borderless], backing: .buffered, defer: false)
win.contentView = web
web.load(URLRequest(url: url))
DispatchQueue.main.asyncAfter(deadline: .now() + life) { exit(0) }
app.run()
