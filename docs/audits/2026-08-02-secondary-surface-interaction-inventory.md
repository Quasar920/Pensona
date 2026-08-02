# 二级界面交互审查清单

审查日期：2026-08-02  
范围：`MultiCurrencyLedger/Views`、`MultiCurrencyLedger/App`、现有单元/UI 测试  
原则：本轮只盘点与测试，不修改任何动效实现。

## 1. 测试结果

执行命令：

```text
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger \
  -destination 'platform=iOS Simulator,id=187635F6-B856-42EE-8E29-2C2D728554EF' \
  -parallel-testing-enabled NO -enableCodeCoverage NO
```

- 单元测试：249 个，3 个失败。
  - `BillSearchServiceTests.testKeywordUsesNormalizedANDAcrossDifferentSearchFields`
    （`MultiCurrencyLedgerTests/BillSearchServiceTests.swift:40`）
  - `LedgerServiceTests.testExportsProduceReadableFiles`
    （`MultiCurrencyLedgerTests/LedgerServiceTests.swift:545`，`missingBook`）
  - `LedgerServiceTests.testMonthlyBudgetUpsertsAndIsolatesBookMonthAndCurrency`
    （`MultiCurrencyLedgerTests/LedgerServiceTests.swift:472`，`missingBook`）
- UI 测试：15 个，6 个失败。
  - 性能旅程 4 个全部因 `root-tab-ledger` 等待条件失败：
    `MultiCurrencyLedgerUITests/MultiCurrencyLedgerPerformanceUITests.swift:26/54`
  - 账单搜索收起/关闭 2 个因 `搜索当前月账单` 等待条件失败：
    `MultiCurrencyLedgerUITests/MultiCurrencyLedgerSmokeUITests.swift:89/104`
  - 已通过的 UI 流程包含：四个根 Tab、资产详情、分类子层/长按操作面板、四个记账标签的 Genie 面板、来源标签取消、交易详情内联操作、备注编辑器键盘。
- 模拟器日志同时出现 SwiftData/CoreData `Cannot use staged migration with an unknown model version`，因此上述 UI 等待失败需要在修复测试夹具/模拟器数据后再判断是否为产品回归。

## 2. 发现的二级界面入口

### A. 原生菜单（点击后出现菜单）——未来 Genie 候选

共 16 处 `Menu`：

- 账户：`Views/Accounts/AccountListView.swift:66`、`AccountDetailView.swift:105`
- 记账上下文：`Views/Entry/EntryContextOverlayPanel.swift:247`、`EntryContextControls.swift:421,558`、`UnifiedEntryView.swift:229`
- 交易/报表：`Views/Transactions/TransactionListView.swift:144`、`ReportsAndCalendarView.swift:221`、`AASplitViews.swift:338`
- 储蓄/计划：`Views/Savings/SavingsGoalViews.swift:860`、`Views/Settings/InstallmentPlanManagementView.swift:115`
- 其他设置/管理入口由同类 `Menu` 触发，需在下一轮逐项走 UI 确认菜单内容和锚点。

### B. 长按上下文菜单——独立于点击菜单，需单独决定是否改 Genie

共 5 处 `contextMenu`：

- `Views/Accounts/AccountListView.swift:325`
- `Views/Accounts/AssetDashboardView.swift:86`
- `Views/Savings/SavingsGoalViews.swift:79,849`
- `Views/Settings/BudgetManagementView.swift:96`

现有 UI 测试只覆盖记账分类长按动作面板（`EntryCategoryPager.swift` 的自定义面板），没有覆盖以上原生 `contextMenu`。

### C. Sheet / Full-screen Cover——点击后拉出的完整二级界面

扫描到 63 个 `.sheet`、1 个 `.fullScreenCover`。主要入口如下：

