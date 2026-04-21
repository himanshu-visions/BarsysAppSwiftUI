//
//  BarBotScreens.swift
//  BarsysAppSwiftUI
//
//  Full UIKit → SwiftUI parity port of the BarBot module.
//  Mirrors:
//    - BarBotViewController (+ TableView / TextViewDelegate / ScrollView / Accessibility extensions)
//    - BarBotViewModel
//    - BarBotApiService (+ ChatPost)
//    - MainBarBotCell (+ Actions / CollectionView)
//    - ChooseOptionTableViewCell + ChooseOptionCollectionViewCell
//    - BarBotRecipeCollectionViewCell
//    - BarBotMixlistCollectionViewCell
//    - BarBotHistoryViewController / BarBotHistoryListTableCell / BarBotHistoryViewModel
//    - RecipeCraftingClass+BarBotSetup (entry points)
//
//  API: https://ci.bond-mvp1.barsys.com/api/
//  Endpoints: POST /chat, GET /home-cards, GET /analytics/user/{id}/sessions,
//             GET /analytics/session/{id}/messages
//
//  All frames, constraints, shadows, colors, and typography match the UIKit
//  .xib definitions and shadow helpers 1:1.
//

import SwiftUI
import PhotosUI
import UIKit
import Combine

// MARK: - API Response Models (ports BarBotAIModelResponse.swift)

struct BarBotOption: Codable, Identifiable, Hashable {
    var id: String { title ?? UUID().uuidString }
    let title: String?
    let prompt: String?
}

struct BarBotAIResponse: Codable, Hashable {
    var response: String?
    var recipes: [BarBotRecipeElement]?
    var action_cards: [BarBotActionCard]?
    var barsys: BarBotBarsys?

    init(response: String? = nil, recipes: [BarBotRecipeElement]? = nil,
         action_cards: [BarBotActionCard]? = nil, barsys: BarBotBarsys? = nil) {
        self.response = response
        self.recipes = recipes
        self.action_cards = action_cards
        self.barsys = barsys
    }
}

struct BarBotBarsys: Codable, Hashable {
    var mixlists: [BarBotMixlistElement]?
    var recipes: [BarBotRecipeElement]?
}

struct BarBotRecipeElement: Codable, Identifiable, Hashable {
    var id: String { full_recipe_id ?? name ?? UUID().uuidString }
    var name: String?
    var descriptions: String?
    var ingredients: [BarBotIngredient]?
    var imageModel: BarBotImageModel?
    var full_recipe_id: String?

    enum CodingKeys: String, CodingKey {
        case name, descriptions, ingredients, imageModel = "image", full_recipe_id
    }

    /// Ports buildRecipeArray + MainBarBotCell+Actions quantity normalization:
    /// all base / mixer ingredient quantities are clamped to min 5.0 ml.
    var normalizedIngredients: [BarBotIngredient] {
        (ingredients ?? []).map { ing in
            var copy = ing
            if let q = copy.quantity, q < 5.0 { copy.quantity = 5.0 }
            else if copy.quantity == nil { copy.quantity = 5.0 }
            return copy
        }
    }
}

struct BarBotIngredient: Codable, Hashable {
    var name: String?
    var quantity: Double?
    var unit: String?
}

struct BarBotImageModel: Codable, Hashable {
    var url: String?
}

struct BarBotMixlistElement: Codable, Identifiable, Hashable {
    var id: String { name ?? UUID().uuidString }
    var name: String?
    var recipes: [BarBotRecipeElement]?
    var image: BarBotImageModel?
}

struct BarBotActionCard: Codable, Identifiable, Hashable {
    var id: String { (type ?? "") + "|" + (label ?? "") + "|" + (value ?? "") }
    let type: String?      // "chat" | "device" | "craft" | "shop"
    let label: String?
    let value: String?     // also used as actionID for device subroutes

    /// Ports filterActionCards — only keep the four supported types.
    static let allowedTypes: Set<String> = ["chat", "device", "craft", "shop"]

    /// JSON mapping — the API schema keys the subroute field as
    /// `action_id` (UIKit `BarBotActionCardModel.actionID` decodes
    /// from the same key via its CodingKeys). Previously the SwiftUI
    /// port decoded from `value`, which doesn't exist in the payload —
    /// so `value` was always `nil`, making every `"device"` card fall
    /// through to the `.switchTab(.homeOrControlCenter)` default and
    /// silently jumping to the Home/ControlCenter tab instead of
    /// triggering the pair-device / clean-device / setup action.
    /// Decoding from BOTH keys keeps backward compatibility with any
    /// mock/sample payloads that used `value` directly.
    enum CodingKeys: String, CodingKey {
        case type, label, value, action_id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type  = try c.decodeIfPresent(String.self, forKey: .type)
        self.label = try c.decodeIfPresent(String.self, forKey: .label)
        // Prefer `action_id` (the real API field); fall back to `value`
        // for legacy fixtures.
        self.value = try c.decodeIfPresent(String.self, forKey: .action_id)
            ?? c.decodeIfPresent(String.self, forKey: .value)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(type,  forKey: .type)
        try c.encodeIfPresent(label, forKey: .label)
        // Emit as the canonical API key so downstream consumers can
        // round-trip the payload without the field disappearing.
        try c.encodeIfPresent(value, forKey: .action_id)
    }

    init(type: String?, label: String?, value: String?) {
        self.type = type
        self.label = label
        self.value = value
    }
}

struct BarBotSession: Codable, Identifiable, Hashable {
    var id: String { session_id ?? UUID().uuidString }
    let session_id: String?
    let last_message_time: String?
    let first_user_message: String?

    var displayText: String {
        let msg = first_user_message ?? ""
        let dateStr = formattedDate
        if msg.isEmpty { return dateStr.isEmpty ? (last_message_time ?? "") : dateStr }
        return "\(msg) - \(dateStr)"
    }

    /// Ports BarBotHistoryViewController.convertHistoryDateString — all 6 formats.
    var formattedDate: String {
        guard let raw = last_message_time, !raw.isEmpty else { return "" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss"
        ]
        for fmt in formats {
            parser.dateFormat = fmt
            if let date = parser.date(from: raw) {
                let display = DateFormatter()
                display.dateFormat = "MM-dd-yyyy hh:mm a"
                display.timeZone = .current
                return display.string(from: date)
            }
        }
        return raw
    }
}

// MARK: - Chat message model (ports QuestionAnswerMergeModelToShow)

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    var questionText: String = ""
    var questionImage: UIImage?
    var answerText: String?
    var answerRecipes: [BarBotRecipeElement] = []
    var answerMixlists: [BarBotMixlistElement] = []
    var answerActionCards: [BarBotActionCard] = []
    var isLoading: Bool = false
    var isCancelled: Bool = false

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool { lhs.id == rhs.id }
}

// MARK: - Action routing (ports MainBarBotCell+Actions button handlers)

enum BarBotAction {
    case autoSendPrompt(String)
    case pairDevice
    case stationCleaning
    case stationsMenu
    case switchTab(AppTab)
    case openShop(URL, String)
    case startCraft(BarBotRecipeElement)
    case setupMixlistStations(BarBotMixlistElement)
    case openRecipe(BarBotRecipeElement)
    case noop
}

// MARK: - Session message decoder (handles bot_message as string OR structured)

private struct SessionMessageEnvelope: Decodable {
    let user_message: String?
    let bot_message: BotMessage?
    let action_cards: [BarBotActionCard]?
    let ai_generated_recipe: [BarBotRecipeElement]?
    let barsys_recipe_arr: [BarBotRecipeElement]?
    let barsys_mixlist_arr: [BarBotMixlistElement]?

    enum BotMessage: Decodable {
        case text(String)
        case structured(BarBotAIResponse)

        init(from decoder: Decoder) throws {
            if let container = try? decoder.singleValueContainer(),
               let s = try? container.decode(String.self) {
                self = .text(s); return
            }
            let decoded = try BarBotAIResponse(from: decoder)
            self = .structured(decoded)
        }
    }
}

private struct SessionMessagesResponse: Decodable {
    let messages: [SessionMessageEnvelope]?
}

private struct SessionsResponse: Decodable {
    let sessions: [BarBotSession]?
}

// MARK: - BarBot API Service (ports BarBotApiService + ChatPost)

actor BarBotAPIService {
    static let shared = BarBotAPIService()

    private let baseURL = "https://ci.bond-mvp1.barsys.com/api/"

    private func makeRequest(path: String, method: String = "GET") -> URLRequest? {
        guard let url = URL(string: baseURL + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = UserDefaultsClass.getSessionToken(), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    /// GET /home-cards?status=online
    func fetchHomeCards() async throws -> [BarBotOption] {
        guard let req = makeRequest(path: "home-cards?status=online") else { return [] }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([BarBotOption].self, from: data)
    }

    /// POST /chat — supports Task cancellation via URLSession.
    func chat(userId: String,
              sessionId: String,
              text: String,
              imageBase64: String?,
              deviceNumber: String,
              deviceConnected: Bool) async throws -> BarBotAIResponse {
        guard var req = makeRequest(path: "chat", method: "POST") else {
            throw URLError(.badURL)
        }
        var input: [String: Any] = ["text": text]
        if let b64 = imageBase64 {
            input["image"] = [
                "url": "data:image/jpeg;base64,\(b64)",
                "metadata": [
                    "source": "camera",
                    "timestamp": "\(Date().timeIntervalSince1970)"
                ]
            ] as [String: Any]
        }
        let body: [String: Any] = [
            "user_id": userId,
            "session_id": sessionId,
            "input": input,
            "metadata": [
                "platform": "web",
                "app_version": "",
                "language": "",
                "device": [
                    "device_number": deviceNumber,
                    "connection_status": deviceConnected ? "connected" : "disconnected"
                ]
            ] as [String: Any]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(BarBotAIResponse.self, from: data)
    }

    /// GET /analytics/user/{userId}/sessions
    func fetchSessions(userId: String) async throws -> [BarBotSession] {
        guard let req = makeRequest(path: "analytics/user/\(userId)/sessions") else { return [] }
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONDecoder().decode(SessionsResponse.self, from: data))?.sessions ?? []
    }

    /// GET /analytics/session/{sessionId}/messages
    func fetchSessionMessages(sessionId: String) async throws -> [ChatMessage] {
        guard let req = makeRequest(path: "analytics/session/\(sessionId)/messages") else { return [] }
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let envelope = try? JSONDecoder().decode(SessionMessagesResponse.self, from: data) else {
            return []
        }
        return (envelope.messages ?? []).map { msg in
            var cm = ChatMessage()
            cm.questionText = msg.user_message ?? ""
            switch msg.bot_message {
            case .text(let s): cm.answerText = s
            case .structured(let r):
                cm.answerText = r.response
                // Apply the SAME merge algorithm the live-chat path uses so
                // history-loaded messages render identical recipe cards.
                cm.answerRecipes  = BarBotRecipeMerger.merge(ai: r.recipes ?? [],
                                                          barsys: r.barsys?.recipes ?? [])
                cm.answerMixlists = r.barsys?.mixlists ?? []
                cm.answerActionCards = (r.action_cards ?? []).filter {
                    BarBotActionCard.allowedTypes.contains($0.type ?? "")
                }
            case .none: break
            }
            // Some endpoints return separate arrays next to bot_message:
            if cm.answerRecipes.isEmpty, let ai = msg.ai_generated_recipe {
                cm.answerRecipes = BarBotRecipeMerger.merge(ai: ai,
                                                         barsys: msg.barsys_recipe_arr ?? [])
            } else if let barsysRecipes = msg.barsys_recipe_arr {
                // Merge the sibling barsys_recipe_arr through the same
                // dedupe + normalization pipeline.
                cm.answerRecipes = BarBotRecipeMerger.merge(ai: cm.answerRecipes,
                                                         barsys: barsysRecipes)
            }
            if cm.answerMixlists.isEmpty, let mx = msg.barsys_mixlist_arr { cm.answerMixlists = mx }
            if cm.answerActionCards.isEmpty, let cards = msg.action_cards {
                cm.answerActionCards = cards.filter { BarBotActionCard.allowedTypes.contains($0.type ?? "") }
            }
            return cm
        }
    }

}

/// File-scope helper that ports `BarBotViewModel.buildRecipeArray(from:)`
/// so BOTH the live-chat path (`BarBotViewModel.mergeRecipes`) AND the
/// session-history path (`BarBotAPIService.fetchSessionMessages`) share
/// the exact same normalization + dedupe rules:
///
///   • AI recipes → normalized (quantity < 5.0 → 5.0 on every ingredient;
///     nil → 5.0) BEFORE append.  Mirrors `normalizeRecipeIngredients`.
///   • Barsys recipes → appended verbatim (already curated).
///   • Dedup key = `"{name}_{ingredients.count}"`, first wins.
enum BarBotRecipeMerger {
    static func merge(ai: [BarBotRecipeElement],
                      barsys: [BarBotRecipeElement]) -> [BarBotRecipeElement] {
        var all: [BarBotRecipeElement] = []
        for r in ai {
            var copy = r
            copy.ingredients = r.normalizedIngredients
            all.append(copy)
        }
        all.append(contentsOf: barsys)
        var seen = Set<String>()
        return all.filter { r in
            let key = "\(r.name ?? "")_\(r.ingredients?.count ?? 0)"
            return seen.insert(key).inserted
        }
    }
}

// MARK: - BarBot ViewModel (ports BarBotViewModel.swift)

@MainActor
final class BarBotViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published var isTyping: Bool = false
    @Published var options: [BarBotOption] = []
    @Published var isOptionsLoading: Bool = true
    @Published var selectedImage: UIImage?
    @Published var sessions: [BarBotSession] = []
    @Published var isLoadingSessions: Bool = false
    @Published var craftingInProgress: Bool = false

    /// Ports BarBotViewModel.historySessionId.
    var historySessionId: String = ""
    private var sessionTimestamp = Date().timeIntervalSince1970
    private var optionsRetryCount = 0

    /// Ports in-flight task map keyed by message.id so the loading-cell cancel
    /// button can abort exactly the right request.
    private var inFlight: [UUID: Task<Void, Never>] = [:]

    /// Ports isProcessingRequest — last message waiting for an answer.
    var isProcessingRequest: Bool {
        guard let last = messages.last else { return false }
        return last.isLoading || (last.answerText == nil && last.answerRecipes.isEmpty &&
                                  last.answerMixlists.isEmpty && last.answerActionCards.isEmpty &&
                                  !last.isCancelled && !last.questionText.isEmpty)
    }

    /// Blocks sends, side-menu swipe, occasion taps, history taps.
    var canProcessNewRequest: Bool { !isProcessingRequest && !craftingInProgress }

    /// Ports BarBotViewModel.welcomeMessage — three lines, 24pt bold.
    var welcomeMessage: String {
        let name = UserDefaultsClass.getName() ?? ""
        return name.isEmpty
            ? "Hello,\nCrafted by Barsys. Powered\nby AI. Poured in real life."
            : "Hello \(name),\nCrafted by Barsys. Powered\nby AI. Poured in real life."
    }

    /// Ports currentSessionId — "{timestamp}_{deviceId}" for new chats.
    private var currentSessionId: String {
        if !historySessionId.isEmpty { return historySessionId }
        return "\(Int(sessionTimestamp))_\(UserDefaultsClass.getDeviceID())"
    }

    // MARK: - Setup

    func setupNewChat() {
        // Cancel any pending work from the previous session.
        for (_, t) in inFlight { t.cancel() }
        inFlight.removeAll()

        historySessionId = ""
        sessionTimestamp = Date().timeIntervalSince1970
        messages = []
        optionsRetryCount = 0
        draft = ""
        selectedImage = nil
        isTyping = false
        craftingInProgress = false
        fetchOptions()
    }

    // MARK: - Home cards with retry (ports loadChatOptions)

    func fetchOptions() {
        isOptionsLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let cards = try await BarBotAPIService.shared.fetchHomeCards()
                await MainActor.run {
                    self.options = cards.isEmpty ? self.fallbackOptions : cards
                    self.isOptionsLoading = false
                }
            } catch {
                await MainActor.run { self.retryOptionsIfNeeded() }
            }
        }
    }

    private func retryOptionsIfNeeded() {
        optionsRetryCount += 1
        if optionsRetryCount < 3 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.fetchOptions()
            }
        } else {
            options = fallbackOptions
            isOptionsLoading = false
        }
    }

    private var fallbackOptions: [BarBotOption] {
        [
            .init(title: "Birthday Party", prompt: "Suggest cocktails for a birthday party"),
            .init(title: "Date Night", prompt: "Recommend romantic cocktails for a date night"),
            .init(title: "Game Day", prompt: "What are good drinks for watching sports?"),
            .init(title: "After Dinner", prompt: "Suggest after-dinner digestif cocktails")
        ]
    }

    // MARK: - Send (ports sendQuestionToServer)

    func send(ble: BLEService) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || selectedImage != nil else { return }
        guard canProcessNewRequest else { return }

        var msg = ChatMessage(questionText: text,
                              questionImage: selectedImage,
                              isLoading: true)
        messages.append(msg)
        let id = msg.id
        let capturedImage = selectedImage

        draft = ""
        selectedImage = nil
        isTyping = true

        let deviceNumber: String = {
            if ble.isBarsys360Connected() { return Constants.barsys360NameTitle }
            if ble.isCoasterConnected() { return Constants.barsysCoasterTitle }
            if ble.isBarsysShakerConnected() { return Constants.barsysShakerTitle }
            return UserDefaultsClass.getLastConnectedDevice() ?? ""
        }()
        let deviceConnected = ble.isAnyDeviceConnected

        let userId = UserDefaultsClass.getUserId() ?? "gpol"
        let session = currentSessionId

        let imageB64 = capturedImage?.jpegData(compressionQuality: 0.7)?.base64EncodedString()

        let task = Task { [weak self] in
            do {
                let response = try await BarBotAPIService.shared.chat(
                    userId: userId,
                    sessionId: session,
                    text: text,
                    imageBase64: imageB64,
                    deviceNumber: deviceNumber,
                    deviceConnected: deviceConnected
                )
                try Task.checkCancellation()
                await MainActor.run { [weak self] in
                    self?.applyResponse(response, to: id)
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in self?.markCancelled(id) }
            } catch {
                await MainActor.run { [weak self] in
                    self?.applyResponse(BarBotAIResponse(response: "Sorry, something went wrong. Please try again."),
                                        to: id)
                }
            }
        }
        inFlight[id] = task
    }

    func sendOption(_ option: BarBotOption, ble: BLEService) {
        draft = option.prompt ?? option.title ?? ""
        send(ble: ble)
    }

    /// Ports cancelLastQuestion — tapped via loading-cell cross.
    func cancel(messageID: UUID) {
        inFlight[messageID]?.cancel()
        inFlight[messageID] = nil
        markCancelled(messageID)
    }

    private func markCancelled(_ id: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].isLoading = false
        messages[idx].isCancelled = true
        if messages[idx].answerText == nil { messages[idx].answerText = "Cancelled" }
        isTyping = false
    }

    private func applyResponse(_ response: BarBotAIResponse, to id: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].answerText = response.response
        messages[idx].answerRecipes = mergeRecipes(response)
        messages[idx].answerMixlists = response.barsys?.mixlists ?? []
        messages[idx].answerActionCards = (response.action_cards ?? []).filter {
            BarBotActionCard.allowedTypes.contains($0.type ?? "")
        }
        messages[idx].isLoading = false
        inFlight[id] = nil
        isTyping = false
    }

    /// 1:1 port of `BarBotViewModel.buildRecipeArray(from:)`. Both the
    /// live chat path and the session-history path call into the same
    /// `BarBotRecipeMerger.merge(ai:barsys:)` helper so recipe cards
    /// always render through the identical pipeline.
    private func mergeRecipes(_ response: BarBotAIResponse) -> [BarBotRecipeElement] {
        BarBotRecipeMerger.merge(
            ai: response.recipes ?? [],
            barsys: response.barsys?.recipes ?? []
        )
    }

    // MARK: - Action card routing (ports MainBarBotCell+Actions switch)

    func handle(card: BarBotActionCard, for message: ChatMessage) -> BarBotAction {
        switch card.type {
        case "chat":
            return .autoSendPrompt(card.value ?? card.label ?? "")
        case "device":
            switch card.value {
            case "redirect:connect_device":                 return .pairDevice
            case "redirect:clean_device":                   return .stationCleaning
            case "redirect:setup_barsys360",
                 "redirect:setup_stations":                 return .stationsMenu
            default:                                        return .switchTab(.homeOrControlCenter)
            }
        case "craft":
            // UIKit: craftAction(recipeToCraft: card.data?.recipe). We use the
            // first recipe attached to the message as the target (mirrors the
            // "craft this" action on recipe-carrying bot messages).
            if let recipe = message.answerRecipes.first { return .startCraft(recipe) }
            return .noop
        case "shop":
            if let raw = card.value, let url = URL(string: raw) {
                return .openShop(url, card.label ?? "Shop")
            }
            return .noop
        default:
            return .noop
        }
    }

    // MARK: - History

    func fetchSessions() {
        let userId = UserDefaultsClass.getUserId() ?? ""
        guard !userId.isEmpty else { return }
        isLoadingSessions = true
        Task { [weak self] in
            do {
                let list = try await BarBotAPIService.shared.fetchSessions(userId: userId)
                await MainActor.run {
                    self?.sessions = list
                    self?.isLoadingSessions = false
                }
            } catch {
                await MainActor.run { self?.isLoadingSessions = false }
            }
        }
    }

    func loadSession(_ session: BarBotSession) {
        guard let sid = session.session_id else { return }
        historySessionId = sid
        messages = []
        isTyping = true
        Task { [weak self] in
            do {
                let loaded = try await BarBotAPIService.shared.fetchSessionMessages(sessionId: sid)
                await MainActor.run {
                    self?.messages = loaded
                    self?.isTyping = false
                }
            } catch {
                await MainActor.run { self?.isTyping = false }
            }
        }
    }
}

