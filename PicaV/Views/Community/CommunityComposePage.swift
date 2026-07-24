import SwiftUI

struct CommunityComposePage: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CommunityComposeViewModel
    @State private var content = ""
    @State private var selectedTopics: [CommunityTopic] = []
    @State private var showsCustomTopic = false
    @State private var customTopic = ""
    @State private var localError: String?

    private let client: AnimeAPIClient
    private let topicColumns = [
        GridItem(.adaptive(minimum: 86, maximum: 150), spacing: 8)
    ]

    init(client: AnimeAPIClient) {
        self.client = client
        _viewModel = StateObject(
            wrappedValue: CommunityComposeViewModel(client: client)
        )
    }

    var body: some View {
        PicaNavigationContainer {
            Group {
                if client.isAccountLoggedIn {
                    composeForm
                } else {
                    loggedOutContent
                }
            }
            .navigationTitle("发布图文")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(viewModel.isPublishing)
                }
            }
        }
        .task {
            if client.isAccountLoggedIn {
                await viewModel.loadTopics()
            }
        }
        .alert("创建话题", isPresented: $showsCustomTopic) {
            TextField("2–6 个字", text: $customTopic)
            Button("取消", role: .cancel) {
                customTopic = ""
            }
            Button("添加") {
                addCustomTopic()
            }
        } message: {
            Text("最多选择 3 个话题")
        }
        .alert("发布失败", isPresented: errorPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(localError ?? viewModel.errorMessage ?? "")
        }
    }

    private var composeForm: some View {
        List {
            Section("内容") {
                TextEditor(text: $content)
                    .frame(minHeight: 150)
                    .disabled(viewModel.isPublishing)
                    .onChange(of: content) { value in
                        if value.count > 500 {
                            content = String(value.prefix(500))
                        }
                    }

                HStack {
                    Text("图文动态")
                    Spacer()
                    Text("\(content.count) / 500")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Section {
                if viewModel.isLoadingTopics {
                    ProgressView("正在加载话题…")
                } else {
                    LazyVGrid(columns: topicColumns, alignment: .leading, spacing: 8) {
                        Button {
                            showsCustomTopic = true
                        } label: {
                            Label("自定义", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        ForEach(viewModel.topics.prefix(30)) { topic in
                            Button {
                                toggle(topic)
                            } label: {
                                Text("#\(topic.name)")
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(
                                CommunityTopicButtonStyle(
                                    selected: selectedTopics.contains(
                                        where: { $0.id == topic.id }
                                    )
                                )
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text("话题")
                    Spacer()
                    Text("\(selectedTopics.count) / 3")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } footer: {
                if selectedTopics.isEmpty {
                    Text("发布前至少选择一个话题。")
                } else {
                    Text(
                        selectedTopics.map { "#\($0.name)" }.joined(separator: "  ")
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task {
                    if await viewModel.publish(
                        content: content,
                        selectedTopics: selectedTopics
                    ) {
                        dismiss()
                    }
                }
            } label: {
                if viewModel.isPublishing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("发布")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                viewModel.isPublishing
                    || content.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                    || selectedTopics.isEmpty
            )
            .padding()
            .background(.bar)
        }
    }

    private var loggedOutContent: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                systemImage: "person.crop.circle.badge.exclamationmark",
                title: "登录后发布动态",
                message: "社区内容会发布到当前平台账号。"
            )

            NavigationLink {
                AccountAuthenticationPage(action: .login)
            } label: {
                Text("登录平台账号")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func toggle(_ topic: CommunityTopic) {
        if let index = selectedTopics.firstIndex(where: { $0.id == topic.id }) {
            selectedTopics.remove(at: index)
        } else if selectedTopics.count < 3 {
            selectedTopics.append(topic)
        } else {
            localError = "最多选择 3 个话题。"
        }
    }

    private func addCustomTopic() {
        let value = customTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        customTopic = ""
        guard (2...6).contains(value.count) else {
            localError = "自定义话题需为 2–6 个字。"
            return
        }
        let topic = CommunityTopic(name: value)
        if !selectedTopics.contains(where: { $0.name == value }) {
            if selectedTopics.count < 3 {
                selectedTopics.append(topic)
            } else {
                localError = "最多选择 3 个话题。"
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { localError != nil || viewModel.errorMessage != nil },
            set: { presented in
                if !presented {
                    localError = nil
                    viewModel.errorMessage = nil
                }
            }
        )
    }
}

private struct CommunityTopicButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundColor(selected ? .white : .accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                selected
                    ? Color.accentColor
                    : Color.accentColor.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
