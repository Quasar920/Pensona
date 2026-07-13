# iCost 功能等价补全实施计划

日期：2026-07-13  
设计依据：`docs/superpowers/specs/2026-07-13-icost-feature-completion-design.md`  
执行方式：在当前工作区接续已有核心闭环改动，按阶段测试、提交和验收；小组件与位置附件延后。

## 执行约束

- 每项业务逻辑先补失败测试，再实现最小通过代码。
- 界面不直接修改钱包余额；所有入口提交 `TransactionDraft`。
- 不覆盖当前未提交的 `LedgerScope`、`TransactionQueryState`、首页和明细范围修复。
- 新文件使用 Xcode 文件系统同步分组自动纳入 Target；仅在确有必要时改 `project.pbxproj`。
- 常规验证使用静态编译和纯逻辑检查；Simulator 只用于阶段性 XCTest、URL Scheme/App Intent、系统权限和最终回归。
- 每个阶段形成独立提交；发现既有无关改动时保留并绕开。

## 阶段 1：核心记账闭环

### 任务 1：完成账本、月份与查询范围

文件：

- `MultiCurrencyLedger/Models/LedgerScope.swift`
- `MultiCurrencyLedger/Models/TransactionQueryState.swift`
- `MultiCurrencyLedger/Views/Home/HomeView.swift`
- `MultiCurrencyLedger/Views/Transactions/TransactionListView.swift`
- `MultiCurrencyLedger/Views/Transactions/TransactionFilterView.swift`
- `MultiCurrencyLedgerTests/LedgerScopeTests.swift`
- 新增 `MultiCurrencyLedgerTests/TransactionQueryStateTests.swift`

步骤：

1. 为组合关键词、日期、金额、账本、账户、币种、类型、分类和排序写失败测试。
2. 修正范围模型的边界、稳定排序和筛选摘要。
3. 将明细页迁移到 `TransactionQueryState`，筛选面板增加自定义日期、金额、账本和排序。
4. 确认首页预算、月度汇总和每日流水使用同一个 `LedgerScope`。
5. 运行受影响测试和 generic iOS build。

### 任务 2：建立统一交易草稿和余额影响

新增文件：

- `MultiCurrencyLedger/Models/TransactionDraft.swift`
- `MultiCurrencyLedger/Services/TransactionImpactCalculator.swift`
- `MultiCurrencyLedgerTests/TransactionDraftTests.swift`
- `MultiCurrencyLedgerTests/TransactionImpactCalculatorTests.swift`

修改文件：

- `MultiCurrencyLedger/Services/LedgerService.swift`
- `MultiCurrencyLedger/Models/LedgerTransaction.swift`

步骤：

1. 为五种交易、手续费、同钱包、币种不匹配、缺失钱包和分类类型写失败测试。
2. 定义草稿字段、规范化、`WalletDelta` 和纯计算影响器。
3. 在 `LedgerService` 增加 create/replace draft API，保留旧 API 作为兼容包装。
4. 确保新增、替换、删除失败时模型和钱包余额全部回滚。
5. 添加商户字段到所有手工入账路径。

### 任务 3：复用录入表单并支持最近选择

新增文件：

- `MultiCurrencyLedger/Views/Entry/TransactionFormState.swift`
- `MultiCurrencyLedger/Views/Entry/TransactionFormSections.swift`
- `MultiCurrencyLedger/Services/RecentEntrySelectionStore.swift`
- `MultiCurrencyLedgerTests/RecentEntrySelectionStoreTests.swift`

修改文件：

- `MultiCurrencyLedger/Views/Entry/EntryView.swift`

步骤：

1. 以纯状态对象表达所有交易类型字段和草稿转换。
2. 为商户、账户/钱包、分类、手续费、调整原因和换汇金额复用表单区块。
3. 最近选择按账本和交易类型保存 UUID；失效引用回退到第一个合法候选。
4. 连续录入保留合法选择，清空金额、商户、备注和类型专属字段。

### 任务 4：完整编辑与复制

修改文件：

- `MultiCurrencyLedger/Views/Transactions/TransactionEditView.swift`
- `MultiCurrencyLedger/Views/Transactions/TransactionDetailView.swift`
- `MultiCurrencyLedger/App/RootTabView.swift`

测试：

- 扩展 `MultiCurrencyLedgerTests/LedgerServiceTests.swift`
- 新增 `MultiCurrencyLedgerTests/TransactionDraftRoundTripTests.swift`

步骤：

1. 编辑页复用录入字段，允许修改类型、钱包、金额、分类、商户、日期、手续费和备注。
2. 保存调用原子 replace draft API。
3. 详情页增加“复制为新交易”；日期默认现在，金额须确认后保存。
4. 覆盖跨钱包、跨类型、失败回滚和复制不直接入账测试。

### 任务 5：阶段 1 验证与提交

1. `xcodebuild` generic iOS Simulator build，不启动 Simulator。
2. 在必须运行 XCTest 时选择单一已安装设备，完成后退出相关进程。
3. 检查 `git diff --check`、工作区状态和阶段 1 验收清单。
4. 提交阶段 1，不夹带无关文件。

## 阶段 2：丰富交易属性

### 任务 6：二级分类与账本作用域

新增/修改：

