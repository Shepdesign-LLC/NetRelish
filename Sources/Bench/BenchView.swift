// BenchView.swift — the web pane (manifest §8 Bench). Chrome is `surface`, hairline-
// separated; nothing brand-colored touches the page. One address bar, back/forward,
// reload, and the active jar's WKWebView underneath.

import Pantry
import SwiftUI

@MainActor
@Observable
final class BenchWebViews {
    private var byJar: [String: JarWebView] = [:]
    func view(for jarId: String) -> JarWebView {
        if let v = byJar[jarId] { return v }
        let v = JarWebView(jarId: jarId)
        byJar[jarId] = v
        return v
    }
}

struct BenchView: View {
    let jar: Jar?
    @State private var webViews = BenchWebViews()
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        if let jar {
            let web = webViews.view(for: jar.id)
            VStack(spacing: 0) {
                addressBar(web)
                Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
                WebViewHost(jarWebView: web)
            }
            .background(NRColor.surface)
            .onChange(of: web.url) { _, new in if !addressFocused { address = new?.absoluteString ?? "" } }
            .onAppear { address = web.url?.absoluteString ?? "" }
            .id(jar.id)   // a different jar is a different bench: its own web view, its own address text
        } else {
            VStack(spacing: NRSpace.sp4) {
                NRLogo.cog.image.resizable().frame(width: 48, height: 48)
                Text("No jar yet. Make one on the Shelf.").font(NRType.font(NRType.fsMd)).foregroundStyle(NRColor.fg2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NRColor.bg)
        }
    }

    private func addressBar(_ web: JarWebView) -> some View {
        HStack(spacing: NRSpace.sp2) {
            Button { web.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!web.canGoBack).help("Back")
            Button { web.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!web.canGoForward).help("Forward")
            TextField("Address", text: $address)
                .textFieldStyle(.plain)
                .font(NRType.font(NRType.fsSm, design: NRType.fontMono))
                .foregroundStyle(NRColor.fg)
                .focused($addressFocused)
                .onSubmit { web.load(address); addressFocused = false }
                .padding(.horizontal, NRSpace.sp3)
                .frame(height: 26)
                .background(NRColor.surface2, in: RoundedRectangle(cornerRadius: NRRadius.r1))
                .overlay(RoundedRectangle(cornerRadius: NRRadius.r1).strokeBorder(addressFocused ? NRColor.focus : .clear, lineWidth: 2))
            Button { web.reload() } label: { Image(systemName: web.isLoading ? "xmark" : "arrow.clockwise") }
                .help(web.isLoading ? "Stop" : "Reload")
        }
        .buttonStyle(.plain)
        .foregroundStyle(NRColor.fg2)
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, NRSpace.sp3)
        .frame(height: 38)
        .background(NRColor.surface)
    }
}
