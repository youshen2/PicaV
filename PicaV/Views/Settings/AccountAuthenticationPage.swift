import SwiftUI

struct AccountAuthenticationPage: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var client: AnimeAPIClient
    @Environment(\.presentationMode) private var presentationMode

    let action: PlatformAccountAction

    @State private var account = ""
    @State private var password = ""
    @State private var confirmedPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section(
                header: Text(settings.activePlatform.displayName),
                footer: Text(accountRules?.accountHint ?? "请输入平台账号")
            ) {
                TextField("账号", text: $account)
                    .textContentType(.username)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                SecureField("密码", text: $password)
                    .textContentType(action == .register ? .newPassword : .password)

                if action == .register {
                    SecureField("确认密码", text: $confirmedPassword)
                        .textContentType(.newPassword)
                }
            }

            if let passwordHint = accountRules?.passwordHint {
                Section {
                    Label(passwordHint, systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }

            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                                .padding(.trailing, 6)
                        }
                        Text(isSubmitting ? "\(action.title)中…" : action.title)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(isSubmitting || account.isEmpty || password.isEmpty)
            }
        }
        .navigationTitle(action.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var accountRules: PlatformAccountRules? {
        settings.activePlatform.accountAuthentication?.rules
    }

    private func submit() {
        errorMessage = localValidationError
        guard errorMessage == nil else { return }

        isSubmitting = true
        Task {
            do {
                try await client.authenticate(
                    account: account,
                    password: password,
                    action: action
                )
                presentationMode.wrappedValue.dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private var localValidationError: String? {
        guard let rules = accountRules else {
            return "当前平台暂不支持\(action.title)。"
        }
        if let message = rules.accountError(
            account.trimmingCharacters(in: .whitespacesAndNewlines)
        ) {
            return message
        }
        if let message = rules.passwordError(password) {
            return message
        }
        if action == .register, password != confirmedPassword {
            return "两次输入的密码不一致。"
        }
        return nil
    }
}