- 账户与资产：`AccountListView.swift:90,93,96`、`AccountDetailView.swift:115,120`、`AssetDashboardView.swift:226`
- 记账四个标签及输入辅助：`TransactionFormSections.swift:403,413,423,434`、`UnifiedEntryView.swift:311`
- 交易列表/详情：`TransactionListView.swift:162,173,182`、`TransactionDetailView.swift:300,305,312,321,329,338,354`、`MonthTransactionListView.swift:96`
- 报表/账本：`ReportsAndCalendarView.swift:238-244`、`StatisticsDashboardView.swift:63`、`LedgerBookViews.swift:95,100,205`
- 搜索/智能草稿：`HomeView.swift:150,358`、`SmartDraftEntryView.swift:79`
- 储蓄与计划：`SavingsGoalViews.swift:115,120,123,128,867,872,877`、`InstallmentPlanManagementView.swift:56,67`、`RecurringScheduleManagementView.swift:57`
- 设置管理：`ExchangeRateListView.swift:44`、`ScopedCategoryManagementView.swift:46,51`、`TransactionTemplateManagementView.swift:70`、`SecurityAndAppearanceViews.swift:152`、`BudgetManagementView.swift:115,127,137`
- 全局入口：`App/RootTabView.swift:76,85`

这些是“点击后出现二级内容”的主体范围。它们并非都应机械替换为 Genie：表单编辑、键盘输入、日期选择、附件编辑等更像任务型 Sheet；需要按锚点与内容归属逐项判断。

### D. Confirmation Dialog——点击后的动作确认层，不建议与内容型 Genie 混为一类

共 17 处，分布在：

- `Entry/UnifiedEntryView.swift:280,294`
- `Entry/Category/EntryCategoryPager.swift:151`
- `Transactions/TransactionListView.swift:185,193`
- `Transactions/TransactionDetailView.swift:366,370,376`
- `Transactions/MonthTransactionListView.swift:99`
- `Books/LedgerBookViews.swift:315`
- `Savings/SavingsGoalViews.swift:110`
- `Settings/SettingsView.swift:208`、`CloudSyncSettingsView.swift:75`、`ExportView.swift:97`、`TransactionImportView.swift:67`
- `Navigation/EntryExpansionContainer.swift:29`
- `Home/HomeView.swift:153`

建议保留系统确认语义；若要统一动效，应另定义“确认层 Genie”规则，不直接套用内容面板 Genie。

### E. 自定义 overlay / 导航二级页

- 记账 Genie 当前已覆盖四个标签：`TransactionFormSections.swift:326,379,384`；现有 UI 测试已验证 AA、组合支付、优惠的打开/关闭，以及来源标签取消。
- 分类子层与长按操作面板：`Entry/Category/EntryCategoryPager.swift:101,245`、`EntrySubcategoryOverlay.swift:22,62,83`；已有 UI 测试覆盖分类子层和操作面板。
- 账单搜索展开/收起浮层：`Transactions/BillSearchView.swift:100,820`；已有关闭和键盘流程测试，但当前两项测试失败。
- 交易详情内联辅助层：`TransactionDetailView.swift:563`。
- 账本/账户/首页等处还有视觉装饰型 `.overlay`，不能仅凭 modifier 名称认定为二级菜单，需要在下一轮通过交互确认。
- 导航型二级页：9 个 `navigationDestination`、4 个 `NavigationLink`，主要覆盖账户详情、交易详情、账本/报表、储蓄目标、设置页；它们是页面层级，不是菜单层，建议单列处理。

## 3. 当前测试覆盖矩阵

已覆盖：

- 记账四标签 Genie：AA、组合支付、优惠及关闭。
- 来源标签保持可见并取消面板。
- 分类点击进入子层、长按进入操作面板。
- 账单搜索展开/关闭、键盘提交路径（但当前等待条件不稳定）。
- 资产详情、交易详情、备注编辑器、根 Tab。

未覆盖或没有可靠覆盖：

- 16 个原生 `Menu` 的实际弹出、菜单项选择、锚点位置。
- 5 个原生 `contextMenu` 的实际弹出与动作结果。
- 绝大多数账户、账本、报表、储蓄、设置管理 Sheet。
- 17 个确认对话框的触发与取消/确认路径。
- 自定义 overlay 中除记账 Genie、分类子层、账单搜索外的分支。
- 导航二级页的完整返回链路与深层入口。

## 4. 结论与下一步边界

本轮筛选出的“所有可能拉起二级界面”的入口，已经按 5 类归档。下一步不应一次性替换所有 `.sheet` 或 `.overlay`；应先从 A 类原生 `Menu`、B 类 `contextMenu`、C 类内容型 Sheet 中逐项确定：触发控件、视觉锚点、是否需要键盘、是否允许拖拽/系统返回、以及是否属于确认语义。确认后再制定统一 Genie 迁移表。

