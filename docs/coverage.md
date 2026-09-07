# 协议覆盖与验收记录

固定上游：`6820f9da169d354bc7e6e93a0aa8683a6bb75792`。

- 设备目录：113 个鼠标及相关接收器 PID。
- 开发阶段本地独立上游测试向量：5854 条；该参考样本及提取／重写脚本不随公开仓库发布。运行数据保留声明式布局 382 个、路由 3648 条。
- Rust 用强类型报文、枚举化参数来源和 Result 执行协议。生产代码不包含 C 翻译层；C 对照库仅用于测试。
- 对照验证命令报文字节、合法/非法结果及读取格式。旧设备软件缓存读取有刻意差异：未知值返回错误，Orochi 回报率缓存返回 Hz，不复制上游截断为 0 的行为。
- Rust 测试共 7 项，其中外部样本对照默认忽略，公开默认集运行 6 项；回归验证短报文不崩溃、错误状态/校验拒绝、未知旧设备配置不写入以及完整配置后缓存更新。

## 实机状态

| 项目 | 结果 |
| --- | --- |
| Swift→UniFFI ABI→Rust，V4 Pro 有线读取 | 通过；`build/hardware-readback.json`，DPI/档位/回报率/电池/充电/休眠/阈值/固件均无读取错误 |
| 独立应用访问 HID | 已添加安装版应用并开启输入监控，真实读取通过 |
| 原生设置内 DPI、档位、回报率、休眠时间写入及回读 | 通过，已恢复 1600 DPI、原始 5 档、1000 Hz、300 秒 |
| 低电量阈值写入并恢复 | 未执行：设备当前原始值 77，超出上游写入范围 12–63，避免无法恢复原设置 |
| V4 Pro 无线读取 | 单次完整读取通过；修复了将非控制 HID 接口重复列为鼠标的问题，见 `build/hardware-wireless-readback.json` |
| 无线连续读取 | 24 次调用测试曾出现设备响应超时，尚未通过稳定性验收 |
| 插拔通知、睡眠唤醒、重启 | 已实现 IOKit 插拔通知；真实事件到 UI 的完整时序仍待用户配合验收 |
| 其他型号 | 缺少硬件验证 |
| 界面 | AppKit 宿主渲染深浅色、低电量、充电、断开、错误、长名称、灯光/滚轮；模拟状态不进入正式应用 |
| 包大小 | 3.68 MB（Apple Silicon 安装版），见 `build/build-metrics.json` |
| 有线版空闲 CPU | 60.64 秒平均 0.825%，面板关闭、设置窗口打开；`build/idle-performance.json`。该测量早于本次扩展面板 |
| 最新版内存与无线 CPU | 物理 footprint 43.44 MiB；无线 60.69 秒平均 CPU 0.725%。面板关闭、设置窗口打开。RSS 124.85 MiB 包含共享映射，单独记录，不将其等同于 physical footprint；见 `build/build-metrics.json` |

## 线程稳定性修复

首次安装版在 GCD 串行队列切换底层线程后，于 `IOHIDManagerSetDeviceMatchingMultiple` → `CFRunLoopAddSource` 崩溃。hidapi 的全局 macOS manager 依赖初始化线程的 RunLoop；仅保证调用串行不够。现在由 Rust 常驻 `razer.hid` 线程持有 HidApi 和全部原生句柄，Swift 通过消息转发访问。验证包括 32 个短生命周期调用线程共享同一 I/O 线程的回归测试，以及 24 次跨调用线程的真实设备完整读取。

测试结束已重新启动雷云。原 DPI 1600、五档、1000 Hz、休眠 300 秒与阈值原始值 77 在无线单次读取中保持一致。

## 小组件与连接反馈更新

