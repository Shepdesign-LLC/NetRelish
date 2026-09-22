#!/usr/bin/env swift
// gen-pantry.swift — reads design/NetRelish.json (System Designer MSON) and writes
// Sources/Pantry/Models/*.swift. The mapping is CLAUDE.md "Schema → Swift".
//
//   swift scripts/gen-pantry.swift design/NetRelish.json Sources/Pantry/Models
//
// What is generated (the SHAPE of the Pantry):
//   Types.swift          every enum type
//   <Model>.swift        a GRDB record per schema: columns, associations, events,
//                        and a `<Model>Methods` protocol listing each method with
//                        its JavaScript behavior quoted above it
//   Seed.swift           the components, as seed rows for the first migration
//
// What is NOT generated (the BEHAVIOR): the method bodies. They are hand-written in
// Sources/Pantry/Behaviors/<Model>+Behavior.swift, mirroring the quoted JS. Because
// each record must conform to its generated protocol, a method that exists in the
// diagram and not in Swift is a compile error, not a silent gap. (ADR 0004)
//
// Mapping (CLAUDE.md):
//   property string/number/boolean/date/object → String/Double/Bool/Date/Data
//   enum type                                  → enum Name: String, Codable, CaseIterable
//   link                                       → `<name>Id: String?` + belongsTo
//   collection [T]                             → hasMany via the inverse link, or a
//                                                join table when both sides are collections
//   method                                     → protocol requirement (body hand-written)
//   event                                      → PantryEvent<T> (AsyncStream + Notification)
//   the root schema (the system's name)        → a single-row table; its collections
//                                                are queries over the whole Pantry

import Foundation

// MARK: - CLI

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2 else {
    FileHandle.standardError.write("usage: gen-pantry.swift <NetRelish.json> <output-dir>\n".data(using: .utf8)!)
    exit(2)
}
func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("gen-pantry: error: \(msg)\n".data(using: .utf8)!)
    exit(1)
}
guard let data = FileManager.default.contents(atPath: args[0]),
      let bundle = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    fail("cannot read \(args[0]) as JSON")
}
let outDir = URL(fileURLWithPath: args[1])

// MARK: - Read the bundle

guard let sysName = bundle["name"] as? String else { fail("bundle has no name") }
let systemName: String = sysName
G.systemName = systemName
let types = bundle["types"] as? [String: [String: Any]] ?? [:]
let schemas = bundle["schemas"] as? [String: [String: Any]] ?? [:]
let models = bundle["models"] as? [String: [String: Any]] ?? [:]
let behaviors = bundle["behaviors"] as? [String: [String: Any]] ?? [:]
let components = bundle["components"] as? [String: [String: [String: Any]]] ?? [:]

struct Field {
    enum Kind { case property(String), link(String), collection(String), method, event }
    let name: String
    let kind: Kind
    let model: [String: Any]   // the model entry: type/readOnly/mandatory/default or params/result
}

enum G { nonisolated(unsafe) static var systemName = "" }
struct Model {
    let name: String
    let description: String
    let fields: [Field]
    var isRoot: Bool { name == G.systemName }
    var table: String { isRoot ? name.lowercased() : Model.plural(name.lowercased()) }
    static func plural(_ s: String) -> String { s.hasSuffix("s") || s.hasSuffix("h") ? s + "es" : s + "s" }
    func fields(_ k: (Field.Kind) -> Bool) -> [Field] { fields.filter { k($0.kind) } }
}

