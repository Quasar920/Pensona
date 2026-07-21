# 全应用透明玻璃 UI 与交互重构实施计划

日期：2026-07-20
状态：待用户复核
依据规格：`docs/superpowers/specs/2026-07-20-full-liquid-glass-ui-interaction-redesign-design.md`
目标工程：`MultiCurrencyLedger.xcodeproj`
最低系统：iOS 26；主要真机：iPhone 17 Pro / iOS 27 beta 3

## 1. 计划目标

在不丢失现有账户、钱包余额、历史交易、预算、AA、报销、附件、导入记录和备份数据的前提下，完成已批准的全应用透明玻璃 UI 与交互重构，并以真机 Release 性能为最终依据。

本计划只描述实施顺序、文件边界、验证方法和停止条件，不代表已经开始修改功能代码。

## 2. 实施原则

1. **数据作用域先于 UI。** 当前交易通过 `Account.book` 间接判断账本；账户全局化前必须先让交易显式记录账本。
2. **兼容字段先保留。** 第一轮迁移不物理删除 `Account.book`、`SavingsGoal.bookID`、标签和 CloudKit 兼容模型；新逻辑停止依赖它们，待一个稳定版本后再考虑清理。
3. **每阶段独立可构建、可测试、可回退。** 不跨多个阶段积累无法运行的大型改动。
4. **业务写入继续集中在 Service。** SwiftUI 只编辑状态并发送意图；余额、交易、AA、报销和迁移保持原子写入。
5. **性能优先于完整折射。** 滚动、按压和导航出现 hitch 时先降低玻璃采样与模糊，不降低输入响应。
6. **先保留历史，再统一展示。** 遇到旧 `.other` 账户、账本分类重复或跨账本转账时，不静默删除或错误归类。
7. **占位图标可替换。** 首期使用统一线宽和尺寸的占位符；正式图标到位后只替换资源。

## 3. 当前实现审计结论

### 3.1 已有可复用基础

- `RootTabView.swift` 已有单一记账展示状态、快速连点保护和按 Tab 的入口显隐 Preference。
- `LedgerGlassComponents.swift` 已有共享按压曲线、内容表面和降低透明度分支。
- `LedgerCategory` 已有 `parentID`、`sortOrder`、`bookID` 和归档字段，可扩展完整父子管理。
- `TransactionFormState`、`TransactionDraft` 和 `LedgerService` 已统一五种交易类型的主要账务写入。
- `AASplitCalculator` 已支持均分，并采用“他人份额向下取整、自己承担尾差”的结果，符合批准规则。
- `PersistentStoreSnapshotService` 已在 SwiftData 打开前创建快照，可作为迁移保护。
- `MoneyFormatter` 已完成格式化器复用。
- 当前工程没有第三方包，使用文件系统同步组，新增 Swift/资源文件无需逐个写入 Build Phase。

### 3.2 必须先处理的结构问题

- `LedgerScope`、`TransactionQueryState`、报表、AA、预算、识别、导入、模板、附件和 URL 草稿都通过 `transaction.sourceAccount?.book` 或 `wallet.account?.book` 判断账本。
- `EntryLoadedView` 只加载当前账本账户，与“账户全局共享”冲突。
- `SavingsGoal` 强制持有 `bookID`，现有计划页按当前账本筛选。
- 分类虽有父子字段，但当前 UI 与 Service 不支持完整的升降级、迁移、带历史引用删除和网格排序。
- 资产页仍保留 matched zoom/cross-fade 分支和 `matchedTransitionSource`，对应用户报告的点击卡死路径。
- 首页和报表根页通过 `@Query` 读取全量交易后在内存过滤，数据增长后会放大主线程压力。
- 还款提醒没有独立模型。
- “待报销”没有明确交易状态字段，现有关系模型只记录实际退款或报销到账。
- 工程尚无 `Localizable.xcstrings`，现有中文文案分散在 View、Model 和 Service 中。

## 4. 阶段总览

| 阶段 | 主题 | 完成标志 |
|---|---|---|
| 0 | 基线与保护 | 当前 Debug/Release/全量测试结果被记录 |
| 1 | Schema 与数据作用域 | 账户全局、交易显式账本、旧数据安全迁移 |
| 2 | 业务链路适配 | 识别、导入、模板、附件、AA、预算均改用交易账本 |
| 3 | 设计系统、设置基础与本地化 | 共享玻璃、颜色、触觉、语言和降级策略可复用 |
| 4 | 根导航与记账容器 | 三段底栏、中央加号、全屏展开和下拉关闭可用 |
| 5 | 分类数据与管理 | 默认分类、父子浮层、长按菜单、排序、迁移删除完成 |
| 6 | 记账主界面 | 五种类型、5×4 分类、键盘、AA、连续记账完成 |
| 7 | 账单页 | 新顶部、月摘要、日期玻璃组、搜索和滑动操作完成 |
| 8 | 资产页 | 全局资产、四模块、类型分组、标准 push 和性能修复完成 |
| 9 | 计划页 | 全局存钱目标和还款提醒完成 |
| 10 | 统计页 | 四分段、四时间范围、按需图表和文字摘要完成 |
| 11 | 设置与全量国际化 | 批准的设置分组和四语言覆盖完成 |
| 12 | 集成、性能与发布验收 | 全量测试、迁移、真机 Release 与无障碍验收通过 |

