# iCost 功能等价补全验收记录

日期：2026-07-13
范围：除桌面/锁屏小组件、位置附件外的设计功能
策略：不复刻 iCost UI；既有逻辑不变时补缺，更严谨的账务规则覆盖底层；非必要不启动 Simulator。

## 功能矩阵

- 核心流水：五类交易统一草稿/校验/余额影响；新增、完整编辑、复制、删除与负余额确认。
- 查询：关键词、账本、账户、钱包币种、类型、分类、标签、日期、金额、排序和月份隔离。
- 丰富属性：二级分类、标签、商户、图片附件、组合付款、模板和批量操作。
- 关系交易：多次部分退款、报销关系、累计上限、净支出和个人承担语义。
- 自动化：周期规则、补生成、暂停/恢复/归档；消费分期与账单分期、尾差和幂等生成键。
- 智能入口：截图识别、App Intents、自然语言文本、系统语音听写和自有 `multiledger://entry`；全部先确认。
- 资产计划：资产/负债/净资产、变化解释、余额对账、周/月/年总预算和分类预算、存钱目标独立分配。
- 报表：日/周/月/年趋势，分类、标签、账户、账本构成和账单日历。
- 数据：59 种 ISO 4217 币种；CSV/TSV/XLSX、iCost/支付宝/微信/云闪付预设、映射预览、去重、错误报告和撤销。
- 备份恢复：全部财务模型、自动化、导入记录与附件内容；版本校验、旧备份迁移、恢复前快照和失败回退。
- 同步：默认关闭的 CloudKit 私有快照、删除标记、双端冲突副本、保留本机/使用云端和删除云端数据。
- 安全体验：Keychain 密码摘要、Face ID/Touch ID/Optic ID、全窗口后台遮挡、秒开记账和系统/浅色/深色外观。
- 数据迁移：旧 8 模型 Schema v1 到当前 23 模型 Schema v2 的轻量迁移；迁移前 store/WAL/SHM 快照与下次启动恢复。

## 静态验收

- `git diff --check` 无空白错误。
- `Info.plist` 与 entitlements 通过 `plutil` 校验。
- Debug 测试目标通过 generic iOS `build-for-testing`，不启动 Simulator。
- generic iOS 静态分析通过。
- 构建产物注册 `multiledger`，并包含麦克风、语音识别和 Face ID 用途说明。
- SwiftData 本地配置显式使用 `.none`，不会因加入 iCloud capability 而绕过“同步默认关闭”。

## 需要真机签名环境确认的系统能力

- Apple Developer 账号中 `iCloud.com.ian.MultiCurrencyLedger` 容器与生产 CloudKit Schema。
- Face ID/Touch ID/Optic ID 提示与后台任务切换截图遮挡。
- 麦克风和 Speech 授权、中文连续听写。
- `multiledger://entry`、App Intent 和快捷指令从系统侧唤起。

这些确认不影响纯逻辑和编译验收；为了遵守“非必要不使用 Simulator”，本轮未启动 Simulator。
