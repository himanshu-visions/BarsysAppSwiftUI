//
//  LocalCache.swift
//  BarsysAppSwiftUI
//
//  Lightweight in-memory cache that mirrors the surface of the UIKit
//  DBManager / AppStateManager. Recipes, mixlists, favorites, the user's
//  My Bar, and the device-name cache all flow through this single store
//  so views observe a single source of truth.
//
//  When wiring the real backend you can either:
//   1. Replace this with a SQLite/SwiftData adapter that persists to disk, or
//   2. Keep it and have your APIClient adapter populate it from real responses
//      whenever data is fetched (matching what MixlistsUpdateClass does today).
//

import Foundation
import Combine

@MainActor
final class LocalCache: ObservableObject {

    static let shared = LocalCache()

    @Published private(set) var recipes: [RecipeID: Recipe] = [:]
    @Published private(set) var mixlists: [MixlistID: Mixlist] = [:]
    @Published private(set) var myBar: [IngredientID: Ingredient] = [:]
    @Published private(set) var favorites: Set<RecipeID> = []
    @Published private(set) var lastUpdatedAt: Date = .distantPast

    private init() {
        // Seed with the same sample data the rest of the app uses.
        let r = SampleData.recipes
        recipes = Dictionary(uniqueKeysWithValues: r.map { ($0.id, $0) })
        mixlists = Dictionary(uniqueKeysWithValues: SampleData.mixlists.map { ($0.id, $0) })
        myBar = Dictionary(uniqueKeysWithValues: SampleData.ingredients.map { ($0.id, $0) })
        favorites = Set(r.compactMap { ($0.isFavourite ?? false) ? $0.id : nil })
    }

    // MARK: - Reads

    func allRecipes() -> [Recipe] {
        Array(recipes.values).sorted { $0.displayName < $1.displayName }
    }

    func allMixlists() -> [Mixlist] {
        Array(mixlists.values).sorted { $0.displayName < $1.displayName }
    }

    func allMyBarIngredients() -> [Ingredient] {
        Array(myBar.values).sorted { $0.name < $1.name }
    }

    func recipe(_ id: RecipeID) -> Recipe? { recipes[id] }
    func mixlist(_ id: MixlistID) -> Mixlist? { mixlists[id] }

    func favouriteRecipes() -> [Recipe] {
        recipes.values.filter { favorites.contains($0.id) }
            .sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Writes

    /// Mirrors `DBManager.insertToDatabaseAndFetchCount`. Replaces all stored
    /// recipes/mixlists with a fresh server snapshot.
    func replace(recipes newRecipes: [Recipe], mixlists newMixlists: [Mixlist]) {
        self.recipes = Dictionary(uniqueKeysWithValues: newRecipes.map { ($0.id, $0) })
        self.mixlists = Dictionary(uniqueKeysWithValues: newMixlists.map { ($0.id, $0) })
        self.lastUpdatedAt = Date()
    }

    func upsert(recipe: Recipe) {
        recipes[recipe.id] = recipe
        lastUpdatedAt = Date()
    }

    func delete(recipe id: RecipeID) {
        recipes.removeValue(forKey: id)
        favorites.remove(id)
    }

    func upsert(mixlist: Mixlist) {
        mixlists[mixlist.id] = mixlist
        lastUpdatedAt = Date()
    }

    func delete(mixlist id: MixlistID) {
        mixlists.removeValue(forKey: id)
    }

    /// Toggle My Bar membership for an ingredient.
    func toggleMyBar(_ ingredient: Ingredient) {
        if myBar[ingredient.id] != nil {
            myBar.removeValue(forKey: ingredient.id)
        } else {
            myBar[ingredient.id] = ingredient
        }
    }

    /// Toggle a recipe as favourite.
    func toggleFavorite(_ id: RecipeID) {
        if favorites.contains(id) {
            favorites.remove(id)
        } else {
            favorites.insert(id)
        }
        if var r = recipes[id] {
            r.isFavourite = favorites.contains(id)
            recipes[id] = r
        }
    }
}
