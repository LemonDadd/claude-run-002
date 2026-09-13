import Foundation
import StoreKit
import Combine
import UIKit

/// 购买结果（供 UI 提示失败/取消/网络错误）
enum PurchaseResult: Equatable {
    case success
    case pending            // 家长审批 / 等待中
    case userCancelled
    case networkError
    case verificationFailed
    case productUnavailable
    case unknown(String)

    var alertMessage: String? {
        switch self {
        case .success, .pending: return nil
        case .userCancelled: return "购买已取消"
        case .networkError: return "网络异常，请检查连接后重试"
        case .verificationFailed: return "收据验证失败，已为你保留权益，请稍后使用恢复购买"
        case .productUnavailable: return "暂时无法获取商品，请稍后再试"
        case .unknown(let msg): return "购买失败：\(msg)"
        }
    }
}

/// StoreKit 运行环境（仅展示/日志用；本地测试与正式环境购买代码完全一致）
enum StoreEnvironment: String {
    case xcode, sandbox, production, unknown
    var displayName: String {
        switch self {
        case .xcode:      return "Xcode 本地测试"
        case .sandbox:    return "TestFlight / 沙盒"
        case .production: return "App Store"
        case .unknown:    return "—"
        }
    }
}

/// Pro 功能门控定义（集中管理免费/Pro 边界）
enum ProFeature {
    case sound(BeatSound)
    case unlimitedPlans
    case fullHistory
    case healthSync
    case stravaSync
    case cadenceDistribution
    case removeAds

    var title: String {
        switch self {
        case .sound(let s):        return "\(s.rawValue)音色"
        case .unlimitedPlans:      return "无限间歇训练模板"
        case .fullHistory:         return "全部历史记录"
        case .healthSync:          return "HealthKit 数据同步"
        case .stravaSync:          return "Strava 数据同步"
        case .cadenceDistribution: return "步频分布图"
        case .removeAds:           return "去除广告"
        }
    }

    var valueDescription: String {
        switch self {
        case .sound:               return "5 种专业节拍音色，跑步更跟节奏"
        case .unlimitedPlans:      return "创建、保存无限个间歇 / 自定义训练计划"
        case .fullHistory:         return "查看 7 天以前的全部跑步记录与曲线"
        case .healthSync:          return "自动同步训练、距离、步数到苹果「健康」"
        case .stravaSync:          return "一键上传轨迹与训练到 Strava"
        case .cadenceDistribution: return "查看你的步频分布与进步趋势"
        case .removeAds:           return "纯净无广告的跑步体验"
        }
    }
}

/// StoreKit 2 订阅管理器
///
/// 设计要点：
/// - Product.products / purchase / Transaction.currentEntitlements 全部使用 StoreKit 2 async API
/// - StoreKit 2 的 VerificationResult 由系统在本地完成收据签名校验（等效“验证收据”）；
///   本地 StoreKit Testing（.storekit）、TestFlight 沙盒、App Store 走完全相同的代码路径，无需切换
/// - 月付/年付为自动续期订阅（同一订阅组），终身买断为非消耗型
/// - App 启动、前后台切换、Transaction.updates 三处驱动状态刷新
@MainActor
final class SubscriptionManager: ObservableObject {

    static let shared = SubscriptionManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var status: SubscriptionStatus
    @Published private(set) var expiryDate: Date?
    @Published private(set) var environment: StoreEnvironment = .unknown
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published var purchaseError: PurchaseResult?
    @Published var didRestore = false

    private var updatesTask: Task<Void, Never>?

    // MARK: 生命周期

