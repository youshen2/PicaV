import SwiftUI

struct RemoteImageViewer: View {
    @Environment(\.presentationMode) private var presentationMode

    private let urls: [URL]
    @State private var selectedIndex: Int

    init(urls: [URL], initialIndex: Int) {
        self.urls = urls
        let lastIndex = max(0, urls.count - 1)
        _selectedIndex = State(
            initialValue: min(max(0, initialIndex), lastIndex)
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if urls.isEmpty {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(
                        Array(urls.enumerated()),
                        id: \.offset
                    ) { index, url in
                        RemoteImageView(
                            url: url,
                            maxPixelSize: 2_000,
                            contentMode: .fit,
                            backgroundColor: .black
                        )
                        .tag(index)
                        .ignoresSafeArea()
                    }
                }
                .tabViewStyle(
                    PageTabViewStyle(indexDisplayMode: .never)
                )
            }
        }
        .overlay(alignment: .top) {
            HStack(spacing: 12) {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .foregroundColor(.white)
                .accessibilityLabel("关闭图片预览")

                Spacer()

                if urls.count > 1 {
                    Text("\(selectedIndex + 1) / \(urls.count)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel(
                            "第 \(selectedIndex + 1) 张，共 \(urls.count) 张"
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
    }
}