var modelsByName: [String: Model] = [:]
for (id, schema) in schemas {
    guard let name = schema["_name"] as? String else { fail("schema \(id) has no _name") }
    guard let model = models[id] else { fail("schema \(name) has no model") }
    var fields: [Field] = []
    for (key, roleAny) in schema where !key.hasPrefix("_") {
        guard let role = roleAny as? String, let entry = model[key] as? [String: Any] else {
            fail("\(name).\(key): missing in the model")
        }
        let kind: Field.Kind
        switch role {
        case "property":
            guard let t = entry["type"] as? String else { fail("\(name).\(key): property with no type") }
            kind = .property(t)
        case "link":
            guard let t = entry["type"] as? String else { fail("\(name).\(key): link with no type") }
            kind = .link(t)
        case "collection":
            guard let t = (entry["type"] as? [String])?.first else { fail("\(name).\(key): collection with no element type") }
            kind = .collection(t)
        case "method": kind = .method
        case "event": kind = .event
        default: fail("\(name).\(key): unknown role \(role)")
        }
        fields.append(Field(name: key, kind: kind, model: entry))
    }
    fields.sort { $0.name < $1.name }
    // Stable, readable order: properties, links, collections, events, methods.
    func rank(_ f: Field) -> Int {
        switch f.kind { case .property: 0; case .link: 1; case .collection: 2; case .event: 3; case .method: 4 }
    }
    fields.sort { rank($0) != rank($1) ? rank($0) < rank($1) : $0.name < $1.name }
    modelsByName[name] = Model(name: name, description: model["_description"] as? String ?? "", fields: fields)
}
guard modelsByName[systemName] != nil else { fail("no root schema named \(systemName)") }

// Behavior bodies, keyed by (component name, method).
var bodies: [String: String] = [:]
for (_, b) in behaviors {
    guard let comp = b["component"] as? String, let state = b["state"] as? String, let action = b["action"] as? String else { continue }
    bodies["\(comp).\(state)"] = action
}

// MARK: - Swift naming and types

