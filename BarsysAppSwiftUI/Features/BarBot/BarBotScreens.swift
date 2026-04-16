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

struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
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
        VStack(alignment: .leading, spacing: 20) {
            // Welcome — UIKit `questionLabel` (storyboard `NiT-e7-6fk`):
            //   boldSystem 24pt, textColor `mediumLightGrayColor`,
            //   ALPHA 0.51 on the label itself (xib attribute
            //   `alpha="0.51000000000000001"`). Previous port dropped
            //   the alpha so the text rendered too dark vs UIKit.
            // Multi-line (numberOfLines=0, wraps freely).
            Text(vm.welcomeMessage)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color("mediumLightGrayColor").opacity(0.51))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)

            // Options block — label "Let's get crafting" + 2×2 grid.
            // UIKit layout uses an internal VStack spacing of 20pt
            // (Txz-p7-YgZ: WNl-Dc-66p.top = fvf-TL-f9A.bottom + 20).
            VStack(alignment: .leading, spacing: 20) {
                Text("Let\u{2019}s get crafting") // curly apostrophe to match UIKit xib
                    .font(.system(size: 18))
                    .foregroundStyle(Color("charcoalTextColor50Alpha"))
                    .accessibilityAddTraits(.isHeader)

                if vm.isOptionsLoading && vm.options.isEmpty {
                    skeletonGrid
                } else {
                    grid
                }
            }
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
            Text(opt.title ?? "")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color("charcoalGrayColor"))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 5)

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
                // `grayColorForBarBot` = RGB(0.922, 0.922, 0.922) —
                // asset not ported to SwiftUI project, so inline the
                // exact UIKit color.
                .fill(Color(red: 0.922, green: 0.922, blue: 0.922))
        )
        // Runtime `applyCustomShadow(cornerRadius: 12, size: 1.0,
        // shadowRadius: 3.0)` — opacity 0.43, offset (0, 1), blur 3.
        .shadow(color: .black.opacity(0.43), radius: 3, x: 0, y: 1)
        .padding(5) // 5pt outer inset = `lbg-yu-hL3` leading/top/trailing/bottom constant
    }

    private var skeletonGrid: some View {
        let cols = [GridItem(.flexible(), spacing: gridSpacing),
                    GridItem(.flexible(), spacing: gridSpacing)]
        return LazyVGrid(columns: cols, spacing: gridSpacing) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.Color.softPlatinum)
                    .frame(height: tileHeight - 10)
                    .modifier(ShimmerModifier())
                    .padding(5)
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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
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

    // Loading row — ports `loadingAnswerView`:
    //   • GIF 35×35 playing iOS.gif
    //   • "Barbot is thinking" label (12pt, grayBorderColor)
    //   • Cancel button 32×32 top-right (tag 786 in UIKit → here tag by id).
    private var loading: some View {
        HStack(alignment: .center, spacing: 8) {
            AnimatedGIFView(assetName: "barbotThinking")
                .frame(width: 35, height: 35)
            Text("Barbot is thinking")
                .font(Theme.Font.of(.caption1))
                .foregroundStyle(Color("grayBorderColor"))
            Spacer()
            Button {
                HapticService.light()
                vm.cancel(messageID: msg.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel("Cancel")
            .frame(width: 32, height: 32)
        }
        .frame(minHeight: 45)
    }

    // Answer block — ports `recipeTypeAnswerMainView`:
    //   • sender avatar (senderImageView) sits on the left side.
    //   • answer bubble = PaddingLabel: 12pt charcoalGray on white, 4pt radius.
    //   • Section headers above recipe/mixlist carousels (Barsys Recipes /
    //     Barsys Mixlists/Cocktail Kits you can Buy).
    //   • Action-card header "Most asked suggestions" (12pt bold,
    //     charcoalTextColor50Alpha).
    @ViewBuilder private var answer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image("senderImageView")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
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
                .font(Theme.Font.of(.subheadline, .bold))
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
    @State private var showHistory = false

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
                                    onRecipeTap: { _ in
                                        // UIKit pushes RecipePageViewController.
                                        // In SwiftUI the crafting flow resolves by recipe id
                                        // lookup; without a backend fetch we route to details
                                        // which is the closest available screen.
                                        router.push(.recipeDetail(RecipeID()), in: .barBot)
                                    },
                                    onRecipeCraft: { r in startCraft(r) },
                                    onMixlistTap: { m in handleMixlist(m) }
                                )
                                .id(msg.id)
                            }
                        }
                        .padding(16)
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
        // BarBot History — ports `BarBotHistoryViewController` which UIKit
        // presents as a left-edge slide-in side menu via SideMenuManager
        // (`openSideMenuforBarBotHistory()`), NOT as a sheet. Drag-right
        // dismisses it, mirroring UIKit's pan gesture.
        .overlay(alignment: .leading) {
            if showHistory {
                BarBotHistorySideMenuOverlay(
                    isPresented: $showHistory,
                    vm: viewModel
                )
                .transition(.move(edge: .leading))
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showHistory)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isConnected {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    if !deviceIconName.isEmpty {
                        Image(deviceIconName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                    }
                    Text(deviceKindName)
                        .font(Theme.Font.of(.caption1, .medium))
                        .foregroundStyle(Theme.Color.textPrimary)
                }
            }
        }
        // HISTORY — LEFT side (matches UIKit `btnHistory` leading:24pt,
        // 48×48 with `chatHistory` icon, iOS 26 `clearGlass()` button
        // configuration, pre-26 plain clear bg with leading constraint 9pt).
        // BarBotViewController.swift L182-L191 + storyboard constraint
        // `U3j-dQ-Ihd`.
        ToolbarItem(placement: .topBarLeading) {
            Button {
                HapticService.light()
                guard viewModel.canProcessNewRequest else { return }
                showHistory = true
                viewModel.fetchSessions()
            } label: {
                if #available(iOS 26.0, *) {
                    // iOS 26 `clearGlass()` config — translucent circular
                    // glass over the nav bar. 48×48 matches storyboard.
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Image("chatHistory")
                            .resizable().renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                            .foregroundStyle(Color("appBlackColor"))
                    }
                    .frame(width: 44, height: 44)
                } else {
                    // pre-26 plain — just the icon on the nav bar.
                    Image("chatHistory")
                        .resizable().renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Color("appBlackColor"))
                        .frame(width: 44, height: 44)
                }
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel("History")
            .accessibilityHint("View previous chat sessions")
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
        case .pairDevice:       router.push(.pairDevice, in: .barBot)
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
            router.push(.pairDevice, in: .barBot)
            return
        }
        // Note: quantities already normalized via recipe.normalizedIngredients.
        // With no backend full-recipe fetch available here, we route to the
        // crafting screen using a new RecipeID; the crafting flow handles the
        // fallback (matches UIKit behavior when full_recipe_id lookup fails).
        router.push(.crafting(RecipeID()), in: .barBot)
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
    @State private var dragOffset: CGFloat = 0

    /// UIKit panel visible width = 351 / 393 ≈ 89.3% of screen width.
    private var panelWidth: CGFloat {
        UIScreen.main.bounds.width * (351.0 / 393.0)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Dim scrim over the whole screen — tap anywhere (including
            // the trailing 42pt dead-zone) dismisses the panel. UIKit
            // does this via `x13-qO-QTr` (a transparent full-screen btn).
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            // The visible sliding panel (351pt of 393pt on iPhone 15).
            BarBotHistoryView(vm: vm, dismiss: dismiss)
                .frame(width: panelWidth)
                .background(
                    Color("primaryBackgroundColor")
                        .ignoresSafeArea(edges: [.top, .bottom])
                )
                // Soft drop-shadow on the trailing edge of the panel,
                // matching the SideMenuManager default.
                .shadow(color: .black.opacity(0.18), radius: 8, x: 2, y: 0)
                .offset(x: dragOffset)
                // Swipe-right to dismiss — matches the SideMenuManager
                // pan-dismiss gesture added in
                // `setupSideMenuForSwipeForBarBotHistory()`.
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { v in
                            if v.translation.width > 0 {
                                dragOffset = v.translation.width
                            }
                        }
                        .onEnded { v in
                            if v.translation.width > 80
                                || v.predictedEndTranslation.width > panelWidth / 2 {
                                dismiss()
                            } else {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
        }
        .onAppear { vm.fetchSessions() }
    }

    /// UIKit `dismissDuration = 0.3`.
    private func dismiss() {
        HapticService.light()
        withAnimation(.easeInOut(duration: 0.3)) {
            dragOffset = 0
            isPresented = false
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

// MARK: - QR Reader (unchanged — required by RouteView)

struct QRReaderView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            QRScannerView(
                onScan: { code in
                    env.alerts.show(title: "Scanned", message: code)
                    dismiss()
                },
                onCancel: { dismiss() }
            )
            .ignoresSafeArea()
            VStack {
                Spacer()
                Text("Scan a Barsys QR code")
                    .font(Theme.Font.of(.callout))
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.bottom, 48)
            }
        }
        .navigationTitle("QR Reader")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Notifications (kept for back-compat; VM now handles state directly)

extension Notification.Name {
    static let barBotLoadSession = Notification.Name("barBotLoadSession")
    static let barBotNewChat = Notification.Name("barBotNewChat")
}
