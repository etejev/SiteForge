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

private enum FillLayerNumericField: Hashable {
    case angle(FillLayerID)
    case stop(FillLayerID, GradientStopID)
}

/// Accessible editor for the canonical `style.fill.layers.v1` list. The
/// controls intentionally submit value edits to `DesignInspectorCommandRegistry`
/// through `WorkspaceShellState`; their row state is a document projection,
/// never a second mutable layer model.
struct FillLayerListInspectorView: View {
    @ObservedObject var state: WorkspaceShellState
    @State private var angleDrafts: [FillLayerID: String] = [:]
    @State private var stopDrafts: [GradientStopID: String] = [:]
    @State private var validationMessages: [FillLayerNumericField: String] = [:]
    @FocusState private var focusedNumericField: FillLayerNumericField?

    private var layers: [CanonicalFillLayer] { state.designInspectorFillLayers() }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
            Text("Fill Layers").font(.headline)
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
                        _ = state.commitDesignFillLayer(
                            .addLinearGradient(
                                id: FillLayerID(), angleDegrees: 0,
                                stops: [
                                    .init(id: GradientStopID(), position: 0, color: .legacySurface),
                                    .init(id: GradientStopID(), position: 1, color: .init(red: 0.18, green: 0.36, blue: 0.86, alpha: 1)),
                                ]
                            ), operation: "add linear gradient", provenance: .accessibility
                        )
                    }
                    .accessibilityIdentifier("inspector.design.layers.addGradient")
                }
                .controlSize(.small)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fill layers")
        .accessibilityIdentifier("inspector.design.layers")
        .onChange(of: focusedNumericField) { previous, current in
            guard let previous, previous != current else { return }
            commitDraft(for: previous)
        }
        .onExitCommand { discardNumericDrafts() }
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
                if layer.kind == .solid, let color = layer.solidColor {
                    NativeDesignColorWell(
                        color: color,
                        isEnabled: layer.isEnabled,
                        accessibilityValue: color.hexadecimalRGBA,
                        accessibilityHint: "Open the native color panel to edit this solid fill layer.",
                        accessibilityIdentifier: "inspector.design.layers.\(layer.id.description).color",
                        accessibilityLabel: "Solid fill color",
                        onCommit: { color in
                            _ = state.commitDesignFillLayer(.setSolidColor(layer.id, color), operation: "edit solid layer color", provenance: .picker)
                        }
                    )
                    .frame(width: 38, height: 22)
                }
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
            if layer.kind == .linearGradient {
                HStack(spacing: 6) {
                    Text("Angle")
                        .font(.caption)
                    TextField("Angle", text: angleBinding(for: layer))
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 54, maxWidth: 80)
                        .focused($focusedNumericField, equals: .angle(layer.id))
                        .onSubmit { commitAngle(layer) }
                        .accessibilityLabel("Linear gradient angle")
                        .accessibilityHint("Enter a finite angle. Return or moving focus commits; Escape restores the authored value.")
                        .accessibilityIdentifier("inspector.design.layers.\(layer.id.description).angle")
                    Text("°").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Button("Add Stop") {
                    _ = state.commitDesignFillLayer(
                        .addStop(layer.id, .init(id: GradientStopID(), position: 0.5, color: .legacySurface), at: layer.stops.count),
                        operation: "add gradient stop", provenance: .accessibility
                    )
                }
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("inspector.design.layers.\(layer.id.description).addStop")
                if let message = validationMessages[.angle(layer.id)] {
                    validationMessage(message, identifier: "inspector.design.layers.\(layer.id.description).angle.validation")
                }
                ForEach(Array(layer.stops.enumerated()), id: \.element.id) { stopIndex, stop in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Stop \(stopIndex + 1)")
                                .font(.caption.weight(.medium))
                            NativeDesignColorWell(
                                color: stop.color,
                                isEnabled: layer.isEnabled,
                                accessibilityValue: stop.color.hexadecimalRGBA,
                                accessibilityHint: "Open the native color panel to edit this gradient stop.",
                                accessibilityIdentifier: "inspector.design.layers.\(layer.id.description).stop.\(stop.id.description).color",
                                accessibilityLabel: "Gradient stop color",
                                onCommit: { color in
                                    _ = state.commitDesignFillLayer(.setStop(layer.id, stop.id, position: stop.position, color: color), operation: "edit gradient stop color", provenance: .picker)
                                }
                            )
                            .frame(width: 38, height: 22)
                            TextField("Position", text: stopBinding(for: stop))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 54)
                                .focused($focusedNumericField, equals: .stop(layer.id, stop.id))
                                .onSubmit { commitStopPosition(stop, in: layer) }
                                .accessibilityLabel("Gradient stop position")
                                .accessibilityHint("Enter 0 through 100. Return or moving focus commits; Escape restores the authored value.")
                                .accessibilityIdentifier("inspector.design.layers.\(layer.id.description).stop.\(stop.id.description).position")
                            Text("%")
                            Button("Move Up", systemImage: "arrow.up") {
                                moveStop(stop, in: layer, from: stopIndex, by: -1)
                            }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 28, minHeight: 24)
                            .disabled(stopIndex == 0)
                            .accessibilityLabel("Move gradient stop up")
                            .accessibilityHint("Move this stop earlier in the authored gradient stop order.")
                            .accessibilityIdentifier("inspector.design.layers.\(layer.id.description).stop.\(stop.id.description).up")
                            Button("Move Down", systemImage: "arrow.down") {
                                moveStop(stop, in: layer, from: stopIndex, by: 1)
                            }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 28, minHeight: 24)
                            .disabled(stopIndex + 1 == layer.stops.count)
                            .accessibilityLabel("Move gradient stop down")
                            .accessibilityHint("Move this stop later in the authored gradient stop order.")
                            .accessibilityIdentifier("inspector.design.layers.\(layer.id.description).stop.\(stop.id.description).down")
                            Button("Remove Stop", systemImage: "trash") {
                                _ = state.commitDesignFillLayer(.removeStop(layer.id, stop.id), operation: "remove gradient stop", provenance: .accessibility)
                            }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 28, minHeight: 24)
                            .disabled(layer.stops.count <= 2)
                            .accessibilityLabel("Remove gradient stop")
                            .accessibilityIdentifier("inspector.design.layers.\(layer.id.description).stop.\(stop.id.description).remove")
                        }
                        .controlSize(.small)
                        if let message = validationMessages[.stop(layer.id, stop.id)] {
                            validationMessage(
                                message,
                                identifier: "inspector.design.layers.\(layer.id.description).stop.\(stop.id.description).position.validation"
                            )
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("inspector.design.layers.\(layer.id.description).stop.\(stop.id.description).row")
                }
            }
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

    private func moveStop(_ stop: CanonicalGradientStop, in layer: CanonicalFillLayer, from index: Int, by delta: Int) {
        let target = index + delta
        guard layer.stops.indices.contains(target) else { return }
        _ = state.commitDesignFillLayer(
            .reorderStop(layer.id, stop.id, to: target),
            operation: "reorder gradient stop",
            provenance: .accessibility
        )
    }

    private func angleBinding(for layer: CanonicalFillLayer) -> Binding<String> {
        let field = FillLayerNumericField.angle(layer.id)
        return Binding(
            get: { angleDrafts[layer.id] ?? String(format: "%.0f", layer.normalizedAngleDegrees ?? 0) },
            set: {
                angleDrafts[layer.id] = $0
                validationMessages.removeValue(forKey: field)
            }
        )
    }

    private func stopBinding(for stop: CanonicalGradientStop) -> Binding<String> {
        Binding(
            get: { stopDrafts[stop.id] ?? String(format: "%.0f", stop.position * 100) },
            set: {
                stopDrafts[stop.id] = $0
                let matchingFields = validationMessages.keys.filter { field in
                    guard case .stop(_, let stopID) = field else { return false }
                    return stopID == stop.id
                }
                for field in matchingFields {
                    validationMessages.removeValue(forKey: field)
                }
            }
        )
    }

    private func commitAngle(_ layer: CanonicalFillLayer) {
        let field = FillLayerNumericField.angle(layer.id)
        guard let text = angleDrafts[layer.id] else { return }
        switch FillLayerNumericDraftValidator.angle(text) {
        case .failure(let error):
            validationMessages[field] = error.message
        case .success(let angle):
            guard state.commitDesignFillLayer(
                .setGradientAngle(layer.id, angle),
                operation: "edit gradient angle",
                provenance: .keyboard
            ) else {
                validationMessages[field] = state.designInspectorFailure?.localizedDescription ?? "The angle could not be committed."
                return
            }
            angleDrafts.removeValue(forKey: layer.id)
            validationMessages.removeValue(forKey: field)
        }
    }

    private func commitStopPosition(_ stop: CanonicalGradientStop, in layer: CanonicalFillLayer) {
        let field = FillLayerNumericField.stop(layer.id, stop.id)
        guard let text = stopDrafts[stop.id] else { return }
        switch FillLayerNumericDraftValidator.percentage(text) {
        case .failure(let error):
            validationMessages[field] = error.message
        case .success(let position):
            guard state.commitDesignFillLayer(
                .setStop(layer.id, stop.id, position: position, color: stop.color),
                operation: "edit gradient stop",
                provenance: .keyboard
            ) else {
                validationMessages[field] = state.designInspectorFailure?.localizedDescription ?? "The stop position could not be committed."
                return
            }
            stopDrafts.removeValue(forKey: stop.id)
            validationMessages.removeValue(forKey: field)
        }
    }

    private func commitDraft(for field: FillLayerNumericField) {
        switch field {
        case .angle(let layerID):
            guard let layer = layers.first(where: { $0.id == layerID }) else {
                angleDrafts.removeValue(forKey: layerID)
                validationMessages.removeValue(forKey: field)
                return
            }
            commitAngle(layer)
        case .stop(let layerID, let stopID):
            guard let layer = layers.first(where: { $0.id == layerID }),
                  let stop = layer.stops.first(where: { $0.id == stopID }) else {
                stopDrafts.removeValue(forKey: stopID)
                validationMessages.removeValue(forKey: field)
                return
            }
            commitStopPosition(stop, in: layer)
        }
    }

    private func discardNumericDrafts() {
        angleDrafts.removeAll()
        stopDrafts.removeAll()
        validationMessages.removeAll()
        focusedNumericField = nil
    }

    private func validationMessage(_ message: String, identifier: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityLabel("Invalid value")
            .accessibilityValue(message)
            .accessibilityIdentifier(identifier)
    }
}
