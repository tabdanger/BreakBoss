// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import CoreAudioKit
import SwiftUI
import UIKit

// MARK: - The plug-in's window
//
// The host opens this when you show BreakBoss's interface. It's the same faceplate as the app,
// scaled to whatever size the host gives it. Closing the window doesn't stop the sound.

public final class BreakBossAUViewController: AUViewController, AUAudioUnitFactory {
    private var unit: BreakBossAudioUnit?
    private var hosting: UIHostingController<AnyView>?

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let made = try BreakBossAudioUnit(componentDescription: componentDescription, options: [])
        unit = made
        DispatchQueue.main.async { [weak self] in self?.showFaceplate() }
        return made
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // The faceplate is 1448 x 1086; hosts scale from about three quarters of that.
        preferredContentSize = CGSize(width: 1086, height: 815)
        showFaceplate()
    }

    private func showFaceplate() {
        guard isViewLoaded, hosting == nil, let unit else { return }
        let face = FaceplateView(controller: unit.controller).preferredColorScheme(.dark)
        let host = UIHostingController(rootView: AnyView(face))
        host.view.backgroundColor = .black
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hosting = host
    }
}
