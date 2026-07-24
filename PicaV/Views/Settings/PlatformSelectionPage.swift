import SwiftUI

struct PlatformSelectionPage: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List {
            Section(
                header: Text("番剧平台"),
                footer: Text("切换后，服务器、账号和播放线路配置会随平台切换。")
            ) {
                ForEach(AnimePlatformRegistry.all, id: \.id) { platform in
                    Button {
                        settings.selectPlatform(platform.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.square.stack.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                                .frame(width: 34)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(platform.displayName)
                                    .foregroundColor(.primary)
                                Text(URL(string: platform.defaultBaseURL)?.host ?? platform.defaultBaseURL)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                            if settings.platformID == platform.id {
                                Image(systemName: "checkmark")
                                    .font(.headline)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("平台与数据源")
        .navigationBarTitleDisplayMode(.inline)
    }
}