- 菜单栏面板直接提供 DPI、切换/编辑/增减档位、回报率及电源控制，灯光和滚轮分区按能力显示。
- 模拟界面生成 22 张截图（11 种状态 × 深浅色），包括展开档位、电源与灯光。模拟截图不表示硬件写入已验收。
- IOKit `IOServiceAddMatchingNotification` 监听 Razer HID 服务加入/移除，150 毫秒合并同次插拔产生的接口事件；忙碌时保留待刷新请求，不丢弃事件。
- 保留 5 秒枚举兜底，无线接收器用查询判断“暂未响应”；不能把接收器仍在 USB 列表等同于鼠标在线。电量显示按 60 秒刷新。
- 断开时保留并标记上次读数，停用面板写入；重连重新读取，不自动套用配置。
- 菜单栏无线 DPI、档位、回报率、休眠真实写入及回读已通过并恢复原设置；实际拔插到 UI 的延迟仍待现场验证。
- macOS 接口依据：[Apple IOServiceAddMatchingNotification](https://developer.apple.com/documentation/iokit/1514362-ioserviceaddmatchingnotification)。

## 每型号对照索引

运行能力与路由关联保留在 `crates/razer-core/src/catalog.json`、`recipes.json`，每个 profile 保留上游 PID 符号来源。表中向量数量记录发布前的本地对照结果；样本文件、生成工具和本机 build 报告不在公开仓库中。

| PID | 上游名称 | 控制项 | 向量数 | 硬件验证 |
| --- | --- | ---: | ---: | --- |
| `0x0013` | Razer Orochi 2011 | 10 | 30 | 缺少硬件验证 |
| `0x0015` | Razer Naga | 12 | 36 | 缺少硬件验证 |
| `0x0016` | Razer DeathAdder 3.5G | 10 | 30 | 缺少硬件验证 |
| `0x001f` | Razer Naga Epic | 14 | 40 | 缺少硬件验证 |
| `0x0020` | Razer Abyssus 1800 | 8 | 24 | 缺少硬件验证 |
| `0x0024` | Razer Mamba 2012 (Wired) | 14 | 40 | 缺少硬件验证 |
| `0x0025` | Razer Mamba 2012 (Wireless) | 14 | 40 | 缺少硬件验证 |
| `0x0029` | Razer DeathAdder 3.5G Black | 6 | 18 | 缺少硬件验证 |
| `0x002e` | Razer Naga 2012 | 12 | 36 | 缺少硬件验证 |
| `0x002f` | Razer Imperator 2012 | 10 | 30 | 缺少硬件验证 |
| `0x0032` | Razer Ouroboros | 13 | 38 | 缺少硬件验证 |
| `0x0034` | Razer Taipan | 10 | 30 | 缺少硬件验证 |
| `0x0036` | Razer Naga Hex (Red) | 10 | 30 | 缺少硬件验证 |
| `0x0037` | Razer DeathAdder 2013 | 14 | 38 | 缺少硬件验证 |
| `0x0038` | Razer DeathAdder 1800 | 8 | 24 | 缺少硬件验证 |
| `0x0039` | Razer Orochi 2013 | 8 | 24 | 缺少硬件验证 |
| `0x003e` | Razer Naga Epic Chroma | 20 | 58 | 缺少硬件验证 |
| `0x003f` | Razer Naga Epic Chroma Dock | 20 | 58 | 缺少硬件验证 |
| `0x0040` | Razer Naga 2014 | 12 | 36 | 缺少硬件验证 |
| `0x0041` | Razer Naga Hex | 10 | 30 | 缺少硬件验证 |
| `0x0042` | Razer Abyssus 2014 | 7 | 19 | 缺少硬件验证 |
| `0x0043` | Razer DeathAdder Chroma | 18 | 52 | 缺少硬件验证 |
| `0x0044` | Razer Mamba (Wired) | 19 | 54 | 缺少硬件验证 |
| `0x0045` | Razer Mamba (Wireless) | 21 | 59 | 缺少硬件验证 |
| `0x0046` | Razer Mamba Tournament Edition | 14 | 37 | 缺少硬件验证 |
| `0x0048` | Razer Orochi (Wired) | 16 | 49 | 缺少硬件验证 |
| `0x004c` | Razer Diamondback Chroma | 14 | 37 | 缺少硬件验证 |
| `0x004f` | Razer DeathAdder 2000 | 14 | 44 | 缺少硬件验证 |
| `0x0050` | Razer Naga Hex V2 | 26 | 75 | 缺少硬件验证 |
| `0x0053` | Razer Naga Chroma | 26 | 75 | 缺少硬件验证 |
| `0x0054` | Razer DeathAdder 3500 | 16 | 46 | 缺少硬件验证 |
| `0x0059` | Razer Lancehead (Wired) | 41 | 118 | 缺少硬件验证 |
| `0x005a` | Razer Lancehead (Wireless) | 43 | 123 | 缺少硬件验证 |
| `0x005b` | Razer Abyssus V2 | 18 | 52 | 缺少硬件验证 |
| `0x005c` | Razer DeathAdder Elite | 20 | 58 | 缺少硬件验证 |
| `0x005e` | Razer Abyssus 2000 | 8 | 24 | 缺少硬件验证 |
| `0x0060` | Razer Lancehead Tournament Edition | 37 | 108 | 缺少硬件验证 |
| `0x0062` | Razer Atheris (Receiver) | 11 | 32 | 缺少硬件验证 |
| `0x0064` | Razer Basilisk | 20 | 58 | 缺少硬件验证 |
| `0x0065` | Razer Basilisk Essential | 15 | 45 | 缺少硬件验证 |
| `0x0067` | Razer Naga Trinity | 8 | 24 | 缺少硬件验证 |
| `0x006a` | Razer Abyssus Elite (D.Va Edition) | 12 | 35 | 缺少硬件验证 |
| `0x006b` | Razer Abyssus Essential | 12 | 35 | 缺少硬件验证 |
| `0x006c` | Razer Mamba Elite | 36 | 104 | 缺少硬件验证 |
| `0x006e` | Razer DeathAdder Essential | 14 | 42 | 缺少硬件验证 |
| `0x006f` | Razer Lancehead Wireless (Receiver) | 43 | 123 | 缺少硬件验证 |
| `0x0070` | Razer Lancehead Wireless (Wired) | 41 | 118 | 缺少硬件验证 |
| `0x0071` | Razer DeathAdder Essential (White Edition) | 14 | 42 | 缺少硬件验证 |
| `0x0072` | Razer Mamba Wireless (Receiver) | 26 | 73 | 缺少硬件验证 |
| `0x0073` | Razer Mamba Wireless (Wired) | 24 | 68 | 缺少硬件验证 |
| `0x0077` | Razer Pro Click (Receiver) | 11 | 32 | 缺少硬件验证 |
| `0x0078` | Razer Viper | 15 | 45 | 缺少硬件验证 |
| `0x007a` | Razer Viper Ultimate (Wired) | 19 | 55 | 缺少硬件验证 |
| `0x007b` | Razer Viper Ultimate (Wireless) | 21 | 60 | 缺少硬件验证 |
| `0x007c` | Razer DeathAdder V2 Pro (Wired) | 19 | 55 | 缺少硬件验证 |
| `0x007d` | Razer DeathAdder V2 Pro (Wireless) | 21 | 60 | 缺少硬件验证 |
| `0x0080` | Razer Pro Click (Wired) | 11 | 32 | 缺少硬件验证 |
| `0x0083` | Razer Basilisk X HyperSpeed | 11 | 32 | 缺少硬件验证 |
| `0x0084` | Razer DeathAdder V2 | 20 | 58 | 缺少硬件验证 |
| `0x0085` | Razer Basilisk V2 | 20 | 58 | 缺少硬件验证 |
| `0x0086` | Razer Basilisk Ultimate (Wired) | 38 | 108 | 缺少硬件验证 |
| `0x0088` | Razer Basilisk Ultimate (Receiver) | 40 | 113 | 缺少硬件验证 |
| `0x008a` | Razer Viper Mini | 15 | 45 | 缺少硬件验证 |
| `0x008c` | Razer DeathAdder V2 Mini | 15 | 45 | 缺少硬件验证 |
| `0x008d` | Razer Naga Left-Handed Edition 2020 | 29 | 84 | 缺少硬件验证 |
| `0x008f` | Razer Naga Pro (Wired) | 33 | 95 | 缺少硬件验证 |
| `0x0090` | Razer Naga Pro (Wireless) | 35 | 100 | 缺少硬件验证 |
| `0x0091` | Razer Viper 8KHz | 13 | 39 | 缺少硬件验证 |
| `0x0094` | Razer Orochi V2 (Receiver) | 11 | 32 | 缺少硬件验证 |
| `0x0095` | Razer Orochi V2 (Bluetooth) | 11 | 32 | 缺少硬件验证 |
| `0x0096` | Razer Naga X | 23 | 68 | 缺少硬件验证 |
| `0x0098` | Razer DeathAdder Essential (2021) | 10 | 30 | 缺少硬件验证 |
| `0x0099` | Razer Basilisk V3 | 24 | 76 | 缺少硬件验证 |
| `0x009a` | Razer Pro Click Mini (Receiver) | 11 | 32 | 缺少硬件验证 |
| `0x009c` | Razer DeathAdder V2 X HyperSpeed | 11 | 32 | 缺少硬件验证 |
| `0x009e` | Razer Viper Mini Signature Edition (Wired) | 11 | 32 | 缺少硬件验证 |
| `0x009f` | Razer Viper Mini Signature Edition (Wireless) | 12 | 35 | 缺少硬件验证 |
| `0x00a1` | Razer DeathAdder V2 Lite | 15 | 45 | 缺少硬件验证 |
| `0x00a3` | Razer Cobra | 13 | 39 | 缺少硬件验证 |
| `0x00a5` | Razer Viper V2 Pro (Wired) | 11 | 32 | 缺少硬件验证 |
| `0x00a6` | Razer Viper V2 Pro (Wireless) | 11 | 32 | 缺少硬件验证 |
| `0x00a7` | Razer Naga V2 Pro (Wired) | 26 | 75 | 缺少硬件验证 |
| `0x00a8` | Razer Naga V2 Pro (Wireless) | 28 | 80 | 缺少硬件验证 |
| `0x00aa` | Razer Basilisk V3 Pro (Wired) | 31 | 95 | 缺少硬件验证 |
| `0x00ab` | Razer Basilisk V3 Pro (Wireless) | 31 | 95 | 缺少硬件验证 |
| `0x00af` | Razer Cobra Pro (Wired) | 26 | 77 | 缺少硬件验证 |
| `0x00b0` | Razer Cobra Pro (Wireless) | 26 | 77 | 缺少硬件验证 |
| `0x00b2` | Razer DeathAdder V3 | 7 | 22 | 缺少硬件验证 |
| `0x00b3` | Razer HyperPolling Wireless Dongle | 14 | 37 | 缺少硬件验证 |
| `0x00b4` | Razer Naga V2 HyperSpeed (Receiver) | 11 | 32 | 缺少硬件验证 |
| `0x00b6` | Razer DeathAdder V3 Pro (Wired) | 11 | 32 | 缺少硬件验证 |
| `0x00b7` | Razer DeathAdder V3 Pro (Wireless) | 11 | 32 | 缺少硬件验证 |
| `0x00b8` | Razer Viper V3 HyperSpeed | 11 | 32 | 缺少硬件验证 |
| `0x00b9` | Razer Basilisk V3 X HyperSpeed | 18 | 52 | 缺少硬件验证 |
| `0x00be` | Razer DeathAdder V4 Pro (Wired) | 11 | 32 | 有线 ABI 读取通过 |
| `0x00bf` | Razer DeathAdder V4 Pro (Wireless) | 11 | 32 | 无线菜单栏 DPI、档位、回报率、休眠写入与恢复回读通过；连续读取曾有超时 |
| `0x00c0` | Razer Viper V3 Pro (Wired) | 11 | 32 | 缺少硬件验证 |
| `0x00c1` | Razer Viper V3 Pro (Wireless) | 12 | 35 | 缺少硬件验证 |
| `0x00c2` | Razer DeathAdder V3 Pro (Wired) | 11 | 32 | 缺少硬件验证 |
| `0x00c3` | Razer DeathAdder V3 Pro (Wireless) | 11 | 32 | 缺少硬件验证 |
| `0x00c4` | Razer DeathAdder V3 HyperSpeed (Wired) | 11 | 32 | 缺少硬件验证 |
| `0x00c5` | Razer DeathAdder V3 HyperSpeed (Wireless) | 11 | 32 | 缺少硬件验证 |
| `0x00c7` | Razer Pro Click V2 Vertical Edition (Wired) | 16 | 47 | 缺少硬件验证 |
| `0x00c8` | Razer Pro Click V2 Vertical Edition (Wireless) | 16 | 47 | 缺少硬件验证 |
| `0x00cb` | Razer Basilisk V3 35K | 27 | 85 | 缺少硬件验证 |
| `0x00cc` | Razer Basilisk V3 Pro 35K (Wired) | 31 | 95 | 缺少硬件验证 |
| `0x00cd` | Razer Basilisk V3 Pro 35K (Wireless) | 31 | 95 | 缺少硬件验证 |
| `0x00d0` | Razer Pro Click V2 (Wired) | 16 | 47 | 缺少硬件验证 |
| `0x00d1` | Razer Pro Click V2 (Wireless) | 16 | 47 | 缺少硬件验证 |
| `0x00d3` | Razer Basilisk Mobile (Wired) | 14 | 41 | 缺少硬件验证 |
| `0x00d4` | Razer Basilisk Mobile (Receiver) | 14 | 41 | 缺少硬件验证 |
| `0x00d6` | Razer Basilisk V3 Pro 35K Phantom Green Edition (Wired) | 26 | 80 | 缺少硬件验证 |
| `0x00d7` | Razer Basilisk V3 Pro 35K Phantom Green Edition (Wireless) | 26 | 80 | 缺少硬件验证 |

## SVG 视觉与调节面板更新

原创应用图标、22 个线性图标和鼠标插画均保留 SVG 源码。正式应用通过资源目录加载矢量资产，AppKit 从 SVG 生成 ICNS。面板采用统一绿色强调、深浅色卡片、DPI 对数滑杆、回报率按钮和电源调节卡片。7 项 Rust 测试和 6 项 Swift 界面/交互逻辑测试通过，2 项硬件测试本轮未执行。生成 22 张模拟状态截图。新版安装包约 5.3 MB；之前的内存/CPU 测量属于此前版本，本轮未重测。新滑杆实机写入尚未验证。详情见 `design/README.md`、`build/svg-ui-report.json`。

## 主窗口重设计与真实菜单栏交互验收

2026-09-07：修复实际 MenuBarExtra 中 ScrollView 零高度，主窗口重做为 900×680 pt 侧栏与调节卡片。7 项 Rust、6 项 Swift 测试通过，硬件自动测试本轮跳过；生成 32 张模拟截图。另通过 CUA 在已安装应用的真实无线 V4 Pro 小组件中完成 DPI、档位、回报率、休眠时间的写入、回读和恢复，以及无效输入回退。雷云临时退出后已重新启动。精确值与验收边界见 `build/main-ui-report.json`。这次没有对滑杆拖动、插拔延迟、睡眠唤醒和其他型号作新增实机结论。

## 原生弹窗与软件扩展（2026-09-07）

菜单栏改用 NSStatusItem / NSPopover 和 AppKit 不透明根视图，避免旧 MenuBarExtra 宿主产生透明上下留白。安装版实际检查：无线常用、电源、展开档位、非法输入恢复和错误反馈，以及权限缺失状态；均未出现旧截图中的空白条。实拍在 build/screenshots/live-popover-*.png。深色及其他设备仍以模拟渲染为准。

已增加按键宏、本机倾斜附加动作、全灯区效果、显式多设备效果同步、序列号界面。Rust 提供来自上游能力表的 tiltSupported，系统输入由 Swift / IOKit 执行。宏未获得新的辅助功能权限，未执行合成输入实机测试；倾斜和多设备灯光缺少相应硬件。不能将这些软件界面及数据测试视为上游所有型号实机通过。此前性能数据早于这些扩展，不能作为新版测量值。
