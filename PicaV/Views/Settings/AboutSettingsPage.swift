import SwiftUI
import UIKit

struct AboutSettingsPage: View {
    @State private var isSharing = false

    private let metadata = AboutAppMetadata.current

    var body: some View {
        List {
            Section {
                AboutAppHeader(metadata: metadata)
            }
            .listRowInsets(
                EdgeInsets(
                    top: 20,
                    leading: 16,
                    bottom: 20,
                    trailing: 16
                )
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section("应用信息") {
                SettingsValueRow(
                    title: "版本",
                    value: metadata.version
                )
                SettingsValueRow(
                    title: "构建",
                    value: metadata.build
                )
            }

            Section(
                header: Text("开源组件"),
                footer: Text("感谢这些项目为播放与媒体处理提供基础能力。")
            ) {
                AboutExternalLinkRow(
                    title: "KSPlayer",
                    subtitle: "视频播放器 · 2.3.4",
                    destination: URL(
                        string: "https://github.com/kingslay/KSPlayer"
                    )!
                )

                AboutExternalLinkRow(
                    title: "FFmpegKit",
                    subtitle: "媒体处理 · 6.1.4",
                    destination: URL(
                        string: "https://github.com/kingslay/FFmpegKit"
                    )!
                )

                AboutExternalLinkRow(
                    title: "GNU GPL v3",
                    subtitle: "查看组件开源许可",
                    destination: URL(
                        string: "https://www.gnu.org/licenses/gpl-3.0.html"
                    )!
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isSharing = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享 PicaV")
            }
        }
        .sheet(isPresented: $isSharing) {
            ActivitySheet(items: [metadata.shareText])
        }
    }
}

private struct AboutAppHeader: View {
    let metadata: AboutAppMetadata

    var body: some View {
        VStack(spacing: 11) {
            Group {
                if let icon = AboutAppIcon.image {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "play.square.stack.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                        .foregroundColor(.accentColor)
                        .background(Color(.secondarySystemGroupedBackground))
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 5)

            Text(metadata.displayName)
                .font(.title2.weight(.bold))

            Text("原生、多平台的番剧与视频客户端")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("版本 \(metadata.version)（\(metadata.build)）")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct AboutExternalLinkRow: View {
    let title: String
    let subtitle: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
    }
}

private struct AboutStatementRow: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}

private struct AboutAppMetadata {
    let displayName: String
    let version: String
    let build: String

    var shareText: String {
        "\(displayName) \(version)（\(build)）— 原生、多平台的番剧与视频客户端"
    }

    static let current = AboutAppMetadata(
        displayName: Bundle.main.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String ?? "PicaV",
        version: Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0",
        build: Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
    )
}

private enum AboutAppIcon {
    static let image: UIImage? = {
        let info = Bundle.main.infoDictionary
        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            guard let icons = info?[key] as? [String: Any],
                  let primary = icons[
                    "CFBundlePrimaryIcon"
                  ] as? [String: Any],
                  let files = primary[
                    "CFBundleIconFiles"
                  ] as? [String] else {
                continue
            }

            for name in files.reversed() {
                if let image = UIImage(named: name) {
                    return image
                }
            }
        }
        return UIImage(named: "AppIcon")
    }()
}
