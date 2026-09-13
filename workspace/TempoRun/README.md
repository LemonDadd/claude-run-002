# TempoRun · iOS 跑步步频器

> 极简、高对比的跑步步频引导 App。Swift + SwiftUI · 最低 iOS 16 · SwiftData（iOS 17 原生 / iOS 16 JSON 兜底）

## 构建

```bash
brew install xcodegen
cd TempoRun
xcodegen generate
open TempoRun.xcodeproj
```

需要在 Xcode 中设置 Development Team；App Group `group.com.temporun.shared` 需要与
你的 TeamID 保持一致（主 App、Widget Extension 两处 entitlements）。

## StoreKit 本地测试（无需开发者账号）

- 配置文件：`TempoRun/TempoRun.storekit`
  - `com.temporun.pro.monthly` 月付自动续期订阅
  - `com.temporun.pro.yearly` 年付，附带 7 天免费试用（introductory offer）
  - `com.temporun.pro.lifetime` 终身买断（非消耗型）
- `project.yml` 的 scheme 已配置 `storeKitConfigurationPath`，`xcodegen generate` 后
  scheme 的 Run → Options → StoreKit Configuration 会自动指向该文件，
  模拟器/真机调试直接走本地购买流程，不连接 App Store 服务器
- 也可在 Xcode 菜单 Debug → StoreKit → Manage Transactions 管理测试交易（退款/过期/续费）
- 产品 ID 全部集中在 `Services/StoreKitConfig.swift`；上架时在 App Store Connect
  创建同 ID 产品后无需改业务代码（本地与正式环境代码路径一致，通过
  `AppTransaction.shared.environment` 自动区分 Xcode / Sandbox / Production）

## 免费 / Pro 边界

| 功能 | 免费 | Pro |
|---|---|---|
| 核心步频器（引导/检测/曲线/跑步记录） | ✅ | ✅ |
| 音色 | 滴答、鼓点（2 种） | 全部 5 种 |
| 间歇模板 | 1 个 | 进阶模板 + 无限自定义 |
| 历史记录 | 最近 7 天 | 全部 |
| HealthKit / Strava 同步 | — | ✅ |
| 步频分布图 | — | ✅ |
| 广告 | 有横幅 | 去除 |

Strava 同步需在 `Services/StravaService.swift` 填入 clientID / clientSecret。

## 工程结构（MVVM 分层）

```
TempoRun/
├── TempoRunApp.swift                 # App 入口（深链、配色、摘要弹窗）
├── Models/
│   ├── RunRecord.swift               # 值类型：RunSummary / Stage / TrackPoint / CadenceSample / 枚举
│   └── SwiftDataModels.swift         # @Model：UserEntity / RunRecordEntity / TrainingPlanEntity（iOS17+）
├── ViewModels/
│   ├── CadenceEngine.swift        ★① 步频检测（加速度计→带通→峰值→窗口→Pedometer 融合）
│   ├── AudioEngine.swift          ★② 节拍混音/调度/后台播放/中断恢复
│   ├── TrainingSession.swift      ★③ 训练状态机（多阶段、渐入、三重提示、偏离报警、聚合保存）
│   └── RunCoordinator.swift          # 全局活动会话 + Widget 命令桥接
├── Services/
│   ├── SensorService.swift           # CMMotionManager(60Hz) + CMPedometer
│   ├── SoundFactory.swift            # 5 种音色程序化合成（滴答/鼓点/木鱼/电子/人声）
│   ├── HapticEngine.swift            # CoreHaptics 左右脚强弱
│   ├── LocationTracker.swift         # GPS 轨迹（有效性筛选 + 跳点剔除，目标误差<3%）
│   ├── SpeechService.swift           # AVSpeechSynthesizer 中文播报
│   ├── LiveActivityService.swift   ★④ Live Activity 生命周期
│   ├── HealthService.swift           # HealthKit（Workout + 距离/步数/卡路里）
│   ├── StravaService.swift           # OAuth2 + GPX 上传
│   ├── AuthService.swift             # Sign in with Apple + 手机号
│   ├── PersistenceStore.swift        # 存储门面 + iOS16 JSONStore + AppSettings
│   └── SwiftDataHistoryStore.swift   # iOS17 SwiftData 实现
├── Views/
│   ├── Home / Cadence / Run / History / Stats / Plans / Settings / Charts / Components
└── Utilities/
    ├── BiquadFilter.swift            # RBJ Biquad（1–5Hz Butterworth 带通）
    ├── PeakDetector.swift            # 自适应阈值峰值检测
    ├── AppConstants.swift / Keychain.swift
Widgets/                              # Widget Extension：锁屏小组件 + Live Activity + 灵动岛
└── RunIntents.swift                  # 暂停/继续/停止/±5 SPM 的 LiveActivityIntent
Shared/                               # App 与 Extension 共享（App Group 模型 / 命令通道 / 格式化）
```

