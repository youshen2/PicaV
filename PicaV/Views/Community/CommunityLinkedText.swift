import Foundation
import SwiftUI

struct CommunityLinkedText: View {
    let content: String
    let font: Font
    var linksAreInteractive = true

    var body: some View {
        Text(
            CommunityLinkHighlighter.attributedString(
                content,
                linksAreInteractive: linksAreInteractive
            )
        )
        .font(font)
        .foregroundColor(.primary)
    }
}

private enum CommunityLinkHighlighter {
    static func attributedString(
        _ content: String,
        linksAreInteractive: Bool
    ) -> AttributedString {
        guard let detector else { return AttributedString(content) }

        let matches = detector.matches(
            in: content,
            range: NSRange(content.startIndex..., in: content)
        )
        guard !matches.isEmpty else { return AttributedString(content) }

        var result = AttributedString("")
        var cursor = content.startIndex

        for match in matches {
            guard let url = match.url,
                  let range = Range(match.range, in: content) else {
                continue
            }

            result.append(
                AttributedString(String(content[cursor..<range.lowerBound]))
            )

            var linkedText = AttributedString(String(content[range]))
            linkedText.foregroundColor = .accentColor
            if linksAreInteractive {
                linkedText.link = url
            }
            result.append(linkedText)
            cursor = range.upperBound
        }

        result.append(AttributedString(String(content[cursor...])))
        return result
    }

    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )
}
