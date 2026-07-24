import SwiftUI

struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 20)
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct SettingsStatusLabel: View {
    let text: String
    let isActive: Bool

    var body: some View {
        Label(text, systemImage: isActive ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundColor(isActive ? .green : .secondary)
    }
}
