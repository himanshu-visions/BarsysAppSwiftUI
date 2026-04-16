//
//  Services.swift
//  BarsysAppSwiftUI
//
//  Service protocols + mock implementations. Every ObservableObject ViewModel in
//  the Features/ folder talks to these, never directly to network/DB/BLE code.
//
//  To wire the real BarsysApp backend back in:
//    1. Create a class that conforms to the protocol below.
//    2. Delegate calls into the existing service layer (MyProfileApiService,
//       LoginSignUpOryApiService, DBManager, BleManager, SocketManager, etc.).
//    3. Swap the Mock* instance in `AppEnvironment.live()` for your real one.
//

import Foundation
import CoreBluetooth
import Combine
import SwiftUI

// MARK: - Errors

enum AppError: LocalizedError {
    case network(String)
    case invalidCredentials
    case notFound
    case bleUnavailable
    case unknown

    var errorDescription: String? {
        switch self {
        case .network(let m): return m
        case .invalidCredentials: return "Invalid credentials. Please try again."
        case .notFound: return "Not found."
        case .bleUnavailable: return "Bluetooth is unavailable."
        case .unknown: return "Something went wrong."
        }
    }
}

// MARK: - APIClient

protocol APIClient: AnyObject {
    func sendOtp(phone: String) async throws
    func verifyOtp(phone: String, code: String) async throws -> UserProfile
    func login(email: String, password: String) async throws -> UserProfile
    func signUp(firstName: String, lastName: String, email: String, phone: String, dob: Date?) async throws -> UserProfile
    func fetchProfile() async throws -> UserProfile
    func updateProfile(_ profile: UserProfile) async throws
    func fetchRecipes() async throws -> [Recipe]
    func fetchMixlists() async throws -> [Mixlist]
    func fetchFavorites() async throws -> [RecipeID]
}

final class MockAPIClient: APIClient {
    func sendOtp(phone: String) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    func verifyOtp(phone: String, code: String) async throws -> UserProfile {
        try await Task.sleep(nanoseconds: 600_000_000)
        guard code == "123456" || code.count == 6 else { throw AppError.invalidCredentials }
        return UserProfile(id: UUID().uuidString,
                           firstName: "Alex",
                           lastName: "Barsys",
                           email: "alex@barsys.com",
                           phone: phone,
                           countryCode: "US")
    }

    func login(email: String, password: String) async throws -> UserProfile {
        try await Task.sleep(nanoseconds: 600_000_000)
        guard !email.isEmpty, password.count >= 6 else { throw AppError.invalidCredentials }
        return UserProfile(id: UUID().uuidString,
                           firstName: "Alex",
                           lastName: "Barsys",
                           email: email,
                           phone: "",
                           countryCode: "US")
    }

    func signUp(firstName: String, lastName: String, email: String, phone: String, dob: Date?) async throws -> UserProfile {
        try await Task.sleep(nanoseconds: 600_000_000)
        return UserProfile(id: UUID().uuidString,
                           firstName: firstName,
                           lastName: lastName,
                           email: email,
                           phone: phone,
                           countryCode: "US",
                           dateOfBirth: dob)
    }

    func fetchProfile() async throws -> UserProfile {
        UserProfile(id: "me",
                    firstName: "Alex",
                    lastName: "Barsys",
                    email: "alex@barsys.com",
                    phone: "+15555550100",
                    countryCode: "US")
    }

    func updateProfile(_ profile: UserProfile) async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
    }

    func fetchRecipes() async throws -> [Recipe] { [] }
    func fetchMixlists() async throws -> [Mixlist] { [] }
    func fetchFavorites() async throws -> [RecipeID] { [] }
}

// MARK: - StorageService

protocol StorageService: AnyObject {
    func allRecipes() -> [Recipe]
    func recipe(by id: RecipeID) -> Recipe?
    func upsert(recipe: Recipe)
    func delete(recipe id: RecipeID)
    func allMixlists() -> [Mixlist]
    func upsert(mixlist: Mixlist)
    func delete(mixlist id: MixlistID)
    func clearRecipesAndMixlists()
    func myBarIngredients() -> [Ingredient]
    func toggleMyBar(_ ingredient: Ingredient)
    func favorites() -> Set<RecipeID>
    func toggleFavorite(_ id: RecipeID)
}

final class MockStorageService: StorageService {
    private var recipes: [RecipeID: Recipe]
    private var mixlists: [MixlistID: Mixlist]
    private var ingredients: [IngredientID: Ingredient]
    private var favs: Set<RecipeID>

    /// Start with EMPTY storage. Real API data is fetched by CatalogService.preload()
    /// on app launch and after login. No more SampleData mixing with real data.
    /// UIKit also starts with empty DB — data comes from API → DBManager.insertToDatabase.
    init() {
        self.recipes = [:]
        self.mixlists = [:]
        self.ingredients = Dictionary(uniqueKeysWithValues: SampleData.ingredients.map { ($0.id, $0) })
        self.favs = []
    }