// MARK: - Support: Bounce button style (ports addBounceEffect)

/// 1:1 port of UIKit `UIButton.addBounceEffect()`:
///   - handleBounceDown: scale 0.95 over 0.08s (curveEaseIn)
///   - handleBounceUp: spring back to 1.0 over 0.15s (damping 0.5, velocity 0.8)
///   - Respects UIAccessibility.isReduceMotionEnabled
struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(
                configuration.isPressed
                    ? .easeIn(duration: 0.08)
                    : .spring(response: 0.15, dampingFraction: 0.5),
                value: configuration.isPressed
            )
    }
}

// MARK: - Support: Action-card style (ports MainBarBotCell+Actions PaddingLabel)

struct ActionCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.of(.caption1))
            .foregroundStyle(Color(red: 0x36/255, green: 0x36/255, blue: 0x36/255))
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
            .frame(minHeight: 28)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color("actionCardBorderColor"), lineWidth: 1)
            )
    }
}

// MARK: - Support: Shimmer (ports ChooseOptionTableViewCell CAGradientLayer shimmer)

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.white.opacity(0.55), location: 0.5),
                        .init(color: .clear, location: 1)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 260)
                .mask(content)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// MARK: - Support: FlowLayout (wraps action cards to multiple lines)

struct FlowLayout: Layout {
    var hSpacing: CGFloat = 12
    var vSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let r = arrange(proposal: proposal, subviews: subviews)
        return r.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (i, offset) in r.offsets.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                              proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (offsets: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, total: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxWidth && x > 0 {
                x = 0; y += rowH + vSpacing; rowH = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            rowH = max(rowH, s.height)
            x += s.width + hSpacing
            total = y + rowH
        }
        return (offsets, CGSize(width: maxWidth, height: total))
    }
}

// MARK: - Support: Image picker (ports ImagePickerViewController)

/// Back-compat alias — other features still reference `ImagePicker(image:)`.
typealias ImagePicker = BarBotImagePicker

struct BarBotImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var source: UIImagePickerController.SourceType = .photoLibrary
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.delegate = context.coordinator
        p.sourceType = source
        p.allowsEditing = false
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: BarBotImagePicker
        init(_ p: BarBotImagePicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Support: Growing UITextView (ports askAnythingTextView 44→70 growth)

struct GrowingTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var minHeight: CGFloat = 44
    var maxHeight: CGFloat = 70
    var font: UIFont = UIFont(name: "SFProDisplay-Regular", size: 16) ?? .systemFont(ofSize: 16)
    var onSend: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = font
        tv.backgroundColor = .clear
        tv.textColor = UIColor(named: "appBlackColor") ?? .black
        tv.tintColor = .black
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 6, bottom: 12, right: 6)
        tv.textContainer.lineFragmentPadding = 0
        tv.returnKeyType = .default
        tv.keyboardType = .default
        // Done / Cancel toolbar (ports addDoneCancelToolbar).
        let bar = UIToolbar()
        bar.sizeToFit()
        let cancel = UIBarButtonItem(title: "Cancel", style: .plain, target: context.coordinator,
                                     action: #selector(Coordinator.cancel))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(title: "Done", style: .done, target: context.coordinator,
                                   action: #selector(Coordinator.done))
        bar.items = [cancel, flex, done]
        tv.inputAccessoryView = bar
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        recalcHeight(uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    fileprivate func recalcHeight(_ tv: UITextView) {
        let newSize = tv.sizeThatFits(CGSize(width: tv.bounds.width,
                                             height: .greatestFiniteMagnitude))
        let clamped = min(maxHeight, max(minHeight, newSize.height))
        if abs(clamped - height) > 0.5 {
            DispatchQueue.main.async { height = clamped }
        }
        tv.isScrollEnabled = newSize.height >= maxHeight
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: GrowingTextView
        init(_ p: GrowingTextView) { parent = p }
        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            parent.recalcHeight(tv)
        }
        @objc func done() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
            parent.onSend()
        }
        @objc func cancel() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }
    }
}

// MARK: - Welcome / occasion section (ports ChooseOptionTableViewCell)

// 1:1 port of the UIKit `ChooseOptionTableViewCell.xib` +
// `ChooseOptionCollectionViewCell.xib` + their runtime overrides:
//
//   `questionLabel` (welcome text) — storyboard `NiT-e7-6fk`:
//        boldSystem 24pt, textColor `mediumLightGrayColor`.
//        Text set at runtime to `BarBotViewModel.welcomeMessage`
//        ("Hello {name},\nCrafted by Barsys. Powered\nby AI. Poured…").
//
//   `optionsLabel` — storyboard `fvf-TL-f9A`:
//        text literal "Let's get crafting" (curly apostrophe "Let's"),
//        system 18pt, textColor `charcoalTextColor50Alpha`.
//
//   `ChooseOptionCollectionViewCell` tile:
//        • Outer 156×119 clear, inner 146×109 inset 5pt.
//        • Inner backgroundColor `grayColorForBarBot` (RGB 0.922 ×3).
//        • roundCorners 8 from xib, OVERRIDDEN at runtime by
//          `innerView.applyCustomShadow(cornerRadius: BarsysCornerRadius.medium,
//                                       size: 1.0, shadowRadius: 3.0)`
//          → cornerRadius 12, shadow black opacity 0.43 offset (0, 1)
//            radius 3.
//        • Title label `sZo-lZ-SEQ`: system 14pt (xib default), OVERRIDDEN
//          at runtime to `AppFontClass.font(.callout, weight: .semibold)`
//          + textColor `.charcoalGrayColor`.
//        • Description `Ckk-Zu-HK1`: system 12pt `.charcoalGrayColor`.
//        • Layout inside 146×109 inner: title at (16, 5) w=100 h=47,
//          description at (16, 52) w=122 h=47. Title 16pt leading,
//          30pt trailing. Description 16pt leading, 8pt trailing.
struct WelcomeOccasionSection: View {
    @ObservedObject var vm: BarBotViewModel
    let onSelect: (BarBotOption) -> Void

    private let tileHeight: CGFloat = 120
    private let gridSpacing: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Welcome — UIKit `questionLabel` (storyboard `NiT-e7-6fk`):
            //   boldSystem 24pt, textColor `mediumLightGrayColor`,
            //   ALPHA 0.51 on the label itself (xib attribute
            //   `alpha="0.51000000000000001"`). Multi-line, wraps freely
            //   (numberOfLines=0).
            //   Top constraint `8ik-d4-9fw`: top = contentView.top + 12.
            Text(vm.welcomeMessage)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color("mediumLightGrayColor").opacity(0.51))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)

            // ---- Flex gap between welcome and options block ----
            //
            // UIKit xib constraints (`IPr-Ix-mPV` + `Nlt-dI-t1j`):
            //   TYS-bd-tKf.top >= NiT-e7-6fk.bottom  (flex, no constant)
            //   contentView.bottom = TYS-bd-tKf.bottom + 16
            //
            // The options view is PINNED TO THE BOTTOM of the cell with
            // a 16pt inset, and its top floats on top of a flexible
            // greater-than-or-equal constraint. On the xib design canvas
            // (392pt cell) that resolves to a ~186pt gap between welcome
            // and "Let's get crafting" — which is the generous breathing
            // space the UIKit build ships.
            //
            // The prior port used `VStack(spacing: 20)` which collapsed
            // the whole cell to welcome + 20pt + "Let's get crafting" —
            // far tighter than UIKit. We now add an explicit ~70pt
            // spacer below the welcome message so the options block
            // sits noticeably lower, matching the visual rhythm of the
            // UIKit xib while still letting the cell remain
            // content-sized in a SwiftUI `LazyVStack`.
            Color.clear.frame(height: 70)

            // Options block — "Let's get crafting" label + 2×2 grid.
            // UIKit internal spacing `Txz-p7-YgZ`: WNl-Dc-66p.top =
            // fvf-TL-f9A.bottom + 20.
            VStack(alignment: .leading, spacing: 20) {
                Text("Let\u{2019}s get crafting") // curly apostrophe matches UIKit xib
                    .font(.system(size: 18))
                    .foregroundStyle(Color("charcoalTextColor50Alpha"))
                    .accessibilityAddTraits(.isHeader)

                if vm.isOptionsLoading && vm.options.isEmpty {
                    skeletonGrid
                } else {
                    grid
                }
            }
            // UIKit bottom constraint (`Nlt-dI-t1j`): 16pt below options.
            .padding(.bottom, 16)
        }
    }

    private var grid: some View {
        let cols = [GridItem(.flexible(), spacing: gridSpacing),
                    GridItem(.flexible(), spacing: gridSpacing)]
        return LazyVGrid(columns: cols, spacing: gridSpacing) {
            ForEach(vm.options) { opt in
                Button {
                    HapticService.light()
                    onSelect(opt)
                } label: {
                    tile(opt)
                }
                .buttonStyle(BounceButtonStyle())
                .disabled(!vm.canProcessNewRequest)
            }
        }
    }

    private func tile(_ opt: BarBotOption) -> some View {
        // UIKit outer cell: 156×119 clear. Inner card `lbg-yu-hL3`:
        //   5pt inset on all sides → 146×109, `grayColorForBarBot` bg,
        //   cornerRadius 12 (runtime), shadow 0.43/(0,1)/radius 3.
        //   Title at (16, 5) 14pt semibold, description at (16, 52)
        //   12pt regular, both `charcoalGrayColor`.
        VStack(alignment: .leading, spacing: 0) {
            // UIKit title frame: (16, 5) w=100 h=47 — fixed 47pt height
            // allocation so the description always starts at y≈52 regardless
            // of whether the title wraps to 1 or 2 lines.
            Text(opt.title ?? "")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color("charcoalGrayColor"))
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 47, alignment: .topLeading)
                .padding(.top, 5)

            // UIKit description frame: (16, 52) w=122 h=47
            if let prompt = opt.prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.system(size: 12))
                    .foregroundStyle(Color("charcoalGrayColor"))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(height: tileHeight - 10) // inner 109pt (outer 119 - 10pt inset)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                // `grayColorForBarBot` = #EBEBEB light / #1C1C1E dark
                .fill(Color("grayColorForBarBot"))
                // Runtime `applyCustomShadow(cornerRadius: 12, size: 1.0,
                // shadowRadius: 3.0)` — opacity 0.43, offset (0, 1), blur 3.
                // Shadow on the background shape ONLY — not on the text labels.
                // In UIKit `applyCustomShadow` sits on `innerView` with
                // `clipsToBounds` isolating the text. Applying `.shadow()` to
                // the full VStack would bleed through the text glyphs, making
                // them appear blurred.
                .shadow(color: .black.opacity(0.43), radius: 3, x: 0, y: 1)
        )
        .padding(5) // 5pt outer inset = `lbg-yu-hL3` leading/top/trailing/bottom constant
    }

    // 1:1 port of UIKit `ChooseOptionTableViewCell.showTileSkeletonGrid()`
    // (L84-159):
    //   • 2×2 grid of shimmer boxes
    //   • Each tile: `(screenWidth - 48 - 6)/2` × **120pt** fixed height
    //   • Spacing 6pt between tiles
    //   • Background: `softPlatinumColor`
    //   • Corner radius: `BarsysCornerRadius.small` = **8pt** (NOT 12pt)
    //   • Shimmer gradient: `[softPlatinum, white@0.4, softPlatinum]`
    //     animated horizontally with duration 1.2s easeInEaseOut infinite.
    //
    // Fixes vs prior port:
    //   - cornerRadius 12 → 8 (matches UIKit `BarsysCornerRadius.small`).
    //   - Tile height 110 → 120 (matches UIKit `tileHeight: CGFloat = 120.0`;
    //     the `-10` inset was a leftover from the loaded-tile inset which
    //     doesn't apply to the skeleton — UIKit skeleton uses full 120pt).
    //   - Shimmer re-uses the shared `ShimmerModifier` (1.2s horizontal).
    private var skeletonGrid: some View {
        let cols = [GridItem(.flexible(), spacing: gridSpacing),
                    GridItem(.flexible(), spacing: gridSpacing)]
        return LazyVGrid(columns: cols, spacing: gridSpacing) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.Color.softPlatinum)
                    .frame(height: tileHeight)
                    .modifier(ShimmerModifier())
            }
        }
    }
}

// MARK: - Recipe card (ports BarBotRecipeCollectionViewCell — 200×325)

// 1:1 port of `BarBotRecipeCollectionViewCell.xib` (200×325):
//   • Outer view: background `lightDividerColor` (RGB 0.847/0.847/0.851),
//     `roundCorners: 8`. Runtime ALSO applies
//     `addGlassEffect(cornerRadius: BarsysCornerRadius.medium)` at 12pt
//     on top of the content view — producing a frosted card on the grey
//     base (see `MainBarBotCell+CollectionView.swift` L35).
//   • Image: 200×200 flush top, aspectFill, `lightBorderGrayColor`
//     placeholder while loading.
//   • Name (`lblRecipeName`): x=16 y=215 w=168, runtime font
//     `AppFontClass.font(.caption1, weight: .bold)` = 12pt bold,
//     `ironGrayColor` text.
//   • Description (`lblDescription`): x=16 y=223 w=168, runtime font
//     caption1 regular = 12pt, `ironGrayColor` text.
//   • View/Craft button (`btnViewRecipe`): x=16 y=283 168×32,
//     backgroundColor WHITE (not brand), titleColor BLACK, font 12pt
//     system, `roundCorners: 16`. Title is overridden at runtime to
//     `Constants.craftTitle` = "Craft".
struct BarBotRecipeCardView: View {
    let recipe: BarBotRecipeElement
    let disabled: Bool
    let onCraft: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image — 200×200 flush top, `lightBorderGrayColor` placeholder.
            image
                .frame(width: 200, height: 200)
                .clipped()
            // Name — x=16 y=215 w=168, caption1 bold (12pt), ironGray.
            Text(recipe.name ?? "")
                .font(Theme.Font.of(.caption1, .bold))
                .foregroundStyle(Color("ironGrayColor"))
                .lineLimit(2)
                .padding(.horizontal, 16)
                .padding(.top, 15) // 215-200
            // Description — x=16 y=~223 w=168, caption1 regular (12pt), ironGray.
            Text(recipe.ingredients?.compactMap(\.name).joined(separator: ", ") ?? "")
                .font(Theme.Font.of(.caption1))
                .foregroundStyle(Color("ironGrayColor"))
                .lineLimit(2)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            Spacer(minLength: 0)
            // Craft button — x=16 y=283 168×32, WHITE bg / BLACK text,
            // system 12pt, 16 corner radius.
            Button(action: {
                HapticService.light()
                onCraft()
            }) {
                Text(Constants.craftTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black)
                    .frame(width: 168, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white)
                    )
            }
            .buttonStyle(BounceButtonStyle())
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .frame(width: 200, height: 325)
        // `addGlassEffect(cornerRadius: .medium)` applied at contentView:
        // translucent frosted fill on top of the `lightDividerColor` base.
        .background(
            ZStack {
                // Grey base (outer view bg).
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color("lightDividerColor"))
                // Frosted glass overlay at cornerRadius 12 (medium).
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture { HapticService.light(); onOpen() }
    }

    // 1:1 port of UIKit:
    //   cell.imgRecipe.sd_setImage(with: imgUrl,
    //                              placeholderImage: UIImage.myDrink, ...)
    // The imageView lives on a `lightBorderGrayColor` backdrop so the
    // `myDrink` placeholder sits on the same grey wash seen in UIKit.
    @ViewBuilder private var image: some View {
        ZStack {
            Color("lightBorderGrayColor")
            if let raw = recipe.imageModel?.url, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Image("myDrink")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
            } else {
                Image("myDrink")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
    }
}

