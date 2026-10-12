import AppKit
import SwiftUI
import WebKit

// MARK: - Help Service

@MainActor
enum HelpService {
    /// Resolves the file URL to the bundled `Help/index.html` file.
    /// Falls back to project `site/index.html` during development.
    static var bundledHelpIndexURL: URL? {
        if let bundleURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Help") {
            return bundleURL
        }
        if let direct = Bundle.main.resourceURL?.appending(path: "Help/index.html"),
           FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        // Fallback for running from source / dev folder
        let devSite = URL(fileURLWithPath: "site/index.html")
        if FileManager.default.fileExists(atPath: devSite.path) {
            return devSite
        }
        return nil
    }

    /// The base directory enclosing the help documentation for sandbox read access.
    static var bundledHelpDirectoryURL: URL? {
        if let dir = Bundle.main.url(forResource: "Help", withExtension: nil) {
            return dir
        }
        if let direct = Bundle.main.resourceURL?.appending(path: "Help", directoryHint: .isDirectory),
           FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        let devSite = URL(fileURLWithPath: "site", isDirectory: true)
        if FileManager.default.fileExists(atPath: devSite.path) {
            return devSite
        }
        return nil
    }

    /// Opens the bundled documentation in the user's default web browser.
    static func openInBrowser() {
        guard let url = bundledHelpIndexURL else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Navigation State

@MainActor
final class HelpNavigationState: ObservableObject {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentTitle: String = "ProPack Documentation"
    weak var webView: WKWebView?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func goHome() {
        guard let indexURL = HelpService.bundledHelpIndexURL,
              let dirURL = HelpService.bundledHelpDirectoryURL else { return }
        webView?.loadFileURL(indexURL, allowingReadAccessTo: dirURL)
    }
}

final class HelpNavDelegate: NSObject, WKNavigationDelegate {
    let state: HelpNavigationState

    init(state: HelpNavigationState) {
        self.state = state
        super.init()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        state.canGoBack = webView.canGoBack
        state.canGoForward = webView.canGoForward
        if let title = webView.title, !title.isEmpty {
            state.currentTitle = title
        }
    }
}

// MARK: - Web View

struct HelpWebView: NSViewRepresentable {
    let state: HelpNavigationState

    func makeCoordinator() -> HelpNavDelegate {
        HelpNavDelegate(state: state)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        state.webView = webView

        if let indexURL = HelpService.bundledHelpIndexURL,
           let dirURL = HelpService.bundledHelpDirectoryURL {
            webView.loadFileURL(indexURL, allowingReadAccessTo: dirURL)
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Help Window View

struct HelpWindowView: View {
    @StateObject private var navState = HelpNavigationState()

    var body: some View {
        Group {
            if HelpService.bundledHelpIndexURL != nil {
                HelpWebView(state: navState)
            } else {
                ContentUnavailableView(
                    "Documentation Not Found",
                    systemImage: "books.vertical",
                    description: Text("The offline documentation could not be loaded from the application bundle.")
                )
            }
        }
        .navigationTitle(navState.currentTitle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { navState.goBack() } label: {
                    Image(systemName: "chevron.backward")
                }
                .disabled(!navState.canGoBack)
                .help("Back")

                Button { navState.goForward() } label: {
                    Image(systemName: "chevron.forward")
                }
                .disabled(!navState.canGoForward)
                .help("Forward")

                Button { navState.goHome() } label: {
                    Image(systemName: "house")
                }
                .help("Documentation Home")

                Button { navState.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    HelpService.openInBrowser()
                } label: {
                    Label("Open in Browser", systemImage: "arrow.up.right.square")
                }
                .help("Open in your default web browser")
            }
        }
    }
}
