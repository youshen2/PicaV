import SwiftUI

struct NetworkSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var baseURLDraft = ""
    @State private var apiPrefixDraft = ""
    @State private var validationError: String?
    @State private var addressUpdateRequestID: UUID?
    @State private var addressUpdateState = APIAddressUpdateState.idle

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
                footer: Text(serverConfigurationFooter)
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
                    addressUpdateState = .idle
                }

                if settings.platformID == .acFan {
                    Button {
                        addressUpdateRequestID = UUID()
                    } label: {
                        HStack {
                            Label(
                                "联网更新 API 地址",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            Spacer()
                            if addressUpdateState.isUpdating {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(addressUpdateState.isUpdating)

                    if let feedback = addressUpdateState.feedback {
                        Label(
                            feedback.message,
                            systemImage: feedback.isError
                                ? "exclamationmark.triangle.fill"
                                : "checkmark.circle.fill"
                        )
                        .font(.footnote)
                        .foregroundColor(feedback.isError ? .red : .green)
                    }
                }
            }
        }
        .navigationTitle("网络")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadDraft)
        .onChange(of: settings.platformID) { _ in
            addressUpdateRequestID = nil
            addressUpdateState = .idle
            loadDraft()
        }
        .task(id: addressUpdateRequestID) {
            guard addressUpdateRequestID != nil else { return }
            await updateAPIAddress()
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

    private var serverConfigurationFooter: String {
        let manualInstructions = "手动编辑后点按“应用配置”。切换服务器会清除当前登录与"
            + "线路信息，并按平台分别保存配置。"
        guard settings.platformID == .acFan else {
            return manualInstructions
        }
        return "“联网更新 API 地址”会通过当前网络获取最新的接口地址，并立即应用" + manualInstructions
    }

    private func loadDraft() {
        baseURLDraft = settings.baseURLText
        apiPrefixDraft = settings.apiPrefix
    }

    private func applyDraft() {
        addressUpdateState = .idle
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

    private func updateAPIAddress() async {
        addressUpdateState = .updating
        do {
            let address = try await AcFanAPIAddressDiscovery.discover(
                route: settings.appNetworkRoute()
            )
            try Task.checkCancellation()
            try settings.applyServerConfiguration(
                baseURLText: address.baseURLText,
                apiPrefix: settings.apiPrefix
            )
            loadDraft()
            addressUpdateState = .success(
                "Base URL 已更新为 \(settings.baseURLText)。"
            )
        } catch is CancellationError {
            addressUpdateState = .idle
        } catch let error as URLError where error.code == .cancelled {
            addressUpdateState = .idle
        } catch {
            addressUpdateState = .failure(error.localizedDescription)
        }
    }
}

private enum APIAddressUpdateState {
    case idle
    case updating
    case success(String)
    case failure(String)

    var isUpdating: Bool {
        if case .updating = self { return true }
        return false
    }

    var feedback: (message: String, isError: Bool)? {
        switch self {
        case .idle, .updating:
            return nil
        case .success(let message):
            return (message, false)
        case .failure(let message):
            return (message, true)
        }
    }
}