    /// Ports DBManager.fetchAllRecipes() — returns all recipes with
    /// ingredientNames computed from nested ingredients if not already set.
    func allRecipes() -> [Recipe] {
        var result = Array(recipes.values)
        for i in result.indices {
            if result[i].ingredientNames == nil || result[i].ingredientNames?.isEmpty == true {
                let names = (result[i].ingredients ?? [])
                    .filter { ($0.category?.primary?.lowercased() ?? "") != "garnish" }
                    .map(\.name)
                    .removingDuplicates()
                result[i].ingredientNames = names.joined(separator: ", ")
            }
        }
        // UIKit DBQueries.swift L60:
        //   `SELECT * FROM recipes ORDER BY createdAt DESC`
        // Newest recipes first. Previous port sorted alphabetically
        // which reversed the entire cache-recipes listing vs UIKit.
        // Fallback to displayName only when the API payload didn't
        // include `createdAt` (some legacy / seed entries).
        return result.sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (l?, r?): return l > r                    // DESC
            case (nil, _?):    return false                    // nils last
            case (_?, nil):    return true
            case (nil, nil):   return lhs.displayName < rhs.displayName
            }
        }
    }
    func recipe(by id: RecipeID) -> Recipe? { recipes[id] }
    func upsert(recipe: Recipe) { recipes[recipe.id] = recipe }
    func delete(recipe id: RecipeID) { recipes.removeValue(forKey: id) }
    /// Ports DBManager.fetchMixlists() SQL JOIN that computes ingredient_names.
    /// UIKit SQL: SELECT m.*, (SELECT GROUP_CONCAT(DISTINCT i.name)
    ///   FROM ingredients i JOIN mixlistrecipes mr ON mr.recipeId = i.recipeId
    ///   WHERE mr.mixlistId = m.id AND LOWER(i.categoryPrimary) != 'garnish')
    /// We replicate this by joining mixlist.recipes with the recipes dict
    /// to compute ingredientNames from stored ingredients.
    func allMixlists() -> [Mixlist] {
        var result = Array(mixlists.values)
        // Compute ingredientNames for each mixlist from nested recipes
        for i in result.indices {
            let mixlist = result[i]
            // If ingredientNames already populated (from API compute), skip
            if let existing = mixlist.ingredientNames, !existing.isEmpty { continue }
            // Compute from nested recipes like UIKit DB JOIN
            let recipeList = mixlist.recipes ?? []
            let allIngredientNames = recipeList
                .flatMap { $0.ingredients ?? [] }
                .filter { ($0.category?.primary?.lowercased() ?? "") != "garnish" } // UIKit: exclude garnish
                .map(\.name)
                .removingDuplicates()
                .sorted()
            if !allIngredientNames.isEmpty {
                result[i].ingredientNames = allIngredientNames.joined(separator: ", ")
            }
        }
        // UIKit DBQueries.swift L28 / L57:
        //   `ORDER BY m.createdAt DESC`
        // Newest mixlists first, same behaviour as the recipes listing.
        return result.sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (l?, r?): return l > r
            case (nil, _?):    return false
            case (_?, nil):    return true
            case (nil, nil):   return lhs.displayName < rhs.displayName
            }
        }
    }

    func upsert(mixlist: Mixlist) { mixlists[mixlist.id] = mixlist }
    func delete(mixlist id: MixlistID) { mixlists.removeValue(forKey: id) }
    func myBarIngredients() -> [Ingredient] { Array(ingredients.values).sorted { $0.name < $1.name } }
    func toggleMyBar(_ ingredient: Ingredient) {
        if ingredients[ingredient.id] != nil {
            ingredients.removeValue(forKey: ingredient.id)
        } else {
            ingredients[ingredient.id] = ingredient
        }
    }
    /// Clear all recipes and mixlists. Called before inserting fresh API data
    /// so sample data doesn't mix with real data.
    func clearRecipesAndMixlists() {
        recipes.removeAll()
        mixlists.removeAll()
    }

    func favorites() -> Set<RecipeID> { favs }
    func toggleFavorite(_ id: RecipeID) {
        if favs.contains(id) { favs.remove(id) } else { favs.insert(id) }
        if var r = recipes[id] {
            r.isFavourite = favs.contains(id)
            recipes[id] = r
        }
    }
}

// MARK: - AuthService

final class AuthService: ObservableObject {
    @Published private(set) var profile: UserProfile = .empty
    @Published private(set) var isAuthenticated: Bool = false

    private let api: APIClient
    private let preferences: PreferencesService

    init(api: APIClient, preferences: PreferencesService) {
        self.api = api
        self.preferences = preferences
    }

    func restoreSession() async {
        // Check BOTH keys: PreferencesService uses "sessionToken",
        // UserDefaultsClass uses "session_token" (the real Ory token).
        // Either being non-nil means the user logged in before.
        let hasPrefsToken = preferences.sessionToken != nil
        let hasOryToken = UserDefaultsClass.getSessionToken()?.isEmpty == false
        guard hasPrefsToken || hasOryToken else { return }

        do {
            profile = try await api.fetchProfile()
            isAuthenticated = true
        } catch {
            // Don't clear session on profile fetch failure — the token may
            // still be valid for recipe/mixlist APIs. Only clear on explicit
            // logout. UIKit never clears session here.
            if hasOryToken {
                isAuthenticated = true  // Trust the stored Ory token
            }
        }
    }

    func sendOtp(phone: String) async throws {
        try await api.sendOtp(phone: phone)
    }

    func verifyOtp(phone: String, code: String) async throws {
        let p = try await api.verifyOtp(phone: phone, code: code)
        applySignedInProfile(p)
    }

    /// Used by callers that get a `UserProfile` directly from the API client
    /// (e.g. SignUp's `verifyRegistrationOtp`) — keeps the auth state machine
    /// in one place AND pushes the profile into the observable
    /// `UserProfileStore` so every SwiftUI view observing the store
    /// (HomeView greeting, SideMenu header) re-renders immediately.
    func applySignedInProfile(_ profile: UserProfile) {
        self.profile = profile
        // OryAPIClient already persists the real session_token to UserDefaults
        // under "sessionToken"; only mint a fresh placeholder if the real flow
        // didn't write one (mock client / unit tests).
        if preferences.sessionToken == nil {
            preferences.sessionToken = UUID().uuidString
        }
        isAuthenticated = true
        // Push every persisted field into the observable store so any view
        // that binds to `@EnvironmentObject var userStore: UserProfileStore`
        // sees the update in its next `body` evaluation.
        UserProfileStore.shared.apply(profile: profile)
    }

    func login(email: String, password: String) async throws {
        profile = try await api.login(email: email, password: password)
        preferences.sessionToken = UUID().uuidString
        isAuthenticated = true
    }

    func signUp(firstName: String, lastName: String, email: String, phone: String, dob: Date?) async throws {
        profile = try await api.signUp(firstName: firstName, lastName: lastName, email: email, phone: phone, dob: dob)
        preferences.sessionToken = UUID().uuidString
        isAuthenticated = true
    }

    func logout() {
        profile = .empty
        preferences.sessionToken = nil
        isAuthenticated = false
    }
}

// MARK: - PreferencesService


