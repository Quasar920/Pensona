# 信用卡外币消费与还款结算设计

日期：2026-07-29  
状态：已完成逐节确认，等待最终书面复核

## 1. 目标

在不新增顶层交易类型、不改变首页和资产页整体结构的前提下，为现有记账流程补充：

- 信用卡外币消费；
- 消费时结算与还款时结算；
- 信用卡按币种维护负债；
- 通过现有“转账”完成同币种及跨币种信用卡还款；
- 本位币金额与外币偿还金额倒推实际汇率；
- 普通部分还款和多次偿还；
- 外币账单分期，并为每期记录独立实际汇率；
- 转账优惠与手续费，以及各自独立的钱包选择；
- 编辑、删除和失败时的完整余额回滚。

本期不建立消费与还款之间的分配模型，不追踪某次还款具体冲减哪一笔消费。

## 2. 现有项目基础

项目已经具备以下能力，实施时应直接复用：

- SwiftUI 界面和 SwiftData 持久化；
- `CurrencyWallet` 多币种钱包模型；
- `Decimal` 金额计算；
- `SupportedCurrency.fractionDigits` 币种小数位规则；
- `LedgerService` 统一交易保存、编辑和删除；
- `TransactionImpactCalculator` 钱包余额影响计算；
- `InstallmentPlan` 和 `InstallmentOccurrence` 分期基础模型；
- 版本化 Schema 与轻量迁移；
- 备份、恢复、统计和余额重算服务。

`CurrencyWallet` 已经承担“账户币种余额”职责，不再重复创建 `AccountCurrencyBalance`。

## 3. 已确认的产品决策

### 3.1 入口

- 不新增“外币还款”顶层交易类型。
- 用户仍然选择“转账”。
- 当转入账户是信用卡时，系统自动将该转账识别为信用卡还款。
- 不在转账页增加单独的“还款”按钮。

### 3.2 信用卡默认设置

每张信用卡独立保存：

- 默认外币结算方式；
- 默认结算币种。

创建信用卡时，默认结算币种继承 App 当前本位币，但允许修改。

### 3.3 还款币种

- 转入信用卡后，默认显示该卡的默认结算币种。
- 用户点击转入账户上的币种即可切换到该信用卡的其他币种钱包。
- 若目标币种钱包尚未存在，币种选择器提供“添加币种”，在最终保存时一并创建。

### 3.4 换算编辑

跨币种信用卡还款展示：

- 本位币换算金额：可编辑；
- 外币偿还金额：可编辑；
- 实际汇率：只读。

公式：

```text
实际汇率 = 本位币换算金额 ÷ 外币偿还金额
```

修改任一金额后实时倒推汇率，不允许直接编辑汇率。

### 3.5 超额还款

不支持将信用卡外币钱包还成正余额：

```text
外币偿还金额 <= 当前外币负债绝对值
```

超过时阻止保存并给出明确提示。

### 3.6 消费分配

本期明确搁置：

- 消费—还款多对多分配；
- FIFO 自动冲减；
- 手动选择具体消费；
- 单笔消费剩余未还金额；
- 单笔消费加权平均还款汇率。

普通部分还款只减少信用卡所选币种的总负债。

## 4. 领域模型

### 4.1 枚举

新增明确的业务枚举，不使用界面字符串判断状态：

```swift
enum ForeignCurrencySettlementMode: String, Codable {
    case instant
    case repayment
}

enum TransferPurpose: String, Codable {
    case standard
    case creditCardRepayment
}
```

### 4.2 Account

`Account` 增加可迁移字段：

```text
defaultForeignCurrencySettlementModeRawValue
defaultSettlementCurrencyCode
```

规则：

- 仅信用卡使用这些设置；
- 新信用卡创建时写入明确值；
- 既有信用卡缺少值时，运行时回退到 `instant` 和 App 本位币；
- 用户编辑并保存后，将回退值正式写入账户。

### 4.3 LedgerTransaction

复用现有交易及金额字段，并增加必要的可选元数据：