## 四个核心模块说明

### ① CadenceEngine（目标准确率 ≥95%）
信号链：加速度模长 → 去重力(HP 1Hz) → 低通 5Hz → 自适应阈值峰值检测
（EMA-RMS×1.35、最小峰间距 0.18s、峰后回落确认）→ 5s 滑窗峰间间隔取中位 →
与 `CMPedometer.currentCadence` 做一致性加权融合（权重 0.3→0.7 自适应）。
输出 2Hz；步数取峰值计数与系统步数的较大值交叉校验。

### ② AudioEngine（节拍延迟 <50ms）
- `AVAudioSession`：`.playback` + `.mixWithOthers`，5ms IO buffer；
- `DispatchSourceTimer`（20ms/2ms leeway）+ 0.15s 提前量，按硬件时钟精确发声；
- 6 个预分配 `AVAudioPlayerNode` 轮转，0 运行时节点分配；
- 左右脚：合成时声像（L0.7/R0.3 与 L0.3/R1.0）+ 音高×1.06 + Haptic 0.45/1.0 三维区分；
- 节拍渐入：每拍 ±2SPM 平滑逼近；独立 mixer 音量，不影响音乐 App；
- 静音循环 buffer 持有后台音频会话；中断 `.began/.ended` 挂起/重置基线恢复；
- 锁屏/耳机线控映射为 暂停/继续/±5。

### ③ TrainingSession 状态机
`idle → running ⇄ paused → finished`；1Hz 主循环（RunLoop.common，滑动不卡）。
间歇多阶段（热身/快跑/慢跑/冷身）按时长或距离自动切换，切换时
**语音(AVSpeechSynthesizer) + 触觉(0.5s continuous) + 整屏色彩闪光** 三重提示；
训练中 `adjustCurrentStageCadence` 只改音频目标（per-stage override），不中断计时与节拍；
±5 SPM 偏离 8s 节流播报 + 橙色横幅；卡路里用 MET 模型按体重估算。

### ④ Live Activity / 灵动岛
- iOS 17：`LiveActivityIntent` 直接在扩展内执行，App Group UserDefaults +
  Darwin 通知把命令转发到主 App（stop 用 `openAppWhenRun` 保证落库）；
- iOS 16：深链 `temporun://cmd/{pause|resume|stop|up|down}` 回 App 执行；
- 灵动岛：紧凑态显示实时 SPM，展开态含 步频/时间/距离/阶段 + 暂停·继续·停止·±5；
- 主 App 同时把状态发布到 App Group，锁屏 Widget 用 Timeline 兜底刷新。

## 非功能指标的实现策略
- 冷启动 <2s：无启动页网络请求，SwiftData 懒加载，引擎在进入跑步页时才创建；
- 后台 1h 耗电 <10%：采样 60Hz 但算法 O(n)、无轮询定位（系统回调驱动）、
  静音保活 buffer 为零样本、Live Activity 1Hz 合批更新；
- 内存 <150MB：轨迹/曲线点为值类型小对象，地图点抽稀到 ≤40；
- 包体 <80MB：5 种音色全部代码合成，零音频/图片资源；
- 户外可读：系统动态色 + 粗字重 + 关键数据 ≥40pt，对比度 ≥4.5:1；
- 无障碍：全控件 VoiceOver 标签、Dynamic Type、偏离自动朗读、
  停止按钮 74pt 热区 + 二次确认防误触。

## 隐私
位置/步频/轨迹仅存本机（SwiftData 或 Documents JSON）；不启用 CloudKit；
HealthKit/Strava 均为用户显式授权后单次写入；设置页可一键删除全部数据。

## 二期
- watchOS 独立 App：watchOS SwiftUI + WorkoutKit + HealthKit 会话下发
- 更多音色扩展、跑步课程社区、音频文件自定义上传
