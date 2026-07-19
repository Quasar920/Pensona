# 多币种账本 UI、交互与流畅度交接文档

更新时间：2026-07-17（续接更新）  
交接对象：下一位负责 SwiftUI / UI / 交互 / 性能的 Agent  
项目目录：`/Users/ian/长期需要/记账Vibe Coding`  
App 名称：多币种账本  
当前分支：`main`  
当前 HEAD：`669f9b2 docs: record iCost completion acceptance`

## 0. 先读结论

这个项目不是要做一个“玻璃越多越高级”的记账 App。最终体验应当是：内容安静、结构清楚、操作像轻薄透明玻璃浮在内容之上；按下立即有反馈，滚动、切页、开关 Sheet 和资产卡转场都跟手；任何 UI 改动都不能破坏钱包余额、预算、统计、退款、报销、AA、备份或迁移的账务语义。

2026-07-17 续接过程中，最新专项的源码实现已经落地，但尚未完成最终视觉、全量测试和真机性能验收。下一位 Agent 的第一优先级不再是重写圆形入口，而是验证当前增量、补齐未完成证据，再继续后续结构优化：

1. 在 iOS 26.5 / iOS 27 实机或稳定 Simulator 上验证 56pt 蓝色圆钮的位置、Tab Bar 最小化、详情隐藏、返回恢复和最后内容避让。
2. 对当前最终集成状态重新执行 generic Debug、generic Release、`build-for-testing` 和完整 143 项单元测试。
3. 完成尚未复跑的 AA 回滚用例，确认本轮 `LedgerService` 交易快照恢复没有引入新回归。
4. 用 Release 真机和 Instruments 验证圆钮、记账 Sheet、分类横滑、月份切换、资产 zoom 与报表范围切换；不能把 Debug Simulator 的观感当性能结论。
5. 上述基线稳定后，再进入流水分页/系统 swipe、报表后台聚合、附件缩略图、导入/同步主线程治理等 P1。

### 0.1 当前最新实现状态

| 范围 | 当前状态 | 已有证据 | 仍缺什么 |
| --- | --- | --- | --- |
| 根级圆形记账入口 | 源码已完成 | accessory/placement 已移除；56pt overlay、单一 presentation、按 Tab 可见性 Preference、快速连点保护已编译 | iOS 26.5/27 截图、命中、Tab Bar 最小化和详情往返人工验收 |
| 高频按压与记账分类 | 源码已完成 | 120ms/100ms strong ease-out；Reduce Motion 只透明度；主/子分类 `LazyHStack`、去逐卡阴影；7/7 相关测试通过 | 真机按压手感和首次 Sheet 帧稳定性 |
| 月份切换 | 源码已完成 | `selectedMonth` 已直接更新，不再包整页 `withAnimation`；generic Debug 编译通过 | Release trace 与连续月份切换录屏 |
| MoneyFormatter | 源码已完成 | 按线程、Locale、币种、样式和精度复用 formatter；Locale/并发测试包含在 7/7 通过结果中 | 压力数据下 Allocations / Time Profiler 对比 |
| 资产环境订阅 | 源码已完成 | 已用 iOS 26.4+ 窄环境 reader；旧系统走 UIKit fallback；不再 `@Environment(\.self)` | 四 Tab 连切和 zoom/cross-fade A/B |
| 原 5 个单测失败 | 部分修复、部分验证 | CSV 3/3、AppLock 2/2、LedgerScope 2/2 已在独立 iOS 26.5 设备通过 | AA 回滚用例、完整 143 项、最终 coverage 收尾 |

视觉验证未完成的原因不是代码已证明正确，而是临时 iOS 26.5 Simulator 首次启动卡在 `CoreLocationMigrator`，App 未成功安装。因此文档将根入口标记为“源码完成、视觉待验收”，不能直接宣称 UI 已完成。

最重要的交接警告：当前工作区有大规模未提交改动。不要执行 `git reset --hard`、`git checkout -- .`、`git clean`，不要从 HEAD 整文件覆盖当前实现，也不要为了“整理”而删除未跟踪文件。

## 1. 文档优先级与冲突处理

仓库里有多轮设计稿，部分内容互相覆盖。遇到冲突时按“更具体、更新、且明确记录用户决定”的原则处理，优先级如下：

| 优先级 | 文档 | 有效范围 |
| --- | --- | --- |
| 1 | 本交接文档 | 汇总后的当前有效决策、现状差距与执行顺序 |
| 2 | `docs/superpowers/specs/2026-07-17-circular-entry-and-jank-reduction-design.md` | 最新记账入口与当前卡顿治理；覆盖第三版稿中的底部 accessory 方案 |
| 3 | `animation-plans/001-replicate-asset-card-motion.md` | 资产卡横滑、按压、系统 zoom、Reduce Motion；是资产动效的专项基线 |
| 4 | `docs/superpowers/specs/2026-07-17-ios27-liquid-glass-app-redesign-design.md` | 全应用信息架构、三层视觉系统、导航、无障碍、性能总原则；文件状态仍是“待用户复核”，只把其中未被专项稿覆盖的原则作为长期基线 |
| 5 | `docs/superpowers/specs/2026-07-17-aa-split-design.md` | AA 分摊和收款的产品、UI 与账务规则 |
| 6 | `docs/superpowers/specs/2026-07-16-secondary-interaction-ui-redesign-design.md` | 记一笔、详情、预算、存钱目标和标签移除的详细交互 |
| 7 | 更早的 spec、`design-qa.md`、`.build/qa-*` 截图 | 历史背景和已验证的旧状态，不是当前像素级真值 |

当前可直接执行的冲突解释：

- 全局第三版稿原先指定 `tabViewBottomAccessory`；最新专项稿已经明确否决。最终目标是右下角 56pt 圆形 overlay。
- 全局第三版稿曾写“原生数字输入”；更早的已确认决定是页面内固定数字键盘，最新专项又明确“本轮不重做记账表单”。因此本轮及近期收敛的执行目标是保留固定数字键盘，只做性能和一致性优化。若以后要完成全表单重构，必须先让用户重新确认是否切换系统键盘。
- 第三版稿曾提出资产账户分组连续列表；用户后续针对资产卡录屏确认了横向银行卡条和卡片身份转场。资产页以 `animation-plans/001` 为准：平面横向卡条、150×190pt、24pt 间距、系统 zoom。
- 旧稿把很多内容卡称为“玻璃卡”。第三版后来明确：内容表面不是 Liquid Glass。当前 `ledgerGlassCard` 已只是 `ledgerContentSurface` 的兼容别名；新代码不要继续扩大这个旧命名。

仍需在扩大范围前确认的一项产品分歧：2026-07-16 的已确认二级页面稿要求资产详情只保留银行卡身份卡和交易，不恢复“卡片管理/添加币种”等区域；2026-07-17 的待复核全局稿又提到币种钱包和对账信息。当前安全基线是维持“身份卡 + 交易”的极简详情，并且绝不恢复旧快捷按钮或大管理区。若用户确认确实需要钱包/对账，则把它们加入安静的普通内容分组或工具栏菜单，而不是重新做一排快捷卡。

## 2. 当前仓库与构建基线

### 2.1 技术栈

- 原生 SwiftUI + SwiftData。
- Xcode 27 beta SDK，项目最低系统版本已改为 iOS 26.0。
- Swift language version 5。
- 无第三方 Swift Package 依赖。
- App target：`MultiCurrencyLedger`。
- Unit test target：`MultiCurrencyLedgerTests`。
- Bundle ID：`com.ian.MultiCurrencyLedger`。
- URL Scheme：`multiledger://entry`。
- 当前仅声明 iPhone 竖屏。

主要入口：

