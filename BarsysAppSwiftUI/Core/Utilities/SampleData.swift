//
//  SampleData.swift
//  BarsysAppSwiftUI
//
//  Sample content so every SwiftUI screen has realistic data to render.
//  Built around the ported Recipe/Ingredient/Mixlist shapes.
//

import Foundation

enum SampleData {

    static let ingredients: [Ingredient] = [
        Ingredient(name: "Gin",            unit: Constants.mlText, category: .init(primary: "Spirits"), quantity: 50),
        Ingredient(name: "Tonic Water",    unit: Constants.mlText, category: .init(primary: "Mixers"),  quantity: 150),
        Ingredient(name: "Lime Juice",     unit: Constants.mlText, category: .init(primary: "Juices"),  quantity: 15, perishable: true),
        Ingredient(name: "Simple Syrup",   unit: Constants.mlText, category: .init(primary: "Syrups"),  quantity: 10),
        Ingredient(name: "White Rum",      unit: Constants.mlText, category: .init(primary: "Spirits"), quantity: 50),
        Ingredient(name: "Mint Leaves",    unit: Constants.mlText, category: .init(primary: "Herbs"),   quantity: 5, perishable: true),
        Ingredient(name: "Club Soda",      unit: Constants.mlText, category: .init(primary: "Mixers"),  quantity: 100),
        Ingredient(name: "Vodka",          unit: Constants.mlText, category: .init(primary: "Spirits"), quantity: 50),
        Ingredient(name: "Cranberry Juice",unit: Constants.mlText, category: .init(primary: "Juices"),  quantity: 100, perishable: true),
        Ingredient(name: "Triple Sec",     unit: Constants.mlText, category: .init(primary: "Liqueurs"),quantity: 15),
        Ingredient(name: "Tequila",        unit: Constants.mlText, category: .init(primary: "Spirits"), quantity: 50),
        Ingredient(name: "Agave Syrup",    unit: Constants.mlText, category: .init(primary: "Syrups"),  quantity: 10),
        Ingredient(name: "Bourbon",        unit: Constants.mlText, category: .init(primary: "Spirits"), quantity: 60),
        Ingredient(name: "Sweet Vermouth", unit: Constants.mlText, category: .init(primary: "Wines"),   quantity: 30),
        Ingredient(name: "Angostura Bitters", unit: Constants.mlText, category: .init(primary: "Bitters"), quantity: 2)
    ]

    private static let highball = Glassware(type: "Highball", chilled: true, rimmed: nil, notes: nil)
    private static let martini  = Glassware(type: "Martini",  chilled: true, rimmed: nil, notes: nil)
    private static let rocks    = Glassware(type: "Rocks",    chilled: false, rimmed: nil, notes: nil)
    private static let coupe    = Glassware(type: "Coupe",    chilled: true, rimmed: nil, notes: nil)

    static let recipes: [Recipe] = [
        Recipe(
            name: "Gin & Tonic",
            description: "Classic refresher",
            image: ImageModel(url: nil, alt: "gin_and_tonic"),
            ingredients: [ingredients[0], ingredients[1], ingredients[2]],
            instructions: [
                "Fill a highball glass with ice.",
                "Pour gin over the ice.",
                "Top with chilled tonic water.",
                "Garnish with a lime wedge."
            ],
            glassware: highball,
            tags: ["Gin", "Refreshing"],
            isFavourite: true,
            barsys360Compatible: true
        ),
        Recipe(
            name: "Mojito",
            description: "Cuban classic",
            image: ImageModel(url: nil, alt: "mojito"),
            ingredients: [ingredients[4], ingredients[5], ingredients[2], ingredients[3], ingredients[6]],
            instructions: [
                "Muddle mint, lime juice and simple syrup in a highball glass.",
                "Add rum and fill with ice.",
                "Top with club soda and stir gently.",
                "Garnish with a mint sprig."
            ],
            glassware: highball,
            tags: ["Rum", "Mint"],
            isFavourite: true,
            barsys360Compatible: true
        ),
        Recipe(
            name: "Cosmopolitan",
            description: "Modern classic",
            image: ImageModel(url: nil, alt: "cosmopolitan"),
            ingredients: [ingredients[7], ingredients[9], ingredients[8], ingredients[2]],
            instructions: [
                "Add all ingredients to a shaker with ice.",
                "Shake vigorously for 10 seconds.",
                "Double-strain into a chilled martini glass.",
                "Garnish with an orange twist."
            ],
            glassware: martini,
            tags: ["Vodka", "Citrus"],
            isFavourite: false,
            barsys360Compatible: true
        ),
        Recipe(
            name: "Margarita",
            description: "Tequila forward",
            image: ImageModel(url: nil, alt: "margarita"),
            ingredients: [ingredients[10], ingredients[9], ingredients[2], ingredients[11]],
            instructions: [
                "Salt the rim of a rocks glass.",
                "Add all ingredients to a shaker with ice.",
                "Shake and strain over fresh ice.",
                "Garnish with a lime wheel."
            ],
            glassware: rocks,
            tags: ["Tequila", "Citrus"],
            isFavourite: true,
            barsys360Compatible: true
        ),
        Recipe(
            name: "Old Fashioned",
            description: "Timeless whiskey",
            image: ImageModel(url: nil, alt: "old_fashioned"),
            ingredients: [ingredients[12], ingredients[3], ingredients[14]],
            instructions: [
                "Add bourbon, simple syrup and bitters to a mixing glass with ice.",
                "Stir until well chilled.",
                "Strain over a large ice cube in a rocks glass.",
                "Garnish with an orange peel."
            ],
            glassware: rocks,
            tags: ["Whiskey", "Strong"],
            isFavourite: false,
            barsys360Compatible: true
        ),
        Recipe(
            name: "Manhattan",
            description: "New York legend",
            image: ImageModel(url: nil, alt: "manhattan"),
            ingredients: [ingredients[12], ingredients[13], ingredients[14]],
            instructions: [
                "Stir ingredients with ice for 30 seconds.",
                "Strain into a chilled coupe.",
                "Garnish with a brandied cherry."
            ],
            glassware: coupe,
            tags: ["Whiskey", "Classic"],
            isFavourite: false,
            barsys360Compatible: false
        )
    ]

    static let mixlists: [Mixlist] = [
        Mixlist(name: "Summer Favorites",
                description: "Light & bright",
                tags: ["Summer", "Refreshing"],
                recipes: [recipes[0], recipes[1], recipes[3]],
                barsys360Compatible: true),
        Mixlist(name: "Whiskey Night",
                description: "Stirred, not shaken",
                tags: ["Whiskey"],
                recipes: [recipes[4], recipes[5]],
                barsys360Compatible: false),
        Mixlist(name: "Modern Classics",
                description: "20th century",
                tags: ["Classics"],
                recipes: [recipes[2], recipes[3], recipes[5]],
                barsys360Compatible: true)
    ]
}