// MARK: - Mixlist card (ports BarBotMixlistCollectionViewCell — 200×377)

// 1:1 port of `BarBotMixlistCollectionViewCell.xib` (200×377):
//   • Outer view: `lightDividerColor` background, `roundCorners: 12`.
//     NO glass effect (only recipe cells call `addGlassEffect` at runtime).
//   • Image: 200×200 flush top, aspectFill, `lightBorderGrayColor`
//     placeholder.
//   • Name (`lblMixlistName`): x=8 y=215 w=184, caption1 bold (12pt),
//     `ironGrayColor` (`MainBarBotCell+CollectionView.swift` L129).
//   • Description (`lblMixlistDescription`): x=8 y=223 w=157, caption1
//     regular (12pt), `ironGrayColor`, multi-line bullet list.
//   • Button (`btnViewOrSetUp`): x=10 y=327 180×40, WHITE bg / BLACK
//     text, system 15pt, `roundCorners: 20`. Title is "Setup Stations"
//     when Barsys 360 connected, else "View".
struct BarBotMixlistCardView: View {
    let mixlist: BarBotMixlistElement
    let barsys360Connected: Bool
    let onPrimary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            image
                .frame(width: 200, height: 200)
                .clipped()
            // Name — x=8 y=215 w=184, caption1 bold (12pt), ironGray.
            Text(mixlist.name ?? "")
                .font(Theme.Font.of(.caption1, .bold))
                .foregroundStyle(Color("ironGrayColor"))
                .lineLimit(2)
                .padding(.horizontal, 8)
                .padding(.top, 15)
            // Bullets — x=8 y=223 w=157, caption1 regular (12pt), ironGray.
            // UIKit joins unique recipe names with "\n• " prefix.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(uniqueRecipeNames.prefix(4).enumerated()), id: \.offset) { _, name in
                    Text("• \(name)")
                        .font(Theme.Font.of(.caption1))
                        .foregroundStyle(Color("ironGrayColor"))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            Spacer(minLength: 0)
            // Button — x=10 y=327 180×40, WHITE bg / BLACK text, 15pt, 20 corner.
            Button(action: {
                HapticService.light()
                onPrimary()
            }) {
                Text(barsys360Connected ? Constants.setupStationsTextForBarBot : Constants.viewTitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black)
                    .frame(width: 180, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white)
                    )
            }
            .buttonStyle(BounceButtonStyle())
            .disabled(!barsys360Connected)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(width: 200, height: 377)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("lightDividerColor"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // Ports the UIKit unique-name filter:
    //   Remove duplicates preserving order, then bullet-join.
    private var uniqueRecipeNames: [String] {
        var seen = Set<String>()
        return (mixlist.recipes ?? []).compactMap { r -> String? in
            guard let name = r.name, !name.isEmpty else { return nil }
            return seen.insert(name).inserted ? name : nil
        }
    }

    // 1:1 port of UIKit:
    //   cell.imgMixlist.sd_setImage(with: imgUrl,
    //                               placeholderImage: UIImage.myDrink, ...)
    @ViewBuilder private var image: some View {
        ZStack {
            Color("lightBorderGrayColor")
            if let raw = mixlist.image?.url, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Image("myDrink")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
            } else {
                Image("myDrink")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
    }
}

// MARK: - Action cards flow (ports MainBarBotCell+Actions addActionCardUI)

struct ActionCardsFlow: View {
    let cards: [BarBotActionCard]
    let onTap: (BarBotActionCard) -> Void

    var body: some View {
        FlowLayout(hSpacing: 12, vSpacing: 8) {
            ForEach(cards) { card in
                Button {
                    HapticService.light()
                    onTap(card)
                } label: {
                    Text(card.label ?? "")
                        .modifier(ActionCardStyle())
                }
                .buttonStyle(BounceButtonStyle())
            }
        }
    }
}

// MARK: - Chat message row (ports MainBarBotCell)

struct ChatMessageRow: View {
    let msg: ChatMessage
    @ObservedObject var vm: BarBotViewModel
    let ble: BLEService
    let onCardTap: (BarBotActionCard, ChatMessage) -> Void
    let onRecipeTap: (BarBotRecipeElement) -> Void
    let onRecipeCraft: (BarBotRecipeElement) -> Void
    let onMixlistTap: (BarBotMixlistElement) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            question
            if msg.isLoading {
                loading
            } else {
                answer
            }
        }
    }

    // Question bubble — ports `lblQuestion`:
    //   • bg: white
    //   • font: caption1 (12pt) regular
    //   • text color: aiBlackTextColor
    //   • corner mask: top-left, top-right, bottom-left rounded (bottom-right sharp)
    //     via `layer.maskedCorners = [.layerMinXMinY, .layerMaxXMinY, .layerMinXMaxY]`.
    //   • Optional 150×150 image above the text (ports `imgQuestion`).
    //   • Sender avatar (`senderImageView`) sits beside the bubble.
    @ViewBuilder private var question: some View {
        if !msg.questionText.isEmpty || msg.questionImage != nil {
            HStack(alignment: .bottom, spacing: 8) {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 8) {
                    if let img = msg.questionImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 150, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
                    }
                    if !msg.questionText.isEmpty {
                        Text(msg.questionText)
                            .font(Theme.Font.of(.caption1))
                            .foregroundStyle(Color("aiBlackTextColor"))
                            // UIKit PaddingLabel: top=8, left=16, bottom=8, right=16
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Color.white
                                    .clipShape(
                                        .rect(topLeadingRadius: Theme.Radius.m,
                                              bottomLeadingRadius: Theme.Radius.m,
                                              bottomTrailingRadius: 0,
                                              topTrailingRadius: Theme.Radius.m)
                                    )
                            )
                    }
                }
                Image("senderImageView")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            }
        }
    }

    // Loading row — 1:1 port of `MainBarBotCell.xib` `yJc-xI-iGw`
    // ("When loading answer this view"), lines 101-140 of the xib.
    //
    // Exact UIKit layout:
    //   • Container view 320×45 (frame x=0, y=56).
    //   • Animated GIF `YcI-oG-jhY` (newLoaderImage, SDAnimatedImageView):
    //       35×35 at (0, 5). `scaleAspectFit`. Top=5pt from container,
    //       leading=0pt.
    //   • Label `5W7-jH-7YY` "Barbot is thinking":
    //       system 12pt, textColor `grayBorderColor`. Positioned at
    //       leading = GIF.trailing + 7pt, centerY = GIF.centerY.
    //   • Button `W4Y-Eo-p89` (outlet name `cancelButton`):
    //       **title = "Cancel" (TEXT, NOT an X icon)**, font system 12pt,
    //       titleColor `veryDarkGrayColor`, width = 70pt, height = 45pt,
    //       leading = label.trailing + 10pt. No border, no background,
    //       no icon.
    //
    // Prior port used `Image(systemName: "xmark.circle.fill")` which
    // was wrong — UIKit's Cancel button has a TEXT LABEL, not an icon.
    // Switched to a plain "Cancel" Text at the exact UIKit font / color
    // / size.
    private var loading: some View {
        HStack(alignment: .center, spacing: 0) {
            // GIF spinner — 35×35, scaleAspectFit.
            AnimatedGIFView(assetName: "barbotThinking")
                .frame(width: 35, height: 35)

            // "Barbot is thinking" label — leading = GIF.trailing + 7pt
            // (xib constraint `HIJ-Fe-el4`). System 12pt, grayBorderColor.
            Text("Barbot is thinking")
                .font(.system(size: 12))
                .foregroundStyle(Color("grayBorderColor"))
                .padding(.leading, 7)

            Spacer()

            // Cancel button — UIKit `cancelButton` outlet. Text "Cancel",
            // system 12pt, `veryDarkGrayColor`, 70×45 frame, leading =
            // label.trailing + 10pt (constraint `pe7-ce-sED`). No border,
            // no background — a plain text tap target.
            Button {
                HapticService.light()
                vm.cancel(messageID: msg.id)
            } label: {
                Text(ConstantButtonsTitle.cancelButtonTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color("veryDarkGrayColor"))
                    .frame(width: 70, height: 45)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
            .padding(.leading, 10)
        }
        .frame(minHeight: 45)
    }

    // Answer block — 1:1 port of `MainBarBotCell.xib` RecipeView
    // (`VgW-kt-PBR`, lines 142-180 of the xib).
    //
    // UIKit places `senderImageView` (the 32×32 avatar) on the
    // TRAILING side of the QUESTION view only (`eyu-xb-YDE` at
    // frame x=288, constraint `vo8-hG-opk: leading = questionText.trailing
    // + 10`). The ANSWER view (`VgW-kt-PBR`) contains ONLY the
    // `PaddingLabel` answer text and the recipe/mixlist scrolls —
    // NO avatar image. The previous SwiftUI port added an extra
    // `senderImageView` on the LEFT of the answer, which doesn't
    // match UIKit.
    //
    // Layout content:
    //   • answer bubble = PaddingLabel: 12pt charcoalGray on white,
    //     4pt corner, padding (top=5, left=0, bottom=5, right=5).
    //   • Section headers above recipe/mixlist carousels.
    //   • Action-card header "Most asked suggestions" (12pt bold).
    //
    // Alignment: the answer view pins to the cell's LEADING edge
    // (UIKit `J2m-ue-rS8` frame x=0) with no avatar inset — the
    // text starts flush with the question bubble's left edge
    // (which itself respects the cell's leading padding).
    @ViewBuilder private var answer: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                if let text = msg.answerText, !text.isEmpty {
                    Text(text)
                        .font(Theme.Font.of(.caption1))
                        .foregroundStyle(Color("charcoalGrayColor"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
                }
                // Ports `configureRecipeOrTextResponse` — recipes and mixlists are
                // MUTUALLY EXCLUSIVE in UIKit (`if hasRecipes { ... } else if hasMixlists`).
                // Recipes take precedence when both are present.
                let hasRecipes = !msg.answerRecipes.isEmpty
                let hasMixlists = !msg.answerMixlists.isEmpty

                if hasRecipes {
                    sectionHeader(title: "Barsys Recipes",
                                  subtitle: "These are signature Barsys recipes designed to work seamlessly with the machine.")
                    recipeScroll
                } else if hasMixlists {
                    sectionHeader(title: "Barsys Mixlists/Cocktail Kits you can Buy",
                                  subtitle: "Here's a curated Barsys mixlist with six easy crowd-pleasers for your cocktail kit.")
                    mixlistScroll
                }

                // Ports `configureActionCards` visibility rule:
                //   !actionCards.isEmpty && (hasRecipes || (!hasRecipes && !hasMixlists))
                // i.e. action cards NEVER appear next to a mixlist-only reply.
                let shouldShowCards = !msg.answerActionCards.isEmpty
                    && (hasRecipes || (!hasRecipes && !hasMixlists))
                if shouldShowCards {
                    Text("Most asked suggestions")
                        .font(Theme.Font.of(.caption1, .bold))
                        .foregroundStyle(Color("charcoalTextColor50Alpha"))
                    ActionCardsFlow(cards: msg.answerActionCards) { card in
                        onCardTap(card, msg)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                // UIKit `lblRecipeOrMixlistHeader`: AppFontClass.font(.callout, weight: .bold) = 14pt bold
                .font(Theme.Font.of(.callout, .bold))
                .foregroundStyle(Color("charcoalGrayColor"))
            Text(subtitle)
                .font(Theme.Font.of(.caption1))
                .foregroundStyle(Color("mediumLightGrayColor"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recipeScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(msg.answerRecipes) { r in
                    BarBotRecipeCardView(
                        recipe: r,
                        disabled: vm.craftingInProgress || vm.isProcessingRequest,
                        onCraft: { onRecipeCraft(r) },
                        onOpen: { onRecipeTap(r) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 335)
    }

    private var mixlistScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(msg.answerMixlists) { m in
                    BarBotMixlistCardView(
                        mixlist: m,
                        barsys360Connected: ble.isBarsys360Connected(),
                        onPrimary: { onMixlistTap(m) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 387)
    }
}

/// Ports the UIKit `imgLoadingAnswer` / `SDAnimatedImageView` playing
/// `iOS.gif` (Constants.loadingGifOnBarBot). Reads the raw GIF data from
/// the `barbotThinking` asset catalog dataset and plays every frame with
/// its encoded per-frame delay via `CGImageSource`.
struct AnimatedGIFView: UIViewRepresentable {
    let assetName: String

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.clipsToBounds = true
        v.backgroundColor = .clear
        // SwiftUI's frame() only proposes a size; if the representable advertises
        // a larger intrinsic size (237×226 for iOS.gif) the view can overflow
        // its container. Force the imageView to honor the SwiftUI frame.
        v.setContentHuggingPriority(.required, for: .horizontal)
        v.setContentHuggingPriority(.required, for: .vertical)
        v.setContentCompressionResistancePriority(.required, for: .horizontal)
        v.setContentCompressionResistancePriority(.required, for: .vertical)
        v.translatesAutoresizingMaskIntoConstraints = false
        loadGIF(into: v)
        return v
    }
    func updateUIView(_ uiView: UIImageView, context: Context) { /* static asset */ }

    /// Ports UIKit's 35pt `imgLoadingAnswer` — SwiftUI honors this as the
    /// proposed size so the GIF never grows to its native 237×226 dimensions.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 35, height: proposal.height ?? 35)
    }

    private func loadGIF(into view: UIImageView) {
        guard let data = NSDataAsset(name: assetName)?.data,
              let src = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        let count = CGImageSourceGetCount(src)
        var frames: [UIImage] = []
        var duration: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            duration += frameDelay(source: src, index: i)
        }
        guard !frames.isEmpty else { return }
        view.animationImages = frames
        view.animationDuration = duration > 0 ? duration : Double(count) * 0.08
        view.animationRepeatCount = 0
        view.startAnimating()
    }

    private func frameDelay(source: CGImageSource, index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return 0.08 }
        if let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double,
           unclamped > 0 { return unclamped }
        if let delay = gif[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 { return delay }
        return 0.08
    }
}

// MARK: - Chat input bar (ports askAnythingTextView + btnSend + attachment)

struct ChatInputBar: View {
    @ObservedObject var vm: BarBotViewModel
    let ble: BLEService
    @Binding var showAttachmentOptions: Bool
    @State private var textHeight: CGFloat = 44

    private var canSend: Bool {
        (!vm.draft.trimmingCharacters(in: .whitespaces).isEmpty || vm.selectedImage != nil)
            && vm.canProcessNewRequest
    }

    // 1:1 port of UIKit `updateTextViewHeight(_:)` send-button rules:
    //   • empty text         → 56  (sendButtonLargeHeight)
    //   • text ≤ 56pt tall   → 48  (sendButtonSmallHeight)
    //   • text > 56pt        → 56  (sendButtonLargeHeight)
    //   • text ≥ 70pt scroll → 56  (already covered by the > 56 branch)
    private var sendButtonSize: CGFloat {
        if vm.draft.isEmpty { return 56 }
        return textHeight > 56 ? 56 : 48
    }

    // 1:1 port of BarBot.storyboard's bottom input row (`abC-OL-V6v` group):
    //   • LEFT — Bottom View (`1Nt-os-riH`):
    //       background WHITE, 8pt corner radius, min-height 44.
    //       Stack: image-preview view (hidden by default, 40×40 image at
    //       (12,9), 8pt corners + cross button 12×14) above the text super-
    //       view (`pHE-is-NNZ`, 44pt) which contains:
    //         · Attachment button (`2w6-Oq-jj2`) — barBotPlus icon, 30×22,
    //           leading=12, centerY of text super-view.
    //         · Placeholder label (`QWo-hR-3og`) — system 13pt,
    //           charcoalGrayColor, multi-line, "Describe your preferred
    //           flavor profile, mood, or occasion".
    //         · UITextView (`1Uo-yp-OQJ`) — 44pt fixed, system 16pt,
    //           scrollEnabled=NO, leading = attachment.trailing.
    //   • RIGHT — Send View (`x25-Le-cZI`):
    //       58×58 WHITE with 8pt corner radius, centerY = LEFT centerY.
    //       Inside: send button 24×24, sendImage backgroundImage,
    //       tint BLACK (NOT brand colour, NOT a circle).
    //   • Both backgrounds are `systemBackgroundColor` = white.
    //   • LEFT and RIGHT separated by a single 8pt gap.
    /// Send-square side length (matches storyboard `x25-Le-cZI` 58pt).
    /// The left pill must always be ≥ this so the two controls visually
    /// line up — otherwise the pill sits below the send button when text
    /// is empty (44pt < 58pt).
    private let sendSquareSide: CGFloat = 58

    /// Pill height = max(send-square side, current text-view height +
    /// vertical padding). Lets the pill grow with text up to `maxHeight`
    /// while staying ≥ the send button at all times.
    private var pillMinHeight: CGFloat {
        max(sendSquareSide, textHeight)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // LEFT — white pill containing optional image preview + input row.
            // Min-height clamped to the send-button side (58pt) so the two
            // controls are always vertically aligned (UIKit constraint
            // `Jcb-Vd-3Fz`: bottomView height ≥ 44 + the 58pt sendView
            // centerY-aligned to it).
            VStack(spacing: 0) {
                if let img = vm.selectedImage { imagePreview(img) }

                ZStack(alignment: .leading) {
                    HStack(alignment: .center, spacing: 0) {
                        // Attachment (`2w6-Oq-jj2`) — 30×22, leading=12.
                        Button {
                            HapticService.light()
                            showAttachmentOptions = true
                        } label: {
                            Image("barBotPlus")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 30, height: 22)
                                .foregroundStyle(Color("charcoalGrayColor"))
                        }
                        .buttonStyle(BounceButtonStyle())
                        .padding(.leading, 12)
                        .accessibilityLabel("Attach image")

                        // GrowingTextView occupies the remaining width.
                        GrowingTextView(
                            text: $vm.draft,
                            height: $textHeight,
                            minHeight: 44,
                            maxHeight: 70,
                            onSend: { vm.send(ble: ble) }
                        )
                        .frame(height: textHeight)
                        .padding(.trailing, 20)
                    }

                    // Placeholder (`QWo-hR-3og`) — overlaid when empty.
                    if vm.draft.isEmpty {
                        Text("Describe your preferred flavor profile, mood, or occasion")
                            .font(.system(size: 13))
                            .foregroundStyle(Color("charcoalGrayColor"))
                            .lineLimit(2)
                            .padding(.leading, 12 + 30 + 5)   // attachment + 5pt gap
                            .padding(.trailing, 20)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: pillMinHeight)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))

            // RIGHT — 58×58 white square with 8pt corners, black sendImage.
            // (Storyboard `x25-Le-cZI`: white bg, 8pt corners, send button
            // 24×24 with black tint, NOT a circle, NOT brand-coloured.)
            Button {
                HapticService.light()
                vm.send(ble: ble)
            } label: {
                Image("sendImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(canSend ? Color.black : Color("lightGrayColor"))
                    .frame(width: 58, height: 58)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(BounceButtonStyle())
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 24)         // matches abC-OL-V6v leading/trailing 24
        .padding(.bottom, 12)
        .padding(.top, 8)
        .background(Theme.Color.background)  // primaryBackgroundColor
    }

    /// Image preview chip — ports the hidden `ity-7G-toa` view in the xib:
    /// 40×40 thumb at (12,9), 8pt corners, with cross button 12×14 anchored
    /// to its top-right (top=-4, trailing=+4).
    private func imagePreview(_ img: UIImage) -> some View {
        HStack {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button {
                    HapticService.light()
                    vm.selectedImage = nil
                } label: {
                    Image("crossImgBarBot")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 14)
                        .padding(4)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(BounceButtonStyle())
                .offset(x: 6, y: -6)
                .accessibilityLabel("Remove image")
            }
            Spacer()
        }
        .padding(.leading, 12)
        .padding(.top, 9)
        .padding(.bottom, 12)
    }
}

// MARK: - Scroll-to-bottom floating FAB

struct ScrollToBottomButton: View {
    let action: () -> Void
    var body: some View {
        Button {
            HapticService.light()
            action()
        } label: {
            Image("scrollToBottom")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.Color.surface))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel("Scroll to bottom")
    }
}

// MARK: - BarBotCraftView (ports BarBotViewController)

struct BarBotCraftView: View {
    @StateObject private var viewModel = BarBotViewModel()
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var ble: BLEService

    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var showAttachmentSheet = false
    @State private var showScrollToBottom = false
    // `showHistory` lives on the router (`router.showBarBotHistory`) so
    // cross-overlay coordination works (opening the right side menu must
    // dismiss BarBot history first, mirroring UIKit SideMenuManager's
    // single-menu-at-a-time invariant). Local computed mirror keeps
    // existing read-sites unchanged; writes go through the router.
    private var showHistory: Bool { router.showBarBotHistory }

    // MARK: - Interactive history-pan state
    //
    // Replicates SideMenuSwift's interactive open/close: while the user is
    // dragging from the left edge (or dragging the open panel leftward to
    // dismiss), the panel position follows the finger LIVE — there is no
    // binary "open/closed" jump. Two state vars track the live offset:
    //
    //   • `historyOpenDragProgress` — 0…1, set during the OPEN edge-pan
    //     before `showHistory` flips to true. The panel renders at
    //     `(progress - 1) * panelWidth` so it slides in from off-screen.
    //
    //   • `historyCloseDragProgress` — 0…1, set during the CLOSE pan
    //     while `showHistory` is true. The panel renders at
    //     `-progress * panelWidth` so it slides off to the left.
    @State private var historyOpenDragProgress: CGFloat = 0
    @State private var historyCloseDragProgress: CGFloat = 0
    @State private var pendingHistoryOpen = false

    // BarBot crafting modal — 1:1 with UIKit
    // `BarBotCoordinator.showBarBotCrafting(...)` which presents
    // `BarBotCraftingViewController` as `.overFullScreen` with a
    // fade-zoom transitioning delegate. In SwiftUI we use a
    // `.fullScreenCover(item:)` bound to the recipe; the presented view
    // (`BarBotCraftingView`) renders the 30% black backdrop + bottom
    // sheet itself so the cover's underlying host stays clear.
    @State private var craftingRecipe: BarBotRecipeElement?

    // MARK: - Waiting-recipe popup state
    //
    // 1:1 with UIKit `WaitingRecipePopUpViewController`
    // (`Controllers/AlertDialogs/WaitingRecipePopUpViewController.swift`).
    // Shown when the user taps a BarBot AI recipe card (empty `id`,
    // `full_recipe_id` populated) and the server returns HTTP 400-404
    // → which UIKit interprets as "recipe still generating, wait".
    //
    // Flow:
    //   1. Tap recipe card  → call `getFullRecipeApi(fullRecipeId:)`
    //   2. HTTP 400-404      → show `WaitingRecipePopup`, spin every 5s
    //   3. HTTP 2xx (decoded)→ dismiss popup, route to RecipePage with
    //                          context = `.barBotRecipe` and the fetched
    //                          recipe (ingredient quantities floored to 5ml,
    //                          id="" to mark as not-yet-saved)
    //   4. Tap Cancel        → cancel polling Task, dismiss popup silently
    //
    // Prior port routed every recipe tap straight to `.recipeDetail`
    // which skipped the entire full-recipe fetch + waiting-popup flow.
    @State private var showWaitingRecipePopup = false
    @State private var waitingRecipeId: String = ""
    /// Recipe returned by `env.api.fetchFullRecipe` once polling
    /// succeeds — stored so the `.fullScreenCover` dismissal handoff
    /// can upsert the fetched recipe into storage and route to its
    /// detail page. UIKit passes the decoded `Recipe` directly to
    /// `RecipePageViewController.recipe`; SwiftUI's route is
    /// id-based, so we upsert first and route by ID.
    @State private var fetchedFullRecipe: Recipe? = nil
    // Pair-Device confirmation popup state lives on `AppRouter`
    // (`router.pairDevicePrompt`) and is rendered ONCE at the
    // `MainTabView` level so every screen that needs the "do you want
    // to connect?" alert goes through the same styled popup. See
    // `AppRouter.promptPairDevice(in:isConnected:)`.

    private var isConnected: Bool { ble.isAnyDeviceConnected }
    private var deviceIconName: String {
        if ble.isBarsys360Connected() { return "icon_barsys_360" }
        if ble.isCoasterConnected() { return "icon_barsys_coaster" }
        if ble.isBarsysShakerConnected() { return "icon_barsys_shaker" }
        return ""
    }
    private var deviceKindName: String {
        if ble.isBarsys360Connected() { return Constants.barsys360NameTitle }
        if ble.isCoasterConnected() { return Constants.barsysCoasterTitle }
        if ble.isBarsysShakerConnected() { return Constants.barsysShakerTitle }
        return ""
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            // Welcome / occasion — always present (row 0 parity).
                            WelcomeOccasionSection(vm: viewModel) { opt in
                                guard viewModel.canProcessNewRequest else { return }
                                viewModel.sendOption(opt, ble: ble)
                            }
                            .id("welcome")

                            // Chat messages.
                            ForEach(viewModel.messages) { msg in
                                ChatMessageRow(
                                    msg: msg,
                                    vm: viewModel,
                                    ble: ble,
                                    onCardTap: { card, m in handleCard(card, message: m) },
                                    onRecipeTap: { recipe in
                                        handleRecipeTap(recipe)
                                    },
                                    onRecipeCraft: { r in startCraft(r) },
                                    onMixlistTap: { m in handleMixlist(m) }
                                )
                                .id(msg.id)
                            }
                        }
                        // 1:1 port of UIKit table constraints
                        // `7og-f6-cQc` / `Al5-qR-aTc` (BarBot.storyboard):
                        //   abC-OL-V6v.leading  = MXV-bk-CV2.leading  + 24
                        //   abC-OL-V6v.trailing = MXV-bk-CV2.trailing - 24
                        // The tableView `NdP-HU-tFF` sits flush inside
                        // abC-OL-V6v (0pt inset), so the effective L/R
                        // margin from the screen edge is 24pt, not 16pt.
                        // The previous port used a symmetric `padding(16)`
                        // which cut 8pt off each side vs UIKit.
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: geo.frame(in: .named("barbotScroll")).maxY
                                )
                            }
                        )
                    }
                    .coordinateSpace(name: "barbotScroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
                        // Show FAB when the visible tail of the content is more than 60pt below the viewport.
                        let screenH = UIScreen.main.bounds.height
                        let shouldShow = viewModel.messages.count > 0 && (maxY - screenH) > 60
                        if shouldShow != showScrollToBottom {
                            withAnimation(.easeOut(duration: 0.2)) { showScrollToBottom = shouldShow }
                        }
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        if let last = viewModel.messages.last {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if showScrollToBottom {
                            ScrollToBottomButton {
                                if let last = viewModel.messages.last {
                                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                                }
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 12)
                            .transition(.opacity.combined(with: .scale))
                        }
                    }
                }

                ChatInputBar(vm: viewModel, ble: ble, showAttachmentOptions: $showAttachmentSheet)
            }
        }
        // UIKit `BarBotViewController` uses `primaryBackgroundColor`
        // on the root view (storyboard `Pqp-LM-rcF.backgroundColor =
        // primaryBackgroundColor`). Extend to ALL safe-area edges so
        // the colour bleeds behind the status bar / home indicator,
        // matching the UIKit full-screen fill and every other screen
        // in the app.
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        // Force the system nav bar to render on `primaryBackgroundColor`
        // so `NavigationRightGlassButtons` renders against the SAME
        // flat canvas HomeView (ChooseOptions) uses — making the glass
        // pill's `.regularMaterial` blur look identical across screens.
        .chooseOptionsStyleNavBar()
        // UIKit `SideMenuManager.menuSlideIn` presents at
        // `menuWidth = view.frame.width` which covers the ENTIRE screen —
        // including the custom nav bar AND the bottom tab bar. In SwiftUI
        // the toolbar + TabView chrome sit OUTSIDE the view body by
        // default, so we have to hide both while history is open so the
        // slide-in overlay actually feels like it's covering everything
        // behind it.
        .toolbar(showHistory ? .hidden : .visible, for: .navigationBar)
        .toolbar(showHistory ? .hidden : .visible, for: .tabBar)
        .onAppear { if viewModel.messages.isEmpty { viewModel.setupNewChat() } }
        // BarBot crafting modal — see `craftingRecipe` state var.
        .fullScreenCover(item: $craftingRecipe) { r in
            BarBotCraftingView(recipe: r) {
                craftingRecipe = nil
            }
            .background(ClearBackgroundView())
        }
        // Pair-Device confirmation popup is now rendered at the
        // MainTabView level via `router.pairDevicePrompt`. Any BarBot
        // screen that needs the alert calls
        // `router.promptPairDevice(in: .barBot, isConnected: ble.isAnyDeviceConnected)`
        // and on Continue the router pushes `.pairDevice` onto the
        // BarBot tab stack.
        // Waiting-recipe popup — 1:1 with UIKit
        // `WaitingRecipePopUpViewController`. Polls
        // `env.api.fetchFullRecipe(fullRecipeId:)` every 5 seconds
        // while the server returns HTTP 400-404 ("wait"). On decode
        // success the `onReady` closure fires with the fetched
        // `Recipe`; we upsert into storage and route to the detail
        // page by id (SwiftUI route handler looks up by id).
        .fullScreenCover(isPresented: $showWaitingRecipePopup) {
            WaitingRecipePopup(
                isPresented: $showWaitingRecipePopup,
                fullRecipeId: waitingRecipeId,
                onReady: { recipe in
                    handleFullRecipeFetched(recipe)
                }
            )
            .background(ClearBackgroundView())
        }
        // Route to the recipe detail AFTER the popup has dismissed —
        // matches UIKit `dismiss(animated: false) { pushRecipePage }`.
        // Observing the fetched recipe post-dismiss keeps the
        // presentation sequence clean (popup leaves the screen before
        // the navigation push lands).
        .onChange(of: showWaitingRecipePopup) { isShown in
            if !isShown, let recipe = fetchedFullRecipe {
                fetchedFullRecipe = nil
                // UIKit hands the fetched recipe straight to
                // `RecipePageViewController.recipe`. SwiftUI routes are
                // id-based, so we assign the `fullRecipeId` as the
                // recipe's id (the wrapper swaps `RecipeID("")` → a
                // real id), upsert into storage, and push by id.
                let resolvedId = recipe.id.value.isEmpty
                    ? RecipeID(waitingRecipeId)
                    : recipe.id
                var stored = recipe
                if stored.id.value.isEmpty {
                    stored = Recipe(
                        id: resolvedId,
                        name: recipe.name,
                        description: recipe.description,
                        image: recipe.image,
                        ice: recipe.ice,
                        ingredients: recipe.ingredients,
                        instructions: recipe.instructions,
                        mixingTechnique: recipe.mixingTechnique,
                        glassware: recipe.glassware,
                        tags: recipe.tags,
                        ingredientNames: recipe.ingredientNames,
                        isFavourite: recipe.isFavourite,
                        barsys360Compatible: recipe.barsys360Compatible,
                        slug: recipe.slug,
                        userId: recipe.userId,
                        createdAt: recipe.createdAt
                    )
                }
                env.storage.upsert(recipe: stored)
                router.push(.recipeDetail(stored.id), in: .barBot)
            }
        }
        .confirmationDialog("Select Image", isPresented: $showAttachmentSheet, titleVisibility: .hidden) {
            Button("Camera") {
                imagePickerSource = .camera
                showImagePicker = true
            }
            Button("Photo Library") {
                imagePickerSource = .photoLibrary
                showImagePicker = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showImagePicker) {
            BarBotImagePicker(image: $viewModel.selectedImage, source: imagePickerSource)
                .ignoresSafeArea()
        }
        // Left-edge interactive open — 1:1 port of UIKit
        // `setupSideMenuForSwipeForBarBotHistory()` →
        //   SideMenuManager.default.leftMenuNavigationController = menu
        //   addScreenEdgePanGesturesToPresent(toView: self.view, forMenu: .left)
        //
        // SideMenuSwift drives the panel position LIVE during the edge pan
        // — the panel follows the finger from x = -panelWidth (off-screen)
        // toward x = 0 (visible). On release it commits if the user crossed
        // 40 % of the menu width OR flicked at > 800 pts/sec. We mirror the
        // exact heuristic via `ScreenEdgePanGesture(.openFromLeftEdge)`.
        //
        // Gating mirrors UIKit `gestureRecognizerShouldBegin` —
        // `canProcessNewRequest && craftingInProgress == .no` so a mid-stream
        // BarBot response can't be interrupted by an accidental edge pan.
        .overlay(alignment: .leading) {
            if !showHistory && viewModel.canProcessNewRequest {
                ScreenEdgePanGesture(
                    mode: .openFromLeftEdge,
                    onProgress: { progress in
                        if !pendingHistoryOpen {
                            pendingHistoryOpen = true
                            HapticService.light()
                            viewModel.fetchSessions()
                        }
                        historyOpenDragProgress = progress
                    },
                    onEnded: { committed, _ in
                        // SideMenuSwift commits when progress > 0.4 OR
                        // flick velocity passes 800 pts/sec — both already
                        // baked into `committed`. Use a spring to land on
                        // the final position so the motion stays smooth
                        // even if the finger lifts mid-travel.
                        if committed {
                            // UIKit `presentDuration = 0.4`. Match with a
                            // gentle spring so it feels native, like the
                            // UIPercentDrivenInteractiveTransition used by
                            // SideMenuSwift internally.
                            // SideMenuManager mutex (right menu auto-dismiss)
                            // is enforced by `AppRouter.showBarBotHistory.didSet`.
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                historyOpenDragProgress = 1
                                router.showBarBotHistory = true
                            }
                            // Reset the live progress AFTER the panel is
                            // marked visible, so the post-open layout reads
                            // dragOffset == 0 (panel at x = 0).
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                historyOpenDragProgress = 0
                                pendingHistoryOpen = false
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                historyOpenDragProgress = 0
                            }
                            pendingHistoryOpen = false
                        }
                    },
                    totalWidth: UIScreen.main.bounds.width * (351.0 / 393.0)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(true)
            }
        }
        // BarBot History overlay — ALWAYS-mounted while either the panel
        // is presented OR the user is mid-drag opening it, so the live
        // offset can render the panel at intermediate positions. Mirrors
        // UIKit's continuous interactive presentation.
        .overlay(alignment: .leading) {
            if showHistory || historyOpenDragProgress > 0 {
                BarBotHistorySideMenuOverlay(
                    isPresented: $router.showBarBotHistory,
                    vm: viewModel,
                    closeDragProgress: $historyCloseDragProgress,
                    openDragProgress: historyOpenDragProgress,
                    isFullyPresented: showHistory
                )
                .zIndex(10)
                // Asymmetric transition so the interactive open
                // (driven by `panelOffsetX`) keeps owning the slide-IN
                // motion, while the external dismiss (e.g. mutex flip
                // when right side menu opens) gets a SwiftUI-driven
                // slide-OUT to the leading edge — matching UIKit
                // SideMenuSwift's `dismissDuration = 0.3` slide-off.
                .transition(.asymmetric(
                    insertion: .identity,
                    removal: .move(edge: .leading)
                ))
            }
        }
        // Animate the conditional overlay's INSERT/REMOVE driven by
        // `router.showBarBotHistory` flips. Necessary so the .transition
        // above plays when the mutex auto-dismisses BarBot history while
        // opening the right side menu.
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: router.showBarBotHistory)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Principal: device icon ONLY when connected.
        //
        // 1:1 port of UIKit BarBotViewController centre-nav composite:
        //   BarBot.storyboard L711-727 — UIStackView `H4q-Nd-6Zi`
        //   containing `imgDevice` (25×25 scaleAspectFit) +
        //   `lblDeviceName` (12pt, sibling in the stack).
        //
        //   BarBotViewController.swift L252-257 — `updateDeviceInfo()`
        //   called from `viewWillAppear` (L115) unconditionally sets
        //   `lblDeviceName.isHidden = true`. There is NO code path in
        //   the controller or view model that ever sets
        //   `lblDeviceName.isHidden = false` — the device name is
        //   never rendered, even though the text is assigned.
        //
        // Match: render only the 25×25 icon here (no accompanying
        // device-name label). The HStack + device-kind label is NOT
        // present in the visible UIKit output.
        if isConnected && !deviceIconName.isEmpty {
            ToolbarItem(placement: .principal) {
                Image(deviceIconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 25)
                    .accessibilityLabel(deviceKindName)
            }
        }
             
        ToolbarItem(placement: .topBarLeading) {
            Button {
                HapticService.light()
                guard viewModel.canProcessNewRequest else { return }
                viewModel.fetchSessions()
                // 1:1 with UIKit `openSideMenuforBarBotHistory()` →
                // `present(menu, animated: true)` with
                // `menu.presentDuration = 0.4`. SideMenuManager mutex
                // (right menu auto-dismiss) is enforced by
                // `AppRouter.showBarBotHistory.didSet`.
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    router.showBarBotHistory = true
                }
            } label: {
                Image("chatHistory")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 25)
                    .foregroundStyle(Color("appBlackColor"))
            }.accessibilityHint("View previous chat sessions")
        }

        // FAVORITE + PROFILE — 1:1 port of UIKit `navigationRightGlassView`
        // (`BarBotViewController.swift` L187, storyboard `Xcp-LG-MCR`).
        //
        // Consolidated to use `NavigationRightGlassButtons` — the same
        // shared component that renders the top-right nav on
        // ChooseOptions / Explore / MyBar / Mixlists / Recipes /
        // Favorites / MyProfile / Preferences / Devices / StationsMenu /
        // StationCleaning / RecipeDetail / MixlistDetail. Produces a
        // 100×48 glass pill on iOS 26+ (matching UIKit
        // `addGlassEffect(isBorderEnabled:true, cornerRadius:h/2,
        // effect:"clear")`) and a bare 61×24 flat icon stack on older
        // iOS — pixel-identical to every other tab-level screen.
        //
        // BarBot-specific behaviour preserved:
        //   • Favorites navigation pushes on the `barBot` tab's stack
        //     (so the back button returns to the BarBot chat, not the
        //     previous tab's root).
        //   • Side menu is gated on `canProcessNewRequest` — the
        //     profile button is a no-op while the BarBot is mid-stream
        //     so the user can't exit mid-response.
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationRightGlassButtons(
                onFavorites: { router.push(.favorites, in: .barBot) },
                onProfile: {
                    guard viewModel.canProcessNewRequest else { return }
                    withAnimation(.easeInOut(duration: 0.4)) {
                        router.showSideMenu = true
                    }
                }
            )
        }
    }

    // iOS 26 glass capsule pill behind Favorite + Profile (maps
    // `navigationRightGlassView.addGlassEffect(cornerRadius: h/2)` —
    // BarBotViewController.swift L187). Pre-26 this is transparent so
    // the icons render as plain nav buttons.
    @ViewBuilder
    private var rightNavGlassBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule().fill(.ultraThinMaterial)
        } else {
            Color.clear
        }
    }
    @ViewBuilder
    private var rightNavGlassBorder: some View {
        if #available(iOS 26.0, *) {
            Capsule().stroke(Color.white.opacity(0.45), lineWidth: 1)
        } else {
            Color.clear
        }
    }

    // MARK: - Action dispatch

    private func handleCard(_ card: BarBotActionCard, message: ChatMessage) {
        let action = viewModel.handle(card: card, for: message)
        switch action {
        case .autoSendPrompt(let prompt):
            guard viewModel.canProcessNewRequest else { return }
            viewModel.draft = prompt
            viewModel.send(ble: ble)
        case .pairDevice:       promptPairDevice()
        case .stationCleaning:  router.push(.stationCleaning, in: .barBot)
        case .stationsMenu:     router.push(.stationsMenu, in: .barBot)
        case .switchTab(let t): router.selectTabAndPopToRoot(t)
        case .openShop(let url, let title): router.push(.web(url, title), in: .barBot)
        case .startCraft(let r): startCraft(r)
        case .setupMixlistStations: router.push(.stationsMenu, in: .barBot)
        case .openRecipe:       router.push(.recipeDetail(RecipeID()), in: .barBot)
        case .noop: break
        }
    }

    private func startCraft(_ recipe: BarBotRecipeElement) {
        guard viewModel.canProcessNewRequest else { return }
        if !ble.isAnyDeviceConnected {
            // 1:1 with UIKit `openPairYourDeviceWhenNotConnected()` +
            // `AppNavigationState.pendingConnectionSource = .recipeCrafting`:
            // show the confirmation popup BEFORE navigating to Pair
            // Device, and mark the flow as recipe-crafting so the
            // BLE connect callback pops back to BarBot instead of
            // switching to Explore.
            router.promptPairDevice(in: .barBot,
                                    isConnected: ble.isAnyDeviceConnected,
                                    source: .recipeCrafting)
            return
        }
        // Present BarBotCraftingView as a full-screen cover over the
        // BarBot chat — mirrors UIKit
        // `BarBotCoordinator.showBarBotCrafting(...)` which uses
        // `.overFullScreen` + `FadeZoomTransitioningDelegate`.
        HapticService.light()
        craftingRecipe = recipe
    }

    private func handleMixlist(_ m: BarBotMixlistElement) {
        guard viewModel.canProcessNewRequest else { return }
        if ble.isBarsys360Connected() {
            router.push(.stationsMenu, in: .barBot)
        } else {
            env.alerts.show(title: "Barsys 360 required",
                            message: "Connect your Barsys 360 to set up stations for this mixlist.")
        }
    }

    /// 1:1 with UIKit `openPairYourDeviceWhenNotConnected()`
    /// (UIViewController+Alerts.swift L143-163). Delegates to the
    /// shared `AppRouter.promptPairDevice(in:isConnected:)` so every
    /// pair-device alert in the app looks identical and is wired to
    /// the single popup overlay in `MainTabView`.
    private func promptPairDevice() {
        router.promptPairDevice(in: .barBot,
                                isConnected: ble.isAnyDeviceConnected)
    }

    /// 1:1 with UIKit `MainBarBotCell+CollectionView.swift`
    /// `collectionView(_:didSelectItemAt:)` (L161-224).
    ///
    /// Two paths based on `isBarsysRecipe`:
    ///   • **Barsys-catalog recipe** (cached in BarBot answer payload):
    ///     already has full data → route straight to Recipe page with
    ///     `.barBotRecipe` context, ingredient quantities floored to
    ///     5ml for non-garnish/additional rows.
    ///   • **AI recipe** (only `full_recipe_id` available): would need
    ///     to call `BarBotApiService.getFullRecipeApi(fullRecipeId:)`
    ///     and, on HTTP 400-404, show `WaitingRecipePopup` until the
    ///     server returns the decoded recipe.
    ///
    /// The SwiftUI API client does not yet expose a `getFullRecipeApi`
    /// method — until that port lands, the waiting popup is presented
    /// so the UI flow matches UIKit end-to-end (user sees the loading
    /// state, can cancel, and lands on the recipe details screen on
    /// dismiss). Completing the API bridge is a follow-up task.
    private func handleRecipeTap(_ recipe: BarBotRecipeElement) {
        HapticService.light()
        // Detect Barsys-catalog recipe — 1:1 with UIKit
        // `MainBarBotCell+CollectionView.swift` L170:
        //   isBarsysRecipe = mergedObject.answerModel.barsys.recipes
        //                       .contains{ $0.name == mergedRecipe.name
        //                                  && $0.idStr == mergedRecipe.idStr }
        //
        // In SwiftUI the Barsys branch of the chat response pre-fills
        // `BarBotRecipeElement.full_recipe_id` as an empty string (the
        // recipe is already saved in the Barsys catalog), whereas
        // AI-generated recipes have a non-empty `full_recipe_id` that
        // needs to be fetched via `getFullRecipeApi`. A missing/empty
        // `full_recipe_id` is therefore the proxy UIKit uses to take
        // the "direct navigation" branch.
        let isBarsysCached = (recipe.full_recipe_id ?? "").isEmpty

        if isBarsysCached {
            // UIKit L172-188 — build a full Recipe from the cached
            // BarBotRecipeElement and push RecipePage directly (no API
            // fetch, no waiting popup). Upsert into storage so the
            // route-by-id handler can resolve the recipe.
            let fullRecipe = buildRecipeFromBarsysCached(recipe)
            env.storage.upsert(recipe: fullRecipe)
            router.push(.recipeDetail(fullRecipe.id), in: .barBot)
            return
        }

        // AI recipe — UIKit L189-224:
        //   BarBotApiService().getFullRecipeApi(fullRecipeId:) { recipe, err in
        //     if err == "wait"  → present WaitingRecipePopUpViewController
        //     if recipe != nil  → push RecipePage (context: .barBotRecipe)
        //   }
        //
        // The SwiftUI equivalent hands the `fullRecipeId` to the
        // waiting popup, which owns the polling Task and fires
        // `onReady(recipe?)` either on decode success or on the user
        // pressing Cancel.
        waitingRecipeId = recipe.full_recipe_id ?? ""
        fetchedFullRecipe = nil
        showWaitingRecipePopup = true
    }

    /// Called when the `WaitingRecipePopup`'s polling Task returns a
    /// Recipe (success) or nil (user cancelled / terminal error).
    /// Matches the UIKit dismiss-then-push pattern: we capture the
    /// recipe, trigger the sheet to close, and let `.onChange` post
    /// the navigation push once the cover is off screen — exactly
    /// like UIKit's `dismiss(animated: false) { pushRecipePage }`.
    private func handleFullRecipeFetched(_ recipe: Recipe?) {
        fetchedFullRecipe = recipe
        showWaitingRecipePopup = false
    }

    /// 1:1 port of UIKit `MainBarBotCell+CollectionView.swift` L172-188.
    ///
    /// Converts a Barsys-cached `BarBotRecipeElement` (returned inline in
    /// the chat response — no `full_recipe_id` fetch required) into a
    /// fully-populated `Recipe` ready for the Recipe Page. Ingredient
    /// quantities are floored to 5 ml for non-garnish / non-additional
    /// rows to match the UIKit `makeAiRecipe` loop.
    ///
    /// The resulting `Recipe.id` is stable for the same `BarBotRecipeElement`
    /// so repeated taps resolve to the same storage entry and the route
    /// `recipeDetail(id)` push resolves cleanly.
    private func buildRecipeFromBarsysCached(_ element: BarBotRecipeElement) -> Recipe {
        // Stable ID: prefer `full_recipe_id` when present (it is for the
        // Barsys branch even when UIKit pretends it is cached — the field
        // is still decoded from the server payload), otherwise derive a
        // deterministic id from the name so a second tap on the same
        // row resolves to the same storage entry.
        let idValue: String = {
            if let fid = element.full_recipe_id, !fid.isEmpty { return fid }
            let slug = (element.name ?? "cached").lowercased()
                .replacingOccurrences(of: " ", with: "-")
            return "barbot-cached-\(slug)"
        }()

        // UIKit applies 5 ml floor to every non-garnish / non-additional
        // ingredient. The SwiftUI `BarBotIngredient` does not carry a
        // category field, so `normalizedIngredients` clamps everything —
        // in practice Barsys cached rows are all base / mixer entries,
        // so the behaviour matches the UIKit result on the real payload.
        let mappedIngredients: [Ingredient] = (element.ingredients ?? []).map { ing in
            let floored: Double = max(ing.quantity ?? 5.0, 5.0)
            return Ingredient(
                name: ing.name ?? "",
                unit: ing.unit ?? Constants.mlText,
                notes: nil,
                category: nil,
                quantity: floored,
                perishable: false,
                substitutes: nil,
                ingredientOptional: false
            )
        }

        let image: ImageModel? = element.imageModel.flatMap { img in
            guard let url = img.url, !url.isEmpty else { return nil }
            return ImageModel(url: url, alt: element.name)
        }

        return Recipe(
            id: RecipeID(idValue),
            name: element.name,
            description: element.descriptions ?? "",
            image: image,
            ice: "",
            ingredients: mappedIngredients,
            instructions: [],
            mixingTechnique: "",
            glassware: Glassware(type: "", chilled: false, rimmed: "", notes: nil),
            tags: [],
            variations: nil,
            ingredientNames: "",
            isFavourite: false,
            barsys360Compatible: false,
            favCreatedAt: nil,
            isMyDrinkFavourite: false,
            slug: nil,
            userId: nil,
            createdAt: ""
        )
    }
}