## 5. 阶段 0：建立可比较的基线

### 5.1 只读检查

执行并保存结果：

```sh
git status --short --branch
git diff --stat
xcodebuild -project MultiCurrencyLedger.xcodeproj -list
```

确认工作区只有本轮批准的规格与计划文档变动；不得清理或覆盖用户文件。

### 5.2 构建与测试基线

使用独立临时 DerivedData：

```sh
MCL_BASELINE_DIR="$(mktemp -d /tmp/mcl-baseline.XXXXXX)"
xcodebuild -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$MCL_BASELINE_DIR" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$MCL_BASELINE_DIR" CODE_SIGNING_ALLOWED=NO build
```

在当前可用的 iOS 26+ Simulator 上执行完整 `MultiCurrencyLedgerTests`。将构建、测试数量、失败列表和 xcresult 路径追加到 `design-qa.md`，不能沿用旧交接文档中的历史结论。

### 5.3 性能基线

在 iPhone 17 Pro 真机 Release 记录三个操作：

1. 资产根页滚动 10 秒。
2. 点击第一张资产卡并返回，连续 10 次。
3. 打开和关闭记账页，连续 10 次。

记录可见卡死、触控无响应、Animation Hitch 和主线程峰值，作为阶段 12 的对照基线。

### 5.4 阶段停止条件

- Debug 或 Release 无法构建时，先修复已有基线问题，不能把基线失败混入新 UI 改造。
- 数据迁移代码开始前，必须确认 `PersistentStoreSnapshotService` 的定向测试通过。

## 6. 阶段 1：Schema、账户全局化与交易显式账本

### 6.1 模型变更

修改：

- `MultiCurrencyLedger/Models/LedgerTransaction.swift`
- `MultiCurrencyLedger/Models/LedgerCategory.swift`
- `MultiCurrencyLedger/Models/SavingsGoal.swift`
- `MultiCurrencyLedger/Models/Account.swift`
- `MultiCurrencyLedger/App/LedgerSchema.swift`
- `MultiCurrencyLedger/App/AppModelContainer.swift`

新增：

- `MultiCurrencyLedger/Models/RepaymentReminder.swift`
- `MultiCurrencyLedger/Services/DataScopeMigrationService.swift`
- `MultiCurrencyLedgerTests/LedgerSchemaMigrationTests.swift`
- `MultiCurrencyLedgerTests/TransactionBookScopeTests.swift`

具体变更：

1. 为 `LedgerTransaction` 增加可迁移的 `bookID` 字段。Schema 层允许旧记录暂时为 nil；所有新写入在 Service 层强制非空。
2. 为 `LedgerTransaction` 增加报销状态字段，状态至少包含 `none` 和 `pending`；实际已报销金额继续由 `TransactionRelation` 计算。
3. 为 `LedgerCategory` 增加系统分类本地化 key、图标来源、占位资源名和用户图标相对路径。
4. 新增全局 `RepaymentReminder`：账户 ID、币种、待还金额、到期日、完成状态、完成时间、创建/更新时间。
5. `SavingsGoal.bookID` 暂时保留为历史来源字段；新增目标和查询不再使用它做可见性过滤。
6. `Account.book` 暂时保留一轮迁移兼容；新账户不再赋值，任何业务查询不得用它决定可见范围。
7. 新增 `LedgerSchemaV3`，版本号递增，并加入迁移阶段。

### 6.2 一次性数据迁移

`DataScopeMigrationService` 在 ModelContainer 成功打开、根 UI 展示前执行幂等迁移：

1. 确认至少存在一个账本；没有时创建“日常账本”。
2. 对 `bookID == nil` 的历史交易按以下顺序回填：来源账户旧账本 → 目标账户旧账本 → 当前默认账本。
3. 历史转账若来源和目标旧账本不同，以来源账户账本作为主账本，并写入迁移诊断计数；不复制交易、不修改余额。
4. 现有账户保留原 `book` 关系作为只读迁移来源，但所有新功能立即按全局账户处理。
5. 现有系统分类转换为全局分类；保留自定义分类、父子关系和交易引用。
6. 现有存钱目标标记为全局可见，不删除原 `bookID`。
7. 迁移全部成功后一次保存并写入迁移完成标志；失败则依赖启动前快照恢复，不写部分完成标志。

