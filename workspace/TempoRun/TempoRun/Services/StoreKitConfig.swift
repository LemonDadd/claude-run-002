import Foundation

/// 订阅方案
enum SubscriptionPlan: String, CaseIterable, Identifiable {
    case monthly
    case yearly
    case lifetime

    var id: String { productID }

    var productID: String { StoreKitConfig.productID(for: self) }

    var title: String {
        switch self {
        case .monthly:  return "Pro 月付"
        case .yearly:   return "Pro 年付"
        case .lifetime: return "Pro 终身买断"
        }
    }

    var subtitle: String {
        switch self {
        case .monthly:  return "按月付费，随时取消"
        case .yearly:   return "年付更划算，前 7 天免费试用"
        case .lifetime: return "一次付费，永久解锁"
        }
    }

    var hasFreeTrial: Bool { self == .yearly }

    /// 是否为终身买断（非续期订阅，StoreKit 中用 nonRenewable/非消耗品）
    var isLifetime: Bool { self == .lifetime }
}

/// 订阅状态（持久化到 User 模型）
enum SubscriptionStatus: String, Codable, CaseIterable {
    case free       // 免费版
    case trial      // 7 天免费试用中（年付首期）
    case pro        // 已订阅（月付/年付在有效期）
    case lifetime   // 终身买断

    var isPro: Bool { self == .pro || self == .lifetime || self == .trial }

    var displayName: String {
        switch self {
        case .free:     return "免费版"
        case .trial:    return "试用中"
        case .pro:      return "Pro 会员"
        case .lifetime: return "Pro 终身"
        }
    }
}

/// 所有 StoreKit 配置集中处。
/// 上架时：在 App Store Connect 创建同名产品 ID 后，无需改动业务代码；
/// 若正式 ID 不同，仅替换本文件的 productID 映射即可。
enum StoreKitConfig {
    /// 产品 ID（App Store Connect / TempoRun.storekit 必须一致）
    static let monthlyID  = "com.temporun.pro.monthly"
    static let yearlyID   = "com.temporun.pro.yearly"
    static let lifetimeID = "com.temporun.pro.lifetime"

    static let subscriptionGroupID = "pro"

    static func productID(for plan: SubscriptionPlan) -> String {
        switch plan {
        case .monthly:  return monthlyID
        case .yearly:   return yearlyID
        case .lifetime: return lifetimeID
        }
    }

    static func plan(for productID: String) -> SubscriptionPlan? {
        switch productID {
        case monthlyID:  return .monthly
        case yearlyID:   return .yearly
        case lifetimeID: return .lifetime
        default:         return nil
        }
    }

    static let allProductIDs: [String] = [monthlyID, yearlyID, lifetimeID]

    /// 年付免费试用天数（与 .storekit / App Store Connect 订阅优惠保持一致）
    static let yearlyTrialDays = 7
}
