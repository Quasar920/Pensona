import AVFAudio
import Foundation
import Speech

enum SmartDraftError: LocalizedError, Equatable {
    case emptyText
    case missingAmount
    case missingWallet
    case missingDestination
    case missingDestinationAmount
    case speechPermissionDenied
    case speechUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyText: AppLocalization.string( "请输入或说出一条记账描述")
        case .missingAmount: AppLocalization.string( "没有识别到金额，请补充数字金额")
        case .missingWallet: AppLocalization.string( "没有可用钱包，请先创建账户，或在描述中写明账户名称")
        case .missingDestination: AppLocalization.string( "转账或换汇需要在描述中依次写出来源账户和目标账户")
        case .missingDestinationAmount: AppLocalization.string( "换汇需要写出换出金额和换入金额")
        case .speechPermissionDenied: AppLocalization.string( "请在系统设置中允许语音识别和麦克风权限")
        case .speechUnavailable: AppLocalization.string( "当前语音识别服务不可用")
        }
    }
}

struct SmartDraftParseResult {
    let draft: TransactionDraft
    let recognizedFields: [String]
    let warnings: [String]
}

struct SmartDraftService {
    func parse(
        _ text: String,
        wallets: [CurrencyWallet],
        categories: [LedgerCategory],
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> SmartDraftParseResult {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw SmartDraftError.emptyText }
        let kind = transactionKind(clean)
        let amounts = amountMatches(clean)
        guard let amount = amounts.first, amount > 0 else { throw SmartDraftError.missingAmount }
        let mentionedWallets = wallets.compactMap { wallet -> (Range<String.Index>, CurrencyWallet)? in
            guard let name = wallet.account?.name, !name.isEmpty,
                  let range = clean.range(of: name, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
            return (range, wallet)
        }.sorted { $0.0.lowerBound < $1.0.lowerBound }.map(\.1)
        let currency = recognizedCurrency(clean)
        let source = mentionedWallets.first(where: { currency == nil || $0.currencyCode == currency })
            ?? wallets.first(where: { currency == nil || $0.currencyCode == currency })
        guard let source else { throw SmartDraftError.missingWallet }

        let isMovement = kind == .transfer || kind == .exchange
        let destination = isMovement
            ? mentionedWallets.dropFirst().first(where: { candidate in
                candidate.id != source.id
                    && (kind == .exchange
                        ? candidate.currencyCode != source.currencyCode
                        : candidate.currencyCode == source.currencyCode)
            })
            : nil
        if isMovement, destination == nil { throw SmartDraftError.missingDestination }
        let destinationAmount = kind == .exchange ? amounts.dropFirst().first : nil
        if kind == .exchange, destinationAmount == nil { throw SmartDraftError.missingDestinationAmount }

        let categoryKind: CategoryKind = kind == .income ? .income : .expense
        let category = categories.first { value in
            value.type == categoryKind
                && clean.range(of: value.name, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        let date = recognizedDate(clean, now: now, calendar: calendar)
        let draft = TransactionDraft(
            type: kind,
            amount: amount,
            sourceWallet: source,
            destinationWallet: destination,
            destinationAmount: destinationAmount,
            date: date,
            note: clean,
            category: category
        )
        _ = try TransactionImpactCalculator().deltas(for: draft)
        var fields = [
            kind.title,
            AppLocalization.string("金额"),
            source.account?.name ?? AppLocalization.string("账户")
        ]
        if category != nil { fields.append("分类") }
        if destination != nil { fields.append("目标账户") }
        if date != calendar.startOfDay(for: now) { fields.append("日期") }
        var warnings: [String] = []
        if (kind == .expense || kind == .income), category == nil {
            warnings.append("未识别分类，请在确认页选择")
        }
        if mentionedWallets.isEmpty {
            warnings.append("未写明账户，已使用当前账本的首个匹配钱包")
        }
        return SmartDraftParseResult(draft: draft, recognizedFields: fields, warnings: warnings)
    }

    private func transactionKind(_ text: String) -> TransactionKind {
        let value = text.lowercased()
        if ["换汇", "兑换", "exchange"].contains(where: value.contains) { return .exchange }
        if ["转账", "转给", "转入", "transfer"].contains(where: value.contains) { return .transfer }
        if ["收入", "工资", "收款", "奖金", "报销", "income"].contains(where: value.contains) { return .income }
        return .expense
    }

    private func amountMatches(_ text: String) -> [Decimal] {
        guard let expression = try? NSRegularExpression(pattern: #"(?<![\d])\d{1,12}(?:[\.,]\d{1,3})?"#) else { return [] }
        let value = text
            .replacingOccurrences(of: #"20\d{2}[-/年]\d{1,2}[-/月]\d{1,2}日?"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\d{1,2}:\d{2}(?::\d{2})?"#, with: " ", options: .regularExpression)
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard let range = Range(match.range, in: value) else { return nil }
            let raw = String(value[range]).replacingOccurrences(of: ",", with: ".")
            return Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
        }
    }

    private func recognizedCurrency(_ text: String) -> String? {
        let upper = text.uppercased()
        if upper.contains("¥") || upper.contains("￥") || text.contains("人民币") { return "CNY" }
        if upper.contains("$") && !upper.contains("HK$") { return "USD" }
        return SupportedCurrency.allCases.first { upper.contains($0.rawValue) }?.rawValue
    }

    private func recognizedDate(_ text: String, now: Date, calendar: Calendar) -> Date {
        if text.contains("前天") { return calendar.date(byAdding: .day, value: -2, to: now) ?? now }
        if text.contains("昨天") || text.contains("昨日") {
            return calendar.date(byAdding: .day, value: -1, to: now) ?? now
        }
        if let expression = try? NSRegularExpression(pattern: #"(20\d{2})[-/年](\d{1,2})[-/月](\d{1,2})日?"#),
           let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           match.numberOfRanges == 4,
           let yearRange = Range(match.range(at: 1), in: text),
           let monthRange = Range(match.range(at: 2), in: text),
           let dayRange = Range(match.range(at: 3), in: text),
           let year = Int(text[yearRange]), let month = Int(text[monthRange]), let day = Int(text[dayRange]),
           let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) {
            return date
        }
        return now
    }
}

@MainActor
final class SpeechDraftTranscriber: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        guard !isRecording else { return }
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            errorMessage = SmartDraftError.speechPermissionDenied.localizedDescription
            return
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard microphone else {
            errorMessage = SmartDraftError.speechPermissionDenied.localizedDescription
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = SmartDraftError.speechUnavailable.localizedDescription
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            errorMessage = nil
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result { self?.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self?.stop() }
                }
            }
        } catch {
            stop()
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
