// NetRelishIntents.swift — the app's App Intents package. It includes the Pantry's,
// which is where the intents themselves live.

import AppIntents
import Pantry

struct NetRelishIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [PantryIntents.self] }
}
