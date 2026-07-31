import SwiftUI

struct NetworkSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var baseURLDraft = ""
    @State private var apiPrefixDraft = ""
    @State private var validationError: String?

    var body: some View {
        Form {
            Section(
                header: Text("应用代理"),
                footer: Text(
                    "可分别配置外部代理服务器，或导入 Clash YAML 使用应用内置代理。"
                )
            ) {
                NavigationLink {
                    AppProxySettingsPage()
                } label: {
                    HStack {
                        Label("代理配置", systemImage: "lock.shield")
                        Spacer()
                        Text(
                            settings.appNetworkRoutingMode.displayName
                        )
                        .foregroundColor(.secondary)
                    }
                }
            }

            Section(
                header: Text(settings.activePlatform.displayName),
                footer: Text(
                    "编辑完成后点按“应用配置”。切换服务器会清除当前登录与线路信息，"
                        + "并按平台分别保存配置。"
                )
            ) {
                TextField("Base URL", text: $baseURLDraft)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                TextField("API 前缀", text: $apiPrefixDraft)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                Button("应用配置") {
                    applyDraft()
                }
                .disabled(!hasPendingChanges)

                Button("恢复当前平台默认值") {
                    baseURLDraft = settings.activePlatform.defaultBaseURL
                    apiPrefixDraft = settings.activePlatform.defaultAPIPrefix
                }
            }

            Section(header: Text("连接状态")) {
                SettingsValueRow(
                    title: "账号会话",
                    value: settings.isAccountLoggedIn ? "已登录" : "未登录"
                )
                SettingsValueRow(
                    title: "游客会话",
                    value: settings.guestSessionActive ? "已建立" : "按需建立"
                )
                SettingsValueRow(
                    title: "当前主机",
                    value: settings.rootURL.host ?? settings.baseURLText
                )
            }
        }
        .navigationTitle("网络")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadDraft)
        .onChange(of: settings.platformID) { _ in
            loadDraft()
        }
        .alert(
            "配置无效",
            isPresented: Binding(
                get: { validationError != nil },
                set: { if !$0 { validationError = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(validationError ?? "")
        }
    }

    private var hasPendingChanges: Bool {
        baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            != settings.baseURLText
            || apiPrefixDraft.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) != settings.apiPrefix
    }

    private func loadDraft() {
        baseURLDraft = settings.baseURLText
        apiPrefixDraft = settings.apiPrefix
    }

    private func applyDraft() {
        do {
            try settings.applyServerConfiguration(
                baseURLText: baseURLDraft,
                apiPrefix: apiPrefixDraft
            )
            loadDraft()
        } catch {
            validationError = error.localizedDescription
        }
    }
}