- App 启动：`MultiCurrencyLedger/App/MultiCurrencyLedgerApp.swift`
- 根导航：`MultiCurrencyLedger/App/RootTabView.swift`
- SwiftData 容器与迁移：`MultiCurrencyLedger/App/AppModelContainer.swift`、`MultiCurrencyLedger/App/LedgerSchema.swift`
- 共享视觉组件：`MultiCurrencyLedger/Views/LedgerGlassComponents.swift`
- 流水：`MultiCurrencyLedger/Views/Home/HomeView.swift`
- 资产：`MultiCurrencyLedger/Views/Accounts/AccountListView.swift`
- 计划：`MultiCurrencyLedger/Views/Savings/SavingsGoalViews.swift`
- 报表：`MultiCurrencyLedger/Views/Transactions/ReportsAndCalendarView.swift`
- 记一笔：`MultiCurrencyLedger/Views/Entry/UnifiedEntryView.swift`、`TransactionFormSections.swift`
- 交易详情与编辑：`MultiCurrencyLedger/Views/Transactions/TransactionDetailView.swift`、`UnifiedTransactionEditView.swift`
- AA：`MultiCurrencyLedger/Views/Transactions/AASplitViews.swift`
- 设置：`MultiCurrencyLedger/Views/Settings/SettingsView.swift`

容易误判的文件名与旧页面：

- 真正的全局新建 `EntryView` 定义在 `Views/Entry/UnifiedEntryView.swift`；`Views/Entry/EntryView.swift` 主要是首页月预算仪表盘/预算编辑内容。
- `SavingsGoalListView` 实际承载“计划”Tab；旧 enum/命名中的 `savings` 不代表一级导航仍叫“存钱”。
- `TransactionFormSections` 仍被交易编辑和周期规则编辑复用；不能因为新建页用了 `EntryComposerView` 就直接删除旧 section。
- `AccountDetailView` 和 `MonthTransactionListView` 当前可能没有活跃导航引用。先用 `rg` 核实调用，再决定保留、接回或删除；不要把它们误当成用户此刻看到的页面。
- `ledgerGlassCard` 是过时兼容命名，实际落到实体内容表面；看到名字不能据此再套一层 Liquid Glass。

### 2.2 工作区状态

续接更新时，`git status --porcelain` 有 84 项：67 个已跟踪修改、2 个已跟踪删除、15 个未跟踪路径。已跟踪 diff 约为 5,047 行新增、1,832 行删除；本交接文档本身仍是未跟踪文件。

这批未提交工作同时包含：

- iOS 26 / Liquid Glass 根架构；
- 首页、资产、计划、报表和详情的大规模 UI 重构；
- 标签功能从产品界面移除；
- 银行卡后四位识别；
- AA 分摊与收款；
- Schema、备份、云同步、账务服务及大量测试调整。

本次续接新增/继续修改的重点文件如下，下一 Agent 必须先看 scoped diff：

- 根入口与显隐：`App/RootTabView.swift`、`HomeView.swift`、`AccountListView.swift`、`SavingsGoalViews.swift`、`ReportsAndCalendarView.swift`。
- 记账卡顿：`Views/LedgerGlassComponents.swift`、`Views/Entry/TransactionFormSections.swift`。
- Formatter：`Utilities/MoneyFormatter.swift`、`MultiCurrencyLedgerTests/CurrencySupportTests.swift`。
- 测试断点修复：`Services/SpreadsheetImportDecoder.swift`、`Models/LedgerScope.swift`、`Services/LedgerService.swift`、`Services/AppLockService.swift`。

不要把它当作可以丢弃的临时工作。开始任何修改前先执行：

```sh
git status --short --branch
git diff --stat
git diff -- MultiCurrencyLedger/App/RootTabView.swift
```

只修改当前任务必需的文件；若某文件已有大段用户改动，使用小块 patch，不要整文件替换。

### 2.3 本次交接已验证的机械基线

初始审阅阶段曾通过 generic Debug、generic Release 和 Debug `build-for-testing`，测试源码中共有 143 个 `test...` 方法。随后在 iPhone 17 Pro / iOS 26.5 Simulator 实际执行全量测试，测试阶段约 94.17 秒，结果为 **143 项中 138 通过、5 个不同用例失败、0 跳过**；coverage 合并/收尾随后卡住。原始失败为：

- `TransactionImportServiceTests.testCSVDecoderHandlesQuotedCommasAndNewlines`：抛出 `emptyFile`；根因是 CRLF 在 `Character` 层可能是一个 newline grapheme，旧代码只分别比较 `"\r"` / `"\n"`。
- `LedgerScopeTests.testScopeKeepsTransactionsAndBudgetsInTheSameBookMonthAndCurrency`：下月 00:00 交易错误进入本月结果。
- `LedgerScopeTests.testScopeIncludesDestinationBookForTransfersAndExcludesMonthBoundary`：本应排除的下月边界转账仍返回 true；根因是 `DateInterval.contains` 的端点语义不符合这里需要的半开月份区间。
- `AASplitFeatureTests.testCollectedAmountCapsLaterSplitEdits`：校验失败后 `expense.sourceWallet` 仍指向替换草稿的钱包，说明 `context.rollback()` 没有自动恢复所有内存关系字段。
- `AppLockServiceTests.testPasswordLifecycleUsesIsolatedKeychainItem`：初始 `hasCredential` 错误为 true，随后抛 `wrongPassword`；旧实现把除 item-not-found 之外的任何 Keychain 状态都当成“已配置”。

续接过程中已写入四项最小修复：

- CSV：将 CRLF grapheme 的判断改为 `Character.isNewline`。
- LedgerScope：月份区间改为 `[start, end)`，不再把下月 00:00 算入本月。
- LedgerService：编辑失败时恢复完整交易字段/关系和钱包快照，修复 AA 校验失败后来源钱包引用未回滚。
- AppLock：明确区分 Keychain success / item-not-found / 其他 OSStatus，避免把环境错误误判成“已设置密码”。

修复后已经独立通过：

- `TransactionFormStateTests` 3/3。
- `CurrencySupportTests` 4/4。
- `TransactionImportServiceTests` 3/3，xcresult：`.build/test-results/csv-after-20260717-1856.xcresult`。
- `AppLockServiceTests` 2/2，xcresult：`.build/test-results/app-lock-clean-after-20260717-1900.xcresult`。
- `LedgerScopeTests` 2/2，xcresult：`.build/test-results/ledger-scope-after-20260717-1901.xcresult`。

仍不能声称“全绿”：`AASplitFeatureTests.testCollectedAmountCapsLaterSplitEdits` 在修复后尚未复跑，完整 143 项也未重跑；最终服务修复加入后尚未重新执行完整 generic Debug / Release。当前准确基线是：**P0 UI 集成态曾 generic Debug 成功，若干定向测试已通过，但当前最终工作树仍需要一次完整构建和全量测试。**

推荐构建命令：

