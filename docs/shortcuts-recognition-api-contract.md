# 快捷指令识别 API 契约

快捷指令完成“截屏 → 从图像提取文本”后，先调用 App 的“获取记账识别候选”，再向用户配置的 API 发出 JSON 请求。

```json
{
  "ocrText": "支付成功 餐饮 CNY 28.00 招商银行1234",
  "context": {
    "bookID": "…",
    "bookName": "日常",
    "accounts": [{"walletID":"…","accountName":"招商银行 1234","accountNote":null,"currencyCode":"CNY"}],
    "categories": [{"name":"餐饮","type":"expense"}]
  }
}
```

API 必须返回 JSON（可以直接作为“识别并记账”的 `识别结果 JSON` 输入）：

```json
{"results":[{"type":"expense","paidAmount":"28.00","originalAmount":null,"discountAmount":"0","feeAmount":"0","currencyCode":"CNY","date":"2026-07-12","time":"18:00","merchantOrCounterparty":"示例商户","sourceAccountHint":"招商银行 1234","destinationAccountHint":null,"categoryCandidate":"餐饮","note":null,"confidence":{"type":0.99,"paidAmount":0.99,"currencyCode":0.99,"account":0.99,"category":0.99}}]}
```

`accountName`、`currencyCode` 与 `categoryCandidate` 必须来自 `context` 中的候选。App 会再次验证金额、OCR 证据、币种、账户、分类与重复记录；不满足条件时不会自动改动余额。
