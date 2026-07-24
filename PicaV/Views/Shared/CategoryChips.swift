import SwiftUI

struct CategoryChips: View {
    let categories: [AnimeCategory]
    let selectedID: String?
    var includesAll = false
    let selection: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if includesAll {
                    chip(title: "全部", id: nil)
                }
                ForEach(categories) { category in
                    chip(title: category.title, id: category.id)
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(title: String, id: String?) -> some View {
        Button {
            selection(id)
        } label: {
            Text(title)
                .font(.subheadline.weight(selectedID == id ? .semibold : .regular))
                .foregroundColor(selectedID == id ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selectedID == id ? Color.accentColor : Color(.secondarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