### 6.3 账务 Service 改造

修改：

- `MultiCurrencyLedger/Services/LedgerService.swift`
- `MultiCurrencyLedger/Models/TransactionDraft.swift`
- `MultiCurrencyLedger/Models/LedgerScope.swift`
- `MultiCurrencyLedger/Models/TransactionQueryState.swift`
- `MultiCurrencyLedger/Services/TransactionImpactCalculator.swift`

规则：

- `LedgerService.create` 必须接收明确的 `bookID`，创建时写入交易。
- 编辑交易默认保留原 `bookID`；只有明确的“迁移账单到账本”操作才能改变。
- `LedgerScope` 和 `TransactionQueryState` 只读取 `transaction.bookID`。
- 任何来源、目标账户是否全局共享都不影响账单所属账本。
- 删除、回滚和批量修改必须保留 `bookID`。

### 6.4 备份与恢复格式

修改：

- `MultiCurrencyLedger/Services/BackupService.swift`
- `MultiCurrencyLedger/Services/ExportService.swift`
- `MultiCurrencyLedgerTests/BackupServiceTests.swift`

要求：

- 备份版本递增，`TransactionBackup` 增加 `bookID` 与报销状态。
- 账户的旧 `bookID` 仅作为兼容字段导出，不再决定恢复后的账户范围。
- 新增还款提醒、分类图标元数据；用户图标文件需要进入备份附件集合。
- 恢复旧版备份时，交易账本按旧账户关系或导入批次账本推导。
- 先验证所有引用，再清空现有数据；失败时保留恢复前快照。

### 6.5 阶段测试

- 旧 Schema → V3 的内存和文件迁移。
- 来源账户、目标账户、无账户和跨旧账本交易的 `bookID` 回填。
- 新账户没有账本关系但能被任意账本交易使用。
- 账单查询只按交易 `bookID` 返回结果。
- 旧备份恢复、新备份往返和图标附件安全路径。
- 迁移重复运行不产生重复数据或修改余额。

### 6.6 阶段完成标志

- 账户全局化后现有资产数量和总余额不变。
- 每笔历史交易都有可解析的主账本。
- 完整测试通过后再进入业务链路适配。

## 7. 阶段 2：识别、导入、模板、附件与关联业务适配

### 7.1 需要修改的调用链

- `Services/RecognitionEntryService.swift`
- `Services/RecognitionWorkflowService.swift`
- `Services/RecognitionContextBuilder.swift`
- `Services/RecognitionAccountMatcher.swift`
- `Recognition/ScreenshotRecognitionCoordinator.swift`
- `Services/TransactionImportService.swift`
- `Services/ShortcutRecognitionImportService.swift`
- `Services/TransactionTemplateService.swift`
- `Models/AutomationTransactionSnapshot.swift`
- `Services/RecurringScheduleService.swift`
- `Services/InstallmentPlanService.swift`
- `Services/URLDraftParser.swift`
- `Services/AttachmentStore.swift`
- `Services/TransactionRelationService.swift`
- `Services/AASplitService.swift`
- `Services/BudgetService.swift`
- `Services/ReportQueryService.swift`

### 7.2 适配规则

- 当前账本由调用方明确传入，不能从账户反推。
- 所有未归档全局账户都可作为候选；模板和自动化仍按其保存的 `bookID` 决定新交易归属。
- 分类使用全局集合，不再按 `category.bookID` 过滤；旧字段只保留兼容。
- 附件路径和元数据使用 `transaction.bookID`。
- 退款、报销到账和 AA 收款交易继承原交易 `bookID`。
- AA 明细支持 `bookID: UUID?`：nil 表示全部账本，非 nil 表示当前账本。
- 预算和统计只匹配 `transaction.bookID`。
- 报表的“账本”维度通过交易 `bookID` 查找 `LedgerBook` 名称。

### 7.3 阶段测试

更新所有依赖 `account.book` 的既有测试，并增加：

- 全局账户在两个账本分别创建交易。
- 识别、URL、模板、周期、导入产生正确的交易账本。
- AA、退款和报销关联交易继承原账本。
- 附件保存使用交易账本目录。
- 当前账本预算和统计不会混入其他账本交易。

### 7.4 阶段完成标志

全仓 `rg` 不再发现业务判断使用 `sourceAccount?.book`、`destinationAccount?.book` 或 `wallet.account?.book`；允许出现的位置仅限迁移兼容、旧备份解码和诊断代码。

