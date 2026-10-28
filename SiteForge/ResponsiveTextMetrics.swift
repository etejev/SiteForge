import CoreText
import Foundation

struct InstalledTypographyFamily: Equatable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    let weights: [CanonicalFontWeight]
}

/// Local font metadata only; never import, register, download or package fonts.
/// Call off-main. Real upright descriptors, not synthesized requests, determine
/// which of the model's four named weights can be offered as installed faces.
enum InstalledTypographyCatalog {
    static func load() -> [InstalledTypographyFamily] {
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? []
        var families: [String: [CanonicalFontWeight]] = [:]
        for descriptor in descriptors {
            guard let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String,
                  !family.isEmpty, family.trimmingCharacters(in: .whitespacesAndNewlines) == family,
                  !family.hasPrefix("."), family.utf8.count <= 128,
                  family.rangeOfCharacter(from: .controlCharacters) == nil else { continue }
            let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [String: Any] ?? [:]
            let symbolic = (traits[kCTFontSymbolicTrait as String] as? NSNumber)?.uint32Value ?? 0
            guard symbolic & CTFontSymbolicTraits.traitItalic.rawValue == 0 else { continue }
            let weight = (traits[kCTFontWeightTrait as String] as? NSNumber)?.doubleValue ?? 0
            if let named = namedWeight(for: weight), !families[family, default: []].contains(named) { families[family, default: []].append(named) }
        }
        families[CanonicalTypography.defaultFamily] = CanonicalFontWeight.allCases
        return families.map { name, weights in
            .init(name: name, weights: CanonicalFontWeight.allCases.filter(weights.contains))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func namedWeight(for trait: Double) -> CanonicalFontWeight? {
        guard trait.isFinite else { return nil }
        let values: [(CanonicalFontWeight, Double)] = [(.regular, 0), (.medium, 0.23), (.semibold, 0.30), (.bold, 0.40)]
        guard let best = values.min(by: { abs($0.1 - trait) < abs($1.1 - trait) }), abs(best.1 - trait) <= 0.055 else { return nil }
        return best.0
    }
    static func matching(_ query: String, in families: [InstalledTypographyFamily]) -> [InstalledTypographyFamily] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return families.filter { text.isEmpty || $0.name.localizedCaseInsensitiveContains(text) }
    }
}

/// SF-0501/0505/0507: platform text shaping without AppKit view ownership.
/// The renderer/editor resolve this same font name; canonical text remains
/// unchanged when a family is unavailable. No mutable font/layout cache exists.
enum ResponsiveTextMetrics {
    struct Font: Equatable, Sendable {
        let postScriptName: String
        let family: String
        let usesFallback: Bool
    }

    static func font(family: String, weight: String, size: Double) -> Font {
        let resolved = platformFont(family: family, weight: weight, size: size)
        return .init(postScriptName: CTFontCopyPostScriptName(resolved) as String,
            family: CTFontCopyFamilyName(resolved) as String,
            usesFallback: family != CanonicalTypography.defaultFamily
                && (CTFontCopyFamilyName(resolved) as String).caseInsensitiveCompare(family) != .orderedSame)
    }

    /// CTFont and NSFont are toll-free bridged. Recreating a private system
    /// font by PostScript name is unsupported and silently substitutes Times.
    static func platformFont(family: String, weight: String, size: Double, opticalSize: Double? = nil) -> CTFont {
        let value: Double = switch weight {
        case "medium": 0.23
        case "semibold": 0.30
        case "bold": 0.40
        default: 0
        }
        let traits = [kCTFontWeightTrait: value] as CFDictionary
        let system = CTFontCreateUIFontForLanguage(.system, CGFloat(size), nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, CGFloat(size), nil)
        let requested = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: family,
            kCTFontTraitsAttribute: traits,
            kCTFontOpticalSizeAttribute: opticalSize ?? size,
        ] as CFDictionary)
        let candidate = CTFontCreateWithFontDescriptor(requested, CGFloat(size), nil)
        let found = (CTFontCopyFamilyName(candidate) as String).caseInsensitiveCompare(family) == .orderedSame
        let useSystem = family == CanonicalTypography.defaultFamily || !found
        let descriptor = useSystem ? CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(system), [kCTFontTraitsAttribute: traits,
                kCTFontOpticalSizeAttribute: opticalSize ?? size] as CFDictionary) : requested
        return CTFontCreateWithFontDescriptor(descriptor, CGFloat(size), nil)
    }

    static func height(text: String, width: Double, typography: CanonicalTypography) -> Double {
        let font = platformFont(family: typography.family, weight: typography.weight.rawValue, size: typography.size)
        // The four-point horizontal text inset is shared with CanvasTextLayout.
        let available = max(1, width - 8)
        let content = text as NSString
        let attributed = NSAttributedString(string: text, attributes: [
            .init(rawValue: kCTFontAttributeName as String): font,
            .init(rawValue: kCTKernAttributeName as String): typography.tracking,
        ])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed as CFAttributedString)
        var offset = 0, lines = 0
        let maximumLines = Int(ceil(CanonicalSizingConstraints.maximum / max(1, typography.lineHeight)))
        while offset < content.length, lines < maximumLines {
            var count = CTTypesetterSuggestLineBreak(typesetter, offset, available)
            if count <= 0 { count = CTTypesetterSuggestClusterBreak(typesetter, offset, available) }
            if count <= 0 { count = content.rangeOfComposedCharacterSequence(at: offset).length }
            offset += count
            lines += 1
        }
        if content.length == 0 || text.hasSuffix("\n") { lines += 1 }
        return min(CanonicalSizingConstraints.maximum, max(1, Double(lines) * typography.lineHeight))
    }
}