```sh
MCL_DERIVED_DIR="$(mktemp -d /tmp/mcl-build.XXXXXX)"
xcodebuild \
  -project MultiCurrencyLedger.xcodeproj \
  -scheme MultiCurrencyLedger \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$MCL_DERIVED_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Release 只需把 `Debug` 改成 `Release`。测试目标编译使用 `build-for-testing`。

## 3. 产品体验北极星

用户希望这个 App 第一眼具备四个特征：

1. 简单易读，不需要先理解复杂金融术语。
2. 交互人性化，高频路径短，状态不会突然丢失。
3. 有 iOS 26/27 Liquid Glass 气质，但不是全屏堆材质。
4. 操作丝滑、跟手，没有可感知的按压迟钝、滚动掉帧、转场卡点或布局抖动。

视觉一句话：**内容安静，操作透明；金额清楚，装饰克制。**

交互一句话：**用户做出动作后立刻看到因果反馈，系统手势永远可中断，不靠延迟任务“等动画结束”。**

工程一句话：**UI 只编辑状态和发出意图，余额与账务写入必须继续由 Service 原子完成。**

## 4. 最终信息架构

根级使用四个原生系统 Tab，每个 Tab 保留自己的 `NavigationStack` 状态：

1. **流水**：月份摘要、交易、搜索、筛选、交易详情。
2. **资产**：总资产、账户卡、账户详情、账户相关交易、对账状态。
3. **计划**：预算、存钱目标、周期记账、分期计划。
4. **报表**：收支趋势、分类构成、日期范围、日历、资产变化解释。

全局“记一笔”不是第五个 Tab。它是覆盖在四个根页面右下角的唯一主操作。

页面标题永远描述当前位置，例如“流水”“资产”“计划”“报表”。账本名称是作用域选择器，不拿账本名替代页面标题。当前代码通过各页 `@AppStorage("selectedBookID")` 共享 ID，但最终应逐步收敛为单一共享账本作用域，避免每页复制选择和校验逻辑。

### 4.1 导航语义

- 详情阅读：系统导航 push。
- 新建或复杂编辑：带独立导航栈的 Sheet。
- 单一选择：Menu、Popover 或半屏 Sheet。
- 需要对比多个选项：可搜索半屏 Sheet。
- 删除、永久清空、回滚余额等破坏性动作：系统确认。
- 普通返回、切换、空表单取消：不弹阻断确认。
- 只有确实存在有效未保存内容时，才询问是否放弃。
- 系统 back、边缘返回、Sheet 下拉和 Tab 切换不叠加自定义导航动画。

## 5. 全局视觉系统

### 5.1 三层结构

#### 内容底层

- 静态、自适应冷灰/系统分组背景。
- 不使用持续移动渐变、全屏动态模糊、大半径实时模糊或循环装饰动画。
- 浅色和深色都使用语义颜色；不要硬编码纯白作为全屏背景。

#### 内容层

- 交易、账户信息、预算、目标、图表、表单分组使用安静的实体或分组内容表面。
- 内容表面只负责分组，不伪装成悬浮按钮。
- 一个区域可以有一个大摘要，但不要在摘要里继续嵌套多层玻璃卡。
- 长列表行不使用实时 Liquid Glass。

#### 功能层

- Tab Bar、toolbar、浮动主按钮、菜单、瞬时操作组和 Sheet chrome 使用系统 Liquid Glass。
- 相邻自定义玻璃操作放进同一个 `GlassEffectContainer`，减少重复采样并保持自然形变。
- 禁止玻璃套玻璃、玻璃上再叠半透明白板。

### 5.2 色彩

- `HomePalette.accent` 的蓝色是唯一品牌主交互色。最新专项要求保留本 App 的蓝色，不复制 iCost 黄色。
- 金额默认使用 `.primary`，不因为收入/支出直接变绿/红。
- 红色只用于欠款、风险、错误、超支或破坏性动作。
- 绿色只用于成功、完成、健康状态。
- 分类色只用于 SF Symbol、圆点或非常轻的识别提示，不染满整张卡。
- 同一屏不要出现多套相近蓝色。

### 5.3 字体与金额

- 优先使用 Dynamic Type 语义样式，而不是到处硬编码字号。
- 页面大标题左对齐；每页只允许一个展示级核心数字。
- 所有金额使用等宽数字，币种与数值基线清楚。
- 大字号下允许内容纵向增长，不以截断、过度缩小或固定 80pt 行高维持旧布局。
- 账户名、关键金额、校验错误不能被省略成无法理解的文本。

### 5.4 形状、间距与命中

- 命中区域至少 44×44pt。
- 圆形主按钮视觉直径 56pt。
- 页面水平边距目前主要为 18–20pt；继续保持一致，不新增随机边距。
- 内容圆角应收敛到少量语义层级：紧凑控件、标准内容表面、大摘要。资产卡源圆角固定约 23pt。
- 新组件必须复用共享 modifier/token，不自行拼白色覆盖、渐变描边、双阴影。

## 6. 根级导航与全局记账按钮

### 6.1 当前实现

这一专项现已写入源码：

- `RootTabView` 已删除 `.tabViewBottomAccessory`、`RootEntryAccessory` 和 `tabViewBottomAccessoryPlacement`。
- 根 overlay 现在放置固定 56pt 蓝色圆钮，使用容器尺寸、安全区、49pt 系统 Tab Bar 内容高度和 18pt 间距定位，不写死具体机型屏幕高度。
- `RootPresentationState.presentNewEntry()` 增加 `entry == nil` 保护，快速连点不会创建第二个 route。
- `RootEntryVisibilityPreferenceKey` 使用按 Tab 映射；根只读取当前 `selection`，后台 Tab 的详情路径不会影响当前按钮。
- 流水交易详情、资产卡/资产交易详情、存钱目标详情均上报 hidden。
- 四个根 ScrollView 使用共享 86pt 尾部滚动净空，最后内容可以滚过圆钮；它不是 `safeAreaInset`，不会压缩 viewport。

机械编译已通过；真实位置、最小化 Tab Bar 和详情往返尚未取得截图/录屏。因此这是“实现完成、人工验收未完成”，不要重复重写，也不要直接标为发布完成。

### 6.2 目标实现

布局关系示意（不是像素稿）：

```text
┌──────────────────────────────────────┐
│ 流水                         账本 ▾  │
│                                      │
│ 月份摘要 / 当前页面内容              │
│                                      │
│ 可滚动内容                           │
│                               ┌────┐ │
│                               │ ＋ │ │  56pt 圆形主按钮
│                               └────┘ │  右 20pt / Tab Bar 上 18pt
├──────────────────────────────────────┤
│   流水       资产       计划       报表 │  四个等宽系统 Tab
└──────────────────────────────────────┘
```

- 删除 `.tabViewBottomAccessory` 和 `tabViewBottomAccessoryPlacement` 依赖。
- 在根视图 overlay 中放置固定圆形按钮；它不参与内容布局。
- 视觉直径 56pt，右边距 20pt，位于可见 Tab Bar 上方 18pt。
- 白色粗体 `plus`，背景使用唯一蓝色品牌强调色；视觉和命中形状都为 `Circle`。
- 按钮只调用已有 `RootPresentationState.presentNewEntry()`。
- 保留 `RootEntryPresenter` 和现有 `EntryView` Sheet；不要增加第二个 `showingEntry` 布尔状态。
- 不实现长按模板、语音入口、中间凸起 Tab 或 iCost 黄色样式。
- VoiceOver label：“记一笔”；hint：“新建一笔交易”。
- 四个根 Tab 显示按钮；隐藏 Tab Bar 的详情页必须同时隐藏按钮。
- 通过“按 Tab 标识的可见性 Preference”把当前 Tab 的根/详情可见状态上报给根容器。根容器只读当前选中 Tab 的值，后台 Tab 的导航路径不能误隐藏当前按钮。
- 横竖安全区变化只改变定位，不改变按钮尺寸；不要读固定屏幕高度。

### 6.3 按压反馈

- 按下曲线约 120ms，释放约 100ms。
- 正常模式可使用轻微中心缩放；不能等待 0.34s 弹簧才显得“按下”。
- Reduce Motion 下取消缩放，只做短透明度变化。
- 几何尺寸、文字和玻璃类型在滚动过程中保持不变。

### 6.4 验收

- 根页面底部不再出现独立附件行。
- 四个 Tab 等宽、命中不被圆钮侵占。
- 连续向下滚动触发 Tab Bar 最小化时，圆钮不改宽、不换文案、不跳动。
- 快速点击不会叠出两个 Sheet。
- 进入交易/资产/目标详情时按钮消失，返回根页时稳定恢复，无延迟任务。

当前验收状态：前述结构均已在源码存在并通过 generic Debug 编译；以上五项仍需在稳定的 iOS 26.5/27 设备逐项人工验证，特别是 49pt Tab Bar 内容高度在常规/最小化形态下的视觉距离。

## 7. 流水页

### 7.1 用户需要看到什么

- 顶部是紧凑的月份收支/预算摘要，不把所有财务指标同时放成大卡。
- AA 待收有紧凑入口：金额、未结清笔数、进入总览。
- 月份切换是一个共享玻璃操作组。
- 交易按日期分组；日期标题显示当日收入和支出摘要。
- 单行只保留：分类图标、商户/名称、分类与时间、金额。
- 金额中性色；图标可保留分类色。
- 搜索和筛选属于流水工具栏，作用域与当前账本、月份一致。

### 7.2 当前实现与差距

- `HomeView.swift:11-18` 在页面边界查询全部交易、汇率、预算、关系和 AA 数据。
- `HomeView.swift:49-73` 在 computed property 中全量过滤并同步计算月摘要。
- 首页只展示当月前 6 条交易，见 `recentDayGroups` 的 `prefix(6)`；搜索入口打开完整 `TransactionListView`。
- 当前使用 `ScrollView + LazyVStack`、每条 80pt 自定义卡和自定义横滑容器。
- 月份切换的整页 `withAnimation` 已移除，`selectedMonth` 现在直接更新；数字/进度仍可保留局部 transition。仍需用 Release 连续切月验证没有聚合长帧。
- `HomeView.swift:576-667` 自定义滑动依赖固定 action 宽度与手工 offset；早期设计允许这样做，但第三版最终方向是高性能系统 List / `swipeActions`。

### 7.3 执行顺序

不要把“圆形入口修复”和“流水改成系统 List”塞进同一个大改动。

短期性能修复：

- 月份改变直接更新状态，数字/进度使用局部 `contentTransition`；不要让整页隐式动画。
- 继续保持稳定 ID。
- 滚动期间不要重新做汇率、预算、报表全量聚合。
- 减少每行阴影和透明层。

后续结构收敛：

- 对长流水使用系统 `List` 或真正惰性、可分页的容器。
- 优先使用系统 `swipeActions`，并提供同名 VoiceOver 动作。
- 移除固定 80pt 行高对大字体的限制。
- 让完整月份记录可浏览，而不是首页数据量永远固定为 6 条；若保留“摘要首页 + 全部流水”两层，应在产品文案和入口上明确。

### 7.4 状态

- 当前月无记录：“还没有记账记录”，提供添加动作。
- 历史月无记录：“当月没有记录”，建议切换月份。
- 未来月无记录：“这个月还没有记录”，不伪造可记账内容。
- 缺汇率时不能默默漏算；显示缺失币种并提供可行动入口。
- 删除失败保留行；删除成功由 SwiftData 查询刷新汇总。

## 8. 资产页与资产卡动效

资产页是全局“内容安静”原则下的一个明确例外：银行卡式身份视觉和卡片到详情的身份转场已经被用户单独确认，应保留。

### 8.1 有效视觉与交互基线

- 顶部只显示一个总资产核心数字、基准币种和隐私开关。
- 隐藏余额时，总资产、卡片金额、相关小计都不能泄露真实值；VoiceOver 也不得朗读真实金额。
- 资产卡横向条使用 `LazyHStack`，约 150×190pt，间距 24pt。
- 卡条作为一个平面随手势移动，不给每张卡加滚动缩放、淡出、旋转、模糊或自动轮播。
- 保留 `.scrollTargetLayout()` 和 `.scrollTargetBehavior(.viewAligned)` 的原生惯性与吸附。
- 点击卡片使用 `matchedTransitionSource` + `.navigationTransition(.zoom(...))`，保留系统可逆边缘返回。
- 正常按压：约 0.96 中心缩放，120ms 强 ease-out，不能大幅变暗。
- Reduce Motion / Prefer Cross-Fade：iOS 27 使用系统 cross-fade；iOS 26 交给 `.automatic`。Reduce Motion 的卡片按压只改变透明度。
- 快速双击只允许 push 一个详情；当前 `guard detailPath.isEmpty` 已实现，应保留。

### 8.2 当前性能问题

资产页的宽环境订阅已经修复：iOS 26.4+ 通过小型 `AccessibilityCrossFadeEnvironmentReader` 只读取 `accessibilityPrefersCrossFadeTransitions`，更早系统走 `UIAccessibility.prefersCrossFadeTransitions`；根 `AccountListView` 不再使用 `@Environment(\.self)`。下一步是用四 Tab 连切与 zoom/cross-fade A/B 证明重算和 hitch 确实下降。

资产估值和每卡估值目前由 computed property 同步计算。先用 Instruments 证明热点，再做缓存；不要无证据重写 SwiftData 架构，也不要为了性能破坏系统 zoom。

当前根页只把前 8 个账户送进卡条。如果产品允许超过 8 个账户，最终必须去掉这个不可见截断，或提供明确的“全部账户”入口；第 9 个账户以后不能成为用户无法到达的数据。

### 8.3 详情页

- 顶部仍是一张对应账户的银行卡式身份卡，只显示账户名、当前账户金额/估值、掩码后四位。
- 不恢复“记一笔”“添加币种”“收付款码”、卡片管理区或非接触信号图标。
- 下方直接显示这张卡相关的全部收入、支出、转账、换汇，按日期倒序。
- 空账户使用简单空状态，不塞快捷入口。
- 银行卡后四位只保存 4 位字符串，支持前导零；未填显示全掩码。永远不保存完整卡号。

当前交付基线维持上面的极简结构。待复核全局稿里提过“币种钱包与对账信息”，但它与已确认的“移除管理区”存在范围冲突。若后续经用户确认要增加，必须使用普通内容分组或工具栏菜单，并与交易列表保持清楚层级；不得恢复旧版快捷按钮阵列、大号“卡片管理”区域或把“添加币种”塞进空状态。

### 8.4 转场 A/B 原则

不要看到卡顿就先删除 zoom。先在相同 Release 构建、相同数据和设备上对 `.automatic` / cross-fade / zoom 做 A/B。只有证据表明 zoom 是剩余 hitch 的来源时，才调整默认策略。

## 9. 计划页

首屏按“状态摘要而不是管理表单”组织四个模块：

1. 本月预算。
2. 存钱目标。
3. 周期记账。
4. 分期计划。

当前 `SavingsGoalListView` 已有预算/周期/分期三项快速入口、存钱分配摘要、进行中/已完成分段和目标卡，属于部分完成。后续应：

- 让每个模块只显示状态、关键金额和最近动作，点入完整管理页。
- 工具栏新建菜单根据当前模块提供明确动作，避免两个含义不明的同级加号。
- 预算超支、目标逾期、周期任务失败才用警示色；普通金额保持中性。
- 目标详情顶部显示目标名、已存、目标金额、剩余、预计完成时间。
- “存入/取出”是目标规划分配，不自动改变钱包余额；页面必须明确说明。
- 分配历史按时间排列，删除要确认。
- 编辑、暂停、完成、归档进入更多菜单。

当前页面仍在多个 computed property 中同步过滤 goal/allocation/account 数据。数据量放大后需测量并缓存，但不能把“存钱分配不改余额”的业务语义改掉。

## 10. 报表页

### 10.1 目标

- 时间范围和账本范围使用清晰的系统控制。
- 收支趋势、分类构成、日历、资产变化解释有明确分段。
- 图表放在安静内容表面，不嵌套多层玻璃。
- 图形必须同时提供可读数字摘要，不依赖颜色传达。
- 动画只在首次进入或范围真正变化时发生；滚动不重复入场。

### 10.2 当前风险

`ReportsAndCalendarView.swift:53-98` 定义三组同步聚合；`body` 在 144-153 行直接读取 trend、breakdown、previousTrend 并生成 slices。任何相关 State、Environment 或 Query 更新都可能在主线程重复过滤、汇率转换和构图。

后续应把输入收敛为不可变 scope key，并使用可取消任务和结果缓存：

- 输入：bookID、日期区间、metric、granularity、dimension、数据版本。
- 输出：趋势、构成、上期对比、缺失汇率。
- 新范围到来时取消旧计算；旧结果不得晚到覆盖新范围。
- 滚动位置变化不能触发聚合。
- 小数据可同步显示，长计算显示占据相近空间的 loading，不让页面跳动。

不要先引入新的全局状态框架；先把聚合从 `body` 热路径移开并测量。

`ReportPalette.ink` / `secondaryInk` 目前使用固定深色 RGB，深色模式存在对比度不足风险。改为 `.primary`、`.secondary` 等语义色，并验证 Increase Contrast；红绿图形不能是唯一的信息通道。

## 11. “记一笔”交互

### 11.1 当前有效页面结构

保留页面内固定数字键盘。打开后用户无需先点 TextField 就能立即输入。顺序是：

1. 关闭、标题、模板入口。
2. 支出、收入、转账、换汇、调整类型切换。
3. 主分类横向区域；有子分类时在下方展开。
4. 分类路径、币种和唯一大金额。
5. 账户、日期、“更多”上下文栏。
6. 固定数字键盘。
7. 低强调“下一笔”和唯一高强调“完成”。

常用路径必须在常见 iPhone 宽度和默认字号下无需滚动；大字体时允许合理滚动，不能通过截断维持假象。

### 11.2 类型与分类

- 支出/收入显示分类。
- 转账显示转出、转入和方向关系。
- 换汇保留换出、换入、实际汇率和手续费规则。
- 调整显示方向、账户、原因。
- 切类型时保留仍合法的账户，清理不兼容字段。
- 主分类可以直接保存；子分类显示“主分类 / 子分类”。
- 展开只用 transform + opacity，无连接线、轨迹和装饰动画。
- Reduce Motion 只淡入。

### 11.3 当前性能修复要求

本节的直接渲染修复已经写入源码：主分类和子分类均使用 `LazyHStack`，避免首次 Sheet 构建全部卡片。

主/子分类重复卡当前已经：

- 只保留轻量填充和描边。
- 移除逐卡阴影和无必要材质采样。
- 选中态使用蓝色细描边和轻填充；原先 `-2pt` 选中位移已删除。
- 不让每张分类卡独占一个昂贵实时玻璃层。

`LedgerGlassPressStyle`、记账主/次按钮现已使用独立 `timingCurve(0.23, 1, 0.32, 1)`：按下 120ms、释放 100ms；`LedgerMotion.responsive = 0.34` 保持不变。Reduce Motion 下 scale 恒为 1，仅保留短透明度反馈。相关表单与 Formatter 测试已 7/7 通过，但真实按压手感仍需真机验收。

### 11.4 数字键盘

- 支持 0–9、小数点、删除、清空、加法、减法和 `00`。
- 币种精度必须遵守 `SupportedCurrency.fractionDigits`。
- 不完整表达式、重复运算符等错误就地提示；不能悄悄改值。
- 不要为每个数字键触发明显重复触觉。
- 按压立即反馈，视觉与轻量触觉发生在同一因果事件。

### 11.5 账户、日期和更多

- 账户选择用半屏，可搜索；行显示账户、类型、币种和余额。
- 转账/换汇只显示合法目标；无合法目标时解释原因。
- 日期弹层提供日期、时间、“回到现在”；取消不修改原值。
- 更多信息包含商户/对方、备注、图片、组合付款、优惠、手续费、报销、AA。
- 已填写内容必须在快速路径中显示摘要，不能因收起而看似丢失。
- 标签入口永远不存在。

### 11.6 保存与错误

- “完成”成功后关闭当前记账 Sheet。
- “下一笔”成功后保留账本、类型、合法账户和分类；清空金额、商户、备注、图片及类型专属临时值。
- 保存期间只防重复提交，不冻结整页。
- 负余额确认完成前不关闭、不重置。
- 校验、数据库、余额更新失败保留全部输入。
- 保存成功时视觉和触觉同刻发生。
- 没有账户时明确提示先创建账户，不能显示一个看似可保存的空表单。

当前实现尚未建立明确的 `isSaving` 防重复提交状态，也没有对有效脏草稿做离开确认；这两项属于必须补齐的交互缺口。防重复只能锁保存动作，不能把整个页面冻结。与此同时，当前支出类型和主完成按钮会使用支出红色，需收敛为品牌蓝主操作；红色保留给校验、风险和破坏性动作。

## 12. 交易详情与编辑

目标结构统一为：顶部摘要 + 内容分组 + 底部/工具栏操作。

- 摘要属于内容层，不是实时玻璃。
- 显示分类路径、金额、类型、日期、账户关系。
- 金额构成显示组合付款、手续费、原价、优惠。
- 备注只在有内容时出现。
- 图片横向缩略图可进入大图；添加和删除保留明确反馈。
- 退款/报销显示原金额、已处理、剩余可处理，不能只是孤立金额列表。
- “编辑”是主操作；复制、模板、退款、报销、AA、删除进更多菜单。
- 删除明确提示会回滚余额。

当前 `TransactionDetailView` 基本具备这些区块和底部玻璃操作栏，但有两个重要差距：

1. `TransactionEditView` 仍使用旧 `Form + TransactionFormSections`，没有真正复用 `EntryComposerView`，视觉与快速记账断层。
2. 详情页传入的编辑保存闭包会调用外层 `dismiss()`，导致编辑保存后可能退出详情。最终目标是只关闭编辑 Sheet，让详情原地随 SwiftData 刷新。

修复编辑路径时必须继续通过 `LedgerService.replaceTransaction` 原子回滚旧影响并应用新影响；不要为视觉一致直接改钱包余额。

## 13. AA 分摊与收款 UI

AA 是“我先垫付”的支出附属能力，不是群组账本或联系人系统。

### 13.1 入口

- 仅支出显示。
- 新建支出在“更多信息”中设置。
- 历史支出在详情更多菜单发起。
- 已设置时摘要：“我和其他 X 人 · 我的承担 ¥Y”。
- AA 与退款、报销互斥；收入、转账、换汇、调整不显示。

### 13.2 设置 Sheet

- 半屏可上拉。
- 显示实付金额。
- “我和其他 [X] 人”，X 必须是正整数。
- 两种方式：AA 均分、自定义其他人合计应还。
- 实时显示“其他人合计应还”和“我的承担”。
- 错误紧邻人数/金额字段，非法时禁用完成。
- 取消或下滑不能修改原交易和既有 AA。

### 13.3 详情卡与收款

- 状态由金额派生：待收款、部分收款、已结清。
- 显示我的承担、已收、待收、进度和可选备注。
- “记录收款”默认填全部剩余，可改部分金额。
- 收款账户只显示同账本、同币种可用钱包。
- 收款历史倒序显示金额、钱包、日期、备注。
- 删除收款需确认并原子扣回钱包余额。
- 已有收款时不能移除 AA 或直接删除原支出。

### 13.4 视觉

状态以文字、轻圆点和进度为主，不铺满红绿。AA 待收不计入普通收入，也不并入可用总资产。

## 14. 设置与管理页

- 使用原生 `Form` / 分组 List，不为每个设置项画玻璃卡。
- 分组：记账、分类与模板、自动化与规划、账户与汇率、数据、安全与外观、关于。
- 危险操作放在对应区域底部并使用破坏性角色。
- 导入、恢复、同步等长任务显示真实进度和最终结果，不能用无限 spinner 假装完成。
- 设置/管理不是视觉秀场；一致性和可读性优先。

产品已删除标签。兼容模型 `TransactionTag` 暂时仍存在于持久化 schema，用于打开旧数据库并清空旧数据；这不是允许恢复标签 UI。当前 `QuickBookkeepingSettingsView` 的 URL Scheme 帮助文字仍把 `tags` 列为支持参数，与解析器和测试冲突，应修正文案，但不要因此删除兼容 schema。

## 15. 空、加载、错误和隐私状态

每个页面至少覆盖：

- 无账本；
- 有账本但无账户；
- 有账户但无交易；
- 历史月空、未来月空；
- 缺汇率；
- 迁移失败；
- 导入/同步网络失败；
- 保存失败；
- 隐藏余额；
- 加载中；
- 无合法目标账户。

规则：

- 字段错误就地显示。
- 页面失败使用非阻断提示并给重试动作。
- 只有不可恢复/破坏性动作才用 modal 确认。
- loading 与最终内容占据近似空间，避免布局跳动。
- 失败不清空草稿、不弹回根页、不改变导航位置。
- 隐私模式不只替换总额；分组小计、账户卡、VoiceOver value 同步隐藏。

## 16. 动效、手势和触觉

### 16.1 默认动效

- 页面状态变化使用临界阻尼约 0.3–0.4s，不回弹。
- 高频按钮使用独立快速 press：约 120ms 按下、100ms 释放。
- 只有用户直接拖拽、快速释放 Sheet 或物理吸附允许轻微回弹，并继承速度。
- Tab、系统返回、Sheet、List 滚动使用系统转场，不叠加自定义动画。
- 金额和图表使用局部 transition，不让整页重新入场。

### 16.2 可中断性

- 逻辑状态不等待动画结束。
- 转场期间不锁输入。
- 自定义拖拽必须从当前呈现值开始，1:1 跟手，释放传递速度。
- 不使用 `Task.sleep`、`asyncAfter`、`.delay` 掩盖初始化或恢复导航。
- 不自绘 back 手势，不盖住系统边缘返回。

### 16.3 触觉

- 保存成功、破坏性确认、物理吸附可轻量触觉。
- Tab、月份、每个数字键不重复震动。
- 触觉不能先于真实成功；数据库失败时不能发“成功”触觉。

## 17. “不卡顿”的定义与量化验收

“感觉还行”不是验收。下一位 Agent 需要同时交付行为证据和性能证据。

### 17.1 交互响应

- 所有可点击控件在下一次可见刷新内开始反馈；不能先停住再缩放。
- 高频按钮按下约 120ms 达到 pressed 状态，释放约 100ms 回到静止。
- 记账入口不包含人为等待，点击后系统 Sheet 立即开始呈现。
- 主线程在核心交互中不应出现可解释不了的连续长任务；任何超过约 50ms 的主线程区段都要定位原因，而不是加 loading 遮盖。

### 17.2 动画与滚动

- 60Hz 帧预算约 16.67ms，120Hz 帧预算约 8.33ms。目标不是伪造一个固定 fps 数字，而是在系统允许的刷新率下没有连续 hitch、明显停顿或回弹断层。
- 流水长列表连续快速滚动时不重复聚合、创建格式化器或生成阴影层。
- 四 Tab 快速连切时没有 accessory 尺寸重排和资产页连带重算。
- 资产卡横滑保持原生惯性；进入/边缘返回可中断且不闪现第二张卡。
- Sheet 连续开关 20 次后内存不持续单向增长，没有残留展示状态。

### 17.3 数据规模

至少用三档数据验证：

- 空数据：验证空状态和布局稳定。
- 常用数据：约 30–100 笔交易、8 个账户、常规分类。
- 压力数据：10,000 笔交易、100 个账户、200 个分类/子分类、50 个计划、1,000 条存钱分配、跨币种和 AA/关系数据，以及 20 张 10–20MB 图片。

资产首屏仍遵守最终产品层级，不需要同时渲染 100 张卡；压力夹具是为了证明查询、汇总、搜索和账户可达性不会因为数据量崩溃。压力数据应通过 Debug-only fixture 生成，不混入生产 seed。

### 17.4 工具和证据

- 功能与视觉：iOS 26.5 或 iOS 27 Simulator。
- 最终性能：Release 真机，优先支持 ProMotion 的 iPhone；Simulator 不能证明 GPU/120Hz 表现。
- Instruments：SwiftUI、Animation Hitches/Core Animation、Time Profiler、Allocations。
- 对比必须使用相同设备、相同 Release 配置、相同数据和同一操作脚本。
- 保留优化前后录屏或 trace，并记录测试系统、设备、数据量、构建配置。

### 17.5 视觉与无障碍矩阵

至少覆盖 320pt、393pt、430pt 三档 iPhone 内容宽度，并交叉检查：

- 浅色 / 深色；
- 默认字号 / 至少 XXL Dynamic Type；
- Reduce Motion / Reduce Transparency / Increase Contrast；
- VoiceOver；
- 空数据 / 长列表 / 多币种缺汇率 / 负余额确认 / 保存失败；
- 四 Tab 连切、圆钮反复开关、快速双击保存、月份连切、资产卡连续进出三次和边缘返回、报表范围连切。

AA 编辑中的删除命中目前约为 36×36pt，低于 44pt 目标；隐私模式、图表和自定义 swipe 也必须有完整 VoiceOver 替代动作与读值，不能只验证视觉截图。

### 17.6 建议性能门槛

以下是下一阶段的验收目标，不是当前已通过的数据。每项至少重复 5–10 次并记录中位数和 p95；最终以同一提交、固定夹具、Release 真机为准。

| 场景 | 建议门槛 |
| --- | --- |
| 冷 / 暖启动 | 冷启动首屏可交互 p95 ≤ 2.0s；暖启动 p95 ≤ 1.0s；首帧后无 >100ms 未解释主线程阻塞 |
| 记账入口 | 圆钮可见反馈 p95 < 50ms；暖启动 Sheet 首个可交互帧 p95 < 250ms，冷启动 < 400ms |
| 数字输入 | 连续 50 次输入 0 丢键；金额可见更新 p95 < 50ms |
| 60/120Hz 动画 | 系统确实提供对应刷新率时，p95 frame 分别不超过约 16.7/8.3ms；30s 核心流程 hitch ratio < 0.5%，0 个 >100ms hitch |
| 10k 流水 | 首屏 p95 < 300ms；滚动不加载整库视图模型；搜索在 150–250ms debounce 后 p95 < 200ms，旧请求可取消 |
| 报表 | 10k 数据切换范围/指标 p95 < 300ms；计算期间滚动/点击反馈 p95 < 100ms，主线程计算段 < 50ms |
| 资产 | 横滑 30s、详情进出 30 次，0 个 >100ms hitch；结束 RSS 不高于开始基线 15% 以上且不持续增长 |
| 附件 | 10 张 20MB 图片进入详情，首批缩略图 p95 < 300ms；峰值 RSS < 300MB；滚动不解码全分辨率原图 |
| 长任务 | 导入、恢复、同步在 100ms 内出现真实进度；执行中普通输入 p95 < 100ms，失败/弱网不冻结 UI |
| 稳定性 | 四 Tab + 记账 Sheet 开关 50 轮，0 重复展示、0 泄漏，结束 RSS 不高于基线 15% 以上 |

门槛不是通过“延后显示”或删掉系统转场来达成。若测量工具本身或系统刷新策略不支持某项百分位，应记录原始 trace、hitch 数和主线程长任务，并解释替代证据。

### 17.7 性能观测与自动化

当前工程没有 UI Test target、`XCTMetric` 性能测试、`os_signpost` 或 MetricKit 指标。建议按风险渐进补齐：

- Signpost：`app.bootstrap`、`entry.present`、`home.monthChange`、`transaction.search`、`report.compute`、`cloud.snapshot/hash/upload`、`attachment.thumbnail/import`、`import.preview/commit`。
- UI 性能测试：启动、圆钮到可交互、流水搜索、长列表滚动、资产详情往返、报表范围切换。
- 指标：`XCTApplicationLaunchMetric`、clock、CPU、memory、storage；关键滚动另用 Animation Hitches / Core Animation trace。
- 线上证据：接入 MetricKit 观察 launch、hitch、memory 和 disk；先建立真实 Release Archive/IPA 体积基线，不把 universal Simulator `.app` 大小当下载体积。
- 每份性能结论附设备、系统、构建 SHA、配置、数据规模和 trace/录屏；相同指标回退超过约 15% 时必须审阅。

## 18. 当前已知卡顿风险清单

状态说明：`源码已处理` 只表示对应热路径已从代码中移除并通过机械编译，不等于 Release 真机性能已验收。

| 优先级 | 位置 | 事实/风险 | 建议 |
| --- | --- | --- | --- |
| P0 | `RootTabView.swift` | **源码已处理**：accessory/placement 已删除，固定圆形 overlay 已加入 | 完成 iOS 26.5/27 位置、最小化、详情隐藏和命中验收 |
| P0 | `LedgerGlassComponents.swift` | **源码已处理**：高频按钮已有独立 120ms/100ms strong ease-out | 真机慢动作检查按下/释放和 Reduce Motion |
| P0 | `TransactionFormSections.swift` | **源码已处理**：分类已 Lazy、去逐卡 surface/shadow | 用首次开 Sheet trace 证明合成成本下降 |
| P0 | `HomeView.swift` | **源码已处理**：月份状态不再进入整页 `withAnimation` | Release 连续切月，确认聚合本身没有长帧 |
| P0 | `MoneyFormatter.swift` | **源码已处理**：按线程和配置复用 formatter，并补 Locale/并发测试 | 用 Allocations / Time Profiler 做前后对比 |
| P1 | `AccountListView.swift` | **源码已处理**：窄环境 reader 替代 `@Environment(\.self)` | 四 Tab 连切与 zoom/cross-fade A/B |
| P1 | `ReportsAndCalendarView.swift:53-153` | 三次同步报表聚合在 body 热路径 | 可取消任务 + scope cache；滚动不触发计算 |
| P1 | `ReportsAndCalendarView.swift` 的 `ReportPalette` | 固定深色 RGB 在深色模式可能不可读 | 换语义色，验证深色与 Increase Contrast |
| P1 | `HomeView.swift:11-73` | 查询全历史再在 computed property 过滤和聚合 | 当前小数据先不重写；压力测试后做有界查询/缓存 |
| P1 | `HomeView.swift:576-667` | 固定尺寸自定义 swipe 与竖向 ScrollView 竞争 | 最终迁移系统 List/swipeActions；短期保持 1:1、稳定、可访问 |
| P1 | `AccountListView.swift` 账户卡数据源 | 只显示前 8 个账户，更多账户不可达 | 去掉静默截断或增加明确“全部账户”路径 |
| P1 | `UnifiedEntryView.swift` 保存动作 | 缺少明确保存中防重状态，快速连点可能重复写入 | 只锁提交动作，保留草稿和其他页面反馈 |
| P1 | `TransactionListView.swift` / `TransactionQueryState.swift` | 搜索每个字符主线程全量拼字符串、过滤和排序 | 150–250ms debounce、scoped fetch/paging、可取消旧请求 |
| P1 | `SavingsGoalViews.swift` | 每个目标重复过滤全部 allocation，详情非惰性展开 | 一次建立 goalID 索引和 summary，长历史使用 LazyVStack/List |
| P1 | `TransactionDetailView.swift` / `AttachmentStore.swift` | body 路径可能同步读盘并解码原图，20MB 写入也在主执行域 | 后台 downsample/cache/文件 I/O，主域只更新模型状态 |
| P1 | `CloudSyncService.swift` / `BackupService.swift` | 全库快照、排序、JSON、hash 和附件 I/O 可能在 MainActor 执行 | 主域只提取 Sendable DTO；序列化、hash、文件 I/O 后台分块执行 |
| P1 | `MultiCurrencyLedgerApp.swift:19-41` | 启动 `.task` 先同步清标签、seed、生成到期项，再可选同步 | Time Profiler 量测；把非首屏必要工作移出首帧，保持事务正确 |
| P1 | 多个根页 | 多组布尔 Sheet 状态和重复账本选择逻辑 | 逐页收敛为 identifiable route；不要一次重写全 App |
| P2 | 多个页面 | 固定字号、固定行高、`minimumScaleFactor` 掩盖大字体问题 | 迁移 Dynamic Type 语义样式，让布局可增长 |
| P2 | `ledgerGlassCard` 调用点 | 名称暗示玻璃，实际已是内容表面，容易被误用 | 新代码用 `ledgerContentSurface`，逐步清理旧别名 |

## 19. 推荐给下一位 Agent 的执行顺序

### 阶段 0：保护基线

1. 阅读本文件和优先级 2–5 的设计稿。
2. 保存 `git status`、`git diff --stat` 和 scoped diff。
3. 先审阅当前 84 项工作区差异，确认不要覆盖刚落地的根入口、卡顿修复和四项测试修复。
4. 在最终当前源码上重新跑 generic Debug、Release、`build-for-testing`。
5. 先定向复跑 `AASplitFeatureTests.testCollectedAmountCapsLaterSplitEdits`，再串行执行完整 143 项并保存 `.xcresult`；禁用 coverage 可用于排除此前收尾卡住，但发布前仍需单独验证 coverage 流程。
6. 不先格式化全仓库，不做无关重命名。

### 阶段 1：圆形入口（源码完成，视觉待验收）

当前已改：

- `MultiCurrencyLedger/App/RootTabView.swift`
- `MultiCurrencyLedger/Views/Home/HomeView.swift`
- `MultiCurrencyLedger/Views/Accounts/AccountListView.swift`
- `MultiCurrencyLedger/Views/Savings/SavingsGoalViews.swift`
- `MultiCurrencyLedger/Views/Transactions/ReportsAndCalendarView.swift`

下一 Agent 不要重新实现这一阶段；先用稳定设备逐项验收布局、滚动最小化、按 Tab 显隐、快速连点、Reduce Motion/Transparency、VoiceOver 和末项避让。只有发现有证据的问题才做 scoped patch。

### 阶段 2：直接卡顿热点（前五项源码完成）

1. `[源码完成]` 分类主/子列表 `LazyHStack`。
2. `[源码完成]` 去重复阴影/材质。
3. `[源码完成]` 月份整页动画改局部。
4. `[源码完成]` MoneyFormatter 安全复用与 Locale/并发测试。
5. `[源码完成]` 资产环境订阅窄化。
6. `[未完成]` 用 Release A/B 确认 asset zoom 是否真是热点。

前五项仍缺 Instruments 前后对比，不能只凭源码变化宣称性能达标。避免把多个变量混在一次测试里。

### 阶段 3：全局语义和页面一致性

1. 内容表面/玻璃操作语义拆分收尾。
2. 交易编辑复用记账 composer，保存后停留详情。
3. 流水长列表迁移系统 List / swipeActions。
4. 报表聚合移出 body 热路径。
5. 共享账本 scope 和 identifiable route 渐进收敛。
6. Dynamic Type、Reduce Transparency、Increase Contrast 清理。

### 阶段 4：最终回归

- 运行全部单元测试。
- 浅/深色。
- Reduce Motion。
- Reduce Transparency。
- Increase Contrast。
- 大字号。
- 空/普通/压力数据。
- 快速记账、连续 Tab、长流水、反复 Sheet、资产 zoom/边缘返回、报表范围切换。
- 真机 Release Instruments 和录屏。

## 20. 测试与运行建议

本机已有 runtime。当前还保留两个已关机的专用 iOS 26.5 Simulator：`Codex AppLock Fix 20260717` 和 `Codex Baseline Fix 20260717`；它们曾用于定向测试。下一 Agent 可先用 `xcrun simctl list devices` 核对状态后复用，或在确认无后续证据依赖时自行清理。也可以创建新的专用模拟器，例如：

```sh
xcrun simctl create \
  'MCL iPhone 17 Pro iOS 26.5' \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5