## 8. 阶段 3：共享设计系统、偏好与国际化基础

### 8.1 新增共享类型

新增：

- `MultiCurrencyLedger/App/AppPreferences.swift`
- `MultiCurrencyLedger/Utilities/AmountSemanticStyle.swift`
- `MultiCurrencyLedger/Services/HapticFeedbackService.swift`
- `MultiCurrencyLedger/Services/GlassQualityController.swift`
- `MultiCurrencyLedger/Localizable.xcstrings`
- `MultiCurrencyLedgerTests/AppPreferencesTests.swift`
- `MultiCurrencyLedgerTests/LocalizationCoverageTests.swift`

修改：

- `Views/LedgerGlassComponents.swift`
- `App/MultiCurrencyLedgerApp.swift`
- `App/RootTabView.swift`
- `Views/Settings/SecurityAndAppearanceViews.swift`

### 8.2 设计 Token

在共享组件中集中定义：

- 页面边距、控件间距、三档圆角、44pt 命中区域、56pt 主按钮。
- 静态冷灰背景与浅/深色柔光。
- 功能玻璃、摘要玻璃、居中操作面板、半屏 Sheet chrome 和透明度降级样式。
- 0.2–0.3 秒的普通动效与独立按压曲线。
- 等宽金额字体、主/次文本和分隔线层级。

禁止页面继续自行拼接 `ultraThinMaterial`、白色覆盖、双阴影和随机渐变描边。

### 8.3 自动玻璃降级

`GlassQualityController` 根据以下信号选择完整或简化玻璃：

- `accessibilityReduceTransparency`
- 低电量模式
- 严重或危急 thermal state
- iOS 26 与 iOS 27 可用能力

降级只替换材质与阴影，不改变布局。生产环境不运行持续 FPS 监控。

### 8.4 偏好

增加并集中管理：

- 浅色、深色、跟随系统。
- 触觉反馈总开关。
- 金额颜色惯例：支出红/收入绿，或支出绿/收入红。
- 首次安装按地区选择默认金额惯例。
- 语言：跟随系统、简中、繁中、英语、日语。

根视图根据语言偏好注入 `Locale`。用户自定义分类名称保持原文；系统分类通过 localization key 显示。

### 8.5 国际化策略

- 新 UI 从第一行代码起只使用可本地化 key。
- Model/Service 的 `LocalizedError` 改用本地化 key，不能继续硬编码中文。
- 执行一次全仓用户可见字符串审计，覆盖新 UI 和仍可进入的旧详情/管理页。
- `LocalizationCoverageTests` 检查四种语言的关键 key 存在、格式参数一致且无空值。

### 8.6 阶段完成标志

- 一个预览页面可实时切换四语言、三种外观、两种金额颜色和透明度降级。
- 共享设计组件通过独立 Preview 展示，后续页面不得重复定义视觉常量。

## 9. 阶段 4：三段底栏与全屏记账容器

### 9.1 根导航重构

修改：

- `App/RootTabView.swift`
- `Views/LedgerGlassComponents.swift`

新增：

- `Views/Navigation/LedgerBottomBar.swift`
- `Views/Navigation/EntryExpansionContainer.swift`
- `MultiCurrencyLedgerTests/RootPresentationStateTests.swift`

实现：

- 保留四个 Tab 各自的 NavigationStack 状态。
- 隐藏系统可见 Tab Bar，使用底部安全区内的三段玻璃导航：左 `账单/资产`、中央透明圆形加号、右 `计划/统计`。
- 中央按钮无蓝色填充，只有加号为系统蓝。
- 详情页通过现有 Preference 统一隐藏整条底栏与中央入口。
- 保留 URL、识别草稿、快捷启动和 App Lock 的单一 RootPresentationState，不创建第二套入口状态。

### 9.2 两阶段展开

- 第一阶段只放大单一玻璃外壳并向上移动。
- 外壳接近全屏后淡入 `EntryView` 内容。
- 关闭时先淡出内容，再收拢外壳回中央加号。
- Reduce Motion 下改为短淡化与底部上移。
- 下拉手势只从顶部手势区开始；容器 1:1 跟随，越过阈值后请求关闭。
- 记账页向容器暴露 `hasUnsavedChanges`；有内容时弹出放弃确认。

### 9.3 阶段测试与验收

- 快速连点只出现一个记账会话。
- 四个 Tab 都从同一中央位置打开。
- 详情页不显示底栏和加号，返回后恢复。
- 外部草稿与识别确认不被普通记账覆盖。
- 下拉取消后表单状态不丢失。
- 真机 Release 连续开关 20 次无卡死。

