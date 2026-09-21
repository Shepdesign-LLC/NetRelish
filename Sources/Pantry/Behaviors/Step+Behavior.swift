// Step+Behavior.swift — hand-written mirror of the diagram's Step.execute (ADR 0004).

import Foundation
import GRDB

extension Step: StepMethods {
    /// `params` is the step's JSON object. Keys used: `label` (a Label id), `jar` (a Jar id).
    var decodedParams: [String: Any] {
        guard let params, let obj = try? JSONSerialization.jsonObject(with: params) as? [String: Any] else { return [:] }
        return obj
    }

    /// Applies one action to one item and returns the updated item. Actions the app
    /// performs on-device from the sealed snapshot (summarize, extractLinks, …) are
    /// no-ops here, exactly as in the diagram: the Pantry records, it does not read pages.
    @discardableResult
    public mutating func execute(_ db: Database, item: Item) throws -> Item {
        var item = item
        let params = decodedParams
        switch action {
        case .addLabel:
            if let label = params["label"] as? String {
                var ids = try item.labels(db).map(\.id)
                if !ids.contains(label) { ids.append(label) }
                try item.setLabels(ids, db)
            }
        case .removeLabel:
            if let label = params["label"] as? String {
                let ids = try item.labels(db).map(\.id).filter { $0 != label }
                try item.setLabels(ids, db)
            }
        case .moveToJar:
            if let jar = params["jar"] as? String {
                item.jarId = jar
                item.state = .jarred
            }
        case .seal:
            try item.seal(db)
        case .summarize, .extractLinks, .extractTasks, .ocrImage, .exportMarkdown, .exportPDF, .runShortcut, .notify:
            break
        }
        item.updatedAt = Date()
        try item.update(db)
        return item
    }
}
