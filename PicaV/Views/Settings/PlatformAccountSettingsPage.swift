import SwiftUI

struct PlatformAccountSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var confirmLogout = false

    var body: some View {
        List {
            Section(header: Text(settings.activePlatform.displayName)) {
                if settings.isAccountLoggedIn {
                    SettingsStatusLabel(text: "已登录", isActive: true)
                    if let session = settings.accountSession {
                        SettingsValueRow(title: "账号", value: session.account)
                        if session.displayName != session.account {
                            SettingsValueRow(title: "昵称", value: session.displayName)
                        }
                        if let userID = session.userID {
                            SettingsValueRow(title: "用户 ID", value: userID)
                        }
                    } else {
                        SettingsValueRow(title: "会话", value: "已配置访问令牌")
                    }
                } else {
                    SettingsStatusLabel(text: "未登录", isActive: false)
                    SettingsValueRow(
                        title: "游客会话",
                        value: settings.guestSessionActive ? "已建立" : "需要时自动建立"
                    )
                }
            }

            if settings.activePlatform.accountAuthentication != nil {
                if settings.isAccountLoggedIn {
                    Section {
                        Button("退出当前平台账号", role: .destructive) {
                            confirmLogout = true
                        }
                    }
                } else {
                    Section(
                        footer: Text("凭据经平台公钥加密后提交；密码不会写入本机存储。")
                    ) {
                        NavigationLink {
                            AccountAuthenticationPage(action: .login)
                        } label: {
                            Label("登录", systemImage: "person.crop.circle.badge.checkmark")
                        }

                        NavigationLink {
                            AccountAuthenticationPage(action: .register)
                        } label: {
                            Label("注册新账号", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }
            } else {
                Section {
                    Text("当前平台未提供账号登录能力。")
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("平台账号")
        .navigationBarTitleDisplayMode(.inline)
        .alert("退出登录？", isPresented: $confirmLogout) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) {
                settings.logoutCurrentAccount()
            }
        } message: {
            Text("只会退出 \(settings.activePlatform.displayName)，收藏和观看历史仍保留在本机。")
        }
    }
}
