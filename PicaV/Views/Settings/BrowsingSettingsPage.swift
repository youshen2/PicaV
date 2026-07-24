import SwiftUI

struct BrowsingSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var cacheCleared = false

    var body: some View {
        Form {
            Section(
                header: Text("图片加载"),
                footer: Text("图片格式与域名规则会随所选平台自动应用。")
            ) {
                Toggle("优先使用图片代理", isOn: $settings.useImageProxy)
                Button("重新载入图片") {
                    Task {
                        await AnimeImagePipeline.shared.clear()
                        cacheCleared = true
                    }
                }
            }
        }
        .navigationTitle("图片加载")
        .navigationBarTitleDisplayMode(.inline)
        .alert("图片缓存已清除", isPresented: $cacheCleared) {
            Button("好", role: .cancel) {}
        }
    }
}