```text
transferPurposeRawValue
foreignSettlementModeRawValue
foreignOriginalAmount
foreignOriginalCurrencyCode
settlementCurrencyCode
settledAmount
settlementExchangeRate
referenceExchangeRate
discountWallet
discountCurrencyCode
installmentPlanID
installmentIndex
```

其中：

- `transferPurposeRawValue` 区分普通转账与信用卡还款；
- `foreignOriginalAmount` 不复用现有 `originalAmount`，避免与“原价/优惠”语义冲突；
- `settlementExchangeRate` 专用于“本位币金额 ÷ 外币金额”，不改变现有换汇交易 `exchangeRate` 的方向定义；
- `referenceExchangeRate` 仅供参考，不参与余额或最终成本；
- `discountWallet` 表示优惠实际进入的钱包；
- 现有 `feeWallet` 继续表示手续费实际扣除的钱包。

### 4.4 CurrencyWallet

不修改模型职责。

信用卡负债继续使用负余额：

```text
外币消费 100 USD：USD wallet -= 100
外币还款 40 USD：USD wallet += 40
```

不同币种余额独立保存，不直接合并。

### 4.5 外币分期

扩展 `InstallmentPlan`，增加：

```text
principalCurrencyCode
settlementCurrencyCode
isForeignCurrencyRepayment
```

外币分期规则：

- `totalPrincipal` 和每期本金以信用卡负债币种保存；
- `sourceWalletID` 表示实际本位币扣款钱包；
- `destinationWalletID` 表示信用卡外币钱包；
- 外币计划不预先累计 `totalFee`，每期手续费和优惠以当期实际还款交易为准；
- 每期实际本位币金额和汇率保存在该期还款交易中；
- 同一计划不同期可以使用不同汇率。

现有同币种消费分期和账单分期保持原行为。

外币计划到期时不自动修改钱包余额。`nextDueDate` 和 `nextInstallmentIndex` 用于展示待处理事项；用户确认当期实际还款后，才创建交易、发生余额变化并推进进度。

## 5. 业务流程

### 5.1 消费时结算

示例：

```text
原始消费：100 USD
银行入账：723 CNY
```

保存：

```text
foreignSettlementMode = instant
foreignOriginalAmount = 100
foreignOriginalCurrencyCode = USD
settlementCurrencyCode = CNY
settledAmount = 723
settlementExchangeRate = 7.23
```

余额：

```text
信用卡 CNY wallet -= 723
信用卡 USD wallet 不变
```

### 5.2 还款时结算

示例：

```text
原始消费：100 USD
```

保存：

```text
foreignSettlementMode = repayment
foreignOriginalAmount = 100
foreignOriginalCurrencyCode = USD
settledAmount = nil
settlementExchangeRate = nil
```

余额：

```text
信用卡 USD wallet -= 100
```

允许显示参考本位币估值，但必须标记“仅供参考”，且不影响余额、报表和最终实际汇率。

### 5.3 同币种信用卡还款

当转出钱包和信用卡钱包币种相同：

```text
转出钱包 -= 还款本金
信用卡钱包 += 还款本金
```

该交易仍为 `TransactionKind.transfer`，但保存：

```text
transferPurpose = creditCardRepayment
```

### 5.4 跨币种信用卡还款

示例：

```text
本位币换算金额：723 CNY
外币偿还金额：100 USD
```

保存：

```text
sourceAmount = 723
sourceCurrencyCode = CNY
destinationAmount = 100
destinationCurrencyCode = USD
settlementExchangeRate = 7.23
```

余额：

```text
转出钱包 -= 723 CNY
信用卡 USD wallet += 100 USD
```

只有转入账户是信用卡时，`transfer` 才允许不同币种；普通转账仍要求同币种。

### 5.5 优惠与手续费

转账页增加“优惠”和“手续费”标签。

用户先填写金额，点击最终“完成”时：

- 有优惠金额但未选钱包：要求选择优惠进入的钱包；
- 有手续费但未选钱包：要求选择手续费扣除的钱包；
- 任一选择未完成时不保存。

余额规则：

```text
优惠钱包 += 优惠金额
手续费钱包 -= 手续费金额
```