```

实际测试：

```sh
xcodebuild \
  -project MultiCurrencyLedger.xcodeproj \
  -scheme MultiCurrencyLedger \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=MCL iPhone 17 Pro iOS 26.5,OS=26.5' \
  test
```

Debug-only 预览环境：

- `HOME_SAMPLE_DATA=1`：空数据库时写入示例数据。
- `APP_PREVIEW_SCREEN=assets`：启动到资产。
- `APP_PREVIEW_SCREEN=entry`：启动后打开记账。
- `HOME_PREVIEW_STATE=book-switcher`。
- `HOME_PREVIEW_STATE=previous-month`。
- `HOME_PREVIEW_STATE=future-month`。
- `HOME_PREVIEW_STATE=travel-book`。
- `HOME_PREVIEW_STATE=budget-editor`。
- `ENTRY_PREVIEW_STATE=over-budget`：配合示例数据设置超预算状态。

注意：示例数据只会在数据库没有账户时 seed。不要在真实用户数据库上运行破坏性清理来获得截图。

## 21. 旧截图如何使用

`.build/qa-*` 中有大量旧版截图，它们可用于理解冷灰背景、金额层级、历史空状态和早期资产方向，但不能当作当前逐像素真值：

- `.build/qa-round4/home-frosted-neutral-final.png`：可参考冷灰背景、金额中性化、轻材质；底部是已经淘汰的旧自绘导航。
- `.build/qa-assets-entry/assets-light.png`：旧资产分组列表，不覆盖当前横向卡条决策。
- `.build/qa-assets-entry/entry-light.png`：旧 Form 式记账，不覆盖当前 `EntryComposerView`。
- `.build/qa-home-budget-gauge/home-light.png`：预算仪表视觉历史，不代表第三版最终信息架构。

当前没有一套在 2026-07-17 最新根架构和圆形入口方案之后完成的全页验收截图。下一位 Agent 完成阶段 1 后应重新建立截图基线，并在文件名/说明中记录设备、系统、主题、数据状态和构建配置。

## 22. 不得破坏的业务边界

- 交易余额变化只能经过 `LedgerService` / 相关 Service。
- UI 表单必须沿 `TransactionFormState → TransactionDraft → TransactionImpactCalculator → LedgerService` 写入；View 不得直接修改 `Wallet.balance`。
- 删除必须回滚对应钱包影响。
- 编辑必须原子撤销旧交易、应用新交易。
- 转账/换汇本金不计普通收支，手续费按既有规则计入。
- 一笔交易只要来源账户或去向账户属于当前账本，就属于该账本作用域；优化查询时不能漏掉从外部账户转入当前账本的交易。
- 组合付款至少两项、金额为正、同币种、钱包不重复且合计严格等于总金额。
- 预算和统计使用 AA 后的“我的承担”；AA 收款不计普通收入。
- AA 仅适用于支出，并与既有退款/报销互斥；已有收款时不能直接移除 AA，收款钱包必须同账本、同币种、可用且未归档。
- 存钱分配不改变钱包余额。
- 缺汇率不能静默伪造总资产。
- 标签已经从产品移除，不能恢复入口，也不能把旧标签拼到备注。
- 银行卡仅保存后四位，不保存完整卡号。
- URL、截图识别、快捷指令、备份、恢复、迁移和 Cloud sync 的数据合同不能因 UI 改版被顺手修改。

## 23. 已知非 UI 风险，交接时不要误判

- 当前 `TransactionTag` 仍在现行 schema 中是兼容策略，并由启动清理服务清空；不要看到类型存在就恢复标签产品功能。
- `QuickBookkeepingSettingsView` 的帮助文案仍声称 URL 支持 `tags`，而解析测试明确拒绝它；这是文案 bug。
- 当前 `.entitlements` 为空，project 也移除了 `CODE_SIGN_ENTITLEMENTS`。设置页仍展示 iCloud 私有同步。签名、CloudKit entitlement 和真实同步能力需要单独验证，不能因 generic build 通过就宣称可用。
- 当前没有 UI test target，交互回归主要依赖单元测试、Debug 环境状态和人工/工具录制。
- 原始 Debug 全量单测为 138/143 通过；CSV、AppLock、LedgerScope 的修复后 suites 已分别全绿，AA 编辑失败回滚和完整 143 项尚未复跑。覆盖率收尾曾卡住；不能把定向测试或 `build-for-testing` 成功等同于全量测试通过。
- 续接中新增的 `LedgerTransactionSnapshot`、CSV newline、LedgerScope 半开区间和 Keychain 状态分类都属于未提交增量；下一 Agent 必须先 scoped review 和全量回归，不能因它们修复了单个断言就跳过业务审查。
- `MultiCurrencyLedgerApp` 启动失败仍以 `fatalError` 结束；迁移恢复体验需要按既有恢复设计继续审阅。

这些问题不应混进圆形按钮的首个 patch，但必须在最终发布前有明确负责人。

## 24. 最终 Definition of Done

只有同时满足以下条件，才能向用户说“UI 交付完成且不卡顿”：

### 根与导航

- [ ] 四个原生 Tab 等宽、状态保留、标题正确。
- [x] 源码中已由右下 56pt 蓝色圆形记账按钮替代 accessory 整行。
- [ ] 按钮在根页显示，详情隐藏，返回稳定恢复。
- [x] 源码保持单一 presentation、快速连点 guard，未新增延迟导航或自定义 back。
- [ ] 在稳定 iOS 26.5/27 设备完成圆钮位置、命中、Tab Bar 最小化和详情往返视觉验收。

### 视觉

- [ ] 内容层没有玻璃套玻璃、整页泛白、双阴影。
- [ ] 功能层玻璃克制且使用共享容器。
- [ ] 金额中性，红/绿只表达状态。
- [ ] 浅色、深色、降低透明度、增强对比度都清楚。
- [ ] Dynamic Type 下核心内容不截断。

### 记账

- [ ] 打开后无需再点金额即可直接输入。
- [ ] 常见宽度默认字号下高频路径无需滚动。
- [x] 分类源码已改为 `LazyHStack`、去逐卡阴影并使用 120ms/100ms 按压曲线。
- [ ] Release 真机证明首次打开、横滑和展开无可见 hitch。
- [ ] 完成/下一笔语义正确；失败与负余额确认保留表单。
- [ ] AA、组合付款、换汇、手续费规则无回归。

### 流水、资产、计划、报表

- [x] 月份状态更新已移出整页隐式动画。
- [ ] 长流水滚动和连续切月通过 Release 性能验收。
- [ ] 资产卡平面横滑、按压快、zoom 可逆、双击不重复 push。
- [ ] 计划四模块状态清晰，存钱分配语义明确。
- [ ] 报表范围切换不会阻塞滚动，图表有数字摘要。

### 性能与测试

- [ ] 当前最终工作树重新完成 Debug generic build。
- [ ] 当前最终工作树重新完成 Release generic build。
- [ ] 当前最终工作树重新完成测试目标构建。
- [ ] 143 项现有单元测试在 iOS 26+ 目标实际运行通过。
- [x] 记账/Formatter 7/7、CSV 3/3、AppLock 2/2、LedgerScope 2/2 定向测试已有通过 xcresult。
- [ ] AA 回滚用例修复后复跑通过。
- [ ] Release 真机完成关键交互 trace，无未解释的主线程长任务或连续可见 hitch。
- [ ] 20 次 Sheet/详情往返后无状态叠加或持续内存增长。
- [ ] 空、常用、压力数据三档均完成回归。

## 25. 可直接发给下一位 Agent 的开场任务

> 你现在接手“多币种账本”的 SwiftUI / UI / 交互 / 性能工作。先完整阅读 `docs/agent-handoff-ui-interaction-performance.md`，以及其中优先级 2–5 的设计稿，再动代码。
>
> 当前 `main` 工作区有大规模未提交改动，它们就是最新产品状态。禁止 reset、checkout、clean、整文件回写或删除未跟踪实现；每次只做 scoped patch，并保留账务、AA、迁移、备份和识别语义。
>
> 最新 P0 已在源码落地：`tabViewBottomAccessory` 已被根级右下 56pt 蓝色圆形 overlay 替换，根入口使用单一 `RootPresentationState`、按 Tab 可见性 Preference、快速连点 guard 和 86pt 根内容尾部净空。不要重新实现；先在稳定 iOS 26.5/27 设备验证右 20pt、Tab Bar 上 18pt、最小化、四根页显示、详情隐藏和返回恢复。
>
> 高频按压 120ms/100ms、分类 `LazyHStack` 与去逐卡阴影、月份局部动画、Formatter 复用、资产环境订阅窄化也已写入源码。下一步是逐项做 Release A/B 和 Instruments 证据，而不是继续凭感觉调动画。资产横向卡条和系统 zoom 已是确认方案，不得回退或自绘返回手势；只有证据表明 zoom 是剩余 hitch 来源时才能调整。
>
> UI 总方向是“内容安静、操作玻璃”：内容层使用语义背景和普通分组表面，只有 Tab、toolbar、圆形主按钮、菜单和 Sheet chrome 使用系统 Liquid Glass；金额默认中性，蓝色是唯一主交互色，红/绿只表达状态；触控至少 44pt，并覆盖 Dynamic Type、VoiceOver、Reduce Motion/Transparency 和 Increase Contrast。
>
> 原始全量单测为 138/143；续接修复后，记账/Formatter 7/7、CSV 3/3、AppLock 2/2、LedgerScope 2/2 已通过，但 AA 回滚用例与完整 143 项尚未复跑，最终服务补丁加入后也尚未重新跑完整 Debug/Release。第一步先完成这些机械基线并保存 `.xcresult`，不得把定向测试写成全量测试全绿。
>
> 每个阶段完成后提交：改动文件与 scoped diff、构建/测试结果、失败项、320/393/430pt 浅深色截图，以及相同 Release 真机数据下的 trace/录屏和量化前后对比。只有本文件 Definition of Done 中的行为、无障碍、业务边界和性能证据全部满足，才能宣称“UI 完成且不卡顿”。