## 10. 阶段 5：默认分类、层级操作与图标

### 10.1 默认分类数据

修改：

- `Services/InitialDataService.swift`
- `Services/CategoryService.swift`
- `Models/LedgerCategory.swift`

新增：

- `Services/DefaultCategoryCatalog.swift`
- `Services/CategoryIconStore.swift`
- `Services/CategoryUsageService.swift`
- `MultiCurrencyLedgerTests/DefaultCategorySeedTests.swift`
- `MultiCurrencyLedgerTests/CategoryHierarchyServiceTests.swift`
- `MultiCurrencyLedgerTests/CategoryIconStoreTests.swift`

`DefaultCategoryCatalog` 按批准规格定义 20 个支出主分类、全部支出子分类、12 个收入主分类及收入子分类，并用稳定 localization key 和稳定逻辑 ID 描述。

新安装直接创建完整目录。旧安装按以下规则升级：

- 已知旧系统分类映射到新 localization key，保留原交易引用。
- 缺失的新默认分类补齐。
- 用户自定义分类不删除，排列在系统默认分类之后。
- 旧 `.other` 或无法识别的数据保留并标记为兼容项，不强制误分类。

### 10.2 CategoryService API

增加原子操作：

- 创建主分类、创建子分类。
- 修改名称与图标。
- 同层批量排序。
- 主分类改为子分类。
- 子分类迁移到其他主分类。
- 子分类提升为主分类。
- 计算历史交易和子分类引用数量。
- 将引用迁移到目标分类后删除。

校验：最多两层；父子必须同为支出或同为收入；不得形成循环；目标分类不能是被删分类本身或其后代。

### 10.3 分类 UI

新增：

- `Views/Entry/Category/EntryCategoryPager.swift`
- `Views/Entry/Category/EntrySubcategoryOverlay.swift`
- `Views/Entry/Category/CategoryActionPanel.swift`
- `Views/Entry/Category/CategoryEditorPanel.swift`
- `Views/Entry/Category/CategoryReorderMode.swift`
- `Views/Entry/Category/CategoryIconPicker.swift`

实现批准的 5×4 整页分类、页码圆点、强虚化子分类玻璃层、每行最多四个固定尺寸子分类、居中操作面板和抖动排序。

长按菜单严格区分：

- 主分类：修改、添加子分类、改为子分类、删除、排序。
- 子分类：修改、迁移至其他分类、改为主分类、删除、排序。

### 10.4 图标

- 首期默认分类使用统一 SF Symbol 占位映射，仅作为临时内置资源。
- 用户上传图标保存到 Application Support 的分类图标目录，数据库只保存安全相对路径。
- 编辑流程提供裁剪、缩放、保留原图或单色化。
- 保存时生成列表缩略图；滚动时不处理原图。
- 删除分类后清理未被引用的用户图标文件。

### 10.5 阶段验收

- 标准字号首屏精确显示 20 个支出主分类。
- 收入按实际数量使用五列布局。
- 分类翻页、子层、长按和排序无明显 hitch。
- 带历史引用删除必须先迁移，并显示准确数量。
- 超大字体自动改列数且分类名称可读。

## 11. 阶段 6：记账主界面与五种交易类型

### 11.1 文件拆分

重构：

- `Views/Entry/UnifiedEntryView.swift`
- `Views/Entry/TransactionFormSections.swift`
- `Models/TransactionFormState.swift`
- `Views/Transactions/UnifiedTransactionEditView.swift`

新增：

- `Views/Entry/EntryKindGlassControl.swift`
- `Views/Entry/EntryContextControls.swift`
- `Views/Entry/EntryAmountPanel.swift`
- `Views/Entry/EntryGlassKeypad.swift`
- `Views/Entry/EntryMovementPanel.swift`
- `Views/Entry/EntryAdjustmentPanel.swift`
- `Views/Entry/EntryInlineValidation.swift`
- `Models/EntrySessionState.swift`
- `MultiCurrencyLedgerTests/EntrySessionStateTests.swift`
- `MultiCurrencyLedgerTests/EntryCalculationTests.swift`

目标是把当前超过千行的共享表单文件拆为单一职责组件，同时继续让新建与编辑复用同一状态和 Service。

### 11.2 布局

固定顺序：交易类型 → 分类/资金路径 → 账户/报销/时间/AA → 金额与备注 → 键盘。

- 顶部五种类型使用一个玻璃分段控制，默认支出。
- 支出和收入接入阶段 5 分类组件。
- 账户、时间和 AA 使用半屏玻璃 Sheet；账户单击即关闭。
- 报销是 `pending/none` 即时开关。
- 备注在金额区域直接输入。