    init() {
        // 先用本地持久化状态占位，随后异步与 StoreKit 对账
        let profile = PersistenceStore.shared.profile
        self.status = profile.subscriptionStatus
        self.expiryDate = profile.subscriptionExpiryDate

        startObservingTransactions()
        Task { await refresh() }

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func handleForeground() {
        Task { await refresh() }
    }

    // MARK: 权益判断

    var isPro: Bool { status.isPro }

    /// 免费版仅解锁：滴答、鼓点
    func isUnlocked(_ feature: ProFeature) -> Bool {
        if isPro { return true }
        switch feature {
        case .sound(let sound):
            return sound == .click || sound == .drum
        case .unlimitedPlans, .fullHistory, .healthSync,
             .stravaSync, .cadenceDistribution, .removeAds:
            return false
        }
    }

    func product(for plan: SubscriptionPlan) -> Product? {
        products.first { $0.id == plan.productID }
    }

    // MARK: 加载产品

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: StoreKitConfig.allProductIDs)
            // 按 月→年→终身 的固定顺序展示
            products = StoreKitConfig.allProductIDs.compactMap { id in
                fetched.first { $0.id == id }
            }
        } catch {
            #if DEBUG
            print("[StoreKit] loadProducts failed: \(error)")
            #endif
            purchaseError = .networkError
        }
    }

    // MARK: 购买

    @discardableResult
    func purchase(_ plan: SubscriptionPlan) async -> PurchaseResult {
        if let product = product(for: plan) {
            return await finishPurchase(product: product)
        }
        await loadProducts()
        guard let product = product(for: plan) else {
            let r: PurchaseResult = .productUnavailable
            purchaseError = r
            return r
        }
        return await finishPurchase(product: product)
    }

    private func finishPurchase(product: Product) async -> PurchaseResult {
        isPurchasing = true
        defer { isPurchasing = false }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch URLError.notConnectedToInternet, URLError.timedOut, URLError.networkConnectionLost {
            let r: PurchaseResult = .networkError
            purchaseError = r
            return r
        } catch {
            let r: PurchaseResult = .unknown(error.localizedDescription)
            purchaseError = r
            return r
        }

        switch result {
        case .userCancelled:
            purchaseError = .userCancelled
            return .userCancelled
        case .pending:
            return .pending
        case .success(let verification):
            // StoreKit 2 已做签名校验；.unverified 不放权益（越狱/中间人风险）
            switch verification {
            case .verified(let transaction):
                await apply(transaction: transaction)
                await transaction.finish()
                return .success
            case .unverified:
                purchaseError = .verificationFailed
                return .verificationFailed
            }
        @unknown default:
            purchaseError = .unknown("未知购买结果")
            return .unknown("未知购买结果")
        }
    }

    // MARK: 恢复购买

    @discardableResult
    func restore() async -> Bool {
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                found = true
                await apply(transaction: transaction)
            }
        }
        if !found { await downgradeToFree() }
        didRestore = true
        return found
    }

    // MARK: 交易监听（续费 / 退款 / 跨设备 / 状态变化）

    private func startObservingTransactions() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { break }
                if case .verified(let transaction) = update {
                    await self.apply(transaction: transaction)
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: 对账（启动 / 前台）

    func refresh() async {
        if products.isEmpty { await loadProducts() }
        await refreshEnvironment()

        var resolved: SubscriptionStatus = .free
        var latestExpiry: Date?
        var hasLifetime = false
        var sawExpiredSubscription = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result else { continue }

            if tx.productType == .nonConsumable, tx.productID == StoreKitConfig.lifetimeID,
               tx.revocationDate == nil {
                hasLifetime = true
                continue
            }

            guard tx.productType == .autoRenewable else { continue }

            // 退款 / 家庭共享移除
            if let revocation = tx.revocationDate, revocation <= Date() { continue }

            let renewal = await renewalState(for: tx.productID)
            let activeByDate = tx.expirationDate.map { $0 > Date() } ?? true
            let active = renewal == .subscribed || renewal == .inGracePeriod
                || renewal == .inBillingRetryPeriod || activeByDate

            if !active {
                sawExpiredSubscription = true
                continue
            }

            let inTrial = tx.offerType == .introductory
                && (tx.expirationDate.map { $0 > Date() } ?? false)

            // pro 优先于 trial
            if !inTrial { resolved = .pro }
            else if resolved != .pro { resolved = .trial }

            if let exp = tx.expirationDate, exp > (latestExpiry ?? .distantPast) {
                latestExpiry = exp
            }
        }

        if hasLifetime {
            resolved = .lifetime
            latestExpiry = nil
        } else if resolved == .free, sawExpiredSubscription {
            // 已过期：显式降为免费
            resolved = .free
            latestExpiry = nil
        }

        status = resolved
        expiryDate = latestExpiry
        persist()
    }

    /// 通过 AppTransaction 判断当前环境：Xcode 本地测试 / 沙盒 / 正式
    private func refreshEnvironment() async {
        guard case .verified(let appTx) = try? await AppTransaction.shared else { return }
        switch appTx.environment {
        case .xcode:      environment = .xcode
        case .sandbox:    environment = .sandbox
        case .production: environment = .production
        default:          environment = .unknown
        }
    }

    // MARK: 单笔交易应用（购买 / 续费 / 更新）

    private func apply(transaction: StoreKit.Transaction) async {
        switch transaction.productType {
        case .nonConsumable where transaction.productID == StoreKitConfig.lifetimeID:
            guard transaction.revocationDate == nil else {
                await downgradeToFree(); return
            }
            status = .lifetime
            expiryDate = nil

        case .autoRenewable:
            if let revocation = transaction.revocationDate, revocation <= Date() {
                await downgradeToFree(); return
            }
            let renewal = await renewalState(for: transaction.productID)
            let activeByDate = transaction.expirationDate.map { $0 > Date() } ?? true
            if !(renewal == .subscribed || renewal == .inGracePeriod
                 || renewal == .inBillingRetryPeriod || activeByDate) {
                await downgradeToFree(); return
            }
            let inTrial = transaction.offerType == .introductory
                && (transaction.expirationDate.map { $0 > Date() } ?? false)
            status = inTrial ? .trial : .pro
            expiryDate = transaction.expirationDate

        default:
            return
        }
        persist()
    }

    /// StoreKit 2：续订状态在 Product.SubscriptionInfo，不在 Transaction 上
    private func renewalState(for productID: String) async -> Product.SubscriptionInfo.RenewalState {
        guard let product = products.first(where: { $0.id == productID }),
              let statuses = try? await product.subscription?.status,
              let state = statuses.first?.state else {
            return .expired
        }
        return state
    }

    private func downgradeToFree() async {
        status = .free
        expiryDate = nil
        persist()
    }

    // MARK: 持久化到 User 模型

    private func persist() {
        var profile = PersistenceStore.shared.profile
        profile.subscriptionStatus = status
        profile.subscriptionExpiryDate = expiryDate
        PersistenceStore.shared.saveProfile(profile)
    }
}
