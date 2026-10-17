// macOS system WebKit host for the gaps lane (the same WebCore and WebPageMac.mm as Safari on this Mac; Safari itself is
// never opened). Loads a URL in an off-screen WKWebView of a given size with a given pageZoom, then either
//   - exits after a lifetime (probe-page mode: the page POSTs its own facts), or
//   - with a plan file, runs the plan's calls in the page after the load and prints their results as one JSON array on stdout.
// usage: wkzoom <url> <widthPx> <heightPx> <pageZoom> <lifetimeSeconds> [<planFile>]
// plan:  { "init": "<js run at document start, or null>", "calls": [ { "fn": "<function source>", "arg": <json> }, ... ] }
//        each call is `return await (fn)(arg)` in the page (callAsyncJavaScript), so an async function is awaited.
import Cocoa
import WebKit

let a = CommandLine.arguments
guard a.count == 6 || a.count == 7, let url = URL(string: a[1]), let w = Double(a[2]), let h = Double(a[3]), let zoom = Double(a[4]), let life = Double(a[5]) else {
  FileHandle.standardError.write("usage: wkzoom <url> <w> <h> <pageZoom> <seconds> [<planFile>]\n".data(using: .utf8)!)
  exit(2)
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

var plan: [String: Any]? = nil
if a.count == 7 {
  guard let data = FileManager.default.contents(atPath: a[6]), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    FileHandle.standardError.write("cannot read the plan file\n".data(using: .utf8)!)
    exit(2)
  }
  plan = obj
}

let config = WKWebViewConfiguration()
if let initJs = plan?["init"] as? String {
  config.userContentController.addUserScript(WKUserScript(source: initJs, injectionTime: .atDocumentStart, forMainFrameOnly: true))
}
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: w, height: h), configuration: config)
web.pageZoom = zoom
// A borderless window far off-screen gives the view a layout; it is never ordered front, so nothing appears.
let win = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: w, height: h), styleMask: [.borderless], backing: .buffered, defer: false)
win.contentView = web

final class Nav: NSObject, WKNavigationDelegate {
  var calls: [[String: Any]] = []
  var results: [Any] = []
  func fail(_ msg: String) {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { next() }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail("navigation failed: \(error)") }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail("navigation failed: \(error)") }
  func next() {
    if results.count == calls.count {
      guard let out = try? JSONSerialization.data(withJSONObject: results) else { fail("results are not JSON") ; return }
      FileHandle.standardOutput.write(out)
      FileHandle.standardOutput.write("\n".data(using: .utf8)!)
      exit(0)
    }
    let c = calls[results.count]
    let fn = c["fn"] as? String ?? ""
    web.callAsyncJavaScript("return await (\(fn))(arg);", arguments: ["arg": c["arg"] ?? NSNull()], in: nil, in: .page) { r in
      switch r {
      case .success(let v): self.results.append(v ?? NSNull()); self.next()
      case .failure(let e): self.fail("call \(self.results.count) failed: \(e)")
      }
    }
  }
}

let nav = Nav()
if let p = plan {
  nav.calls = (p["calls"] as? [[String: Any]]) ?? []
  web.navigationDelegate = nav
}
web.load(URLRequest(url: url))
DispatchQueue.main.asyncAfter(deadline: .now() + life) { exit(plan == nil ? 0 : 3) }
app.run()
