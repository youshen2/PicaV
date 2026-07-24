import SwiftUI

struct LoadStateView: View {
    let state: LoadState
    var retry: (() -> Void)?

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("正在载入番剧…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        case .loaded:
            EmptyView()
        case .failed(let message):
            EmptyStateView(
                systemImage: "wifi.exclamationmark",
                title: "暂时无法载入",
                message: message,
                actionTitle: retry == nil ? nil : "重试",
                action: retry
            )
            .frame(maxWidth: .infinity, minHeight: 280)
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(28)
    }
}