### 11.3 键盘与计算

实现批准的五列四行键盘，四则运算使用四个独立按键。计算状态使用 Decimal，不通过 Double 中转；连续运算、删除、小数位和不同币种精度均有单测。

### 11.4 五种类型

- 支出/收入：要求金额、账户、分类。
- 转账：并排转出/转入账户，交换按钮；同币种。
- 换汇：卖出/买入账户与币种、两边金额和汇率任一项联动；避免循环更新。
- 调整：最终余额和增减金额两种模式；最终写入仍转换为现有 adjustment draft。
- 交易类型切换清理不兼容字段，但不改变当前账本。

### 11.5 AA

- UI 只输入包含自己的总人数。
- 内部转换为现有 `otherPeopleCount = totalPeople - 1`。
- UI 不暴露 custom 模式，但保留历史自定义 AA 的读取和编辑兼容。
- 均分金额使用币种精度，自己承担尾差。

### 11.6 连续记账与完成

修正 `TransactionFormState.resetForContinuousEntry`：

- 保留交易类型、账户和原时间。
- 清空金额、目标金额、分类、备注、报销、AA、计算表达式和临时校验。
- 不保留上一笔分类。

完成后由 Root 显示“已记账”短提示并执行反向收拢动画。

### 11.7 编辑复用

`UnifiedTransactionEditView` 改为同一 `EntryView` 的 edit mode：预填交易、保留原账本、保存后原地刷新详情。删除旧的重复字段实现前，先确认周期规则或模板编辑未引用它们。

### 11.8 阶段验收

- 五种类型均能新建、编辑、连续记账和失败恢复。
- 校验错误显示在对应字段，不只弹总错误。
- 键盘上方没有大块空白。
- 分类与键盘使用同一玻璃语言。
- 下拉关闭、保存和负余额确认不重复提交。

## 12. 阶段 7：账单页

### 12.1 查询与状态

新增：

- `Services/BillQueryService.swift`
- `Models/BillPageState.swift`
- `MultiCurrencyLedgerTests/BillQueryServiceTests.swift`

修改：

- `Views/Home/HomeView.swift`
- `Views/Transactions/MonthTransactionListView.swift`
- `Views/Transactions/TransactionDetailView.swift`

`BillQueryService` 使用 `bookID + [monthStart, nextMonthStart)` FetchDescriptor 读取当前月，而不是 `@Query` 全历史后过滤。查询结果映射为日期分组和月摘要。

### 12.2 页面实现

- 移除大型标题。
- 顶部第一行：当前账本玻璃胶囊、可展开搜索、设置。
- 月份左对齐显示 `年月⌄`；点击打开年月选择，左右手势只加载相邻月份。
- 一张月摘要玻璃面板显示支出、收入、结余和预算剩余。
- 点击预算剩余进入当前月预算设置。
- 每日一张玻璃组，始终展开；同日行使用细分隔线。
- 使用子分类时只显示子分类图标和名称。
- 左滑删除、右滑编辑、单击详情。
- 金额颜色通过 `AmountSemanticStyle` 统一决定。

### 12.3 搜索

- 圆形放大镜通过 glass effect ID 横向形变为搜索框。
- 搜索仍限制在当前账本和当前月份。
- 输入防抖只影响查询触发，不延迟按压和文字显示。

### 12.4 阶段验收

- 大量历史数据下进入账单页只抓取当前月。
- 月份边界不串数据。
- 日期玻璃组滚动无持续 hitch。
- 左右滑动操作与系统返回手势不冲突。

## 13. 阶段 8：资产页与卡死治理

### 13.1 数据服务

新增：

- `Services/AssetDashboardService.swift`
- `Models/AssetDashboardSnapshot.swift`
- `MultiCurrencyLedgerTests/AssetDashboardServiceTests.swift`

修改：

- `Views/Accounts/AccountListView.swift`
- `Views/Accounts/AccountDetailView.swift`
- `Services/AssetSummaryService.swift`
- `Services/AASplitService.swift`

根页不再订阅全历史交易。资产快照只包含总资产、四模块汇总、分组小计和账户行所需字段。

### 13.2 分组映射

- 银行卡：`.bankCard`、`.savings`
- 信用账户：`.creditCard`
- 现金：`.cash`
- 投资账户：`.investment`
- 储值卡：`.eWallet`
- 借贷账户：`.receivable`、`.payable`

旧 `.other` 账户只在实际存在时显示兼容“其他”分组，并在编辑时要求用户归入批准的六类；新建页面不再提供 `.other`。

### 13.3 四个顶部模块

- AA：现有未结清 AA 汇总。
- 报销：`pending` 支出减去已经到账的报销关系。
- 借入：应付/借入余额汇总。
- 借出：应收/借出余额汇总。

