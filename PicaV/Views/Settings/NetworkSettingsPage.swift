import SwiftUI

struct NetworkSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section(
                header: Text(settings.activePlatform.displayName),
                footer: Text("服务器配置按平台分别保存。默认通过 HTTPS 连接，API 前缀通常为 /api。")
            ) {
                TextField("Base URL", text: $settings.baseURLText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                TextField("API 前缀", text: $settings.apiPrefix)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Button("恢复当前平台默认值") {
                    settings.restoreServerDefaults()
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
    }
}