func swiftType(_ t: String) -> String {
    switch t {
    case "string": "String"
    case "number": "Double"
    case "boolean": "Bool"
    case "date": "Date"
    case "object": "Data"
    default:
        if types[t] != nil { t }                      // an enum
        else if modelsByName[t] != nil { "String" }    // a link, stored as the foreign key
        else { fail("unknown type \(t)") }
    }
}
func upper(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

/// Which model on the other side holds the inverse link for a collection, if any.
func inverseLink(from owner: Model, collectionOf target: String) -> Field? {
    modelsByName[target]?.fields.first { if case .link(let t) = $0.kind { return t == owner.name } else { return false } }
}

/// The literal for a model default, or nil when the property is optional.
func defaultLiteral(_ f: Field, type t: String) -> String? {
    let mandatory = f.model["mandatory"] as? Bool ?? false
    guard mandatory else { return nil }
    let d = f.model["default"]
    switch t {
    case "string": return "\"\(d as? String ?? "")\""
    case "number": return "\((d as? Double) ?? 0)"
    case "boolean": return (d as? Bool ?? false) ? "true" : "false"
    case "date": return "Date()"          // the MSON default is the epoch placeholder; "now" is the intent
    case "object": return "Data(\"{}\".utf8)"
    default:
        if types[t] != nil, let v = d as? String { return ".\(v)" }
        return nil
    }
}

func docComment(_ text: String, indent: String = "") -> String {
    text.split(separator: "\n", omittingEmptySubsequences: false).map { "\(indent)/// \($0)" }.joined(separator: "\n")
}

// MARK: - Emit

var files: [String: String] = [:]
let header = """
// GENERATED by scripts/gen-pantry.swift from design/NetRelish.json — DO NOT EDIT.
// Regenerate:  swift scripts/gen-pantry.swift design/NetRelish.json Sources/Pantry/Models
// CI fails if this file differs from a fresh run. Change the diagram, not this file.

"""

// --- Types.swift ------------------------------------------------------------
do {
    var s = header + "import Foundation\nimport GRDB\n"
    for name in types.keys.sorted() {
        let t = types[name]!
        let values = t["value"] as? [String] ?? []
        s += "\n/// \(t["description"] as? String ?? "")\n"
        s += "public enum \(name): String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {\n"
        for v in values { s += "    case \(v)\n" }
        s += "}\n"
    }
    files["Types.swift"] = s
}

// --- One file per model -----------------------------------------------------
for name in modelsByName.keys.sorted() {
    let m = modelsByName[name]!
    var s = header + "import Foundation\nimport GRDB\n\n"
    s += docComment(m.description) + "\n"
    s += "public struct \(m.name): Codable, Identifiable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {\n"
    s += "    public static let databaseTableName = \"\(m.table)\"\n\n"
    s += "    /// The MSON `_id`.\n    public var id: String\n"

    // Properties
    var initParams: [(String, String, String?)] = [("id", "String", "UUID().uuidString")]
    for f in m.fields({ if case .property = $0 { true } else { false } }) {
        guard case .property(let t) = f.kind else { continue }
        let st = swiftType(t)
        let dflt = defaultLiteral(f, type: t)
        let optional = dflt == nil
        let readOnly = f.model["readOnly"] as? Bool ?? false
        s += "    /// `\(f.name)` · \(t)\(readOnly ? " · read-only" : "")\n"
        s += "    public \(readOnly ? "let" : "var") \(f.name): \(st)\(optional ? "?" : "")\n"
        initParams.append((f.name, st + (optional ? "?" : ""), dflt ?? "nil"))
    }
    // Links → foreign keys
    for f in m.fields({ if case .link = $0 { true } else { false } }) {
        guard case .link(let t) = f.kind else { continue }
        s += "    /// `\(f.name)` → \(t). The foreign key; fetch the record with `\(f.name)(_:)`.\n"
        s += "    public var \(f.name)Id: String?\n"
        initParams.append(("\(f.name)Id", "String?", "nil"))
    }
    if m.isRoot {
        s += "\n    /// The one row. `start` creates it if it is missing.\n    public static let singletonId = \"pantry\"\n"
    }

    // Init
    s += "\n    public init(\n"
    s += initParams.map { "        \($0.0): \($0.1)\($0.2.map { " = \($0)" } ?? "")" }.joined(separator: ",\n")
    s += "\n    ) {\n"
    for p in initParams { s += "        self.\(p.0) = \(p.0)\n" }
    s += "    }\n"

    // Columns
    s += "\n    public enum Columns {\n        public static let id = Column(\"id\")\n"
    for f in m.fields({ if case .property = $0 { true } else { false } }) {
        s += "        public static let \(f.name) = Column(\"\(f.name)\")\n"
    }
    for f in m.fields({ if case .link = $0 { true } else { false } }) {
        s += "        public static let \(f.name)Id = Column(\"\(f.name)Id\")\n"
    }
    s += "    }\n"

    // Associations: links
    let links = m.fields({ if case .link = $0 { true } else { false } })
    let collections = m.fields({ if case .collection = $0 { true } else { false } })
    if !links.isEmpty || !collections.isEmpty {
        s += "\n    // MARK: Associations\n"
    }
    for f in links {
        guard case .link(let t) = f.kind else { continue }
        s += "\n    public static let \(f.name) = belongsTo(\(t).self, key: \"\(f.name)\", using: ForeignKey([\"\(f.name)Id\"]))\n"
        s += "    public func \(f.name)(_ db: Database) throws -> \(t)? {\n"
        s += "        guard let \(f.name)Id else { return nil }\n"
        s += "        return try \(t).fetchOne(db, key: \(f.name)Id)\n    }\n"
    }
    for f in collections {
        guard case .collection(let t) = f.kind else { continue }
        if m.isRoot {
            // Root collections are queries over the whole Pantry (CLAUDE.md non-negotiable 2).
            s += "\n    /// `\(f.name)` — all \(t) rows"
            if f.name == "brine" {
                s += ", except that Brine is a query: `jar == nil && state == .brined`.\n"
                s += "    public func \(f.name)(_ db: Database) throws -> [\(t)] {\n"
                s += "        try \(t).filter(\(t).Columns.jarId == nil && \(t).Columns.state == ItemState.brined).order(\(t).Columns.updatedAt.desc).fetchAll(db)\n    }\n"
            } else {
                let order = modelsByName[t]!.fields.contains { $0.name == "sortOrder" } ? ".order(\(t).Columns.sortOrder)" : ""
                s += ".\n    public func \(f.name)(_ db: Database) throws -> [\(t)] {\n        try \(t)\(order).fetchAll(db)\n    }\n"
            }
        } else if let inv = inverseLink(from: m, collectionOf: t) {
            s += "\n    public static let \(f.name) = hasMany(\(t).self, key: \"\(f.name)\", using: ForeignKey([\"\(inv.name)Id\"]))\n"
            s += "    public func \(f.name)(_ db: Database) throws -> [\(t)] {\n"
            s += "        try \(t).filter(\(t).Columns.\(inv.name)Id == id).fetchAll(db)\n    }\n"
        } else {
            // Both sides are collections: a join table, named after the two tables in alphabetical order.
            let other = modelsByName[t]!
            let join = [m.table, other.table].sorted().joined(separator: "_")
            s += "\n    /// Many-to-many through `\(join)`.\n"
            s += "    public static let \(f.name)Pivot = hasMany(Table(\"\(join)\"), using: ForeignKey([\"\(m.name.lowercased())Id\"]))\n"
            s += "    public static let \(f.name) = hasMany(\(t).self, through: \(f.name)Pivot, using: Table(\"\(join)\").belongsTo(\(t).self, using: ForeignKey([\"\(t.lowercased())Id\"])))\n"
            s += "    public func \(f.name)(_ db: Database) throws -> [\(t)] {\n"
            s += "        try \(t).fetchAll(db, sql: \"SELECT t.* FROM \(other.table) t JOIN \(join) j ON j.\(t.lowercased())Id = t.id WHERE j.\(m.name.lowercased())Id = ?\", arguments: [id])\n    }\n"
            s += "    public func set\(upper(f.name))(_ ids: [String], _ db: Database) throws {\n"
            s += "        try db.execute(sql: \"DELETE FROM \(join) WHERE \(m.name.lowercased())Id = ?\", arguments: [id])\n"
            s += "        for other in ids { try db.execute(sql: \"INSERT INTO \(join) (\(m.name.lowercased())Id, \(t.lowercased())Id) VALUES (?, ?)\", arguments: [id, other]) }\n    }\n"
        }
    }

    // Events
    let events = m.fields({ if case .event = $0 { true } else { false } })
    if !events.isEmpty { s += "\n    // MARK: Events\n" }
    for f in events {
        let params = f.model["params"] as? [[String: Any]] ?? []
        let t = (params.first?["type"] as? String).map(swiftTypeForEvent) ?? m.name
        s += "\n    /// `\(f.name)` — an `AsyncStream<\(t)>`; also posted as `Notification.Name(\"\(systemName).\(m.name).\(f.name)\")`.\n"
        s += "    public static let \(f.name) = PantryEvent<\(t)>(\"\(systemName).\(m.name).\(f.name)\")\n"
    }
    s += "}\n"

    // Methods → protocol
    let methods = m.fields({ if case .method = $0 { true } else { false } })
    if !methods.isEmpty {
        s += "\n/// The methods the diagram gives `\(m.name)`. Bodies live in Behaviors/\(m.name)+Behavior.swift\n"
        s += "/// and mirror the JavaScript quoted here. `\(m.name)` must conform, so a missing body is a compile error.\n"
        s += "public protocol \(m.name)Methods {\n"
        for f in methods {
            let params = f.model["params"] as? [[String: Any]] ?? []
            let result = f.model["result"] as? String
            if let js = bodies["\(m.name).\(f.name)"] {
                s += "\n" + docComment("```javascript\n\(js)\n```", indent: "    ") + "\n"
            } else {
                fail("\(m.name).\(f.name) has no behavior body in the bundle")
            }
            let sig = params.map { p in
                let n = p["name"] as! String
                let t = p["type"]
                let st = (t as? [String]).map { "[\($0[0])]" } ?? swiftTypeForEvent(t as! String)
                return "\(n): \(st)"
            }
            let mutating = m.isRoot ? "" : "mutating "
            let ret = result.map { " -> \(swiftTypeForEvent($0))" } ?? ""
            s += "    \(mutating)func \(f.name)(\(([ "_ db: Database" ] + sig).joined(separator: ", "))) throws\(ret)\n"
        }
        s += "}\n"
    }
    files["\(m.name).swift"] = s
}

func swiftTypeForEvent(_ t: String) -> String {
    switch t {
    case "string": "String"; case "number": "Double"; case "boolean": "Bool"; case "date": "Date"; case "object": "Data"
    default: t
    }
}

// --- Schema.swift -----------------------------------------------------------
// The tables, as the diagram defines them today. The first migration calls this;
// once V1 ships, later changes become hand-written migrations (V2…) and this file
// documents the target shape. See ADR 0004.
do {
    func sqlType(_ t: String) -> String {
        switch t {
        case "string": "TEXT"; case "number": "DOUBLE"; case "boolean": "BOOLEAN"; case "date": "DATETIME"; case "object": "BLOB"
        default:
            if types[t] != nil { "TEXT" } else { fail("schema: unknown type \(t)") }
        }
    }
    var s = header + "import Foundation\nimport GRDB\n\n"
    s += "/// Creates every table, join table and index the diagram implies. Called by Migrations/V1.\n"
    s += "public enum PantrySchema {\n"
    s += "    /// Table names, in creation order (referenced tables first).\n"
    // Creation order: a table only after every table it links to (topological; ties alphabetical).
    var ordered: [Model] = []
    var remaining = modelsByName.values.sorted { $0.name < $1.name }
    while !remaining.isEmpty {
        let done = Set(ordered.map(\.name))
        guard let next = remaining.first(where: { m in
            m.fields.allSatisfy { if case .link(let t) = $0.kind { return done.contains(t) || t == m.name } else { return true } }
        }) else { fail("schema: circular links among \(remaining.map(\.name))") }
        ordered.append(next)
        remaining.removeAll { $0.name == next.name }
    }
    s += "    public static let tables: [String] = [\(ordered.map { "\"\($0.table)\"" }.joined(separator: ", "))]\n\n"
    s += "    public static func create(_ db: Database) throws {\n"
    var joins: Set<String> = []
    var joinDDL: [String] = []
    var indexes: [String] = []
    for m in ordered {
        s += "        try db.create(table: \"\(m.table)\") { t in\n"
        s += "            t.primaryKey(\"id\", .text)\n"
        for f in m.fields {
            switch f.kind {
            case .property(let t):
                let mandatory = f.model["mandatory"] as? Bool ?? false
                s += "            t.column(\"\(f.name)\", .\(sqlType(t).lowercased()))\(mandatory ? ".notNull()" : "")\n"
                if types[t] != nil || ["updatedAt", "createdAt", "url"].contains(f.name) {
                    indexes.append("        try db.create(indexOn: \"\(m.table)\", columns: [\"\(f.name)\"])")
                }
            case .link(let t):
                let target = modelsByName[t]!
                s += "            t.belongsTo(\"\(f.name)\", inTable: \"\(target.table)\", onDelete: .setNull)\n"
            case .collection(let t):
                guard !m.isRoot, inverseLink(from: m, collectionOf: t) == nil else { continue }
                let other = modelsByName[t]!
                let join = [m.table, other.table].sorted().joined(separator: "_")
                guard !joins.contains(join) else { continue }
                joins.insert(join)
                let (aName, aTable, bName, bTable) = m.table < other.table
                    ? (m.name.lowercased(), m.table, t.lowercased(), other.table)
                    : (t.lowercased(), other.table, m.name.lowercased(), m.table)
                joinDDL.append("""
        try db.create(table: "\(join)") { t in
            t.belongsTo("\(aName)", inTable: "\(aTable)", onDelete: .cascade).notNull()
            t.belongsTo("\(bName)", inTable: "\(bTable)", onDelete: .cascade).notNull()
            t.primaryKey(["\(aName)Id", "\(bName)Id"])
        }

""")
            default: break
            }
        }
        s += "        }\n"
    }
    for j in joinDDL { s += j }
    s += indexes.joined(separator: "\n") + "\n"
    s += "    }\n}\n"
    files["Schema.swift"] = s
}

