import SwiftUI

struct PlaybackSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section(
                header: Text("播放行为"),
                footer: Text("线路 ID 留空时由平台自动选择可用线路。")
            ) {
                Toggle("自动连播下一集", isOn: $settings.autoplayNextEpisode)
                TextField("首选线路 ID（可选）", text: $settings.preferredCDNID)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
        }
        .navigationTitle("详情与播放")
        .navigationBarTitleDisplayMode(.inline)
    }
}