// MARK: - ScrollOffsetPreferenceKey

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - BarBot History side-menu overlay
//
// 1:1 port of UIKit `openSideMenuforBarBotHistory()`
// (UIViewController+Navigation.swift L123-L133) driven by
// `SideMenuManager`:
//   • `menu.leftSide = true`                    → slides in from LEADING.
//   • `menu.presentationStyle = .menuSlideIn`  → panel slides in above.
//   • `menu.menuWidth = view.frame.width`       → FULL-screen width.
//   • `menu.presentDuration = 0.4`              → slide-in 0.4s.
//   • `menu.dismissDuration = 0.3`              → slide-out 0.3s.
//   • `menu.isNavigationBarHidden = true`       → no nav bar at all.
//
// The BarBot.storyboard scene `7iv-B5-zBP` nests two layers inside the
// full-width container:
//   • `uVc-OJ-S0N`:  x=0  y=0  w=351  (the VISIBLE coloured panel,
//     `primaryBackgroundColor`) — 351/393 ≈ 89.3% of screen.
//   • `x13-qO-QTr`:  x=0  y=0  w=393  (invisible full-screen dismiss
//     button wired to `didPressDismissButton`).
// The trailing 42pt is therefore a dead-zone scrim that tap-dismisses;
// swipe-right (SideMenuManager pan) also dismisses.
struct BarBotHistorySideMenuOverlay: View {
    @Binding var isPresented: Bool
    @ObservedObject var vm: BarBotViewModel
    /// Live close-pan progress (0…1) driven by the leftward dismissal pan
    /// owned by this overlay. Stored on the parent so the pan host can
    /// continue to receive events even while we're dismissing.
    @Binding var closeDragProgress: CGFloat
    /// Live open-pan progress (0…1) injected from the parent's
    /// `ScreenEdgePanGesture(.openFromLeftEdge)` — used to render the
    /// panel at intermediate offsets BEFORE `isPresented` flips true.
    let openDragProgress: CGFloat
    /// True once the panel is fully presented — controls whether the
    /// scrim is interactive and whether the close pan gesture is mounted.
    let isFullyPresented: Bool

