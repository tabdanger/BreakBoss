// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI

struct EngineControlsView: View {
    @ObservedObject var controller: KnockController
    @Environment(\.dismiss) private var dismiss
    private var controls: [KParam] {
        switch controller.mode {
        case .modern: return [.boost, .punch, .analogEQ, .tighten, .grit, .shine, .noise]
        case .vintage: return [.drive, .bounce, .velocity, .grit, .shine, .tighten, .noise]
        case .texture: return [.resample, .instability, .textureDelay, .gatedReverb, .drive, .shine, .noise]
        }
    }
    var body: some View {
        NavigationView {
            Form {
                Picker("World", selection: Binding(get: { controller.mode.rawValue }, set: {
                    controller.selectMode(SoundMode(rawValue: $0) ?? .modern)
                })) {
                    ForEach(SoundMode.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }.pickerStyle(.segmented)
                Section("Instrument") {
                    Picker("Pad behavior", selection: Binding(get: { controller.playMode.rawValue }, set: {
                        controller.selectPlayMode(PlayMode(rawValue: $0) ?? .oneShot)
                    })) {
                        Text("One-Shot").tag(PlayMode.oneShot.rawValue)
                        Text("Loop").tag(PlayMode.loop.rawValue)
                    }.pickerStyle(.segmented)
                    ForEach([KParam.pitch, .tune, .velocity, .filter, .clipDrive, .output], id: \.rawValue) { parameter in
                        parameterSlider(parameter)
                    }
                }
                Section(controller.mode.title) {
                    ForEach(controls, id: \.rawValue) { parameter in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(parameter == .bounce ? "Swing" : parameter.name)
                                Spacer()
                                Text(parameter.text(controller.value(parameter))).foregroundColor(.secondary)
                            }
                            Slider(value: Binding(get: { controller.value(parameter) }, set: { controller.set(parameter, $0) }), in: 0...1)
                                .tint(ScopeView.red)
                        }
                    }
                }
                Section("Master") {
                    Toggle("Clipper", isOn: Binding(get: { controller.value(.clipper) > 0.5 }, set: { controller.set(.clipper, $0 ? 1 : 0) }))
                    Toggle("Tempo sync", isOn: Binding(get: { controller.value(.tempoSync) > 0.5 }, set: { controller.set(.tempoSync, $0 ? 1 : 0) }))
                    Toggle("Follow DAW", isOn: Binding(get: { controller.value(.followDAW) > 0.5 }, set: { controller.set(.followDAW, $0 ? 1 : 0) }))
                }
            }
            .navigationTitle("Engine controls").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.navigationViewStyle(.stack).preferredColorScheme(.dark)
    }

    private func parameterSlider(_ parameter: KParam) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(parameter.name)
                Spacer()
                Text(parameter.text(controller.value(parameter))).foregroundColor(.secondary)
            }
            Slider(value: Binding(get: { controller.value(parameter) }, set: { controller.set(parameter, $0) }), in: 0...1)
                .tint(ScopeView.red)
        }
    }
}