根页默认全账本；明细页提供“全部账本 / 当前账本”。

### 13.4 账户卡

- 单列、按类型分组、组标题显示小计。
- 通用字段：图标、名称、余额。
- 银行卡：后四位。
- 信用账户：可用额度与待还金额。
- 投资账户：收益金额。
- 删除 `matchedTransitionSource`、`.navigationTransition(.zoom)` 和相关 namespace/偏好分支。
- 点击账户卡只使用标准 NavigationStack push。

### 13.5 隐私

隐藏总资产、四模块金额、分组小计和账户金额；名称与后四位保留。隐私状态仍复用现有 AppStorage，并加入截图/后台遮罩回归。

### 13.6 性能验收

- Release 真机连续进入/返回账户详情 20 次无卡死。
- Time Profiler 中点击账户不执行全量历史统计。
- 滚动中不创建图片处理任务或大范围 formatter。

## 14. 阶段 9：计划页与还款提醒

### 14.1 数据层

新增：

- `Services/RepaymentReminderService.swift`
- `MultiCurrencyLedgerTests/RepaymentReminderServiceTests.swift`

修改：

- `Services/SavingsGoalService.swift`
- `Views/Savings/SavingsGoalViews.swift`
- `Services/BackupService.swift`

`SavingsGoalService` 查询所有目标，不按 bookID 过滤；新目标保留兼容来源值但全局可见。还款提醒 Service 负责创建、修改、完成、恢复完成和删除，不注册系统通知。

### 14.2 页面

- 左上 `＋ 新增计划`，点击后选择存钱目标或还款提醒。
- 上方直接显示存钱目标，下方直接显示还款提醒。
- 存钱卡显示名称、当前/目标金额、进度、目标日期和“存入”。
- 还款提醒显示账户、待还、日期、剩余天数和完成状态，右侧玻璃勾选。
- 隐藏预算、周期和分期入口；原服务与模型暂保留供旧数据、备份和兼容页面使用。

### 14.3 阶段验收

- 切换账本不改变目标与提醒列表。
- “存入”继续通过现有 SavingsAllocation 原子更新。
- 勾选还款只修改提醒状态，不自动创建交易或通知。

## 15. 阶段 10：统计页

### 15.1 状态与服务

新增：

- `Models/StatisticsPageState.swift`
- `Services/StatisticsDashboardService.swift`
- `MultiCurrencyLedgerTests/StatisticsRangeTests.swift`
- `MultiCurrencyLedgerTests/StatisticsDashboardServiceTests.swift`

修改：

- `Views/Transactions/ReportsAndCalendarView.swift`
- `Services/ReportQueryService.swift`

`StatisticsPageState` 管理概览/分类/资产/日历以及周/月/年/自定义范围。日期区间统一使用半开区间。

### 15.2 按需聚合

- SwiftData 查询先按当前交易 `bookID` 和日期范围裁剪。
- 主线程只提取必要字段为 Sendable DTO；聚合和排序在后台任务执行。
- 切换分段时取消旧任务，只保留当前分段结果。
- 结果使用 scope + range cache key，账单变化后失效。

### 15.3 UI

- 第一层玻璃分段：概览、分类、资产、日历。
- 第二层：周/月/年/自定义和当前日期范围。
- 每个图表一张大型玻璃面板，不再嵌套卡片。
- 图表拖动显示节点；只在跨过有效节点时触觉反馈。
- 每个图表下方提供可访问文字摘要。

### 15.4 阶段验收

- 一次只计算当前分段。
- 快速切换范围不会显示过期结果。
- VoiceOver 可读取图表摘要。
- 滚动时图表不重复入场或重新聚合。

## 16. 阶段 11：设置页与全量四语言

### 16.1 设置结构

修改：

- `Views/Settings/SettingsView.swift`
- `Views/Settings/SecurityAndAppearanceViews.swift`
- `App/RootTabView.swift`

设置首页只显示批准分组：

1. 数据导入与导出
2. 安全与隐私
3. 外观与金额颜色
4. 币种与汇率
5. 数据恢复与迁移
6. 语言
7. 关于与帮助

云同步、标签、分类、预算、周期和分期不在设置首页显示。现有 CloudKit 代码和兼容模型保留但无入口。

### 16.2 玻璃分组列表

使用原生滚动和行交互，每个大分组由一张玻璃容器承载；危险操作只出现在相应详情底部，不能与普通设置混排。

### 16.3 国际化收尾