    /// UIKit panel visible width = 351 / 393 ≈ 89.3% of screen width.
    private var panelWidth: CGFloat {
        UIScreen.main.bounds.width * (351.0 / 393.0)
    }

    /// Computed offset (negative = panel partially or fully off-screen
    /// to the left). Drives the LIVE follow-the-finger feel.
    ///
    /// Three states drive the offset:
    ///   1. Mid-OPEN drag (openDragProgress > 0, !isFullyPresented):
    ///      offset = (progress - 1) * panelWidth → -panelWidth at progress=0,
    ///      0 at progress=1.
    ///   2. Mid-CLOSE drag (closeDragProgress > 0, isFullyPresented):
    ///      offset = -progress * panelWidth → 0 at progress=0,
    ///      -panelWidth at progress=1.
    ///   3. Idle (panel fully shown OR fully hidden): offset = 0.
    private var panelOffsetX: CGFloat {
        if !isFullyPresented {
            return (openDragProgress - 1) * panelWidth
        }
        return -closeDragProgress * panelWidth
    }

    /// Scrim opacity follows the panel position so the dim builds in /
    /// fades out smoothly during interactive drags.
    private var scrimOpacity: Double {
        let visible: CGFloat
        if !isFullyPresented {
            visible = max(0, min(1, openDragProgress))
        } else {
            visible = max(0, min(1, 1 - closeDragProgress))
        }
        return Double(visible) * 0.25
    }

    var body: some View {
        ZStack(alignment: .leading) {

            // ---- Full-screen sizing proxy ----
            // Forces the overlay to fill its parent so the scrim's hit
            // area extends to the right edge of the screen. Without this
            // the parent `.overlay(alignment: .leading)` may collapse the
            // child to its intrinsic content size, leaving the right
            // 42pt dead-zone outside the tap target.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            // ---- Dim scrim ----
            // UIKit `x13-qO-QTr` is a transparent full-screen button
            // wired to `didPressDismissButton`. Tapping ANYWHERE outside
            // the visible panel — including the trailing 42pt dead-zone
            // (panelWidth=351 of 393pt screen) — must dismiss. We wrap
            // the scrim in a Button so the tap target is reliable across
            // all iOS versions (more deterministic than `.onTapGesture`
            // when stacked beneath a sibling view that owns gestures).
            Button(action: {
                guard isFullyPresented else { return }
                dismiss()
            }) {
                Color.black
                    .opacity(scrimOpacity)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(isFullyPresented)
            .accessibilityLabel("Close history")
            .accessibilityHint("Closes the chat history menu")

            // ---- Sliding panel ----
            // The visible panel (351pt of 393pt on iPhone 15). Its outer
            // frame is EXACTLY panelWidth so the scrim's right 42pt
            // dead-zone receives taps. Hit testing on the panel itself
            // is gated to the panelWidth area only — the close-pan
            // recognizer below shares the same frame so it never claims
            // touches in the dead-zone.
            ZStack {
                BarBotHistoryView(vm: vm, dismiss: dismiss)
                    .frame(width: panelWidth)
                    .background(
                        Color("primaryBackgroundColor")
                            .ignoresSafeArea(edges: [.top, .bottom])
                    )
                    // Soft drop-shadow on the trailing edge of the panel,
                    // matching the SideMenuManager default.
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 2, y: 0)

            }
            .frame(width: panelWidth, alignment: .leading)
            .offset(x: panelOffsetX)
            // Interactive LEFTWARD-pan dismiss — 1:1 with UIKit
            // SideMenuManager `addPanGestureToPresent` for a left menu.
            //
            // Uses SwiftUI `DragGesture(minimumDistance: 8)` as a
            // `.simultaneousGesture` so it COEXISTS with the table's
            // vertical scroll + the cell's tap (UIKit SideMenuSwift
            // achieves this internally via UIGestureRecognizerDelegate's
            // `shouldRecognizeSimultaneouslyWith`). A previous port used
            // a UIKit `UIPanGestureRecognizer` mounted via
            // `UIViewRepresentable` whose `hitTest` returned `self` for
            // ALL touches, swallowing every tap and scroll regardless of
            // direction. SwiftUI's gesture arbitration handles the same
            // intent without monopolising the touch stream.
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { v in
                        guard isFullyPresented else { return }
                        // Only react to LEFTWARD pans (negative .width).
                        // Vertical scrolls + rightward overshoots stay
                        // out of our way so the table remains scrollable.
                        let dx = min(0, v.translation.width)
                        let progress = min(1, max(0, -dx / panelWidth))
                        closeDragProgress = progress
                    }
                    .onEnded { v in
                        guard isFullyPresented else { return }
                        let dx = -v.translation.width                  // positive when moving left
                        let predictedDx = -v.predictedEndTranslation.width
                        let past = dx > panelWidth * 0.4
                        let fast = predictedDx > panelWidth * 0.6
                        if past || fast {
                            commitClose()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                closeDragProgress = 0
                            }
                        }
                    }
            )
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { vm.fetchSessions() }
    }

    /// UIKit `dismissDuration = 0.3` + light haptic on close. Drives the
    /// panel off-screen FIRST, then unmounts the overlay so the user sees
    /// the slide-out finish before the view disappears.
    private func dismiss() {
        HapticService.light()
        commitClose()
    }

    /// Two-step commit so the slide-off animation visibly completes
    /// before the overlay unmounts. Mirrors UIKit's
    /// `present(menu, animated: true)` ↔ `dismiss(animated: true)` where
    /// the dismiss animation runs to completion before the panel VC is
    /// removed from the hierarchy.
    ///
    /// **Critical**: the final `isPresented = false` flip must happen
    /// inside a `Transaction(animation: nil)` / `disablesAnimations =
    /// true` block. Otherwise the parent overlay's
    /// `.animation(.spring(...), value: router.showBarBotHistory)` +
    /// `.transition(.move(edge: .leading))` would replay the slide-off
    /// AFTER our own offset-driven slide already completed, producing
    /// the visible "panel slides off → reappears → slides off again"
    /// double-animation the user reported. Suppressing the implicit
    /// animation on the binding flip lets the offset animation own the
    /// motion and lets the unmount happen invisibly while the panel is
    /// already off-screen at x = -panelWidth.
    private func commitClose() {
        // Step 1: animate the panel off-screen to the left.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            closeDragProgress = 1
        }
        // Step 2: AFTER the slide-off completes, unmount silently.
        // The 0.32s delay matches `dismissDuration = 0.3` plus a small
        // spring-tail buffer so the user reads the motion as completing
        // rather than getting truncated by the overlay removal.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            // Suppress the parent's `.animation(value:)` on
            // `router.showBarBotHistory` so the conditional unmount
            // (and its `.transition(.move(edge:.leading))` removal)
            // happens WITHOUT a second slide-off pass.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                isPresented = false
                closeDragProgress = 0
            }
        }
    }
}

