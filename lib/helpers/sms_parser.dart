import 'package:spend_analyzer/models/transaction_model.dart';

class SmsParser {
  static TransactionModel? parseSms(String sms) {
    final debitKeywords = ['spent', 'debited', 'paid', 'deducted'];
    final creditKeywords = ['credited', 'received', 'added', 'deposit'];

    bool isDebit = debitKeywords.any(
      (keyword) => sms.toLowerCase().contains(keyword),
    );
    bool isCredit = creditKeywords.any(
      (keyword) => sms.toLowerCase().contains(keyword),
    );

    String transactionType;

    if (isDebit && !isCredit) {
      transactionType = 'debit';
    } else if (isCredit && !isDebit) {
      transactionType = 'credit';
    } else {
      // If both debit and credit keywords are present, or neither,
      // it's ambiguous or not a relevant transaction.
      return null;
    }

    // Regex to find amount (handles integers and decimals)
    final amountRegex = RegExp(
      r'(?:rs\.?|inr|\$|eur|£)\s*([\d,]+\.?\d*)',
      caseSensitive: false,
    );
    var amountMatch = amountRegex.firstMatch(sms);

    // Fallback for direct "debited by [amount]" or "spent [amount]"
    if (amountMatch == null) {
      final amountRegexFallback = RegExp(
        r'(?:debited by|spent|paid)\s+([\d,]+\.?\d*)',
        caseSensitive: false,
      );
      amountMatch = amountRegexFallback.firstMatch(sms);
    }

    double? amount;
    if (amountMatch != null) {
      amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    }

    if (amount == null) return null;

    // Regex to find vendor
    String vendor = 'Unknown';

    // Pattern 1: paid/sent/trf to [Vendor]
    final vendorRegexTo = RegExp(
      r'(?:paid to|sent to|trf to|to)\s+([A-Za-z0-9\s]+?)(?:\s+on|\s+ref|\s+upi|\s+at|\.|$)',
      caseSensitive: false,
    );
    final vendorMatchTo = vendorRegexTo.firstMatch(sms);

    if (vendorMatchTo != null) {
      vendor = vendorMatchTo.group(1)!.trim();
    } else {
      // Pattern 2: at/on [Vendor]
      final vendorRegexAt = RegExp(
        r'(?:at|on)\s+([A-Za-z0-9\s]+?)(?:\s+on|\s+at|\.|$)',
        caseSensitive: false,
      );
      final vendorMatchAt = vendorRegexAt.firstMatch(sms);
      if (vendorMatchAt != null) {
        vendor = vendorMatchAt.group(1)!.trim();
      } else {
        // Pattern 3: by [Vendor]
        final vendorRegexBy = RegExp(
          r'by\s+([A-Za-z0-9\s]+?)(?:\s+on|\.|$)',
          caseSensitive: false,
        );
        final vendorMatchBy = vendorRegexBy.firstMatch(sms);
        if (vendorMatchBy != null) {
          vendor = vendorMatchBy.group(1)!.trim();
        }
      }
    }

    return TransactionModel(
      amount: amount,
      vendor: vendor,
      date: DateTime.now(),
      rawSms: sms,
      source: 'SMS',
      transactionType: transactionType,
    );
  }
}
