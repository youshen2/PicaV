import SwiftUI

struct PlaybackSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var client: AnimeAPIClient
    @State private var lines: [CDNLine] = []
    @State private var linesState: LoadState = .idle

    var body: some View {
        Form {
            Section(
                header: Text("播放行为"),
                footer: Text("自动线路会优先使用详情返回的可用线路。")
            ) {
                Toggle("自动连播下一集", isOn: $settings.autoplayNextEpisode)
                Picker("首选线路", selection: $settings.preferredCDNID) {
                    Text("自动").tag("")
                    ForEach(lines) { line in
                        Text(line.name).tag(line.id)
                    }
                    if !settings.preferredCDNID.isEmpty,
                       !lines.contains(
                           where: { $0.id == settings.preferredCDNID }
                       ) {
                        Text("已保存线路").tag(settings.preferredCDNID)
                    }
                }

                if case .failed = linesState {
                    Button("重新载入线路") {
                        Task { await loadLines(force: true) }
                    }
                }
            }

            Section(
                header: Text("下载"),
                footer: Text(
                    "关闭后，在蜂窝网络下启动的下载会等待你连接 Wi‑Fi 后重试。"
                )
            ) {
                Toggle(
                    "允许使用蜂窝网络",
                    isOn: $settings.downloadOverCellular
                )
            }
        }
        .navigationTitle("详情与播放")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: settings.platformID) {
            await loadLines(force: true)
        }
    }

    private func loadLines(force: Bool) async {
        guard force || linesState == .idle else { return }
        linesState = .loading
        do {
            lines = try await client.fetchCDNLines()
                .stableUniqued(id: \.id)
            linesState = .loaded
        } catch is CancellationError {
            linesState = lines.isEmpty ? .idle : .loaded
        } catch {
            linesState = .failed(error.localizedDescription)
        }
    }
}
