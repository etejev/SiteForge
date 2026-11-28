import SwiftUI

enum FillLayerNumericDraftError: Error, Equatable {
    case empty
    case notFinite
    case outsidePercentageRange

    var message: String {
        switch self {
        case .empty, .notFinite:
            "Enter a finite number."
        case .outsidePercentageRange:
            "Enter a position from 0 through 100 percent."
        }
    }
}

enum FillLayerNumericDraftValidator {
    static func angle(_ text: String) -> Result<Double, FillLayerNumericDraftError> {
        finiteNumber(text).map { angle in
            let remainder = angle.truncatingRemainder(dividingBy: 360)
            return remainder < 0 ? remainder + 360 : remainder
        }
    }

    static func percentage(_ text: String) -> Result<Double, FillLayerNumericDraftError> {
        finiteNumber(text).flatMap { value in
            guard (0...100).contains(value) else { return .failure(.outsidePercentageRange) }
            return .success(value / 100)
        }
    }

    private static func finiteNumber(_ text: String) -> Result<Double, FillLayerNumericDraftError> {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return .failure(.empty) }
        guard let value = Double(candidate), value.isFinite else { return .failure(.notFinite) }
        return .success(value)
    }
}

/// Accessible editor for the canonical `style.fill.layers.v1` list. The
/// controls intentionally submit value edits to `DesignInspectorCommandRegistry`
/// through `WorkspaceShellState`; their row state is a document projection,
/// never a second mutable layer model.
struct FillLayerListInspectorView: View {
    @ObservedObject var state: WorkspaceShellState
    @Binding var activeFillID: FillLayerID?
    private var layers: [CanonicalFillLayer] { state.designInspectorFillLayers() }

    var body: some View {
        GroupBox("Fill Layers") {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            if let reason = state.designInspectorLayerEditingReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("inspector.design.layers.unavailable")
            } else {
                if let summary = state.designInspectorLayerSelectionSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("inspector.design.layers.selectionSummary")
                }
                ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                    layerRow(layer, index: index)
                }
                HStack(spacing: 7) {
                    Button("Add Solid") {
                        _ = state.commitDesignFillLayer(
                            .addSolid(id: FillLayerID(), color: .legacySurface),
                            operation: "add solid layer", provenance: .accessibility
                        )
                    }
                    .accessibilityIdentifier("inspector.design.layers.addSolid")
                    Button("Add Linear Gradient") {
                        let id = FillLayerID()
                        if state.commitDesignFillLayer(
                            .addLinearGradient(
                                id: id, angleDegrees: 0,
                                stops: [
                                    .init(id: GradientStopID(), position: 0, color: .legacySurface),
                                    .init(id: GradientStopID(), position: 1, color: .init(red: 0.18, green: 0.36, blue: 0.86, alpha: 1)),
                                ]
                            ), operation: "add linear gradient", provenance: .accessibility
                        ) {
                            activeFillID = id
                        }
                    }
                    .accessibilityIdentifier("inspector.design.layers.addGradient")
                }
                .controlSize(.small)
            }
        }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fill layers")
        .accessibilityIdentifier("inspector.design.layers")
    }

    @ViewBuilder
    private func layerRow(_ layer: CanonicalFillLayer, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Button("Delete", systemImage: "trash") {
                    _ = state.commitDesignFillLayer(.remove(layer.id), operation: "remove fill layer", provenance: .accessibility)
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 28, minHeight: 24)
                .controlSize(.small)
                .accessibilityLabel("Delete fill layer")
                .accessibilityIdentifier("inspector.design.layers.\(layer.id.description).delete")
                Toggle(isOn: Binding(
                    get: { layer.isEnabled },
                    set: { enabled in
                        _ = state.commitDesignFillLayer(.setEnabled(layer.id, enabled), operation: enabled ? "enable fill layer" : "disable fill layer", provenance: .accessibility)
                    }
                )) {
                    Text(layer.kind == .solid ? "Solid fill" : "Linear gradient")
                        .lineLimit(1)
                }
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("inspector.design.layers.\(layer.id.description).enabled")
                Spacer(minLength: 0)
            }
            if layer.kind == .solid, let color = layer.solidColor {
                DesignColorEditor(state: state, color: color, isEnabled: layer.isEnabled,
                    label: "Solid fill color", identifier: "inspector.design.layers.\(layer.id.description).color",
                    edit: { .fill(.setSolidColor(layer.id, $0)) })
            }
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button("Up") { move(layer, from: index, by: -1) }
                    .disabled(index == 0)
                    .accessibilityIdentifier("inspector.design.layers.\(layer.id.description).up")
                Button("Down") { move(layer, from: index, by: 1) }
                    .disabled(index + 1 == layers.count)
                    .accessibilityIdentifier("inspector.design.layers.\(layer.id.description).down")
            }
            .controlSize(.small)
        }
        .padding(6)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector.design.layers.\(layer.id.description).row")
    }

    private func move(_ layer: CanonicalFillLayer, from index: Int, by delta: Int) {
        let target = index + delta
        guard layers.indices.contains(target) else { return }
        _ = state.commitDesignFillLayer(.reorder(layer.id, to: target), operation: "reorder fill layer", provenance: .accessibility)
    }
}