// --- Seed.swift -------------------------------------------------------------
do {
    var s = header + "import Foundation\nimport GRDB\n\n"
    s += "/// The bundle's components — the rows a fresh Pantry starts with. Applied by the first migration.\n"
    s += "public enum PantrySeed {\n    public static func apply(_ db: Database) throws {\n"
    // Order: anything the root references first; the root last.
    let order = components.keys.sorted { ($0 == systemName ? 1 : 0, $0) < ($1 == systemName ? 1 : 0, $1) }
    for modelName in order {
        guard let m = modelsByName[modelName] else { fail("component of unknown model \(modelName)") }
        for cid in components[modelName]!.keys.sorted() {
            let c = components[modelName]![cid]!
            var cols: [(String, String)] = [("id", "\"\(cid)\"")]
            for f in m.fields {
                guard let v = c[f.name] else { continue }
                switch f.kind {
                case .property(let t):
                    switch t {
                    case "string": cols.append((f.name, "\"\(v as! String)\""))
                    case "number": cols.append((f.name, "\((v as? Double) ?? Double(v as! Int))"))
                    case "boolean": cols.append((f.name, (v as! Bool) ? "true" : "false"))
                    default:
                        if types[t] != nil { cols.append((f.name, "\"\(v as! String)\"")) }
                        else { fail("seed \(modelName).\(f.name): unsupported type \(t)") }
                    }
                case .link:
                    cols.append(("\(f.name)Id", "\"\(v as! String)\""))
                case .collection(let t):
                    // Root collections are queries, so a seed list here is only a statement of
                    // which rows exist; those rows are seeded by their own model above.
                    let ids = v as! [String]
                    s += "        // \(modelName).\(f.name) = \(ids) — \(t) rows seeded above\n"
                default: break
                }
            }
            // Mandatory columns not in the seed take the model default.
            for f in m.fields {
                guard case .property(let t) = f.kind, c[f.name] == nil, let d = defaultLiteral(f, type: t) else { continue }
                let lit = types[t] != nil ? "\"\(f.model["default"] as! String)\"" : (t == "date" ? "Date()" : d)
                cols.append((f.name, lit))
            }
            let names = cols.map { $0.0 }.joined(separator: ", ")
            let marks = cols.map { _ in "?" }.joined(separator: ", ")
            let vals = cols.map { $0.1 }.joined(separator: ", ")
            s += "        try db.execute(sql: \"INSERT OR IGNORE INTO \(m.table) (\(names)) VALUES (\(marks))\", arguments: [\(vals)])\n"
        }
    }
    s += "    }\n}\n"
    files["Seed.swift"] = s
}

// --- Write --------------------------------------------------------------------
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
// Remove stale generated files so a renamed schema cannot leave an orphan behind.
if let existing = try? FileManager.default.contentsOfDirectory(atPath: outDir.path) {
    for f in existing where f.hasSuffix(".swift") && files[f] == nil {
        let path = outDir.appendingPathComponent(f)
        if let head = try? String(contentsOf: path, encoding: .utf8).prefix(40), head.contains("GENERATED") {
            try? FileManager.default.removeItem(at: path)
        }
    }
}
for (name, content) in files {
    try! content.write(to: outDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
}
print("wrote \(files.count) files to \(outDir.path): \(files.keys.sorted().joined(separator: ", "))")
