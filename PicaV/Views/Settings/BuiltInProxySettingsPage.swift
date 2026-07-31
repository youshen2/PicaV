import SwiftUI
import UniformTypeIdentifiers

struct BuiltInProxySettingsPage: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var showingPasteImporter = false
    @State private var showingSubscriptionImporter = false
    @State private var showingFileImporter = false
    @State private var isImportingFile = false
    @State private var testingProfileID: UUID?
    @State private var feedback: Feedback?

    var body: some View {
        Form {
            Section(
                header: Text("Clash YAML 节点"),
                footer: Text(
                    "点按节点会立即选择并切换到内置代理。密钥保存在钥匙串；"
                        + "节点不可用时不会回退直连。"
                )
            ) {
                if settings.appBuiltInProxyProfiles.isEmpty {
                    Text("还没有导入任何节点")
                        .foregroundColor(.secondary)
                }

                ForEach(settings.appBuiltInProxyProfiles) { profile in
                    nodeButton(profile)
                }
                .onDelete(perform: deleteProfiles)
            }

            Section(
                header: Text("导入"),
                footer: Text(
                    "支持 Clash proxies 列表中的 HTTP、SOCKS5、Shadowsocks、"
                        + "VMess（alterId=0、TCP）和 Trojan（TCP）。"
                )
            ) {
                Button {
                    showingFileImporter = true
                } label: {
                    Label("从 YAML 文件导入", systemImage: "doc.badge.plus")
                }
                .disabled(isImportingFile)

                Button {
                    showingPasteImporter = true
                } label: {
                    Label("粘贴 YAML 导入", systemImage: "doc.on.clipboard")
                }

                Button {
                    showingSubscriptionImporter = true
                } label: {
                    Label("从订阅链接导入", systemImage: "link.badge.plus")
                }
            }

            if let selected = settings.selectedBuiltInProxyProfile {
                Section("所选节点") {
                    SettingsValueRow(
                        title: "名称",
                        value: selected.name
                    )
                    SettingsValueRow(
                        title: "协议",
                        value: selected.kind.displayName
                    )
                    SettingsValueRow(
                        title: "服务器",
                        value: selected.displayAddress
                    )
                    if selected.skipCertificateVerification {
                        Label(
                            "该节点会跳过 Trojan 服务器证书校验",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundColor(.orange)
                    }

                    Button {
                        Task { await test(selected) }
                    } label: {
                        if testingProfileID == selected.id {
                            HStack {
                                ProgressView()
                                Text("正在测试所选节点")
                            }
                        } else {
                            Text("测试所选节点")
                        }
                    }
                    .disabled(testingProfileID != nil)
                }
            }

            if let feedback {
                Section("结果") {
                    Label(
                        feedback.message,
                        systemImage: feedback.isError
                            ? "exclamationmark.triangle"
                            : "checkmark.circle"
                    )
                    .foregroundColor(
                        feedback.isError ? .red : .green
                    )
                }
            }

            Section(
                header: Text("当前限制"),
                footer: Text(
                    "WS、gRPC、HTTP/2、Shadowsocks 插件、VMess TLS 与非零 alterId "
                        + "会在导入报告中明确跳过，避免生成无法连接的假节点。"
                )
            ) {
                SettingsValueRow(title: "传输", value: "TCP")
                SettingsValueRow(title: "代理目标", value: "HTTP / HTTPS")
            }
        }
        .navigationTitle("内置代理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !settings.appBuiltInProxyProfiles.isEmpty {
                EditButton()
            }
        }
        .sheet(isPresented: $showingPasteImporter) {
            ClashYAMLPasteImportSheet { summary in
                feedback = Feedback(
                    message: reportMessage(summary),
                    isError: false
                )
            }
            .environmentObject(settings)
        }
        .sheet(isPresented: $showingSubscriptionImporter) {
            ClashYAMLSubscriptionImportSheet { summary in
                feedback = Feedback(
                    message: reportMessage(summary),
                    isError: false
                )
            }
            .environmentObject(settings)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: ClashYAMLDocumentTypes.supported,
            allowsMultipleSelection: false,
            onCompletion: handleFileSelection
        )
    }

    private func nodeButton(
        _ profile: AppBuiltInProxyProfile
    ) -> some View {
        Button {
            select(profile)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name)
                        .foregroundColor(.primary)
                    Text(
                        "\(profile.kind.displayName) · \(profile.displayAddress)"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()
                if settings.selectedBuiltInProxyID == profile.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .accessibilityLabel("已选择")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func select(_ profile: AppBuiltInProxyProfile) {
        do {
            try settings.selectBuiltInProxyProfile(profile.id)
            feedback = Feedback(
                message: "已切换到内置节点“\(profile.name)”。",
                isError: false
            )
        } catch {
            feedback = Feedback(
                message: error.localizedDescription,
                isError: true
            )
        }
    }

    private func deleteProfiles(at offsets: IndexSet) {
        let ids = offsets.compactMap { index in
            settings.appBuiltInProxyProfiles.indices.contains(index)
                ? settings.appBuiltInProxyProfiles[index].id
                : nil
        }
        do {
            for id in ids {
                try settings.removeBuiltInProxyProfile(id)
            }
            feedback = Feedback(
                message: "已删除 \(ids.count) 个节点及其钥匙串密钥。",
                isError: false
            )
        } catch {
            feedback = Feedback(
                message: error.localizedDescription,
                isError: true
            )
        }
    }

    private func handleFileSelection(
        _ result: Result<[URL], Error>
    ) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isImportingFile = true
            Task {
                defer { isImportingFile = false }
                do {
                    let parsed = try await ClashYAMLImportWorker.parse(
                        fileURL: url
                    )
                    let summary =
                        try settings.importBuiltInProxyParseResult(
                            parsed
                        )
                    feedback = Feedback(
                        message: reportMessage(summary),
                        isError: false
                    )
                } catch {
                    feedback = Feedback(
                        message: error.localizedDescription,
                        isError: true
                    )
                }
            }
        case .failure(let error):
            feedback = Feedback(
                message: error.localizedDescription,
                isError: true
            )
        }
    }

    private func test(_ profile: AppBuiltInProxyProfile) async {
        testingProfileID = profile.id
        feedback = nil
        defer { testingProfileID = nil }
        do {
            let statusCode = try await AppProxyConnectionTester.test(
                route: settings.networkRoute(
                    forBuiltInProxyProfileID: profile.id
                ),
                targetURL: settings.rootURL
            )
            feedback = Feedback(
                message: "“\(profile.name)”连接成功（HTTP \(statusCode)）。",
                isError: false
            )
        } catch {
            feedback = Feedback(
                message: error.localizedDescription,
                isError: true
            )
        }
    }

    private func reportMessage(
        _ summary: AppBuiltInProxyImportSummary
    ) -> String {
        guard !summary.skippedMessages.isEmpty else {
            return summary.message
        }
        let details = summary.skippedMessages
            .prefix(5)
            .joined(separator: "；")
        let suffix = summary.skippedMessages.count > 5
            ? "；其余原因已省略"
            : ""
        return "\(summary.message) 跳过原因：\(details)\(suffix)。"
    }

    private struct Feedback {
        let message: String
        let isError: Bool
    }
}

private enum ClashYAMLDocumentTypes {
    static let supported: [UTType] = {
        var types = [UTType.plainText]
        if let yaml = UTType(filenameExtension: "yaml") {
            types.append(yaml)
        }
        if let yml = UTType(filenameExtension: "yml"),
           !types.contains(yml) {
            types.append(yml)
        }
        return types
    }()
}