final class PreferencesService: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var measurementUnit: MeasurementUnit {
        didSet { defaults.set(measurementUnit.rawValue, forKey: "measurementUnit") }
    }

    @Published var selectedCountryCode: String {
        didSet { defaults.set(selectedCountryCode, forKey: "selectedCountryCode") }
    }

    @Published var hasSeenTutorial: Bool {
        didSet { defaults.set(hasSeenTutorial, forKey: "hasSeenTutorial") }
    }

    var sessionToken: String? {
        get { defaults.string(forKey: "sessionToken") }
        set {
            if let v = newValue { defaults.set(v, forKey: "sessionToken") }
            else { defaults.removeObject(forKey: "sessionToken") }
        }
    }

    init() {
        let unit = defaults.string(forKey: "measurementUnit").flatMap(MeasurementUnit.init(rawValue:)) ?? .ml
        self.measurementUnit = unit
        self.selectedCountryCode = defaults.string(forKey: "selectedCountryCode") ?? "US"
        self.hasSeenTutorial = defaults.bool(forKey: "hasSeenTutorial")
    }
}

// MARK: - BLEService


/// Mirrors `BleManager.disconnectedTypeState` — was the last disconnect
/// triggered by the user (tapping Disconnect in Control Center) or something
/// else (timeout, BLE off, peripheral vanished)?
enum BleDisconnectedState {
    case notManuallyDisconnected
    case manuallyDisconnected
}

enum BleReconnectionState {
    case idle
    case attempting
}

// MARK: - BLE characteristic UUIDs (ports `BLEManagerConstants` from
//         BarsysApp/Helpers/Constants/Constants+UI.swift L221-223)

/// Nordic UART Service (NUS) characteristic UUIDs used by every Barsys
/// peripheral. These MUST match the firmware exactly — a mismatch means
/// `peripheral(_:didDiscoverCharacteristicsFor:)` never finds the write
/// characteristic, `writeCharacteristic` stays nil, and `send(_:)`
/// silently returns false for every command. This was the root cause
/// of "Reset System doesn't work" / "Flush doesn't work" / all BLE
/// commands silently failing in release mode.
enum BLECharacteristicUUID {
    /// RX on the peripheral (app writes here). NUS TX UUID.
    static let write = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    /// TX on the peripheral (peripheral notifies here). NUS RX UUID.
    static let read  = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
}

final class BLEService: NSObject, ObservableObject {
    @Published private(set) var discovered: [BarsysDevice] = []
    @Published private(set) var connected: [BarsysDevice] = []
    @Published private(set) var state: DeviceConnectionState = .disconnected
    @Published var bluetoothAuthorized: Bool = false
    @Published private(set) var lastSentCommand: BleCommand?

    // MARK: - Characteristics (ports BleManager.writeCharacteristic /
    //         readCharacteristic — populated by
    //         `peripheral(_:didDiscoverCharacteristicsFor:)`)
    private(set) var readCharacteristic: CBCharacteristic?

    // MARK: - Command queue (ports BleManager.commandQueue + isWriting
    //         + processNextCommand)
    //
    // UIKit serializes writes via a lock-protected queue so back-to-back
    // commands don't race when CoreBluetooth is still processing the
    // previous `writeValue(_:for:type:)`. The previous SwiftUI port
    // wrote directly which works for single commands but breaks when
    // the Cleaning flow fires flush + readCommand + another command
    // rapidly (e.g. Clean → Pause → Stop in <500ms).
    private var commandQueue: [(command: String, characteristic: CBCharacteristic)] = []
    private var isWritingCommand: Bool = false
    private let commandQueueLock = NSLock()

    /// Most recent parsed BLE response from the connected device. Views
    /// observe this with `.onReceive($ble.lastResponse)` to drive their
    /// state machines (cleaning flow, crafting, etc.). Mirrors UIKit
    /// `BleManagerDelegate.bleDidReceiveData(_:)` callback chain.
    @Published private(set) var lastResponse: BleResponse?

    /// Ports `BleManager.disconnectedTypeState`.
    @Published var disconnectedState: BleDisconnectedState = .notManuallyDisconnected
    /// Ports `BleManager.reconnectionState`.
    @Published var reconnectionState: BleReconnectionState = .idle

    // MARK: - Post-connection callbacks
    //
    // These closures are set by the app layer (MainTabView / AppEnvironment)
    // so BLEService can trigger UI actions (toast, tab switch) without
    // importing SwiftUI view types. Mirrors the UIKit pattern where
    // BleManager.bleDelegate callbacks drive UI changes.

    /// Called after a successful connection. Ports the toast "{name} is Connected."
    /// and the tab switch to Explore in `moveToDevicePairedScreenAfterConnectionSuccessfully`.
    var onDeviceConnected: ((_ deviceName: String) -> Void)?

    /// Called after disconnection. Ports the toast "{name} is Disconnected."
    var onDeviceDisconnected: ((_ deviceName: String) -> Void)?

    // MARK: - CoreBluetooth (ports BleManager singleton)

    private var centralManager: CBCentralManager?
    /// The peripheral we're currently connecting / connected to.
    private(set) var connectedPeripheral: CBPeripheral?
    /// Write characteristic discovered after connection. Set by the
    /// `peripheral(_:didDiscoverCharacteristicsFor:)` delegate method
    /// (when implemented). Used by `send(_:)` to push BleCommand bytes
    /// to the connected device — matches UIKit `BleManager.writeCommand(_:)`.
    var writeCharacteristic: CBCharacteristic?
    /// Temporary device name stored during connection (UIKit: tempDeviceName).
    private var pendingDeviceName: String = ""

    /// The device kind filter currently active during a scan.
    /// Ports `DeviceListViewController.selectedDeviceType`.
    private(set) var scanFilter: DeviceKind?

    /// Non-published shadow storage for smoothed RSSI and lastSeen.
    /// Writing to `@Published discovered` on every BLE callback (~10/sec)
    /// causes SwiftUI to re-render the entire popup each time, creating
    /// visible "Excellent/Good/Fair" flickering. This shadow stores the
    /// latest smoothed RSSI + lastSeen WITHOUT triggering objectWillChange.
    /// Only when the signal *bracket* changes do we copy into `discovered`.
    private var rssiShadow: [String: (smoothedRSSI: Int, lastSeen: Date)] = [:]

