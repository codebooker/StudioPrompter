import SwiftUI

@main struct StudioPrompterCompanionApp: App {
    @StateObject private var receiver = RemoteReceiver()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            CompanionView(receiver: receiver).preferredColorScheme(.dark)
                .onAppear { receiver.browse() }
                .onChange(of: phase) { phase in
                    if phase == .background { receiver.disconnect(keepScript: true) }
                }
        }
    }
}

struct CompanionView: View {
    @ObservedObject var receiver: RemoteReceiver
    private let accent = Color(red: 1, green: 0.49, blue: 0.29)
    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.06, blue: 0.069).ignoresSafeArea()
            if receiver.document != nil {
                RemoteCanvas(receiver: receiver).ignoresSafeArea()
                    .onTapGesture { receiver.toggleControls() }
                if receiver.showControls || !receiver.connected {
                    VStack {
                        VStack(alignment: .leading, spacing: 10) {
                          HStack {
                            Label(receiver.connected ? "Live from your Mac" : receiver.status,
                                  systemImage: receiver.connected ? "checkmark.circle.fill" : "wifi.exclamationmark")
                                .foregroundStyle(receiver.connected ? .green : .orange)
                            Spacer()
                            if !receiver.connected { Button("Reconnect", action: receiver.reconnect).disabled(receiver.connecting) }
                            Button(receiver.connected ? "Disconnect" : "Back to setup") { receiver.disconnect() }
                            if receiver.connected { Button("Hide controls", action: receiver.hideControls) }
                          }
                          if !receiver.connected {
                              Text("Keep your Mac and iPad on the same network. Check that StudioPrompter is still open on the Mac, then reconnect.")
                                  .font(.callout).foregroundStyle(.secondary)
                          }
                        }.padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .simultaneousGesture(TapGesture().onEnded { receiver.keepControlsVisible() })
                        Spacer()
                    }.padding().transition(.opacity)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Label("StudioPrompter Companion", systemImage: "text.alignleft").font(.system(size: 30, weight: .semibold))
                        Text("The reading display for StudioPrompter on your Mac.").font(.title2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Connect to the same network", systemImage: "wifi").font(.headline)
                            Text("Connect your iPad to the same Wi-Fi network as your Mac. A Mac connected by Ethernet to that same network works too.")
                                .foregroundStyle(.secondary)
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        if let pairedHost = receiver.pairedMac {
                            VStack(alignment: .leading, spacing: 14) {
                                Label(pairedHost.name, systemImage: "desktopcomputer").font(.headline)
                                Text(pairedHost.removed ? "This iPad was removed by the producer. Pair again to reconnect." : "This Mac is remembered. Reconnect to pick up its current script position.")
                                    .font(.callout).foregroundStyle(.secondary)
                                HStack {
                                    if !pairedHost.removed {
                                        Button(receiver.connecting ? "Connecting…" : "Reconnect", action: receiver.reconnect)
                                            .buttonStyle(.borderedProminent).disabled(receiver.connecting)
                                    }
                                    Button(pairedHost.removed ? "Pair again" : "Forget Mac", action: receiver.forgetMac)
                                        .buttonStyle(.bordered).disabled(receiver.connecting)
                                }
                                Text("Pairings survive app and device restarts. Forget Mac clears the pairing on this iPad.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        } else {
                        Text("On your Mac, choose Prompter Output → Connect iPad. Enter its pairing code here, then select your Mac.")
                        TextField("ABCD–EFGH–JKLM", text: $receiver.code)
                            .font(.system(size: 24, weight: .medium, design: .monospaced))
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .padding(18).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Pairing code")
                        VStack(spacing: 12) {
                            ForEach(receiver.hosts) { host in
                                Button { receiver.connect(host) } label: {
                                    HStack { Image(systemName: "desktopcomputer"); Text(host.name); Spacer(); Image(systemName: "arrow.right") }
                                        .padding(18).background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
                                }.disabled(receiver.connecting)
                            }
                            if receiver.hosts.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Label("Looking for your Mac…", systemImage: "wifi").font(.headline)
                                    Text("Check that both devices are on the same network and Local Network access is allowed for both apps. Guest or public Wi-Fi can block devices from finding each other.")
                                        .font(.callout).foregroundStyle(.secondary)
                                    Button("Search again", action: receiver.restartDiscovery)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        }
                        if receiver.pairedMac != nil { Button("Search again", action: receiver.restartDiscovery).disabled(receiver.connecting) }
                        Text(receiver.status).font(.callout).foregroundStyle(.secondary)
                        Text("Your script travels over an encrypted local connection. No internet connection is needed. Speech recognition and controls stay on the Mac.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.frame(maxWidth: 560).padding(40).frame(maxWidth: .infinity)
                }
            }
        }.animation(.easeInOut(duration: 0.2), value: receiver.showControls)
            .tint(accent).statusBarHidden(receiver.document != nil && !receiver.showControls)
    }
}