- 扩展 `LedgerCategory` 的父分类、账本、归档和时间字段。
- 新增 `CategoryService` 与树形查询测试。
- 重构 `CategoryManagementView`、录入/编辑分类选择和统计路径。
- 加入版本化 SwiftData Schema 与迁移测试夹具。

### 任务 7：标签

新增：

- `TransactionTag`、标签关系、`TagService`、管理/选择页面和组合查询测试。
- 明细筛选、批量操作和统计使用同一标签关系。

### 任务 8：图片附件

新增：

- `TransactionAttachment`、`AttachmentStore`、PhotosPicker 入口和文件校验测试。
- 图片写入 Application Support，数据库只保存相对路径与元数据。

### 任务 9：模板

新增：

- `TransactionTemplate`、模板草稿编解码、失效引用校验、模板管理和快速使用入口。

### 任务 10：组合付款

新增：

- `TransactionPaymentPart`、多钱包影响计算、金额守恒验证和付款明细编辑 UI。
- 旧交易继续适配为单付款明细。

### 任务 11：退款和报销

新增：

- `TransactionRelation`、退款/报销服务、详情入口、状态摘要和统计口径测试。
- 覆盖多次部分退款、超额退款、部分报销和跨钱包入账。

### 任务 12：批量操作

新增：

- 批量选择模式、变更预览、原子批次服务、失败回滚和整批撤销测试。

### 任务 13：阶段 2 验证与提交

- 迁移夹具、财务影响测试、generic build、必要的单次 UI 验收。

## 阶段 3：自动化与 URL Scheme

### 任务 14：周期账单

- 新增 `RecurringSchedule`、规则计算、唯一生成键、到期扫描、暂停/恢复/补生成和管理页面。
- 测试跨月、月末、时区、重复运行和归档。

### 任务 15：消费分期与账单分期

- 新增 `InstallmentPlan`、期次模型、生成服务、信用账户关联、手续费分配和管理页面。
- 测试本金守恒、尾差、提前结束、重复生成和两类分期统计语义。

### 任务 16：独立 URL Scheme

- 在 Target 注册自有 Scheme；新增 `URLDraftParser` 和 App 路由状态。
- 只解析白名单字段并生成待确认草稿；非法/跨账本参数拒绝。
- 用 parser 单元测试为主，阶段末做一次必要的系统跳转验证。

### 任务 17：统一智能入口

- 将截图、文本、语音、快捷指令和 URL 草稿统一到确认模型。
- 扩展 App Intents；自动入账继续受安全评估和用户显式开关限制。
- 完成阶段 3 验证与提交。

## 阶段 4：资产、统计、预算与存钱

### 任务 18：资产管理和对账

- 补账户编辑、排序、隐藏/归档、钱包停用/恢复、余额差异检查。
- 新增资产/负债/净资产变化解释服务及测试。

### 任务 19：日历和多维统计

- 新增统计查询状态、日/周/月/年聚合、一级/二级分类、标签、账户和账本维度。
- 账本首页提供搜索、月历和统计入口，沿用现有视觉系统。

### 任务 20：多周期和分类预算

- 扩展预算模型为周/月/年作用域及可选分类。
- 新增预算统计服务、复制上期预算、分类详情跳转和历史/未来语义测试。

### 任务 21：存钱目标

- 新增 `SavingsGoal`、`SavingsAllocation`、目标服务和完整页面。
- 测试分配不影响钱包、资产、收入支出和预算。

### 任务 22：阶段 4 验证与提交

- 聚合性能、账本/时间范围、缺失汇率、目标独立性和必要 UI 验收。

## 阶段 5：数据与平台能力

### 任务 23：扩充币种和汇率

- 将硬编码币种扩展为 50+ 常用 ISO 4217 币种，集中定义小数位与显示信息。
- 保留旧 rawValue，测试零/二/三位小数币种和汇率缺失。

### 任务 24：导入管线

- 新增导入预览、字段映射、平台适配器注册、指纹去重、错误行报告和批次撤销。
- 支持通用 CSV/XLSX 及 iCost、支付宝、微信、云闪付预设。

### 任务 25：完整备份和恢复

- 扩展 JSON 快照覆盖全部模型与附件索引。
- 恢复前自动快照，支持校验、迁移、预览和失败回退。

### 任务 26：iCloud 私有同步

- 新增同步协议、CloudKit 适配器、删除标记、冲突副本、状态页和关闭/重新开启流程。
- 测试使用内存 fake；最后做必要的真实容器验证。

### 任务 27：密码、生物识别与后台遮挡

- 新增 Keychain、LocalAuthentication 抽象、锁屏状态机、隐私遮罩和恢复流程。
- 不在日志、UserDefaults、URL 或同步记录中保存凭证。

### 任务 28：秒开与设置整理

- 启动后可直接进入记账，但必须尊重锁屏和确认规则。
- 设置按记账、分类标签、自动化、数据同步、安全外观分组。

### 任务 29：最终验收

- 全量迁移、财务一致性、导入恢复、同步冲突、安全和性能回归。
- 仅此阶段进行一次必要的完整 Simulator/设备 UI 回归。
- 核对 iCost 功能矩阵，确认除小组件和位置附件外没有空白模块。
- 更新设计/QA 文档并提交最终结果。