- 对所有可到达页面执行四语言逐屏检查。
- 中文不作为其他语言的 fallback 成品文案。
- 检查金额、日期、星期、月份、币种名和复数格式。
- 系统默认分类使用本地化 key；用户分类不自动翻译。
- 英文、日文和繁中超长文案不得破坏玻璃按钮与 44pt 命中区域。

### 16.4 阶段验收

- App 内切换语言后根页面、记账、详情、设置和错误提示同步变化。
- 重启后保留手动语言；“跟随系统”继续响应系统设置。
- 两套金额颜色预览与实际账单行一致。

## 17. 阶段 12：集成、测试、性能与发布验收

### 17.1 自动测试

执行：

- 完整 `MultiCurrencyLedgerTests`。
- 新增 `MultiCurrencyLedgerUITests` 目标，覆盖启动、四 Tab、记账、分类子层、账单滑动、资产详情和计划完成的最小烟雾路径。
- Debug 与 Release generic build。
- `build-for-testing`。
- 迁移测试至少覆盖当前正式 Schema、空库和含跨账本历史交易的库。

### 17.2 真机性能

使用 iPhone 17 Pro / iOS 27 beta 3 的 Release 构建：

- Time Profiler：资产卡进入、记账展开、月份切换、统计范围切换。
- Core Animation / Animation Hitches：四个根页面连续滚动。
- Allocations：分类翻页、用户图标列表和金额格式化。
- SwiftUI：检查重复 body 更新和大范围依赖。

目标：

- 点击立即出现下一帧反馈。
- 资产详情连续进入/返回不出现可感知卡死。
- 根页面滚动维持稳定交互帧率；ProMotion 设备尽量贴近 120Hz，最低不能持续跌破 60fps。
- 关键操作不出现超过 100ms 的主线程阻塞。

### 17.3 外观与无障碍矩阵

逐项验证：

- 浅色、深色、跟随系统。
- 完整玻璃、降低透明度、低电量和高 thermal 降级。
- Reduce Motion。
- 默认字号和至少两档辅助功能字号。
- VoiceOver 顺序、标签、提示和自定义滑动操作。
- 简中、繁中、英语、日语。

### 17.4 数据与恢复演练

- 从迁移前快照恢复。
- 导出新备份、清空、恢复并比较对象数量与余额。
- 分类删除迁移、账户删除保护、账本删除保护。
- 保存失败、恢复失败和图标文件缺失时的错误路径。

### 17.5 最终视觉验收

使用 Debug 预览种子和真机数据生成：账单、资产、计划、统计、记账主屏、子分类浮层、分类操作面板、浅/深色和超大字体截图。逐项对照批准规格，不以生成概念图作为像素级真值。

## 18. 建议提交边界

若用户授权提交，按以下边界建立独立提交，避免把迁移和视觉混在一起：

1. Schema 与数据作用域迁移。
2. 业务链路显式账本适配。
3. 共享设计系统与偏好/本地化基础。
4. 三段导航与记账容器。
5. 分类模型、默认数据和管理 UI。
6. 记账主界面。
7. 账单页。
8. 资产页与性能治理。
9. 计划页与还款提醒。
10. 统计页。
11. 设置与国际化收尾。
12. 集成、性能与 QA 修复。

未经用户明确要求，不自动创建分支、提交或推送。

## 19. 风险与应对

### 19.1 SwiftData 迁移风险

风险最高。采用新增可选字段、应用层幂等回填、启动前快照和兼容字段保留，避免同一版本同时删除旧关系。

### 19.2 全局账户影响外围功能

识别、导入、模板、周期、附件、AA 和预算都需要显式账本。阶段 2 完成前不得进入新 UI 实现。

### 19.3 玻璃与性能冲突

只让短暂浮层和批准的摘要/分组使用真实玻璃；列表惰性加载；低电量、thermal 和降低透明度自动降级。

### 19.4 国际化与用户分类

系统分类用 localization key，用户自定义名称保持原文。用户修改系统分类名称后，该分类转为自定义显示名，避免语言切换覆盖用户编辑。

### 19.5 旧 `.other` 账户

不把它自动误分到六个批准类型。只有存在旧数据时显示兼容“其他”组，并在编辑时引导重新选择类型；新建入口不提供该类型。

### 19.6 iOS 27 beta 波动

性能结论同时对比 iOS 26 稳定运行环境。若只在 beta 系统复现，保留系统版本证据，但应用仍需避免可控的主线程阻塞与多层玻璃。

## 20. 开始编码前的门禁

只有以下条件全部满足后才进入阶段 0/1 的代码修改：

- 用户批准本实施计划。
- 当前工作区状态已记录。
- 基线 Debug、Release 和测试结果已保存。
- 数据迁移策略、跨旧账本转账的来源账本优先规则和兼容字段保留策略未被用户否决。
