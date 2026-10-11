import Foundation

/// Market menus and hours.
/// PLACEHOLDER: item names follow Chick-fil-A's app, but prices and hours are
/// estimates until they're checked against Grubhub for the Stamp location.
enum MarketMenu {
    static let locations: [MarketLocation] = [
        MarketLocation(id: "cfa-stamp", name: "Chick-fil-A", building: "Stamp", isLive: true),
        MarketLocation(id: "subway-stamp", name: "Subway", building: "Stamp", isLive: false),
        MarketLocation(id: "starbucks", name: "Starbucks", building: "Campus", isLive: false),
        MarketLocation(id: "ncm", name: "North Campus Market", building: "Ellicott", isLive: false),
    ]

    static let schedules: [String: DiningHallSchedule] = [
        "cfa-stamp": DiningHallSchedule(
            hallId: "cfa-stamp",
            weekdayWindows: [MealWindow(name: "Open", openMinute: 10 * 60 + 30, closeMinute: 21 * 60)],
            fridayWindows: [MealWindow(name: "Open", openMinute: 10 * 60 + 30, closeMinute: 17 * 60)],
            weekendWindows: [MealWindow(name: "Open", openMinute: 11 * 60, closeMinute: 16 * 60)]
        )
    ]

    // MARK: Shared option groups

    private static let sides = OptionGroup(
        id: "side", title: "Choose a side",
        choices: [
            OptionChoice(id: "fries", name: "Waffle Fries"),
            OptionChoice(id: "mac", name: "Mac & Cheese", priceDelta: 0.90),
            OptionChoice(id: "fruit", name: "Fruit Cup", priceDelta: 0.90),
        ],
        minSelect: 1
    )

    private static let drinkChoices = [
        OptionChoice(id: "lemonade", name: "Lemonade"),
        OptionChoice(id: "diet-lemonade", name: "Diet Lemonade"),
        OptionChoice(id: "sweet-tea", name: "Sweet Tea"),
        OptionChoice(id: "unsweet-tea", name: "Unsweet Tea"),
        OptionChoice(id: "coke", name: "Coca-Cola"),
        OptionChoice(id: "diet-coke", name: "Diet Coke"),
        OptionChoice(id: "sprite", name: "Sprite"),
        OptionChoice(id: "drpepper", name: "Dr Pepper"),
        OptionChoice(id: "water", name: "Bottled Water"),
    ]

    private static let mealDrink = OptionGroup(id: "drink", title: "Choose a drink", choices: drinkChoices, minSelect: 1)

    private static let mealSize = OptionGroup(
        id: "size", title: "Meal size",
        choices: [
            OptionChoice(id: "m", name: "Medium"),
            OptionChoice(id: "l", name: "Large", priceDelta: 0.80),
        ],
        minSelect: 1
    )

    private static func sauces(max: Int) -> OptionGroup {
        OptionGroup(
            id: "sauce", title: "Sauces",
            choices: [
                OptionChoice(id: "cfa", name: "Chick-fil-A Sauce"),
                OptionChoice(id: "poly", name: "Polynesian"),
                OptionChoice(id: "honey-mustard", name: "Honey Mustard"),
                OptionChoice(id: "bbq", name: "Barbeque"),
                OptionChoice(id: "ranch", name: "Garden Herb Ranch"),
                OptionChoice(id: "buffalo", name: "Zesty Buffalo"),
                OptionChoice(id: "sriracha", name: "Sweet & Spicy Sriracha"),
            ],
            maxSelect: max
        )
    }

    private static let sandwichMods = OptionGroup(
        id: "mods", title: "Customize",
        choices: [
            OptionChoice(id: "no-pickles", name: "No Pickles"),
            OptionChoice(id: "extra-pickles", name: "Extra Pickles"),
            OptionChoice(id: "add-cheese", name: "Add Pepper Jack", priceDelta: 0.60),
            OptionChoice(id: "multigrain", name: "Multigrain Bun"),
        ],
        maxSelect: 4
    )

    private static let drinkSize = OptionGroup(
        id: "size", title: "Size",
        choices: [
            OptionChoice(id: "s", name: "Small"),
            OptionChoice(id: "m", name: "Medium", priceDelta: 0.40),
            OptionChoice(id: "l", name: "Large", priceDelta: 0.80),
        ],
        minSelect: 1
    )

    private static let sideSize = OptionGroup(
        id: "size", title: "Size",
        choices: [
            OptionChoice(id: "m", name: "Medium"),
            OptionChoice(id: "l", name: "Large", priceDelta: 0.60),
        ],
        minSelect: 1
    )

    private static var meal: [OptionGroup] { [mealSize, sides, mealDrink] }

    // MARK: Items