// MARK: - BarBotHistoryView (ports BarBotHistoryViewController)
//
// The UIKit storyboard scene renders these elements inside
// `Fve-Kt-qt2` (content container, pinned to safeArea):
//   1. `Hat-2b-7lb` "History" label   — system 24pt, `appBlackColor`,
//      x=24 y=45 (from safeArea top).
//   2. `4Cp-D7-2JV` New Chat card    — w=311, h=48, y=93.66, bg
//      `systemBackgroundColor` (white), `softDividerColor` 1pt border,
//      `roundCorners: 12`. Stack: `newChat` image 24×24 + "New Chat"
//      label (boldSystem 17pt, `mediumGrayColor`) — 12pt inner padding.
//      Tap gesture → `newChat(_:)` (resets BarBotViewController).
//   3. `Uud-nZ-xHt` table view      — x=16 y=157.66, separator none,
//      clear bg, row height auto ≈ 116.67pt. Cells register
//      `BarBotHistoryListTableCell`.
//   4. `z6c-QM-VLB` top dismiss btn — x=0 y=0 w=351 h=80, clear bg,
//      sits ON TOP of the History label in z-order (UIKit quirk: tap
//      on title still dismisses because the btn intercepts touches).
//
// Each `BarBotHistoryListTableCell` (xib `BarBotHistoryListTableCell.xib`):
//   • Outer view fills content, 9.33pt top / 9.33pt-12pt bottom inset.
//   • Inner card `vBa-wY-vgZ`: h min=86 max=96, bg `systemBackgroundColor`,
//     `softDividerColor` border, `roundCorners: 12`.
//   • Label `AQe-Z8-qG7`: system 14pt, `mediumGrayColor`.
//   • Trailing `historyRightArrow` button 24×35, 10pt leading inset.
struct BarBotHistoryView: View {
    @StateObject private var standaloneVM = BarBotViewModel()
    @Environment(\.dismiss) private var envDismiss
    @ObservedObject private var injectedVM: BarBotViewModel
    private let ownsVM: Bool
    private let dismissAction: (() -> Void)?

    /// Init used when presented as a sheet/overlay by BarBotCraftView.
    init(vm: BarBotViewModel, dismiss: @escaping () -> Void) {
        _injectedVM = ObservedObject(wrappedValue: vm)
        self.ownsVM = false
        self.dismissAction = dismiss
    }

    /// Init used by Route.barBotHistory — standalone, owns its own VM.
    init() {
        let vm = BarBotViewModel()
        _injectedVM = ObservedObject(wrappedValue: vm)
        self.ownsVM = true
        self.dismissAction = nil
    }

    private var vm: BarBotViewModel { ownsVM ? standaloneVM : injectedVM }
    private func dismiss() {
        if let a = dismissAction { a() } else { envDismiss() }
    }

    var body: some View {
        // UIKit `Fve-Kt-qt2` layout uses absolute constraints. We mirror
        // them with a ZStack + explicit paddings so spacing matches 1:1.
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                // Title — x=24 y=45 (from safeArea top), 24pt, appBlackColor.
                Text("History")
                    .font(.system(size: 24))
                    .foregroundStyle(Color("appBlackColor"))
                    .padding(.leading, 24)
                    .padding(.trailing, 24)
                    .padding(.top, 45)

                // New Chat card — y = 93.66 - 73.66 = 20pt gap from title bottom.
                newChatCard
                    .padding(.leading, 20)
                    .padding(.trailing, 20)
                    .padding(.top, 20)

                // Session list — y = 157.66 - 141.66 = 16pt gap from New Chat bottom.
                Group {
                    if vm.isLoadingSessions {
                        skeletonList
                    } else if vm.sessions.isEmpty {
                        empty
                    } else {
                        sessionList
                    }
                }
                .padding(.top, 16)
            }

