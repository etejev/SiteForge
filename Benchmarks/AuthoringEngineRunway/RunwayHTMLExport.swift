import Foundation

struct RunwayHTMLExport: Sendable {
    func document(root: RunwayLayoutNode, viewport: RunwaySize) throws -> String {
        guard viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0 else { throw RunwayError.invalidConstraints }
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><style>
        html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden}
        *{box-sizing:border-box}
        .node{background:transparent;border:0 solid transparent}
        </style></head><body>
        \(element(root, parentAxis: nil, isRoot: true, viewport: viewport))
        </body></html>
        """
    }

    private func element(
        _ node: RunwayLayoutNode,
        parentAxis: RunwayAxis?,
        isRoot: Bool,
        viewport: RunwaySize
    ) -> String {
        var declarations: [String] = ["position:relative"]
        if isRoot {
            declarations += ["width:\(px(viewport.width))", "height:\(px(viewport.height))"]
        } else {
            declarations += dimension("width", node.width, intrinsic: node.intrinsic.width, isMain: parentAxis == .horizontal)
            declarations += dimension("height", node.height, intrinsic: node.intrinsic.height, isMain: parentAxis == .vertical)
            let mainRule = parentAxis == .horizontal ? node.width : node.height
            declarations.append(mainRule == .fill ? "flex:1 1 0" : "flex:0 0 auto")
        }
        declarations += [
            "min-width:\(px(node.constraints.minWidth))",
            "min-height:\(px(node.constraints.minHeight))",
        ]
        if node.constraints.maxWidth.isFinite { declarations.append("max-width:\(px(node.constraints.maxWidth))") }
        if node.constraints.maxHeight.isFinite { declarations.append("max-height:\(px(node.constraints.maxHeight))") }
        if let axis = node.axis {
            declarations += [
                "display:flex",
                "flex-direction:\(axis == .horizontal ? "row" : "column")",
                "align-items:\(alignment(node.alignment))",
                "gap:\(px(node.gap))",
                "padding:\(px(node.padding.top)) \(px(node.padding.trailing)) \(px(node.padding.bottom)) \(px(node.padding.leading))",
                "overflow:\(node.overflow == .clip ? "hidden" : "visible")",
            ]
        }
        let children = node.children.map {
            element($0, parentAxis: node.axis, isRoot: false, viewport: viewport)
        }.joined()
        return "<div class=\"node\" data-runway-id=\"\(escaped(node.id.rawValue))\" style=\"\(declarations.joined(separator: ";"))\">\(children)</div>"
    }

    private func dimension(_ name: String, _ length: RunwayLength, intrinsic: Double, isMain: Bool) -> [String] {
        switch length {
        case .fixed(let value): return ["\(name):\(px(value))"]
        case .intrinsic: return ["\(name):\(px(intrinsic))"]
        case .fill: return isMain ? [] : ["\(name):100%"]
        }
    }

    private func alignment(_ alignment: RunwayAlignment) -> String {
        switch alignment {
        case .start: "flex-start"
        case .center: "center"
        case .end: "flex-end"
        case .stretch: "stretch"
        }
    }

    private func px(_ value: Double) -> String { String(format: "%.6fpx", value) }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