    private static let placeholderItems: [String: [MarketItem]] = [
        "cfa-stamp": [
            MarketItem(id: "cfa-sandwich-meal", name: "Chick-fil-A Chicken Sandwich Meal", category: "Meals", emoji: "🍔", ddPrice: 10.29, calories: 1020,
                       detail: "Sandwich with a side and a drink",
                       options: meal + [sandwichMods, sauces(max: 2)]),
            MarketItem(id: "cfa-deluxe-meal", name: "Chicken Sandwich Deluxe Meal", category: "Meals", emoji: "🥬", ddPrice: 11.09, calories: 1100,
                       detail: "With lettuce, tomato and cheese",
                       options: meal + [sandwichMods, sauces(max: 2)]),
            MarketItem(id: "cfa-spicy-meal", name: "Spicy Chicken Sandwich Meal", category: "Meals", emoji: "🌶️", ddPrice: 10.69, calories: 1080,
                       options: meal + [sandwichMods, sauces(max: 2)]),
            MarketItem(id: "cfa-nugget-meal", name: "8ct Nuggets Meal", category: "Meals", emoji: "🍗", ddPrice: 10.09, calories: 880,
                       options: meal + [sauces(max: 2)]),
            MarketItem(id: "cfa-strips-meal", name: "3ct Chick-n-Strips Meal", category: "Meals", emoji: "🍗", ddPrice: 10.49, calories: 950,
                       options: meal + [sauces(max: 2)]),

            MarketItem(id: "cfa-sandwich", name: "Chick-fil-A Chicken Sandwich", category: "Entrées", emoji: "🥪", ddPrice: 5.69, calories: 420,
                       options: [sandwichMods, sauces(max: 1)]),
            MarketItem(id: "cfa-spicy", name: "Spicy Chicken Sandwich", category: "Entrées", emoji: "🌶️", ddPrice: 6.09, calories: 450,
                       options: [sandwichMods, sauces(max: 1)]),
            MarketItem(id: "cfa-nuggets-8", name: "8ct Nuggets", category: "Entrées", emoji: "🍗", ddPrice: 5.49, calories: 250,
                       options: [sauces(max: 2)]),
            MarketItem(id: "cfa-nuggets-12", name: "12ct Nuggets", category: "Entrées", emoji: "🍗", ddPrice: 7.69, calories: 380,
                       options: [sauces(max: 3)]),
            MarketItem(id: "cfa-cobb", name: "Cobb Salad", category: "Entrées", emoji: "🥗", ddPrice: 10.99, calories: 830,
                       options: [OptionGroup(id: "dressing", title: "Dressing", choices: [
                           OptionChoice(id: "avocado-lime", name: "Avocado Lime Ranch"),
                           OptionChoice(id: "ranch", name: "Garden Herb Ranch"),
                           OptionChoice(id: "balsamic", name: "Light Balsamic Vinaigrette"),
                       ], minSelect: 1)]),

            MarketItem(id: "cfa-fries", name: "Waffle Fries", category: "Sides", emoji: "🍟", ddPrice: 2.69, calories: 420, options: [sideSize]),
            MarketItem(id: "cfa-mac", name: "Mac & Cheese", category: "Sides", emoji: "🧀", ddPrice: 3.89, calories: 450, options: [sideSize]),
            MarketItem(id: "cfa-fruit", name: "Fruit Cup", category: "Sides", emoji: "🍓", ddPrice: 3.89, calories: 60, options: [sideSize]),

            MarketItem(id: "cfa-lemonade", name: "Lemonade", category: "Drinks", emoji: "🍋", ddPrice: 2.59, calories: 220, options: [drinkSize]),
            MarketItem(id: "cfa-tea", name: "Iced Tea", category: "Drinks", emoji: "🧋", ddPrice: 2.39, calories: 120,
                       options: [drinkSize, OptionGroup(id: "tea", title: "Sweet or unsweet", choices: [
                           OptionChoice(id: "sweet", name: "Sweet"),
                           OptionChoice(id: "unsweet", name: "Unsweet"),
                       ], minSelect: 1)]),
            MarketItem(id: "cfa-shake", name: "Milkshake", category: "Drinks", emoji: "🥤", ddPrice: 4.79, calories: 630,
                       options: [OptionGroup(id: "flavor", title: "Flavor", choices: [
                           OptionChoice(id: "cookies", name: "Cookies & Cream"),
                           OptionChoice(id: "chocolate", name: "Chocolate"),
                           OptionChoice(id: "strawberry", name: "Strawberry"),
                           OptionChoice(id: "vanilla", name: "Vanilla"),
                       ], minSelect: 1)]),
        ]
    ]

    /// Hand-entered items, used by demo data so it works whatever menu is bundled
    static func placeholderItem(_ id: String) -> MarketItem? {
        placeholderItems.values.joined().first { $0.id == id }
    }

    // MARK: Bundled Grubhub captures

    /// Menus from umd-dining-api/tools/import_grubhub_menu.py, falling back to the placeholder
    static let items: [String: [MarketItem]] = {
        var result = placeholderItems
        for location in locations {
            if let file = loadBundled(location.id) { result[location.id] = file.items.map(\.marketItem) }
        }
        return result
    }()

    /// When each bundled menu was captured from Grubhub; missing = placeholder
    static let capturedOn: [String: String] = {
        var result: [String: String] = [:]
        for location in locations {
            if let file = loadBundled(location.id) { result[location.id] = file.capturedOn }
        }
        return result
    }()

    private static func loadBundled(_ locationId: String) -> MenuFile? {
        guard let url = Bundle.main.url(forResource: "market-menu-\(locationId)", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MenuFile.self, from: data)
    }

    private struct MenuFile: Decodable {
        let capturedOn: String
        let items: [Item]

        enum CodingKeys: String, CodingKey {
            case capturedOn = "captured_on"
            case items
        }

        struct Item: Decodable {
            let id, name, category, emoji, description: String
            let price: Double
            let options: [Group]

            var marketItem: MarketItem {
                MarketItem(id: id, name: name, category: category, emoji: emoji, ddPrice: price,
                           detail: description, options: options.map(\.optionGroup))
            }
        }

        struct Group: Decodable {
            let id, title: String
            let min, max: Int
            let choices: [Choice]

            var optionGroup: OptionGroup {
                OptionGroup(id: id, title: title,
                            choices: choices.map { OptionChoice(id: $0.id, name: $0.name, priceDelta: $0.price) },
                            minSelect: min, maxSelect: max)
            }
        }

        struct Choice: Decodable {
            let id, name: String
            let price: Double
        }
    }
}
