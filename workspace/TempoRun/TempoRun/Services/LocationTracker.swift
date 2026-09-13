import CoreLocation

/// App 启动/首页预热定位权限用的轻量代理（不开始更新，只弹窗）
final class LocationPermissionPrimer: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPermissionPrimer()
    private let manager = CLLocationManager()

    func requestWhenInUse() {
        manager.delegate = self
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
}

/// GPS 轨迹记录。
/// 精度策略：
/// - 运动型距离筛选（horizontalAccuracy ≤ 30m、时间戳新鲜）
/// - 无效点（静止漂移/水平跳变 > 8m/s 即 28.8km/h）剔除
/// - 目标距离误差 <3%
final class LocationTracker: NSObject, ObservableObject {

    enum Permission: Equatable {
        case unknown, granted, denied
    }

    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var track: [TrackPoint] = []
    @Published private(set) var isTracking = false
    /// 当前定位授权（UI 据此显示“去设置开启定位”引导）
    @Published private(set) var permission: Permission = .unknown

    private let manager = CLLocationManager()
    private var lastMeasured: CLLocation?
    private var elevationGain: Double = 0
    private var lastAlt: CLLocation?
    /// 授权未决时调用了 start，待授权成功后补启动
    private var wantsTracking = false
    /// Always 升级只请求一次，用户跳过后不再反复弹
    private var didRequestAlways = false

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        // 后台定位只能在拿到 Always 授权后开启（见授权回调），否则会触发系统断言崩溃
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = false
        permission = Self.permission(from: manager.authorizationStatus)
    }

    /// App 启动 / 进入跑步页时可提前请求前台定位
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        reset()
        wantsTracking = true
        didRequestAlways = manager.authorizationStatus == .authorizedAlways

        switch manager.authorizationStatus {
        case .notDetermined:
            // 等 locationManagerDidChangeAuthorization 回调里真正启动
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            manager.allowsBackgroundLocationUpdates = true
            beginUpdates()
        case .authorizedWhenInUse:
            beginUpdates()
            // Always 升级统一在授权变更回调里请求，避免重复弹窗
        case .denied, .restricted:
            permission = .denied
        @unknown default:
            manager.requestWhenInUseAuthorization()
        }
    }

    func stop() {
        wantsTracking = false
        isTracking = false
        manager.stopUpdatingLocation()
    }

    var ascentMeters: Double { elevationGain }

    private func reset() {
        distanceMeters = 0
        elevationGain = 0
        lastMeasured = nil
        lastAlt = nil
        track.removeAll(keepingCapacity: true)
    }

    private func beginUpdates() {
        permission = .granted
        guard !isTracking else { return }
        isTracking = true
        manager.startUpdatingLocation()
        manager.requestLocation() // 立即取一次，缩短首屏定位时间
    }

    private static func permission(from status: CLAuthorizationStatus) -> Permission {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }

    private func isValid(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= AppConstants.minLocationAccuracy else { return false }
        guard abs(location.timestamp.timeIntervalSinceNow) < AppConstants.maxLocationAge else { return false }
        if let prev = lastMeasured {
            let dt = location.timestamp.timeIntervalSince(prev.timestamp)
            guard dt > 0 else { return false }
            let d = location.distance(from: prev)
            if d / dt > 8.0 { return false } // 28.8km/h 以上判为跳点
        }
        return true
    }
}

extension LocationTracker: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations {
            guard isValid(loc) else { continue }
            if let prev = lastMeasured {
                let d = loc.distance(from: prev)
                // 合理步幅：单次增量 ≥0.5m 才累计，过滤静止抖动
                if d >= 0.5 { distanceMeters += d }
                if let la = lastAlt, loc.altitude > la.altitude {
                    let gain = loc.altitude - la.altitude
                    if gain < 3 { elevationGain += gain } // 过滤 GPS 高程噪声
                }
            }
            lastMeasured = loc
            lastAlt = loc
            lastLocation = loc
            track.append(TrackPoint(timestamp: loc.timestamp,
                                    latitude: loc.coordinate.latitude,
                                    longitude: loc.coordinate.longitude,
                                    altitude: loc.altitude,
                                    horizontalAccuracy: loc.horizontalAccuracy))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // requestLocation 在定位不可用时会回调错误；持续更新不受影响
        if let clError = error as? CLError, clError.code == .denied {
            permission = .denied
            isTracking = false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        permission = Self.permission(from: status)

        switch status {
        case .authorizedAlways:
            manager.allowsBackgroundLocationUpdates = true
            if wantsTracking { beginUpdates() }
        case .authorizedWhenInUse:
            if wantsTracking {
                beginUpdates()
                // 前台授权已到手，尝试升级 Always（只请求一次）
                if !didRequestAlways {
                    didRequestAlways = true
                    manager.requestAlwaysAuthorization()
                }
            }
        case .denied, .restricted:
            isTracking = false
            wantsTracking = false
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}