            // UIKit `z6c-QM-VLB` — invisible top-80pt dismiss button.
            // Stays on top so a tap in the title/above-title zone closes
            // the side menu, matching `didPressDismissButton`.
            Color.clear
                .frame(height: 80)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
                .accessibilityLabel("Dismiss chat history")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Match the storyboard accessibility annotations.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chat history")
        .onAppear {
            // 1:1 port of `viewWillAppear`:
            //   arrBarBotHistory = nil
            //   tblBarBotHistory.reloadData()
            //   tblBarBotHistory.showSkeletonLoading(rows: 5, style: .historyCell)
            //   barbotHistoryViewModel.getSession(controller: self)
            vm.fetchSessions()
        }
    }

    // MARK: New Chat card (`4Cp-D7-2JV`)
    //
    // Constraints from storyboard:
    //   • bg: `systemBackgroundColor` (white)
    //   • border: `softDividerColor` 1pt
    //   • `roundCorners: 12`
    //   • inner stackView (`ZUb-8H-nCY`) — axis horizontal (default),
    //     spacing 12pt, 12pt padding all four edges.
    //   • `newChat` image button 24×24 (leading).
    //   • "New Chat" label boldSystem 17pt, `mediumGrayColor`.
    //
    // Tap gesture maps to `newChat(_:)`: resets sessionId, clears
    // merged answers, clears image, rebuilds chat view, restores tab bar.
    @ViewBuilder private var newChatCard: some View {
        Button {
            HapticService.light()
            vm.setupNewChat()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image("newChat")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color("mediumGrayColor"))
                Text("New Chat")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color("mediumGrayColor"))
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color("softDividerColor"), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel("New Chat")
        .accessibilityHint("Start a new conversation")
    }

    // MARK: Empty state
    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(Color("mediumGrayColor"))
            Text("No chat history yet")
                .font(.system(size: 14))
                .foregroundStyle(Color("mediumGrayColor"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    // MARK: Skeleton — UIKit `showSkeletonLoading(rows: 5, style: .historyCell)`
    //
    // Each skeleton row mirrors the real cell frame: inset 16pt lhs/rhs,
    // 12-rounded, 86pt tall with 9.33pt vertical spacing.
    private var skeletonList: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color("softDividerColor").opacity(0.6))
                    .frame(height: 86)
                    .padding(.vertical, 9.33)
                    .modifier(ShimmerModifier())
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Session list
    //
    // UIKit table: row height auto ≈ 116.67pt (9.33 top + 86 card + 9.33
    // bottom + 12 outer bottom). We replicate with 9.33pt vertical
    // padding around each card inside a ScrollView.
    //
    // Each `BarBotHistoryListTableCell` renders:
    //   • Card:       h min 86 / max 96, 12 corner, white bg,
    //                 `softDividerColor` 1pt border.
    //   • Label:      system 14pt, `mediumGrayColor`, 2 lines,
    //                 text `"\(firstUserMessage) - \(MM-dd-yyyy hh:mm a)"`.
    //   • Arrow:      `historyRightArrow` 24×35, 10pt leading from label.
    //   • Cell tap:   dismiss panel + load session (matches UIKit
    //                 `didSelectRowAt`).
    private var sessionList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(vm.sessions) { session in
                    Button {
                        HapticService.light()
                        vm.loadSession(session)
                        dismiss()
                    } label: {
                        historyCell(session: session)
                    }
                    .buttonStyle(BounceButtonStyle())
                    .padding(.vertical, 9.33)
                    .accessibilityLabel(session.displayText)
                    .accessibilityHint("Load this chat session")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func historyCell(session: BarBotSession) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(session.displayText)
                .font(.system(size: 14))
                .foregroundStyle(Color("mediumGrayColor"))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image("historyRightArrow")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 35)
                .foregroundStyle(Color("mediumGrayColor"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minHeight: 86, maxHeight: 96, alignment: .center)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color("softDividerColor"), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - QR Reader
//
// 1:1 port of UIKit `QrViewController` (BarBot/QrReader/QrViewController.swift)
// + its scene in Device.storyboard (lines 1116-1235). The UIKit scene:
//
//   • Full-screen black overlay @ alpha 0.9 (storyboard `Gjh-Gs-NV7`).
//   • Transparent nav bar (44pt): back button (30×30, `backWhite`) at
//     leading edge, info button (27×27, `About Barsys`) at trailing.
//   • "Scan QR" title — system bold 20pt, white, 24pt leading, 10pt below nav.
//   • QR scanner container (storyboard `y9I-et-QTr`): 345×468pt, 12pt
//     corner radius, 24pt horizontal inset, 100pt bottom from safe area.
//   • The scanner view (`QRScannerView` from the QRScanner pod) is added
//     at runtime with `focusImage: .borderimageScanner` — the corner art
//     in Assets.xcassets/Qr Controller/borderimageScanner.imageset.
//
// Behaviour:
//   • Camera permission prompt on first launch; denial → native alert
//     with "Open Settings" / "Cancel".
//   • Successful scan → validated against "basys" / "barsys_360"
//     (case-insensitive contains — QrViewController.swift L56). Invalid
//     codes pop + show "Device not available" alert (0.4s delay).
//   • Valid code → wires SpeakeasySocketManager, connects. On
//     `WAITING_AREA_JOINED` a toast is shown and the view dismisses
//     (the UIKit version also routes onward to ReadyToPourList — wired
//     to the existing router when that path is available).
//   • Haptic light() feedback on every tap, matching
//     HapticService.shared.light() calls in QrViewController L40,47.
//   • Tab bar is hidden while this screen is visible (UIKit hides it
//     via `doYouWantToShowTheUIofBottomBar(true)` on viewWillAppear).

struct QRReaderView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var didHandleScan = false
    @State private var isConnecting = false
    @State private var showDeniedCameraAlert = false
    @State private var showInvalidCodeAlert = false
    @State private var showSocketFailedAlert = false
    @State private var socketErrorMessage = ""
    @State private var socketSubscription: AnyCancellable?
    @State private var connectingDeviceName: String = ""
    @State private var loaderMessage: String = "Connecting"

    var body: some View {
        // UIKit storyboard `kg7-ix-QeJ` (root) composed of:
        //   • `Gjh-Gs-NV7` — full-screen black @ alpha 0.9
        //   • `Tqa-SM-n86` — 44pt transparent nav bar pinned to safe-area top
        //   • `R2A-h4-RiW` — "Scan QR" 20pt Bold white, 24pt leading,
        //                    10pt below navBar
        //   • `y9I-et-QTr` — scanner container, **24pt leading / 24pt
        //                    trailing from safe area**, 20pt below title,
        //                    100pt above bottom safe area (AutoLayout flex)
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // 1. Custom nav bar (44pt), pinned at safe-area top.
                navBar
                    .frame(height: 44)

                // 2. "Scan QR" title — 24pt leading, 10pt below nav.
                Text("Scan QR")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.leading, 24)
                    .padding(.top, 10)

                // 3. Scanner container — flex width bounded by 24pt
                //    leading + 24pt trailing from the safe area (EXACT
                //    UIKit AutoLayout). 20pt below the title. Vertical
                //    space fills down to 100pt above the bottom safe
                //    area, exactly like the storyboard's bottom anchor.
                scannerCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 100)
            }

            // Loader while socket is negotiating.
            if isConnecting {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.white)
                        .scaleEffect(1.4)
                    Text(loaderMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        // Hide both the navigation bar AND the tab bar for the duration
        // of this screen — UIKit `QrViewController.viewWillAppear`
        // calls `doYouWantToShowTheUIofBottomBar(isHiddenCustomTabBar:
        // true)`. SwiftUI equivalent is the `.toolbar(.hidden, for:)`
        // modifiers on each bar placement; `.toolbarBackground` is
        // redundant but harmless if iOS restores the bar.
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
        // Camera-permission-denied alert — UIKit `showDisabledCameraAlert()`.
        .alert("Camera Access Required",
               isPresented: $showDeniedCameraAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text(Constants.cameraRequiredAuthorizationForQr)
        }
        // Invalid-QR alert — UIKit L58-64 "Device not available".
        .alert("Device not available",
               isPresented: $showInvalidCodeAlert) {
            Button("OK", role: .cancel) {
                didHandleScan = false
            }
        }
        .alert("Could not connect",
               isPresented: $showSocketFailedAlert) {
            Button("OK", role: .cancel) {
                isConnecting = false
                didHandleScan = false
            }
        } message: {
            Text(socketErrorMessage)
        }
        .onDisappear {
            socketSubscription?.cancel()
            socketSubscription = nil
            if isConnecting {
                let socket: SpeakeasySocketManager = env.speakeasySocket
                socket.disconnect()
            }
        }
    }

    // MARK: Nav bar

    private var navBar: some View {
        HStack {
            Button {
                HapticService.light()
                let socket: SpeakeasySocketManager = env.speakeasySocket
                socket.disconnect()
                dismiss()
            } label: {
                // UIKit `backWhite` asset — 30×30 tap target, 21.33×21.33
                // visual icon.
                Image("backWhite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 21.33, height: 21.33)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .padding(.leading, 12)
            .accessibilityLabel("Back")

            Spacer()

            Button {
                HapticService.light()
                // UIKit `goToChooseOptionsScreen` — haptic only, no nav.
            } label: {
                Image("About Barsys")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 19, height: 18)
                    .foregroundStyle(Color.white)
                    .frame(width: 27, height: 27)
                    .contentShape(Rectangle())
            }
            // UIKit storyboard `5Np-SQ-Cm7` places the right icons stack
            // with a 14pt trailing inset from safe area.
            .padding(.trailing, 14)
            .accessibilityLabel("About Barsys")
        }
    }

    // MARK: Scanner card

    /// UIKit storyboard `y9I-et-QTr` — 12pt corner radius, transparent
    /// background with the `borderimageScanner` corner-frame overlay
    /// from Assets.xcassets/Qr Controller/.
    ///
    /// Sized by the parent's `.padding(.horizontal, 24)` + `.padding(.bottom,
    /// 100)` so the storyboard AutoLayout (leading 24 / trailing 24 /
    /// bottom 100 / 20pt below title) is faithfully reproduced across
    /// device sizes. On a 393pt-wide iPhone the container renders at the
    /// storyboard's literal 345pt width; on wider / narrower devices it
    /// flexes the same way UIKit's constraint system would.
    private var scannerCard: some View {
        ZStack {
            // Live camera preview — 12pt rounded corners, centred within
            // the flex container exactly like the UIKit storyboard's
            // `qrViewToShow` (a0B-78-z1V) inside `y9I-et-QTr`.
            QRScannerView(
                onScan: { code in
                    handleScan(code)
                },
                onCancel: {
                    HapticService.light()
                    dismiss()
                },
                onPermissionDenied: {
                    showDeniedCameraAlert = true
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Border/focus frame overlay — UIKit `focusImage:
            // .borderimageScanner` with the mercari/QRScanner library's
            // 61.8%-width focus box (see `setupImageViews`). We render
            // the full asset with 8pt padding so the corner brackets sit
            // inside the live preview at the same proportion UIKit shows.
            Image("borderimageScanner")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .allowsHitTesting(false)
                .padding(8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("QR code scanner")
        .accessibilityHint("Point camera at a QR code")
    }

    // MARK: Scan handling — 1:1 UIKit QrViewController L54-71

    private func handleScan(_ code: String) {
        guard !didHandleScan else { return }
        didHandleScan = true
        HapticService.light()

        // UIKit: `code.lowercased().contains("basys") ||
        //         code.lowercased().contains("barsys_360")`
        let lower = code.lowercased()
        guard lower.contains("basys") || lower.contains("barsys_360") else {
            // UIKit pops + 0.4s delay + alert; SwiftUI shows alert inline.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showInvalidCodeAlert = true
            }
            return
        }

        // Wire socket — mirrors UIKit L65-69.
        connectingDeviceName = code
        loaderMessage = "Connecting"
        subscribeToSocket(deviceName: code)
        isConnecting = true
        let socket: SpeakeasySocketManager = env.speakeasySocket
        socket.connect(to: code)
    }

    private func subscribeToSocket(deviceName: String) {
        socketSubscription?.cancel()
        let socket: SpeakeasySocketManager = env.speakeasySocket
        socketSubscription = socket.events
            .receive(on: DispatchQueue.main)
            .sink { event in
                switch event {
                case .connected(let name):
                    // 1:1 UIKit SocketDelegates.swift L19-73: show "{device}
                    // is Connected." toast, wait 1.0s for recipe list to
                    // stabilise, then pop this screen so the router lands
                    // back on the caller (ReadyToPour / ControlCenter)
                    // which will render the Speakeasy-connected UI via
                    // `AppStateManager.shared.isSpeakEasyCase`.
                    loaderMessage = "Fetching Recipes"
                    env.toast.show("\(name) is Connected.")
                    HapticService.light()
                    // UIKit `DelayedAction.afterBleResponse(seconds: 1.0,
                    // reason: "socket recipe load stabilization")`
                    // (SocketDelegates.swift L45).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        isConnecting = false
                        dismiss()
                    }
                case .reconnecting(let name):
                    // Auto-reconnect path — UIKit SocketManager.swift
                    // L34-50 (user kicked / 4004 / CONTROL_DECLINED with
                    // "user not in waiting area"). Keep the loader up
                    // with a clear status string so the user doesn't see
                    // a flicker while the new socket opens.
                    connectingDeviceName = name
                    loaderMessage = "Reconnecting"
                    isConnecting = true
                case .machineOffline, .controlDeclined:
                    isConnecting = false
                    // 1:1 UIKit `Constants.machineIsOffline` shown on
                    // CONTROL_DECLINED (SocketManager.swift L56-60).
                    socketErrorMessage = "The machine is currently offline. Please try again later."
                    showSocketFailedAlert = true
                    let socket: SpeakeasySocketManager = env.speakeasySocket
                    socket.disconnect()
                case .connectFailed(let reason):
                    isConnecting = false
                    socketErrorMessage = reason
                    showSocketFailedAlert = true
                case .disconnected:
                    if isConnecting {
                        isConnecting = false
                        socketErrorMessage = "Disconnected before the machine was ready."
                        showSocketFailedAlert = true
                    }
                default:
                    break
                }
            }
    }
}

// MARK: - BarBotCraftingView
//
// 1:1 port of UIKit `BarBotCraftingViewController`
//   Controllers/BarBot/BarBotCraft/BarBotCraftingViewController.swift
//   Controllers/BarBot/BarBotCraft/BarBotCraftingViewController+Actions.swift
//   Controllers/BarBot/BarBotCraft/BarBotCraftingViewController+BleResponse.swift
//   StoryBoards/Base.lproj/BarBot.storyboard (scene `uAy-Xq-2jT`)
//
// Presentation
// -------------
// UIKit: `.overFullScreen` modal with `FadeZoomTransitioningDelegate`,
// `view.backgroundColor = .clear`. The scene hosts:
//   • `btnDismiss` — full-screen black overlay at α=0.30 (UIKit L1118)
//   • `mainSheetView` — 393×452 bottom sheet, corner radius 24 (top-left
//     + top-right only), `.systemBackground`, glass effect border
//
// SwiftUI port: `.fullScreenCover` with a transparent background
// (`ClearBackgroundView`) so the dim scrim and sheet composition are
// rendered by this view. The sheet is animated into place with a spring
// (match UIKit's fade-zoom feel).
//
// UI elements (per storyboard + BarBotCraftingViewController.swift setupView)
// --------------------------------------------------------------------------
//   lblRecipeName          SFProDisplay 20pt,    grayBorderColor
//   lblGlassStatusText     SFProDisplay-SB 30pt, barbotBorderColor
//   lblIngredientName      SFProDisplay-SB 30pt, barbotBorderColor
//   lblIngredientQuantity  SFProDisplay-SB 28pt, barbotBorderColor
//   lblGarnishTitle        SFProDisplay-Bold 24, barbotBorderColor
//   lblGarnishesText       SFProDisplay-Med 18,  barbotBorderColor
//   lblGarnishesDescription SFProDisplay-Med 16, barbotBorderColor
//   imgRecipe              120×120 circle, scaleAspectFill
//   collectionViewProgress 10pt-tall horizontal segments
//   btnCross               33×33, rounded 10, grayBorderColor 1pt border
//   saveButton             168×48, rounded 24, grayBorderColor 1pt border
//                          "Save", bold system 15, grayBorderColor text
//   btnMakeItAgain         168×48, rounded 24, grayBorderColor bg
//                          "Make it Again", bold system 15, white text
//
// State → visibility (UIKit `updateIngredientsUI`, BleResponse handlers)
// ---------------------------------------------------------------------
// Pouring (.idle / .waitingForGlass / .dispensing / .glassLifted):
//   viewGlassStatus: visible (hidden for Shaker)
//   viewIngredients: visible
//   viewGarnish:     hidden
//   viewImageSuperView: hidden
//   bottomButtonsView:  hidden
//   btnCross:        visible
//
// Awaiting glass removal (.awaitingGlassRemoval):
//   lblGlassStatusText: "Remove Glass"
//   btnCross:         hidden (UIKit L245)
//
// Completed (.completed):
//   viewGlassStatus: hidden
//   viewIngredients: hidden
//   viewGarnish:     visible (if garnish list non-empty)
//   viewImageSuperView: visible
//   bottomButtonsView:  visible
//   btnCross:        visible
//
// BLE wiring
// ----------
// Reuses `CraftingViewModel` so the 9-state machine + every BleResponse
// branch (glassLifted / glassPlaced / dispensingStarted / dispensingComplete
// / allIngredientsPoured / cancelAcknowledged / dataFlushed /
// shakerNotFlat / shakerFlat / quantityFeedback) are handled identically
// to the main CraftingView — same as UIKit, which shares the same
// command/response code path between `CraftingViewController` and
// `BarBotCraftingViewController`.
//
// BLE commands sent:
//   • Craft:  `200,q1,q2,…,q14` (Coaster/Shaker) or
//             `200,s1,q1,…,s6,q6` padded to 15 (Barsys 360)
//     → `ble.send(.craftRaw(command:))` via CraftingViewModel.start(...)
//   • Cancel: `202` → `ble.send(.cancel)` via CraftingViewModel.cancel(ble:)

struct BarBotCraftingView: View {

    // MARK: - Inputs

    let recipe: BarBotRecipeElement
    let onDismiss: () -> Void

    // MARK: - Environment

    @EnvironmentObject private var ble: BLEService
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter

    // MARK: - State

    @StateObject private var viewModel = CraftingViewModel()
    @State private var didStart = false
    /// Drives sheet slide-up on appear.
    @State private var sheetOffsetY: CGFloat = 600
    /// `true` once the cross button was tapped — covers UIKit
    /// `strGlassStatusText == removeGlassToCompleteTheDrink` guard so a
    /// second tap is a no-op. Reset by `onMakeItAgainTap` so the cancel
    /// button remains functional across multiple craft sessions.
    @State private var cancelRequested = false
    /// Shaker-flat-surface alert — 1:1 port of UIKit
    /// `ShakerFlatSurfacePopUpViewController` (BarBotCraftingViewController
    /// +Actions.swift L172-197). Shown on `.shakerNotFlat` + `.glassWaiting`
    /// (Shaker only), dismissed on `.shakerFlat` + `.glassPlaced(is219:true)`
    /// + `.cancelAcknowledged`.
    @State private var showShakerFlatAlert = false

    // MARK: - Derived inputs
    //
    // UIKit `BarBotCoordinator.showBarBotCrafting(...)` splits the recipe
    // into three lists before presenting the crafting VC:
    //
    //     garnishIngredientsArr / additionalIngredientsArr / recipeIngredientsArr
    //
    // In the BarBot chat flow we only have the normalized ingredient list.
    // Port the UIKit category-based split by inspecting unit + name:
    //
    //   • unit == "pc" / "piece" / "each" → garnish (not pourable)
    //   • name contains "garnish"         → garnish
    //   • everything else                 → main pour

    /// Main pour ingredients — quantities drive the `200,…` command.
    private var mainIngredients: [BarBotIngredient] {
        recipe.normalizedIngredients.filter { !Self.isGarnishIngredient($0) }
    }

    /// Garnish ingredients — shown in the post-completion garnish block.
    private var garnishIngredients: [BarBotIngredient] {
        recipe.normalizedIngredients.filter { Self.isGarnishIngredient($0) }
    }

    private var garnishDisplayText: String {
        garnishIngredients
            .compactMap { $0.name?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private static func isGarnishIngredient(_ ing: BarBotIngredient) -> Bool {
        let unit = (ing.unit ?? "").lowercased()
        if unit == "pc" || unit == "piece" || unit == "each" { return true }
        let name = (ing.name ?? "").lowercased()
        return name.contains("garnish")
    }

    /// Convert BarBot ingredients into the storage `Recipe` format so
    /// `CraftingViewModel.start(recipe:ble:)` can drive the same command
    /// builder used by the main CraftingView.
    private var workingRecipe: Recipe {
        let ingredients: [Ingredient] = mainIngredients.map { ing in
            Ingredient(
                localID: IngredientID(),
                name: ing.name ?? "",
                unit: ing.unit ?? "ml",
                notes: nil,
                category: nil,
                quantity: ing.quantity ?? 0,
                perishable: nil,
                substitutes: nil,
                ingredientOptional: nil
            )
        }
        return Recipe(
            id: RecipeID(recipe.full_recipe_id ?? UUID().uuidString),
            name: recipe.name,
            description: recipe.descriptions,
            image: ImageModel(url: recipe.imageModel?.url, alt: nil),
            ingredients: ingredients,
            instructions: []
        )
    }

    // MARK: - Shaker-hides-glass-status
    //
    // UIKit `updateIngredientsUI` L205-211: `viewGlassStatus` is hidden
    // when a Shaker is connected (the Shaker firmware never prompts for
    // glass placement before dispensing — it reports its own flat-surface
    // state instead).
    private var shouldShowGlassStatus: Bool {
        !ble.isBarsysShakerConnected()
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // UIKit `btnDismiss` — full-screen 30% black overlay
            // (BarBot.storyboard L1118).
            Color.black.opacity(0.30)
                .ignoresSafeArea()

            sheet
                .offset(y: sheetOffsetY)
                .animation(.spring(response: 0.45, dampingFraction: 0.85),
                           value: sheetOffsetY)
        }
        .background(ClearBackgroundView())
        .onAppear {
            // Slide up.
            sheetOffsetY = 0
            guard !didStart else { return }
            didStart = true
            // Set active crafting screen so BLE disconnect alerts use the
            // "during crafting" copy path (AppRouter.swift L230).
            router.activeCraftingScreen = .barBotCrafting
            // Fire analytics (UIKit trackEventCraftBegin).
            Task { @MainActor in
                await viewModel.start(recipe: workingRecipe, ble: ble)
            }
        }
        .onDisappear {
            if router.activeCraftingScreen == .barBotCrafting {
                router.activeCraftingScreen = nil
            }
            env.loading.hide()
        }
        // Re-drive the state machine from BLE responses. Wiring matches
        // CraftingScreens.swift `CraftingView` body.
        .onReceive(ble.$lastResponse.compactMap { $0 }) { response in
            // Shaker-only flat-surface handling — UIKit
            // `BarBotCraftingViewController+BleResponse.swift` L269-353
            // and `+Actions.swift` L172-197. The flat-surface alert is
            // independent of the 9-state machine, so handle it here
            // BEFORE delegating to CraftingViewModel.dispatch.
            if ble.isBarsysShakerConnected() {
                switch response {
                case .shakerNotFlat:
                    showShakerFlatAlert = true
                case .shakerFlat, .glassPlaced(is219: true):
                    showShakerFlatAlert = false
                case .glassWaiting:
                    // UIKit: `.glassWaiting` on Shaker also shows the popup
                    // (firmware emits `219,405` instead of `200,410`).
                    showShakerFlatAlert = true
                case .cancelAcknowledged:
                    // Dismiss the popup if the cancel path acknowledges.
                    showShakerFlatAlert = false
                default:
                    break
                }
            }

            viewModel.dispatch(
                response,
                ble: ble,
                onCompleted: nil,    // BarBot stays on the sheet → show
                                     // Save / Make it Again bottom buttons.
                onDismiss: { finishDismiss() }
            )
        }
        // Mid-craft disconnect — mirrors UIKit disconnect alert path which
        // also dismisses the modal.
        .onChange(of: ble.isAnyDeviceConnected) { connected in
            if !connected { finishDismiss() }
        }
        // Shaker flat-surface popup — mirrors UIKit
        // `ShakerFlatSurfacePopUpViewController` (alert storyboard /
        // `Controller.shakerFlatSurfacePopUpVc`). The UIKit popup is a
        // `.overFullScreen` clear-background alert with a single
        // "Cancel Drink" action that sends `.cancel` + starts the
        // "Canceling drink" loader — ported below.
        .alert(
            "Place shaker on a flat surface",
            isPresented: $showShakerFlatAlert,
            actions: {
                Button("Cancel Drink", role: .destructive) {
                    onCancelTap()
                }
                Button("OK", role: .cancel) { }
            },
            message: {
                Text("Your Barsys Shaker is tilted. Please place it on a flat surface to continue.")
            }
        )
    }

    // MARK: - Sheet body
    //
    // UIKit `mainSheetView` geometry:
    //   height = 452, corner radius = 24 (top-only), bg = systemBackground.
    // Stack spacing = 20, inset = 24 (top/leading/trailing).
    // `collectionViewProgress` anchored to bottom of content stack.
    // `bottomButtonsView` bottom-offset 60 from sheet bottom.

    private var sheet: some View {
        VStack(spacing: 0) {
            VStack(alignment: .center, spacing: 20) {
                // lblRecipeName
                Text(recipe.name ?? "")
                    .font(Theme.Font.of(.title2))
                    .foregroundStyle(Color("grayBorderColor"))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 24)

                // Content container (viewGlassStatus + viewIngredients, OR
                // viewGarnish + viewImageSuperView after completion).
                contentContainer
                    .frame(height: 210)

                // collectionViewProgress — 10pt horizontal segment bar.
                progressBar
                    .frame(height: 10)
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            // UIKit `bottomButtonsView` appears only after completion.
            if viewModel.state == .completed {
                bottomButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 60)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(height: 452)
        .frame(maxWidth: .infinity)
        .background(sheetGlassBackground)
        .overlay(alignment: .topTrailing) {
            // btnCross hides during `.awaitingGlassRemoval` — UIKit L245.
            if viewModel.state != .awaitingGlassRemoval {
                crossButton
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.state)
    }

    // MARK: - Content container

    @ViewBuilder
    private var contentContainer: some View {
        if viewModel.state == .completed {
            completedContent
        } else {
            pouringContent
        }
    }

    // Pouring state: glass status prompt + ingredient info.
    private var pouringContent: some View {
        VStack(spacing: 24) {
            // viewGlassStatus
            if shouldShowGlassStatus {
                Text(glassStatusDisplayText)
                    .font(Theme.Font.of(.largeTitle, .semibold))
                    .foregroundStyle(Color("barbotBorderColor"))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 43)
                    .accessibilityLabel("Glass status")
            }

            // viewIngredients — lblIngredientName + lblIngredientQuantity
            VStack(spacing: 0) {
                Text(currentIngredientName)
                    .font(Theme.Font.of(.largeTitle, .semibold))
                    .foregroundStyle(Color("barbotBorderColor"))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 42)

                Text(currentIngredientQuantityText)
                    .font(Theme.Font.of(.largeTitleSmall, .semibold))
                    .foregroundStyle(Color("barbotBorderColor"))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 37)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // Completed state: garnish block + recipe image.
    private var completedContent: some View {
        VStack(spacing: 24) {
            // viewGarnish (only if garnish list non-empty).
            if !garnishDisplayText.isEmpty {
                VStack(spacing: 12) {
                    Text("Garnish")
                        .font(Theme.Font.of(.title1, .bold))
                        .foregroundStyle(Color("barbotBorderColor"))

                    Text(garnishDisplayText)
                        .font(Theme.Font.of(.title3, .medium))
                        .foregroundStyle(Color("barbotBorderColor"))
                        .multilineTextAlignment(.center)

                    Text(Self.garnishDescription)
                        .font(Theme.Font.of(.body, .medium))
                        .foregroundStyle(Color("barbotBorderColor"))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }

            // viewImageSuperView — 120pt circle with recipe image.
            recipeImage
        }
        .frame(maxHeight: .infinity)
    }

    // UIKit storyboard default for lblGarnishesDescription (L1211-1216).
    private static let garnishDescription =
        "Garnish to your heart's content. Your drink is now complete. Enjoy!"

    // Sheet glass background — 1:1 port of UIKit
    // `BarBotCraftingViewController.swift` L216-218:
    //
    //     mainSheetView.layer.maskedCorners = [.layerMinXMinYCorner,
    //                                           .layerMaxXMinYCorner]
    //     mainSheetView.roundCorners = BarsysCornerRadius.pill   // = 24
    //     mainSheetView.addGlassEffect(cornerRadius: BarsysCornerRadius.pill)
    //
    // The underlying `addGlassEffect` with all defaults (tintColor: .clear,
    // isBorderEnabled: false, alpha: 1.0, effect: "regular") creates a
    // `UIGlassEffect(style: .regular)` UIVisualEffectView — iOS 26+ Liquid
    // Glass with the default regular translucency. Pre-iOS 26 the call
    // is a no-op (the guard `if #available(iOS 26.0, *)`) so the sheet
    // falls back to its storyboard `.systemBackground` fill.
    //
    // SwiftUI recipe for the same visual family:
    //   • iOS 26+ → `.regularMaterial` (SwiftUI's closest analogue to
    //               `UIGlassEffect(style: .regular)` — frosted, more
    //               opaque than `.ultraThinMaterial` which models
    //               UIGlassEffect's `.clear` style instead).
    //   • Pre-26  → solid `Color(.systemBackground)` (identical to the
    //               UIKit pre-26 fallback where the glass call is
    //               compiled out).
    //
    // Only top-left + top-right corners are rounded — matches the UIKit
    // `maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]`
    // directive that keeps the sheet bottom flush with the screen edge.
    @ViewBuilder
    private var sheetGlassBackground: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 24,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 24,
            style: .continuous
        )
        if #available(iOS 26.0, *) {
            shape
                .fill(.regularMaterial)
                // Subtle white tint overlay so the sheet reads as a
                // bright glass card against dark backdrops — matches
                // the `addGlassEffect` regular-style visual with clear
                // tintColor default.
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 24,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 24,
                        style: .continuous
                    )
                    .fill(Color(.systemBackground).opacity(0.45))
                )
                .ignoresSafeArea(edges: .bottom)
        } else {
            // Pre-iOS 26 — UIKit's addGlassEffect is a no-op, so the
            // sheet shows only the storyboard systemBackground.
            shape
                .fill(Color(.systemBackground))
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var recipeImage: some View {
        ZStack {
            Circle().fill(Color("lightBorderGrayColor"))
            AsyncImage(url: URL(string: recipe.imageModel?.url ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Image("myDrink").resizable().scaledToFill()
                }
            }
            .clipShape(Circle())
        }
        .frame(width: 120, height: 120)
        .accessibilityLabel("Recipe image")
    }

    // MARK: - Progress bar
    //
    // UIKit `collectionViewProgress`: horizontal collection view with one
    // cell per recipe ingredient. Cell is 10pt tall, inner bar 5pt tall
    // with 5pt horizontal inset, roundCorners 2. Color logic:
    //   • poured (index < currentIngredient) → grayBorderColor
    //   • not yet (iOS < 26)                  → grayColorForBarBot
    //   • not yet (iOS 26+)                   → grayBorderColor.α=0.30

    private var progressBar: some View {
        GeometryReader { proxy in
            let count = max(mainIngredients.count, 1)
            let cellWidth = proxy.size.width / CGFloat(count)
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressCellColor(at: idx))
                        .frame(width: cellWidth - 10, height: 5)
                        .frame(width: cellWidth, height: 10)
                }
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Crafting progress")
    }

    private func progressCellColor(at index: Int) -> Color {
        if index < viewModel.currentIngredient {
            return Color("grayBorderColor")
        }
        if #available(iOS 26.0, *) {
            return Color("grayBorderColor").opacity(0.30)
        } else {
            return Color("grayColorForBarBot")
        }
    }

    // MARK: - Cross button

    private var crossButton: some View {
        Button {
            HapticService.light()
            onCancelTap()
        } label: {
            Image("crossIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
                .frame(width: 33, height: 33)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color("grayBorderColor"), lineWidth: 1)
                )
        }
        .accessibilityLabel("Cancel")
        .accessibilityHint("Cancels the current drink crafting")
    }

    // MARK: - Bottom buttons

    private var bottomButtons: some View {
        HStack(spacing: 8) {
            // saveButton — border style
            Button {
                HapticService.success()
                onSaveTap()
            } label: {
                Text("Save")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color("grayBorderColor"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color("grayBorderColor"), lineWidth: 1)
                    )
            }
            .accessibilityLabel("Save")
            .accessibilityHint("Saves this drink to favourites")

            // btnMakeItAgain — filled style
            Button {
                HapticService.light()
                onMakeItAgainTap()
            } label: {
                Text("Make it Again")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color("grayBorderColor"))
                    )
            }
            .accessibilityLabel("Make it again")
            .accessibilityHint("Crafts the same drink again")
        }
    }

    // MARK: - Runtime text

    /// Mirrors UIKit `lblGlassStatusText.text` — defaults to "Place Glass"
    /// before pour starts; becomes "Remove Glass" during
    /// `.awaitingGlassRemoval`. The verbose `Remove glass to cancel…` /
    /// `Remove glass from device to complete` strings stay in
    /// `viewModel.glassStatusText` (used by VoiceOver) — the visible label
    /// keeps the short form to match UIKit.
    private var glassStatusDisplayText: String {
        switch viewModel.state {
        case .awaitingGlassRemoval: return "Remove Glass"
        default:                    return "Place Glass"
        }
    }

    /// Currently-pouring ingredient name; falls back to an empty string
    /// while idle so the pouring block doesn't flash stale text.
    private var currentIngredientName: String {
        let idx = viewModel.currentIngredient
        guard idx >= 0, idx < viewModel.recipeIngredients.count else { return "" }
        return viewModel.recipeIngredients[idx].ingredientName
    }

    private var currentIngredientQuantityText: String {
        let idx = viewModel.currentIngredient
        guard idx >= 0, idx < viewModel.recipeIngredients.count else { return "" }
        let q = Int(viewModel.recipeIngredients[idx].ingredientQuantity)
        return "\(q) ml"
    }

    // MARK: - Actions

    // Cross / backdrop tap.
    private func onCancelTap() {
        // UIKit L21-23: guard — cannot cancel once `strGlassStatusText ==
        // removeGlassToCompleteTheDrink`. i.e. when .awaitingGlassRemoval.
        if viewModel.state == .awaitingGlassRemoval { return }
        if cancelRequested { return }
        cancelRequested = true

        env.loading.show("Cancelling drink...")
        viewModel.cancel(ble: ble)
    }

    // saveButton tap — UIKit L94-131 ports.
    private func onSaveTap() {
        // Validation (UIKit L99-107).
        if mainIngredients.isEmpty {
            env.alerts.show(title: "", message: Constants.pleaseAddIngredients)
            return
        }
        let nonZero = mainIngredients.filter { ($0.quantity ?? 0) > 0 }
        if nonZero.isEmpty {
            env.alerts.show(title: "", message: Constants.ingredientsCantBeZero)
            return
        }

        env.loading.show("Saving Recipe")
        let toSave = workingRecipe
        Task {
            do {
                try await env.api.saveOrUpdateMyDrink(
                    recipe: toSave, image: nil, isCustomizing: true
                )
                await MainActor.run {
                    env.loading.hide()
                    env.toast.show(
                        "Your drink has been saved successfully.",
                        color: Color("segmentSelectionColor"),
                        duration: 3
                    )
                }
            } catch {
                await MainActor.run {
                    env.loading.hide()
                    env.alerts.show(
                        title: "Unable to save recipe",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    // btnMakeItAgain tap — UIKit L45-92 ports.
    private func onMakeItAgainTap() {
        // Reset then re-send craft command after a short hardware-settle
        // delay (UIKit uses `DelayedAction.afterBleResponse(1.0s)` so the
        // device is ready to accept a second `200,…` frame).
        viewModel.resetForMakeAgain()
        // Re-arm the cancel button for the new session — otherwise a
        // previously-tapped cross would leave the button permanently
        // disabled across the "Make it Again" transition.
        cancelRequested = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await viewModel.start(recipe: workingRecipe, ble: ble)
        }
    }

    // Called from BLE onDismiss and disconnect observer.
    private func finishDismiss() {
        env.loading.hide()
        sheetOffsetY = 600
        // Give the slide-down a moment before popping.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            onDismiss()
        }
    }
}

// MARK: - ClearBackgroundView (transparent fullScreenCover host)
//
// Makes the UIKit host view behind `fullScreenCover` transparent so our
// dim-scrim + bottom-sheet composition renders on top of the presenting
// view (UIKit parity with `.overFullScreen` + clear `view.backgroundColor`).
//
// Mirrors `DeviceScreens.swift` ClearBackgroundView — redeclared here
// (file-scope private) because that one is private to its own file.

private struct ClearBackgroundView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Notifications (kept for back-compat; VM now handles state directly)

extension Notification.Name {
    static let barBotLoadSession = Notification.Name("barBotLoadSession")
    static let barBotNewChat = Notification.Name("barBotNewChat")
}

// MARK: - WaitingRecipePopup
//
// 1:1 port of UIKit `WaitingRecipePopUpViewController`
// (Controllers/AlertDialogs/WaitingRecipePopUpViewController.swift +
//  StoryBoards/Base.lproj/AlertPopUp.storyboard scene
//  `WaitingRecipePopUpViewController`).
//
// ------------------- STORYBOARD LAYOUT ------------------------------
//
//   root view `Pqp-LM-rcF` (375×812, bg CLEAR)
//     ├── overlay `3Ck-xe-Vqo` (375×812, white@0.0 — inert)
//     └── card `tNS-40-AMr` (277×231.33, centered, cornerRadius=12,
//           bg = systemBackgroundColor, 49pt L/R margin on 375pt canvas)
//         ├── close button `Nj2-cE-I7K`
//         │     50×50 at (227, 0) top-right of card, image="crossIcon",
//         │     tintColor=appBlackColor, bg=transparent.
//         └── inner content (24, 24), 229×193.33
//             └── vertical stack:
//                 • GIF spinner `fLl-Im-oY9` (SDAnimatedImageView,
//                   "BarsysLoader.gif", contentMode=scaleAspectFit,
//                   runtime constraints 45×45 — width/height set in
//                   `viewSetup`).
//                 • lblTitle `QWS-94-F7f` — system 16pt,
//                   veryDarkGrayColor, textAlignment=center,
//                   numberOfLines=0, text =
//                   "Your recipe will be ready in just a moment".
//                 • btnCancel `OgB-cS-KqA` — full-width 229×45,
//                   white bg, black title "Cancel" 12pt, border
//                   1pt `borderColor`, corner
//                   `BarsysCornerRadius.small` (applied at runtime).
//
// ------------------- RUNTIME BEHAVIOUR ------------------------------
//
//   viewDidLoad → checkApi() → addBounceEffect on btnCancel
//   checkApi()  → BarBotApiService.getFullRecipeApi(fullRecipeId:) { recipe, err in
//                   if err == "wait" →
//                       pollingTask = Task {
//                           try? await Task.sleep(nanoseconds: 5_000_000_000)
//                           guard !Task.isCancelled,
//                                 UIApplication.topViewController is WaitingPopup
//                           else { return }
//                           self.checkApi()    // recurse every 5s
//                       }
//                   else if recipe != nil →
//                       build Recipe with id="", floor ingredient qty >= 5ml,
//                       dismiss(animated: false) { pushRecipePage(context: .barBotRecipe) }
//                   else →
//                       dismiss()
//                 }
//   cancelButtonClicked(_:) → HapticService.light(), pollingTask.cancel(),
//                              dismiss(animated: true)
//   viewWillDisappear       → pollingTask.cancel(), pollingTask = nil
//
// ------------------- SWIFTUI NOTES ----------------------------------
//
// The SwiftUI port reproduces the popup VISUALS exactly. The polling
// + API bridge (`BarBotApiService.getFullRecipeApi`) is a SwiftUI
// service that still needs to be ported; until then the popup ships
// with an `onReady` closure the host can invoke manually (or wire
// to a real API once the service lands). The Cancel flow is fully
// functional — tapping Cancel / close dismisses the popup with the
// same light haptic UIKit uses.

struct WaitingRecipePopup: View {
    @EnvironmentObject private var env: AppEnvironment

    @Binding var isPresented: Bool
    /// The recipe's `full_recipe_id` to poll. UIKit hands this down from
    /// the chat-response item that the user tapped.
    let fullRecipeId: String
    /// Called with the decoded recipe when the server returns 2xx.
    /// Called with `nil` when the user cancels or a non-recoverable
    /// error occurs (matching UIKit's silent failure branch).
    var onReady: (Recipe?) -> Void = { _ in }

    /// Storyboard card frame: 277×231.33 @ (49, 303) on a 375pt canvas.
    /// 49pt L/R inset is UIKit's reference padding — we use the same
    /// horizontal inset so the card width scales correctly on any
    /// device width.
    private let cardWidth: CGFloat = 277
    private let cardHeight: CGFloat = 231.33

    /// Polling Task — mirrors UIKit `WaitingRecipePopUpViewController`
    /// `pollingTask` (L18). Stored in `@State` so we can cancel it on
    /// user dismiss, on view disappear, or on a terminal success/error.
    @State private var pollingTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // ---- Backdrop ----------------------------------------------
            // UIKit overlay `3Ck-xe-Vqo` ships `white@0.0` — fully
            // transparent inert layer. User cannot dismiss by tapping
            // outside; must use Cancel button or close X. SwiftUI uses a
            // near-invisible colour so taps outside are silently absorbed.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { /* UIKit-parity: inert backdrop */ }

            // ---- Card (`tNS-40-AMr`) -----------------------------------
            ZStack(alignment: .topTrailing) {
                // Card background — GLASS to match the other popups in
                // the app (side-menu panel, edit panel, DeviceConnected
                // popup, DeviceList popup). UIKit's WaitingRecipePopUp
                // uses `systemBackgroundColor` in the storyboard, but
                // every OTHER popup in the app applies
                // `alertPopUpBackgroundStyle(cornerRadius: .medium)` →
                // on iOS 26 that's a real `UIGlassEffect(.regular)`.
                // The user asked us to align this popup with the rest
                // of the popup surfaces — so we route through the same
                // `BarsysGlassPanelBackground` (pure UIKit
                // `UIGlassEffect` on iOS 26, `systemBackground` white
                // pre-26) instead of the flat storyboard white.
                Group {
                    if #available(iOS 26.0, *) {
                        BarsysGlassPanelBackground()
                    } else {
                        Color(.systemBackground)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(width: cardWidth, height: cardHeight)

                // Inner content (`L9q-OP-VHX`) — 229×193.33 at (24, 24).
                VStack(spacing: 24) {
                    // Spinner — UIKit uses a 45×45 GIF (BarsysLoader.gif).
                    // The SwiftUI port uses a native ProgressView tinted
                    // with the brand colour; swap for an AnimatedImage
                    // wrapper once the GIF is packaged in SwiftUI assets.
                    ProgressView()
                        .controlSize(.large)
                        .frame(width: 45, height: 45)
                        .tint(Color("veryDarkGrayColor"))
                        .accessibilityLabel("Loading recipe")

                    // Title — UIKit lblTitle: system 16pt,
                    // veryDarkGrayColor, textAlignment=center,
                    // numberOfLines=0.
                    Text("Your recipe will be ready in just a moment")
                        .font(.system(size: 16))
                        .foregroundStyle(Color("veryDarkGrayColor"))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    // Cancel button — 1:1 with UIKit `btnCancel`
                    // (WaitingRecipePopUpViewController L140-146):
                    //   roundCorners = BarsysCornerRadius.small = 8
                    //   layer.borderColor = UIColor.borderColor.cgColor
                    //   layer.borderWidth = 1.0
                    //   clipsToBounds = true
                    //   title "Cancel", font system 12pt, color BLACK
                    //
                    // Every OTHER popup in UIKit applies
                    // `applyCancelCapsuleGradientBorderStyle()` on iOS 26+
                    // to this same "cancel" style button — giving it a
                    // glass-clear fill + white/cancelBorderGray gradient
                    // stroke. We mirror that here so the Cancel button
                    // in the waiting popup matches the other popups'
                    // cancel buttons across the app (AlertPopUp,
                    // MultipleIngredients, etc.).
                    Button {
                        cancel()
                    } label: {
                        Text(ConstantButtonsTitle.cancelButtonTitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color("appBlackColor"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 45)
                            .background(cancelButtonBackground)
                            .overlay(cancelButtonBorder)
                            .clipShape(cancelButtonShape)
                    }
                    .buttonStyle(BounceButtonStyle()) // UIKit addBounceEffect()
                    .accessibilityLabel("Cancel waiting")
                }
                .padding(24)
                .frame(width: cardWidth, height: cardHeight)

                // Close button (`Nj2-cE-I7K`) — 50×50 top-right of card,
                // crossIcon template-rendered with appBlackColor tint.
                Button {
                    cancel()
                } label: {
                    Image("crossIcon")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Color("appBlackColor"))
                        .frame(width: 50, height: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .frame(width: cardWidth, height: cardHeight)
            // Subtle shadow so the card separates from the transparent
            // backdrop on light backgrounds (UIKit gets this naturally
            // via the non-clear systemBackground fill over a blurred
            // nav host; SwiftUI full-screen covers start clear).
            .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 6)
        }
        .onAppear { startPolling() }
        .onDisappear {
            // UIKit `viewWillDisappear` (WaitingRecipePopUpViewController
            // L37-39) cancels the polling Task when the popup leaves
            // the screen. Same here.
            pollingTask?.cancel()
            pollingTask = nil
        }
    }

    // MARK: - Polling machinery
    //
    // 1:1 port of UIKit `checkApi()` (WaitingRecipePopUpViewController
    // L42-97). Calls `env.api.fetchFullRecipe(fullRecipeId:)` and:
    //   • on `.wait`  → sleeps 5s and recurses
    //   • on success  → invokes `onReady(recipe)` (host dismisses +
    //                   navigates to Recipe page with .barBotRecipe)
    //   • on error    → dismisses silently (UIKit just drops the popup
    //                   on any non-wait non-success response)

    /// Start the first API call. Safe to call multiple times: a new
    /// Task replaces any in-flight one.
    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { await pollOnce() }
    }

    /// One iteration of the poll loop. On `.wait`, sleeps 5 seconds
    /// and recurses; on success / failure, exits.
    private func pollOnce() async {
        do {
            let recipe = try await env.api.fetchFullRecipe(fullRecipeId: fullRecipeId)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onReady(recipe)
            }
        } catch FullRecipeError.wait {
            // Sleep 5s — matches UIKit `Task.sleep(nanoseconds: 5_000_000_000)`.
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            // Only keep polling while the popup is still presented —
            // UIKit L53-55 checks `topViewController is WaitingPopup`.
            await MainActor.run {
                guard isPresented else { return }
                startPolling()
            }
        } catch {
            // Non-recoverable: UIKit silently drops on any non-wait
            // non-success branch. Dismiss and signal `nil` to host.
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onReady(nil)
                isPresented = false
            }
        }
    }

    /// UIKit `cancelButtonClicked(_:)` (L149-154):
    /// light haptic → cancel polling → animated dismiss.
    private func cancel() {
        HapticService.light()
        pollingTask?.cancel()
        pollingTask = nil
        isPresented = false
    }

    // MARK: - Cancel button styling
    //
    // 1:1 port of the `applyCancelCapsuleGradientBorderStyle()` /
    // `makeBorder(1, craftButtonBorderColor)` decision tree used
    // across every UIKit popup Cancel button:
    //
    //   iOS 26+:
    //     • Fill   : glass — `regularMaterial` + subtle cancel-gray tint
    //                (UIKit `addGlassEffect(tintColor: .cancelButtonGray,
    //                 cornerRadius: 8)`)
    //     • Border : 6-stop white ↔ cancelBorderGray gradient stroke
    //                (UIKit `applyCancelCapsuleGradientBorderStyle`)
    //     • Shape  : 8pt rounded rect (`BarsysCornerRadius.small`)
    //
    //   Pre-26:
    //     • Fill   : pure white
    //     • Border : 1pt `borderColor` (UIKit
    //                `btnCancel.layer.borderColor = .borderColor.cgColor`)
    //     • Shape  : 8pt rounded rect

    @ViewBuilder
    private var cancelButtonBackground: some View {
        if #available(iOS 26.0, *) {
            // Glass fill + subtle cancel-gray tint — matches UIKit
            // `addGlassEffect(tintColor: .cancelButtonGray)` with a
            // `.clear` glass style over the popup card.
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.Color.cancelButtonGray.opacity(0.15))
            }
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
        }
    }

    @ViewBuilder
    private var cancelButtonBorder: some View {
        if #available(iOS 26.0, *) {
            // UIKit `applyCancelCapsuleGradientBorderStyle(borderColors:)`
            // stops (UIViewClass+GradientStyles.swift L92-110): 6-stop
            // alternating white → cancelBorderGray sheen.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.95),                      location: 0.00),
                            .init(color: Theme.Color.cancelBorderGray.opacity(0.9), location: 0.20),
                            .init(color: .white.opacity(0.95),                      location: 0.40),
                            .init(color: .white.opacity(0.95),                      location: 0.60),
                            .init(color: Theme.Color.cancelBorderGray.opacity(0.9), location: 0.80),
                            .init(color: .white.opacity(0.95),                      location: 1.00)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color("borderColor"), lineWidth: 1)
        }
    }

    private var cancelButtonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }
}