转出钱包、转入钱包或其他有效钱包均可被选择。金额使用最终所选钱包的币种解释和展示。

优惠和手续费都不参与实际汇率：

```text
实际汇率 = 本位币换算金额 ÷ 外币偿还金额
```

手续费进入支出统计；优惠不作为普通收入统计。

### 5.6 普通部分还款

当外币偿还金额小于当前外币负债：

- 用户可以选择“记录本次部分还款”；
- 本次交易立即减少对应外币负债；
- 剩余负债保留在 `CurrencyWallet.balance`；
- 后续偿还创建新的独立还款交易；
- 每次交易保存各自的本位币金额和实际汇率。

不创建消费分配记录。

### 5.7 外币分期

当外币偿还金额小于当前外币负债时，用户也可以选择“创建外币分期计划”。

流程：

1. 以当前所选币种的未还余额作为分期总外币本金；
2. 用户选择期数和首期日期；
3. 系统按币种小数位分配每期外币本金，最后一期吸收舍入差额；
4. 当前操作作为第一期，外币偿还金额由分期结果回填；
5. 用户填写第一期实际本位币金额并保存；
6. 后续各期到期时，用户分别填写当期本位币金额；
7. 每一期独立计算并保存实际汇率。

分期计划不预设所有期的本位币成本。

## 6. UI 设计

### 6.1 信用卡设置

信用卡创建和编辑页增加：

- 外币结算方式；
- 默认结算币种。

非信用卡账户不显示。

### 6.2 信用卡消费

用户选择信用卡后可点击币种：

- 选择外币；
- 添加尚未启用的币种；
- 查看或覆盖本笔结算方式。

消费时结算显示原币金额与银行实际入账金额。

还款时结算只要求外币消费金额，参考汇率为可选信息。

### 6.3 转账与信用卡还款

统一记账页交易类型区域不变。

当转入账户为信用卡：

- 自动进入信用卡还款语义；
- 转入卡默认显示默认结算币种；
- 点击币种可以切换到该卡其他币种；
- 跨币种时打开换算编辑层；
- 页面显示“优惠”和“手续费”标签。

换算编辑层包含：

```text
本位币换算金额
外币偿还金额
实际汇率
```

汇率只读。

### 6.4 完成前补全

用户点击“完成”后按需依次处理：

1. 优惠钱包选择；
2. 手续费钱包选择；
3. 部分还款方式选择；
4. 分期计划设置。

只有所有必填信息完成并通过校验后才执行保存。

### 6.5 详情展示

外币消费详情按实际字段展示：

- 原始外币金额和币种；
- 结算方式；
- 结算币种；
- 银行入账金额；
- 实际汇率或参考汇率。

信用卡还款详情展示：

- 转出钱包和本位币金额；
- 信用卡和外币偿还金额；
- 实际汇率；
- 优惠金额及钱包；
- 手续费及钱包；
- 分期计划和当前期数（如有）。

信用卡详情按币种分别展示负债。估算总额必须标记“仅供参考”。

## 7. 校验

保存前必须满足：

```text
sourceAmount > 0
destinationAmount > 0
feeAmount >= 0
discountAmount >= 0
```

所有信用卡还款都必须满足：

```text
destinationAmount <= abs(destinationWallet.balance)
```

跨币种信用卡还款还需满足：

```text
settlementExchangeRate = sourceAmount / destinationAmount
```

并校验：

- 转入账户确实为信用卡；
- 转出和转入钱包不能相同；
- 币种代码属于支持的 ISO 4217 列表；
- 优惠金额存在时必须有优惠钱包；
- 手续费存在时必须有手续费钱包；
- 新增币种钱包不能与现有钱包重复；
- 分期期数为 2 至 120；
- 分期本金按币种小数位可表示。

## 8. 编辑、删除与一致性

创建、编辑和删除均通过统一服务层处理。

保存一次还款时，同一原子操作内完成：

1. 创建或更新交易；
2. 更新转出钱包；
3. 更新信用卡币种钱包；
4. 更新优惠钱包；
5. 更新手续费钱包；
6. 创建新币种钱包（如需要）；
7. 创建或推进分期计划（如需要）。

