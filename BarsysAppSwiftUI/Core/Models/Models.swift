//
//  Models.swift
//  BarsysAppSwiftUI
//
//  Domain models ported from BarsysApp/Controllers/AllMixlists/MixlistModel.swift
//  and related files. Field shapes match the real JSON schema so swapping in the
//  production API client is a matter of wiring JSONDecoder — no view changes.
//
//  The only intentional divergence from UIKit is strongly-typed navigation IDs
//  (RecipeID, MixlistID, DeviceID, IngredientID). These wrap the server's
//  String ids so NavigationStack paths can hold them as Hashable values.
//

import Foundation
import SwiftUI

// MARK: - Strong IDs

// Strong-typed wrappers around the underlying server `id` strings.
// CRITICAL: encode/decode as a SINGLE VALUE (the raw string) — without
// this the JSON payload would contain `"id": {"value": "abc"}` instead
// of `"id": "abc"`, which the recipes API rejects with a 4xx and which
// surfaced as the persistent "Unable to save recipe" error during edits.
// UIKit `Recipe.id` is a `String`, so the server only accepts the
// scalar form on the wire.
struct RecipeID: Hashable, Codable {
    let value: String
    init(_ value: String = UUID().uuidString) { self.value = value }
    init(from decoder: Decoder) throws {
        self.value = try decoder.singleValueContainer().decode(String.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}
struct MixlistID: Hashable, Codable {
    let value: String
    init(_ value: String = UUID().uuidString) { self.value = value }
    init(from decoder: Decoder) throws {
        self.value = try decoder.singleValueContainer().decode(String.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}
struct DeviceID: Hashable, Codable {
    let value: String
    init(_ value: String = UUID().uuidString) { self.value = value }
    init(from decoder: Decoder) throws {
        self.value = try decoder.singleValueContainer().decode(String.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}
struct IngredientID: Hashable, Codable {
    let value: String
    init(_ value: String = UUID().uuidString) { self.value = value }
    init(from decoder: Decoder) throws {
        self.value = try decoder.singleValueContainer().decode(String.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

// MARK: - User / Profile

struct UserProfile: Codable, Hashable {
    var id: String
    var firstName: String
    var lastName: String
    var email: String
    var phone: String
    var countryCode: String
    var dateOfBirth: Date?
    var avatarURL: URL?

    var fullName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }

    static let empty = UserProfile(id: "", firstName: "", lastName: "", email: "", phone: "", countryCode: "")
}

// MARK: - Country (ports BarsysApp/Helpers/Constants/Constants+UI.swift)
//
// Field names match the real Countries.json bundled in the project (loaded
// at startup by `loadCountries()` — same approach as LoginViewModel).

struct Country: Codable, Hashable, Identifiable {
    var name: String
    var dial_code: String
    var code: String       // ISO
    var flag: String       // emoji
    var age: String

    var id: String { code }

    /// Legacy Swift-style accessor used by call sites that prefer camelCase.
    var dialCode: String { dial_code }

    static let unitedStates = Country(name: "United States", dial_code: "1", code: "US", flag: "🇺🇸", age: "21")
    static let unitedKingdom = Country(name: "United Kingdom", dial_code: "44", code: "GB", flag: "🇬🇧", age: "18")
    static let india         = Country(name: "India", dial_code: "91", code: "IN", flag: "🇮🇳", age: "21")
    static let germany       = Country(name: "Germany", dial_code: "49", code: "DE", flag: "🇩🇪", age: "18")
    static let france        = Country(name: "France", dial_code: "33", code: "FR", flag: "🇫🇷", age: "18")
    static let australia     = Country(name: "Australia", dial_code: "61", code: "AU", flag: "🇦🇺", age: "18")
    static let japan         = Country(name: "Japan", dial_code: "81", code: "JP", flag: "🇯🇵", age: "20")

    static let sample: [Country] = [.unitedStates, .unitedKingdom, .india, .germany, .france, .australia, .japan]
}

/// Ports `CountryObject` from Constants+UI.swift — top-level wrapper for the
/// JSON file shape `{ "country": [Country, …] }`.
struct CountryObject: Codable {
    let country: [Country]
}

/// Loads the bundled Countries.json (matches LoginViewModel.getAllCountries()).
enum CountryLoader {
    static func loadAll() -> [Country] {
        guard let url = Bundle.main.url(forResource: "Countries", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONDecoder().decode(CountryObject.self, from: data) else {
            return Country.sample
        }
        return obj.country
    }
}

// MARK: - Image wrapper (ports `ImageModel`)

struct ImageModel: Codable, Hashable {
    var url: String?
    var alt: String?
}

// MARK: - Category (ports `Category`)

struct IngredientCategory: Codable, Hashable {
    var primary: String?
    var secondary: String?
    var flavourTags: [String]?

    init(primary: String? = nil, secondary: String? = nil, flavourTags: [String]? = nil) {
        self.primary = primary
        self.secondary = secondary
        self.flavourTags = flavourTags
    }
}

// MARK: - Glassware (ports the Glassware struct from MixlistModel.swift)

struct Glassware: Codable, Hashable {
    var type: String?
    var chilled: Bool?
    var rimmed: String?
    var notes: String?

    var displayName: String {
        type ?? "Rocks"
    }
}

// MARK: - Ingredient (ports `Ingredient` from MixlistModel.swift)

struct Ingredient: Codable, Hashable, Identifiable {
    let localID: IngredientID
    var name: String
    var unit: String
    var notes: String?
    var category: IngredientCategory?
    var quantity: Double?
    var perishable: Bool?
    var substitutes: [String]?
    var ingredientOptional: Bool?

    var id: IngredientID { localID }

    /// Quantity in the canonical storage unit (ml). Falls back to 0.
    var quantityML: Double { quantity ?? 0 }

    init(localID: IngredientID = IngredientID(),
         name: String,
         unit: String = Constants.mlText,
         notes: String? = nil,
         category: IngredientCategory? = nil,
         quantity: Double? = nil,
         perishable: Bool? = false,
         substitutes: [String]? = nil,
         ingredientOptional: Bool? = false) {
        self.localID = localID
        self.name = name
        self.unit = unit
        self.notes = notes
        self.category = category
        self.quantity = quantity
        self.perishable = perishable
        self.substitutes = substitutes
        self.ingredientOptional = ingredientOptional
    }

    enum CodingKeys: String, CodingKey {
        case name, unit, notes, category, quantity, perishable, substitutes
        case ingredientOptional = "optional"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.localID = IngredientID()
        self.name = try c.decode(String.self, forKey: .name)
        self.unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? Constants.mlText
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.category = try c.decodeIfPresent(IngredientCategory.self, forKey: .category)
        self.quantity = try c.decodeIfPresent(Double.self, forKey: .quantity)
        self.perishable = try c.decodeIfPresent(Bool.self, forKey: .perishable)
        self.substitutes = try c.decodeIfPresent([String].self, forKey: .substitutes)
        self.ingredientOptional = try c.decodeIfPresent(Bool.self, forKey: .ingredientOptional)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(unit, forKey: .unit)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(quantity, forKey: .quantity)
        try c.encodeIfPresent(perishable, forKey: .perishable)
        try c.encodeIfPresent(substitutes, forKey: .substitutes)
        try c.encodeIfPresent(ingredientOptional, forKey: .ingredientOptional)
    }
}

// MARK: - Variation (ports `Variation`)

struct Variation: Codable, Hashable {
    var name: String?
    var desc: String?
    var modifications: [String]?
}

// MARK: - Recipe (ports `Recipe` from MixlistModel.swift)

struct Recipe: Hashable, Identifiable, Codable {
    let id: RecipeID
    var name: String?
    var description: String?
    var image: ImageModel?
    var ice: String?
    var ingredients: [Ingredient]?
    var instructions: [String]
    var mixingTechnique: String?
    var glassware: Glassware?
    var tags: [String]?
    var variations: [Variation]?
    var ingredientNames: String?
    var isFavourite: Bool?
    var barsys360Compatible: Bool?
    var favCreatedAt: Int32?
    var isMyDrinkFavourite: Bool?
    var slug: String?
    var userId: String?
    /// Creation timestamp — maps to UIKit `recipes.createdAt` column.
    /// Needed so `CatalogService.allRecipes()` can reproduce the SQL
    /// `ORDER BY createdAt DESC` UIKit uses (DBQueries.swift L60).
    var createdAt: String?

    // Convenience accessors used by SwiftUI views.
    var displayName: String { name ?? "Untitled" }
    var subtitle: String { description ?? "" }
    var imageName: String { slug ?? "wineglass" }
    var imageURL: String { image?.url ?? "" }
    var craftDurationSeconds: Int { 45 }

    init(id: RecipeID = RecipeID(),
         name: String? = nil,
         description: String? = nil,
         image: ImageModel? = nil,
         ice: String? = nil,
         ingredients: [Ingredient]? = nil,
         instructions: [String] = [],
         mixingTechnique: String? = nil,
         glassware: Glassware? = nil,
         tags: [String]? = nil,
         variations: [Variation]? = nil,
         ingredientNames: String? = nil,
         isFavourite: Bool? = nil,
         barsys360Compatible: Bool? = nil,
         favCreatedAt: Int32? = nil,
         isMyDrinkFavourite: Bool? = nil,
         slug: String? = nil,
         userId: String? = nil,
         createdAt: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.image = image
        self.ice = ice
        self.ingredients = ingredients
        self.instructions = instructions
        self.mixingTechnique = mixingTechnique
        self.glassware = glassware
        self.tags = tags
        self.variations = variations
        self.ingredientNames = ingredientNames
        self.isFavourite = isFavourite
        self.barsys360Compatible = barsys360Compatible
        self.favCreatedAt = favCreatedAt
        self.isMyDrinkFavourite = isMyDrinkFavourite
        self.slug = slug
        self.userId = userId
        self.createdAt = createdAt
    }

    // 1:1 with UIKit `Recipe.CodingKeys` (MixlistModel.swift L77-91).
    // Without these, JSONEncoder uses the Swift property names which
    // would emit `barsys360Compatible` / `userId` / `created_at` etc.
    // in the WRONG case — the server rejects the payload and the save
    // fails with the generic "Unable to save recipe" message.
    enum CodingKeys: String, CodingKey {
        case id, name, description, image, ice, ingredients, instructions
        case mixingTechnique = "mixingTechnique"
        case glassware, tags, variations
        case createdAt = "created_at"
        case ingredientNames = "ingredient_names"
        case isFavourite
        case barsys360Compatible = "barsys_360_compatible"
        case favCreatedAt
        case isMyDrinkFavourite = "favorite"
        case slug
        case userId = "user_id"
    }
}

// MARK: - Mixlist (ports `Mixlist` from MixlistModel.swift)

struct Mixlist: Hashable, Identifiable {
    let id: MixlistID
    var name: String?
    var description: String?
    var tags: [String]?
    var createdAt: String?
    var updatedAt: String?
    var recipes: [Recipe]?
    var isDeleted: Bool?
    var image: ImageModel?
    var barsys360Compatible: Bool?
    var slug: String?
    var ingredientNames: String?

    var displayName: String { name ?? "Untitled Mixlist" }
    var subtitle: String { description ?? "" }
    var imageURL: String { image?.url ?? "" }
    var recipeIDs: [RecipeID] { (recipes ?? []).map(\.id) }

    init(id: MixlistID = MixlistID(),
         name: String? = nil,
         description: String? = nil,
         tags: [String]? = nil,
         recipes: [Recipe]? = nil,
         image: ImageModel? = nil,
         barsys360Compatible: Bool? = nil,
         slug: String? = nil,
         ingredientNames: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.tags = tags
        self.recipes = recipes
        self.image = image
        self.barsys360Compatible = barsys360Compatible
        self.slug = slug
        self.ingredientNames = ingredientNames
    }
}

// MARK: - Device

enum DeviceKind: String, Codable, CaseIterable {
    case shaker
    case coaster
    case barsys360

    var displayName: String {
        switch self {
        case .shaker:    return IsDeviceType.barsysShaker.rawValue
        case .coaster:   return IsDeviceType.coaster.rawValue
        case .barsys360: return IsDeviceType.barsys360.rawValue
        }
    }
}

enum DeviceConnectionState: String, Codable, Hashable {
    case disconnected, discovering, connecting, connected, failed
}

struct BarsysDevice: Hashable, Identifiable {
    let id: DeviceID
    var name: String
    var kind: DeviceKind
    var serial: String
    var state: DeviceConnectionState
    var batteryPercent: Int?
    var firmwareVersion: String?

    /// BLE signal strength (dBm). Updated on every discovery callback.
    /// Ports `DiscoveredDevice.rssi` from UIKit.
    var rssi: Int = -50

    /// Last time this device was seen during scanning. Used for stale-device
    /// pruning (UIKit removes devices not seen in 12 seconds).
    var lastSeen: Date = Date()

    // MARK: - Signal helpers (ports DiscoveredDevice computed properties)

    /// SF Symbol name for the signal strength level.
    var signalIconName: String {
        switch rssi {
        case (-50)...:      return "wifi"
        case (-70)...(-51): return "wifi"
        case (-80)...(-71): return "wifi.exclamationmark"
        default:            return "wifi.slash"
        }
    }

    /// Display text for the signal strength level.
    var signalLevelText: String {
        switch rssi {
        case (-50)...:      return "Excellent"
        case (-70)...(-51): return "Good"
        case (-80)...(-71): return "Fair"
        default:            return "Weak"
        }
    }

    /// Color matching UIKit's RSSI-based tint.
    var signalColor: Color {
        switch rssi {
        case (-50)...:      return .green
        case (-70)...(-51): return .blue
        case (-80)...(-71): return .orange
        default:            return .red
        }
    }
}

// MARK: - Measurement preference

enum MeasurementUnit: String, Codable, CaseIterable, Identifiable {
    case ml
    case oz
    var id: Self { self }
    var label: String { self == .ml ? "Milliliters (ml)" : "Ounces (oz)" }
    var shortLabel: String { self == .ml ? Constants.mlText : Constants.ozText }
}

// MARK: - BarBot chat

struct BarBotMessage: Identifiable {
    let id: UUID
    let sender: Sender
    var text: String
    let timestamp: Date
    let attachments: [Attachment]
    /// Optional image attachment (user-picked photo). Not Hashable,
    /// so BarBotMessage uses Identifiable instead of Hashable.
    var image: UIImage?

    enum Sender: String { case user, bot }
    enum Attachment: Hashable { case recipe(RecipeID), mixlist(MixlistID), image(String) }

    init(id: UUID = UUID(), sender: Sender, text: String, timestamp: Date = Date(), attachments: [Attachment] = [], image: UIImage? = nil) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
        self.attachments = attachments
        self.image = image
    }
}

// MARK: - Auth

enum LoginMethod: String, Hashable { case phone, email }

// MARK: - Array helpers

extension Array where Element: Hashable {
    /// Returns the array with duplicates removed, preserving order.
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