    // MARK: - Init

    override init() {
        super.init()
        // Create CBCentralManager — triggers centralManagerDidUpdateState
        // immediately. Matches UIKit BleManager init.
        centralManager = CBCentralManager(delegate: self, queue: nil,
                                          options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: - Connection queries (match BleManager API surface)

    func isBarsys360Connected() -> Bool {
        connected.contains { $0.kind == .barsys360 }
    }
    func isCoasterConnected() -> Bool {
        connected.contains { $0.kind == .coaster }
    }
    func isBarsysShakerConnected() -> Bool {
        connected.contains { $0.kind == .shaker }
    }
    var isAnyDeviceConnected: Bool {
        !connected.isEmpty
    }
    func getConnectedDeviceName() -> String {
        connected.first?.name ?? ""
    }
    var connectedDeviceKind: IsDeviceType? {
        guard let first = connected.first else { return nil }
        switch first.kind {
        case .barsys360: return .barsys360
        case .coaster:   return .coaster
        case .shaker:    return .barsysShaker
        }
    }

    // MARK: - Command sending (mirrors BleManager+Commands.swift)

    /// 1:1 port of `BleManager.writeCommand(_:)`. Encodes the BleCommand
    /// rawValue (e.g. "202" for `.cancel`, "227,1," for `.flushStation(1)`)
    /// as UTF-8 bytes and writes them to the connected peripheral's write
    /// characteristic with `.withResponse` confirmation.
    ///
    /// Previously this method was a stub that only stashed `lastSentCommand`
    /// — which meant the Reset System button + every Pause/Stop/Flush
    /// command from the Cleaning flow silently no-op'd. Wiring it through
    /// `CBPeripheral.writeValue(_:for:type:)` makes those flows actually
    /// reach the firmware.
    @discardableResult
    func send(_ command: BleCommand) -> Bool {
        lastSentCommand = command

        guard connectedPeripheral != nil,
              let characteristic = writeCharacteristic else {
            #if DEBUG
            print("[BLEService] send(\(command.rawValue)) skipped — no peripheral / characteristic.")
            #endif
            return false
        }
        guard !command.rawValue.isEmpty else {
            #if DEBUG
            print("[BLEService] send skipped — empty command.")
            #endif
            return false
        }

        // 1:1 port of UIKit `BleManager.writeCommand(_:)` command queue:
        //   • enqueue under the lock
        //   • processNextCommand() dequeues + writes via CBPeripheral
        //   • didWriteValueFor marks isWriting=false + drains the queue
        commandQueueLock.lock()
        commandQueue.append((command: command.rawValue, characteristic: characteristic))
        commandQueueLock.unlock()

        processNextCommand()
        #if DEBUG
        print("[BLEService] enqueue \(command.rawValue)")
        #endif
        return true
    }

    /// 1:1 port of UIKit `BleManager.processNextCommand`. Drains one
    /// command at a time — CoreBluetooth can only process one
    /// `writeValue(_:for:type:)` at a time per peripheral; back-to-back
    /// calls without waiting for `didWriteValueFor` can drop writes.
    private func processNextCommand() {
        commandQueueLock.lock()
        guard !isWritingCommand else {
            commandQueueLock.unlock()
            return
        }
        guard !commandQueue.isEmpty else {
            commandQueueLock.unlock()
            return
        }
        let next = commandQueue.removeFirst()
        isWritingCommand = true
        commandQueueLock.unlock()

        guard let payload = next.command.data(using: .utf8) else {
            commandQueueLock.lock()
            isWritingCommand = false
            commandQueueLock.unlock()
            processNextCommand()
            return
        }
        connectedPeripheral?.writeValue(payload,
                                        for: next.characteristic,
                                        type: .withResponse)
    }

    /// 1:1 port of UIKit `BleManager.clearCommandQueue()`. Called on
    /// disconnect + manual cancel to drop pending writes.
    private func clearCommandQueue() {
        commandQueueLock.lock()
        commandQueue.removeAll()
        isWritingCommand = false
        commandQueueLock.unlock()
    }

    /// 1:1 port of UIKit `BleManager.readCommand(_:)` — subscribes to
    /// the read characteristic so `peripheral(_:didUpdateValueFor:)`
    /// starts receiving device notifications. The Cleaning +
    /// Crafting flows require this subscription to be active; without
    /// it, the firmware's state transitions never reach the app.
    func subscribeToReadCharacteristic() {
        guard let peripheral = connectedPeripheral,
              let readChar = readCharacteristic else { return }
        peripheral.readValue(for: readChar)
        peripheral.setNotifyValue(true, for: readChar)
    }

    /// Public hook that any callsite can use to feed a raw BLE notification
    /// string into the response stream. Mirrors UIKit
    /// `BleManagerDelegate.bleDidReceiveData(_:)`. The CBPeripheralDelegate
    /// `peripheral(_:didUpdateValueFor:error:)` extension calls this once
    /// the project wires it up; the cleaning ViewModel observes
    /// `$lastResponse` and drives the state machine off the parsed enum.
    func process(rawResponse raw: String) {
        let parsed = BleResponse(raw: raw)
        DispatchQueue.main.async { [weak self] in
            self?.lastResponse = parsed
        }
        #if DEBUG
        print("[BLEService] response \(raw) → \(parsed)")
        #endif
    }

    /// Test/Demo helper — lets a ViewModel inject a synthetic response
    /// (used by the local cleaning simulator when no real BLE device is
    /// connected so the state machine still runs end-to-end).
    func emitForTesting(_ response: BleResponse) {
        lastResponse = response
    }

    // MARK: - Reconnect flow (ports reconnectNowIfPreviouslyConnected)

    func attemptReconnect(toDeviceNamed name: String) {
        guard reconnectionState != .attempting else { return }
        reconnectionState = .attempting
        startScan()
        // Auto-reconnect timeout after 10s
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.reconnectionState == .attempting else { return }
            self.reconnectionState = .idle
            if self.connected.isEmpty {
                self.state = .disconnected
            }
        }
    }

    // MARK: - Scanning
    //
    // Ports BleManager.startBleScan() + BleManagerDelegate+Discovery.
    // CBCentralManager discovers peripherals incrementally. Each discovery
    // goes through the same filtering + dedup pipeline as the UIKit
    // `bleDidDiscoverDevice` delegate callback.

    /// Start BLE scan with an optional device-kind filter.
    func startScan(for kind: DeviceKind? = nil) {
        scanFilter = kind
        state = .discovering
        guard let cm = centralManager, cm.state == .poweredOn else { return }
        // Restart scan — allowing duplicates so we get RSSI updates
        cm.stopScan()
        cm.scanForPeripherals(withServices: nil,
                              options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    /// Convenience overload preserving the old call-site signature.
    func startScan() {
        startScan(for: scanFilter)
    }

    func stopScan() {
        centralManager?.stopScan()
    }

    /// Clear discovered devices list.
    func clearDiscovered() {
        discovered.removeAll()
        rssiShadow.removeAll()
    }

    /// Prune devices not seen since `threshold`.
    /// Checks the shadow storage for the authoritative lastSeen timestamp
    /// (the @Published array's lastSeen may be stale when signal bracket
    /// hasn't changed, because we skip publishing to avoid flicker).
    @discardableResult
    func pruneStaleDevices(olderThan threshold: Date) -> Bool {
        let before = discovered.count
        discovered.removeAll { device in
            let shadowLastSeen = rssiShadow[device.id.value]?.lastSeen ?? device.lastSeen
            return shadowLastSeen < threshold
        }
        // Also clean shadow entries for removed devices
        let activeIDs = Set(discovered.map(\.id.value))
        rssiShadow = rssiShadow.filter { activeIDs.contains($0.key) }
        return discovered.count != before
    }

    // MARK: - Connecting
    //
    // Ports BleManager.connect(to:deviceName:)

    func connect(_ device: BarsysDevice) async {
        state = .connecting
        // Find the CBPeripheral from discovered list
        // The device.id.value is the peripheral UUID string
        guard let cm = centralManager else {
            state = .failed
            return
        }

        // Retrieve peripheral by UUID
        let peripherals = cm.retrievePeripherals(withIdentifiers:
            [UUID(uuidString: device.id.value)].compactMap { $0 })
        guard let peripheral = peripherals.first else {
            state = .failed
            return
        }

        pendingDeviceName = device.name
        connectedPeripheral = peripheral

        // Wait for connection callback via delegate
        return await withCheckedContinuation { continuation in
            self._connectContinuation = continuation
            cm.connect(peripheral, options: nil)
            // Timeout after 12 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                guard let self else { return }
                if let cont = self._connectContinuation {
                    self._connectContinuation = nil
                    self.state = .failed
                    cont.resume()
                }
            }
        }
    }
    private var _connectContinuation: CheckedContinuation<Void, Never>?

    func disconnect(_ device: BarsysDevice) {
        // Disconnect from CoreBluetooth
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connected.removeAll { $0.id == device.id }
        connectedPeripheral = nil
        if connected.isEmpty { state = .disconnected }
        UserDefaultsClass.storeIsManuallyDisconnected(true)
        disconnectedState = .manuallyDisconnected
        reconnectionState = .idle
    }

    func rename(_ device: BarsysDevice, to newName: String) {
        if let idx = connected.firstIndex(where: { $0.id == device.id }) {
            connected[idx].name = newName
        }
    }

    // MARK: - Device name → DeviceKind mapping
    //
    // Ports the filtering logic from BleManagerDelegate+Discovery.swift:
    //   barsyscoaster: name contains "barsys_c" AND NOT "barsys_s"
    //   barsysShaker: name contains "barsys_s"
    //   barsys360: name contains "barsys_360" OR "basys_360" OR "barsys360"

    private func deviceKind(fromName name: String) -> DeviceKind? {
        let lowered = name.lowercased()
        if lowered.contains("barsys_s") && !lowered.contains("barsys_cst") {
            return .shaker
        } else if lowered.contains("barsys_c") {
            return .coaster
        } else if lowered.contains("barsys_360") || lowered.contains("basys_360") || lowered.contains("barsys360") {
            return .barsys360
        }
        return nil
    }

    /// Check if a device name matches the current scan filter.
    /// Ports the `matchesFilter` logic in `bleDidDiscoverDevice`.
    private func matchesScanFilter(name: String) -> Bool {
        guard let filter = scanFilter else { return true } // No filter = accept all
        guard let kind = deviceKind(fromName: name) else { return false }
        return kind == filter
    }
}

// MARK: - CBCentralManagerDelegate
//
// Ports BleManager+Commands.swift delegate methods.

extension BLEService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch central.state {
            case .poweredOn:
                self.bluetoothAuthorized = true
            case .poweredOff:
                self.bluetoothAuthorized = false
            case .unauthorized:
                self.bluetoothAuthorized = false
            default:
                break
            }
        }
    }

    /// Ports `centralManager(_:didDiscover:advertisementData:rssi:)` from
    /// BleManager+Commands.swift + the filtering/dedup in
    /// BleManagerDelegate+Discovery.bleDidDiscoverDevice.
    ///
    /// RSSI smoothing: raw BLE RSSI fluctuates 10-20 dBm between
    /// consecutive advertisements (~10/sec). Applying an exponential
    /// moving average (EMA) with α=0.2 dampens jitter, and we only
    /// publish a change to the `@Published discovered` array when the
    /// signal *bracket* changes (Excellent/Good/Fair/Weak). This prevents
    /// SwiftUI from re-rendering 10 times a second while still reflecting
    /// real signal changes within ~2 seconds — matching the UIKit UX where
    /// `configureSignal` only visually updates when the level text differs.
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = (advName ?? peripheral.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard matchesScanFilter(name: name) else { return }

        let rawRSSI = RSSI.intValue
        guard rawRSSI != 127 else { return } // 127 = unavailable, skip
        let peripheralID = peripheral.identifier.uuidString
        let kind = deviceKind(fromName: name) ?? .coaster
        let now = Date()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Look up the shadow entry for this peripheral (by UUID)
            let shadowKey = peripheralID
            let oldSmoothed = self.rssiShadow[shadowKey]?.smoothedRSSI ?? rawRSSI

            // Exponential moving average: α=0.2 dampens jitter
            let smoothed = Int(0.2 * Double(rawRSSI) + 0.8 * Double(oldSmoothed))

            // Always update shadow (non-published, no SwiftUI re-render)
            self.rssiShadow[shadowKey] = (smoothedRSSI: smoothed, lastSeen: now)

            let oldBracket = self.signalBracket(oldSmoothed)
            let newBracket = self.signalBracket(smoothed)
            let bracketChanged = oldBracket != newBracket

            // DEDUP STEP 1: Check by UUID (same physical device)
            if let idx = self.discovered.firstIndex(where: { $0.id.value == peripheralID }) {
                if bracketChanged {
                    // Signal level changed visually → update @Published array
                    self.discovered[idx].rssi = smoothed
                    self.discovered[idx].lastSeen = now
                }
                // If bracket is the same, do NOT touch @Published discovered
                // at all — prevents objectWillChange from firing. The shadow
                // still has the latest lastSeen for stale pruning.
                return
            }

            // DEDUP STEP 2: Check by case-insensitive name
            let nameLower = name.lowercased()
            if let idx = self.discovered.firstIndex(where: {
                $0.name.lowercased() == nameLower
            }) {
                if bracketChanged {
                    self.discovered[idx].rssi = smoothed
                    self.discovered[idx].lastSeen = now
                }
                return
            }

            // STEP 3: Truly new device — append to @Published array
            let device = BarsysDevice(
                id: DeviceID(peripheralID),
                name: name,
                kind: kind,
                serial: "",
                state: .disconnected,
                rssi: smoothed,
                lastSeen: now
            )
            self.discovered.append(device)
        }
    }

    /// Signal bracket for RSSI — used to decide if a UI update is needed.
    /// Returns 0-3 matching the four levels in DiscoveredDevice.
    private func signalBracket(_ rssi: Int) -> Int {
        switch rssi {
        case (-50)...:      return 3 // Excellent
        case (-70)...(-51): return 2 // Good
        case (-80)...(-71): return 1 // Fair
        default:            return 0 // Weak
        }
    }

    /// Ports `centralManager(_:didConnect:)` from BleManager+Commands.swift.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let deviceName = self.pendingDeviceName
                .replacingOccurrences(of: "\r\n", with: "")
                .trimmingCharacters(in: .whitespaces)
            let kind = self.deviceKind(fromName: deviceName) ?? .coaster

            let device = BarsysDevice(
                id: DeviceID(peripheral.identifier.uuidString),
                name: deviceName,
                kind: kind,
                serial: "",
                state: .connected,
                rssi: 0,
                lastSeen: Date()
            )
            self.connected.append(device)
            self.state = .connected
            self.connectedPeripheral = peripheral

            // CRITICAL — ports UIKit L184-185:
            //   peripheral.delegate = self
            //   peripheral.discoverServices(nil)
            // This kicks off the service → characteristic discovery
            // pipeline so `writeCharacteristic` + `readCharacteristic`
            // get populated. Without these lines the previous SwiftUI
            // port had NO way to write OR read BLE commands — every
            // `send()` call fell through the nil-characteristic guard.
            peripheral.delegate = self
            peripheral.discoverServices(nil)

            UserDefaultsClass.storeLastConnectedDevice(deviceName)
            UserDefaultsClass.storeIsManuallyDisconnected(false)
            self.disconnectedState = .notManuallyDisconnected
            self.reconnectionState = .idle

            // Notify app layer — shows toast + switches to Explore tab.
            // Ports BleManager+Commands.swift line 187:
            //   showToast(message: "\(name) is Connected.", duration: 6.0, textColor: .segmentSelectionColor)
            // + moveToDevicePairedScreenAfterConnectionSuccessfully() line 177:
            //   tab.selectedIndex = Tab.explore.rawValue
            self.onDeviceConnected?(deviceName)

            // Resume the async connect() call
            if let cont = self._connectContinuation {
                self._connectContinuation = nil
                cont.resume()
            }
        }
    }

    /// Ports `centralManager(_:didDisconnectPeripheral:error:)`.
    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Drop any pending writes — UIKit L195: `clearCommandQueue()`
            self.clearCommandQueue()

            let uuid = peripheral.identifier.uuidString
            let disconnectedName = self.connected.first { $0.id.value == uuid }?.name ?? ""
            self.connected.removeAll { $0.id.value == uuid }
            if self.connected.isEmpty {
                self.state = .disconnected
            }
            self.connectedPeripheral = nil
            // Clear characteristics so next connection cycle rediscovers them
            // (ports UIKit L257-258: writeCharacteristic=nil / readCharacteristic=nil).
            self.writeCharacteristic = nil
            self.readCharacteristic = nil

            // Notify app layer — shows toast + reverts tab.
            // Ports BleManager+Commands.swift line 214:
            //   showToast(message: "\(name) is Disconnected.", duration: 5.0, textColor: .errorLabelColor)
            if !disconnectedName.isEmpty {
                self.onDeviceDisconnected?(disconnectedName)
            }
        }
    }

    /// Ports `centralManager(_:didFailToConnect:error:)`.
    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state = .failed
            self.connectedPeripheral = nil
            if let cont = self._connectContinuation {
                self._connectContinuation = nil
                cont.resume()
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
//
// 1:1 port of the peripheral delegate methods in
// `BarsysApp/Controllers/BleManager/BleManager+Commands.swift`. Without
// these callbacks the CoreBluetooth connection sits idle — no
// characteristics are ever resolved and no notifications ever reach
// the app. The previous SwiftUI port was missing this entire extension,
// which is why EVERY BLE command silently failed in release:
//
//   • `didDiscoverServices`         → iterates services, asks each to
//                                      discover its characteristics.
//   • `didDiscoverCharacteristicsFor` → finds the NUS write + read
//                                      characteristics by UUID, stores
//                                      them for `send(_:)`, subscribes
//                                      to the read characteristic so
//                                      `didUpdateValueFor` starts
//                                      receiving device notifications.
//   • `didUpdateValueFor`           → feeds the raw response string
//                                      into `process(rawResponse:)`
//                                      which publishes `$lastResponse`.
//                                      Views drive state machines off
//                                      that publisher.
//   • `didWriteValueFor`            → marks the queue as ready for the
//                                      next command and calls
//                                      `processNextCommand()` to drain
//                                      it.

extension BLEService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            #if DEBUG
            print("[BLEService] didDiscoverServices error: \(String(describing: error))")
            #endif
            return
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil, let characteristics = service.characteristics else {
            #if DEBUG
            print("[BLEService] didDiscoverCharacteristicsFor error: \(String(describing: error))")
            #endif
            return
        }
        let writeUUID = CBUUID(string: BLECharacteristicUUID.write)
        let readUUID  = CBUUID(string: BLECharacteristicUUID.read)
        for characteristic in characteristics {
            if characteristic.uuid == writeUUID {
                writeCharacteristic = characteristic
                // UIKit L278: also enables notify on the write char so
                // the firmware can acknowledge writes through the same
                // characteristic on some device revisions.
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.uuid == readUUID {
                readCharacteristic = characteristic
                // Subscribe immediately so `didUpdateValueFor` starts
                // firing for every BLE notification. Without this, the
                // Cleaning + Crafting state machines never advance.
                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        #if DEBUG
        print("[BLEService] characteristics ready — write: \(writeCharacteristic != nil), read: \(readCharacteristic != nil)")
        #endif
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, let data = characteristic.value,
              let raw = String(data: data, encoding: .utf8) else {
            return
        }
        // 1:1 port of UIKit L265-270:
        //   didReceivedData?(string)
        //   bleDelegate?.bleDidReceiveData(string)
        // In SwiftUI the observer is any view that binds to
        // `$lastResponse` — notably the Cleaning + Crafting view
        // models via `.onReceive(ble.$lastResponse)`.
        process(rawResponse: raw)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        // 1:1 port of UIKit L290-303. Mark the write as complete so the
        // queue can drain its next command, then kick `processNextCommand`.
        commandQueueLock.lock()
        isWritingCommand = false
        commandQueueLock.unlock()

        if let error = error {
            #if DEBUG
            print("[BLEService] didWriteValueFor error: \(error.localizedDescription)")
            #endif
        }
        processNextCommand()
    }
}

// MARK: - SocketService


final class SocketService: ObservableObject {
    @Published private(set) var isConnected: Bool = false

    func connect() { isConnected = true }
    func disconnect() { isConnected = false }
    func send(_ event: String, payload: [String: Any] = [:]) { /* no-op mock */ }
}

// MARK: - BrazeService, Analytics

final class BrazeService {
    func track(event: String, properties: [String: Any] = [:]) {}
    func setUser(id: String) {}
}

final class AnalyticsService {
    func track(_ name: String, properties: [String: Any] = [:]) {}
    func screen(_ name: String) {}
}

// MARK: - CatalogService


final class CatalogService: ObservableObject {
    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var mixlists: [Mixlist] = []
    @Published private(set) var isLoading = false

    private let storage: StorageService
    private var api: APIClient?

    init(storage: StorageService) {
        self.storage = storage
    }

    /// Set the API client after init (avoids circular dependency in AppEnvironment).
    func setAPI(_ api: APIClient) {
        self.api = api
    }

    /// Load recipes and mixlists. First shows cached data, then fetches fresh
    /// data from the API in the background (ports the UIKit
    /// MixlistViewModel.getAllMixlistData + getCacheRecipesData flow).
    ///
    /// UIKit data pipeline:
    ///   1. Show cached DB data immediately
    ///   2. API call: GET cache/recipes?timestamp={last_fetch_epoch}
    ///   3. API call: GET cache/mixlists?timestamp={last_fetch_epoch}
    ///   4. Insert API data into SQLite (DBManager.insertToDatabase)
    ///   5. Reload UI from DB
    ///   6. Save current timestamp for next incremental fetch
    /// Full data sync matching the UIKit chain from MixlistsUpdateClass.updateMixlists:
    ///   1. GET cache/recipes?timestamp=          → getCacheRecipesData
    ///   2. GET cache/mixlists?timestamp=         → getAllMixlistData
    ///   3. GET my/cache/recipes/favorites?timestamp=  → getFavouritesData
    ///   4. For each favourite: update recipe.isFavourite in storage
    ///   5. Insert mixlists + nested recipes to storage (DBManager.insertToDatabase)
    ///   6. Save timestamps to UserDefaults
    ///   7. Update cacheRecipesTimestamp for 1-hour staleness check
    /// Minimum seconds between API calls to prevent 429 rate limiting.
    /// UIKit doesn't have explicit rate limiting but its sequential flow
    /// naturally spaces requests. SwiftUI's reactive nature can trigger
    /// multiple preload() calls rapidly (tab switch, onAppear, connection).
    private var lastAPICallTime: Date = .distantPast
    private let minAPIInterval: TimeInterval = 30 // 30 seconds between fetches

    func preload() async {
        // 1. Show cached data immediately
        recipes = storage.allRecipes()
        mixlists = storage.allMixlists()

        guard let api else { return }

        // Rate limit: skip API call if called too recently (prevents 429)
        // BUT always allow if storage is empty (e.g. app restart — in-memory storage lost)
        let storageIsEmpty = recipes.isEmpty && mixlists.isEmpty
        let elapsed = Date().timeIntervalSince(lastAPICallTime)
        if elapsed < minAPIInterval && !storageIsEmpty {
            print("[CatalogService] Skipping API call — last fetch was \(Int(elapsed))s ago")
            return
        }

        // If storage is empty (app restart), clear timestamps so API returns FULL data
        // instead of empty incremental response. UIKit persists to SQLite so this
        // doesn't happen there — but our in-memory storage needs a fresh fetch.
        if storageIsEmpty {
            UserDefaults.standard.removeObject(forKey: "updatedDataTimeStampForCacheRecipeData")
            UserDefaults.standard.removeObject(forKey: "updatedDataTimeStampForMixlistData")
            UserDefaults.standard.removeObject(forKey: "updatedDataTimeStampForFavourites")
            print("[CatalogService] Storage empty — cleared timestamps for fresh API fetch")
        }

        isLoading = true
        lastAPICallTime = Date()

        let currentTimestamp = Int(Date().timeIntervalSince1970)

        do {
            // 2. Fetch recipes + mixlists in parallel
            async let apiRecipes = api.fetchRecipes()
            async let apiMixlists = api.fetchMixlists()
            let (freshRecipes, freshMixlists) = try await (apiRecipes, apiMixlists)

            // 3. Insert data — always upsert (INSERT OR REPLACE like UIKit)
            let hasRealData = !freshRecipes.isEmpty || !freshMixlists.isEmpty
            if hasRealData {
                print("[CatalogService] Inserting \(freshRecipes.count) recipes + \(freshMixlists.count) mixlists")
            }

            // 4. Insert recipes to storage (ports insertCacheRecipeDatabase)
            for recipe in freshRecipes {
                storage.upsert(recipe: recipe)
            }

            // 5. Insert mixlists + nested recipes (ports _insertToDatabase)
            for mixlist in freshMixlists {
                storage.upsert(mixlist: mixlist)
                for nestedRecipe in mixlist.recipes ?? [] {
                    storage.upsert(recipe: nestedRecipe)
                }
            }

            // 6. Fetch and sync favourites (ports getFavouritesData + updateFavouriteStatus)
            do {
                let favIDs = try await api.fetchFavorites()
                if !favIDs.isEmpty {
                    // Mark each favourite recipe in storage
                    let currentFavs = storage.favorites()
                    for favID in favIDs {
                        if !currentFavs.contains(favID) {
                            storage.toggleFavorite(favID)
                        }
                    }
                    print("[CatalogService] Synced \(favIDs.count) favourites from API")
                }
            } catch {
                print("[CatalogService] Favourites sync failed: \(error)")
            }

            // 7. Reload published arrays
            recipes = storage.allRecipes()
            mixlists = storage.allMixlists()

            // 8. Save timestamps (ports saveUpdatedDataTimeStamp* methods)
            if hasRealData {
                UserDefaults.standard.set(currentTimestamp, forKey: "updatedDataTimeStampForCacheRecipeData")
                UserDefaults.standard.set(currentTimestamp, forKey: "updatedDataTimeStampForMixlistData")
                UserDefaults.standard.set(freshMixlists.count, forKey: "coreDataMixlistCount")
                lastFetchTimestamp = Date()
            }
        } catch {
            print("[CatalogService] API fetch failed: \(error)")
            // On failure, keep existing data (don't clear what we have)
            recipes = storage.allRecipes()
            mixlists = storage.allMixlists()
        }

        isLoading = false
        print("[CatalogService] Loaded \(recipes.count) recipes, \(mixlists.count) mixlists")
    }

    /// Pull-to-refresh (ports UIKit refresh control handler).
    func refresh() async {
        await preload()
    }

    // MARK: - Cache staleness (ports AppStateManager.areCacheRecipesStale)

    /// Last time recipes were fetched from API.
    private var lastFetchTimestamp: Date = .distantPast
    /// 1 hour cache expiration (ports AppStateManager.cacheExpirationInterval = 3600)
    private let cacheExpirationInterval: TimeInterval = 3600

    /// Returns true if recipes haven't been fetched in over 1 hour.
    var areCacheRecipesStale: Bool {
        Date().timeIntervalSince(lastFetchTimestamp) > cacheExpirationInterval
    }

    /// Check staleness and refresh if needed. Called from view onAppear.
    func refreshIfStale() async {
        if areCacheRecipesStale {
            print("[CatalogService] Cache is stale (>\(Int(cacheExpirationInterval))s), refreshing...")
            await preload()
        }
    }

    /// Toggle favourite status locally + call API.
    /// Ports FavoriteRecipeApiService.likeUnlikeApi() + DBManager.updateFavouriteStatus().
    func toggleFavourite(recipeId: RecipeID) {
        let wasFav = storage.favorites().contains(recipeId)
        storage.toggleFavorite(recipeId)
        recipes = storage.allRecipes()

        // Fire-and-forget API call to sync with server
        if let api = api as? OryAPIClient {
            Task {
                await api.toggleFavoriteOnServer(recipeId: recipeId.value, isFavourite: !wasFav)
            }
        }
    }
}

// MARK: - Loading / Alerts


final class LoadingState: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var message: String = ""

    func show(_ message: String = "Loading…") {
        self.message = message
        isVisible = true
    }

    func hide() {
        isVisible = false
        message = ""
    }
}

struct AppAlertItem: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String
    var primaryActionTitle: String = "OK"
    var primaryAction: (() -> Void)?
    /// Optional secondary button — when set, renders a two-button alert
    /// (1:1 with UIKit `showCustomAlertMultipleButtons`). For the
    /// "Ingredients may be spoiled. Clean the machine before use."
    /// alert the primary is "Clean" (tinted) and the secondary is
    /// "Okay".
    var secondaryActionTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    static func == (lhs: AppAlertItem, rhs: AppAlertItem) -> Bool { lhs.id == rhs.id }
}


final class AlertQueue: ObservableObject {
    @Published var current: AppAlertItem?

    func show(title: String = "Barsys", message: String = "", primary: String = "OK", action: (() -> Void)? = nil) {
        current = AppAlertItem(title: title, message: message, primaryActionTitle: primary, primaryAction: action)
    }

    /// Two-button variant — 1:1 port of UIKit
    /// `showCustomAlertMultipleButtons(title:subTitleStr:cancelButtonTitle:continueButtonTitle:…)`.
    /// `primary` is the left-side tinted button (UIKit names it
    /// `cancelButtonTitle` even though it's visually the primary
    /// action for decision alerts); `secondary` is the right-side
    /// neutral button.
    func show(title: String,
              message: String = "",
              primaryTitle: String,
              secondaryTitle: String,
              onPrimary: (() -> Void)? = nil,
              onSecondary: (() -> Void)? = nil) {
        current = AppAlertItem(
            title: title,
            message: message,
            primaryActionTitle: primaryTitle,
            primaryAction: onPrimary,
            secondaryActionTitle: secondaryTitle,
            secondaryAction: onSecondary
        )
    }

    func dismiss() { current = nil }
}