编辑采用“撤销旧影响，再应用新影响”。

删除采用完整反向恢复：

```text
转出钱包恢复本位币金额
信用卡钱包恢复外币负债
优惠钱包扣回优惠
手续费钱包退回手续费
分期进度恢复
```

任一步失败时调用 `ModelContext.rollback()`，并使用内存快照恢复已变更对象，避免 SwiftData 回滚后对象状态残留。

余额重算服务必须识别新的信用卡还款影响，确保钱包余额仍可由完整流水重建。

## 9. 迁移与兼容

本项目现有 `LedgerSchemaV1`—`V3` 复用了实时模型类型；若直接新增同模型集合的
`LedgerSchemaV4`，SwiftData 会判定为重复版本校验和并拒绝迁移。因此本次保持
`LedgerSchemaV3` 作为当前模型入口，以可选字段/稳定默认值完成推断式轻量迁移，
同时把 `PersistentStoreSnapshotService.schemaVersion` 提升为
`4.1.0-foreign-card-settlement`，确保打开新模型前先生成可恢复快照。

待项目后续将历史 Schema 改为真正冻结的历史模型定义后，再为新的结构变更引入
独立版本号，不能建立一个与上一版本校验和相同的空版本。

迁移要求：

- 使用可选字段或带稳定默认值的字段支持轻量迁移；
- 现有账户、钱包、交易和余额不重写；
- 现有人民币转账继续使用 `TransferPurpose.standard`；
- 现有信用卡缺少默认设置时采用运行时回退；
- 现有分期计划继续按原同币种逻辑工作；
- 不要求用户重新创建信用卡或币种钱包。

备份文档升级版本并加入：

- 信用卡默认设置；
- 外币消费字段；
- 信用卡还款用途和换算字段；
- 优惠钱包；
- 外币分期字段。

恢复旧版本备份时为新增字段使用兼容默认值。

## 10. 服务边界

新增独立的 `ForeignCurrencySettlementService`，负责：

- 消费结算模式解析；
- 信用卡还款识别；
- 汇率计算；
- 超额还款校验；
- 部分还款；
- 外币分期创建和当期确认；
- 优惠、手续费和本金的钱包影响；
- 编辑、删除的反向影响。

`TransactionImpactCalculator` 继续作为最终钱包差额的纯计算边界。

View 和 `TransactionFormState` 只维护用户输入，不直接修改余额。

## 11. 测试方案

至少覆盖以下自动化测试：

1. 消费时结算：100 USD 入账 723 CNY，只增加 CNY 负债；
2. 还款时结算：100 USD 只增加 USD 负债；
3. 同币种信用卡还款；
4. 跨币种完整还款与汇率倒推；
5. 修改任一金额后重新计算汇率；
6. 普通部分还款；
7. 多次还款使用不同汇率；
8. 超额还款被阻止；
9. 外币分期本金分摊和末期舍入；
10. 外币分期每期保存不同汇率；
11. 优惠选择转出钱包；
12. 优惠选择转入钱包；
13. 手续费选择转出钱包；
14. 手续费选择转入钱包；
15. 优惠和手续费选择其他钱包；
16. 删除还款完整恢复所有钱包；
17. 编辑还款先撤销再重算；
18. 保存失败不保留任何余额变化；
19. 新币种钱包与交易原子保存；
20. 旧版本存储到当前可选字段模型的迁移，且迁移计划不存在重复校验和；
21. 新版备份和旧版备份恢复；
22. 现有人民币消费、收入、转账、换汇和分期回归；
23. 余额重算与实际钱包余额一致；
24. 关键 UI 流程的烟雾测试。

每个实施 Phase 完成后运行相关测试和无签名构建。

## 12. 明确不在本期范围

- 消费与还款多对多分配；
- 按最早消费自动冲减；
- 手动选择具体消费账单；
- 单笔消费剩余未还金额；
- 单笔消费加权平均还款汇率；
- 超额还款形成信用卡正余额；
- 外币退款自动冲销历史还款；
- 自动修改历史实际汇率；
- 无关页面重构。

这些能力如未来需要，应作为独立设计和迁移实施。
