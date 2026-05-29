import PaperInboxCore
import SwiftUI

enum CollectionTagSize {
    case mini
    case regular

    var font: Font {
        switch self {
        case .mini:
            return .caption2.weight(.medium)
        case .regular:
            return .caption.weight(.medium)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .mini:
            return 6
        case .regular:
            return 9
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .mini:
            return 3
        case .regular:
            return 5
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .mini:
            return 5
        case .regular:
            return 6
        }
    }

    var maximumTextWidth: CGFloat {
        switch self {
        case .mini:
            return 96
        case .regular:
            return 170
        }
    }
}

enum CollectionTagColor {
    static func color(for collection: PaperCollection, in allCollections: [PaperCollection]) -> Color {
        let orderedCollections = allCollections.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        guard let index = orderedCollections.firstIndex(where: { $0.id == collection.id }) else {
            return color(for: collection)
        }

        return palette[index % palette.count]
    }

    static func color(for collection: PaperCollection) -> Color {
        let seed = collection.id.isEmpty ? collection.name : collection.id
        return palette[stableIndex(for: seed, count: palette.count)]
    }

    private static let palette: [Color] = (0..<72).map { index in
        let hue = (Double(index) * 0.618_033_988_749_895).truncatingRemainder(dividingBy: 1)
        let saturationBands = [0.62, 0.74, 0.54, 0.68]
        let brightnessBands = [0.72, 0.62, 0.80]
        return Color(
            hue: hue,
            saturation: saturationBands[index % saturationBands.count],
            brightness: brightnessBands[(index / saturationBands.count) % brightnessBands.count]
        )
    }

    private static func stableIndex(for value: String, count: Int) -> Int {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return Int(hash % UInt64(count))
    }
}

struct CollectionTagView: View {
    let collection: PaperCollection
    var allCollections: [PaperCollection] = []
    var isSelected = true
    var size: CollectionTagSize = .regular
    var showsCheckmark = false

    private var baseColor: Color {
        allCollections.isEmpty
            ? CollectionTagColor.color(for: collection)
            : CollectionTagColor.color(for: collection, in: allCollections)
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(collection.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: size.maximumTextWidth, alignment: .leading)

            if showsCheckmark && isSelected {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
            }
        }
        .font(size.font)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(baseColor.opacity(isSelected ? 0.20 : 0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .stroke(baseColor.opacity(isSelected ? 0.58 : 0.28), lineWidth: 1)
        )
    }
}

struct CollectionTagStripView: View {
    let collections: [PaperCollection]
    var allCollections: [PaperCollection] = []
    var limit = 3
    var size: CollectionTagSize = .mini

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(collections.prefix(limit))) { collection in
                CollectionTagView(
                    collection: collection,
                    allCollections: allCollections.isEmpty ? collections : allCollections,
                    size: size
                )
            }

            let remainingCount = collections.count - min(collections.count, limit)
            if remainingCount > 0 {
                Text("+\(remainingCount)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.secondary.opacity(0.10))
                    )
            }
        }
        .lineLimit(1)
    }
}
