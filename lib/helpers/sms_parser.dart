import 'package:spend_analyzer/models/transaction_model.dart';

class SmsParser {
  /// Parses raw bank SMS messages and returns a [TransactionModel] if it is a
  /// valid debit or credit transaction. Returns null if ambiguous, invalid, or blacklisted.
  static TransactionModel? parseSms(String sms) {
    // 1. The Blacklist
    final blacklist = [
      'otp',
      'recharge',
      'expiring',
      'due',
      'reminder',
      'balance is',
      'data pack',
      'clear your dues',
    ];

    final lowerSms = sms.toLowerCase();
    for (var word in blacklist) {
      if (lowerSms.contains(word)) {
        return null;
      }
    }

    // 2. Transaction Type Detection using word boundaries (\b)
    final debitRegex = RegExp(
      r'\b(spent|debited|paid|deducted|dr)\b',
      caseSensitive: false,
    );
    final creditRegex = RegExp(
      r'\b(credited|received|added|deposit|cr)\b',
      caseSensitive: false,
    );

    bool isDebit = debitRegex.hasMatch(sms);
    bool isCredit = creditRegex.hasMatch(sms);

    String transactionType;
    if (isDebit && !isCredit) {
      transactionType = 'debit';
    } else if (isCredit && !isDebit) {
      transactionType = 'credit';
    } else {
      // Ambiguous (both present) or neither keywords present.
      return null;
    }

    // 3. Amount Extraction
    // Matches patterns like "Rs. 500", "INR 1,200.50", "$50", or raw amount following a keyword
    // Uses lookarounds or direct capturing groups: ((?:rs\.?|inr|\$|eur|£)\s*)?([\d,]+\.?\d*)
    // We try to find amount preceded by currency symbol first, then fallback to keywords.
    final amountSymbolRegex = RegExp(
      r'(?:rs\.?|inr|\$|eur|£)\s*([\d,]+\.\d{1,2}|[\d,]+)',
      caseSensitive: false,
    );
    var amountMatch = amountSymbolRegex.firstMatch(sms);

    if (amountMatch == null) {
      // Fallback: looking for amount near keywords. E.g "debited by 500.00"
      final amountActionRegex = RegExp(
        r'(?:debited by|spent|paid|deducted|credited by|received)\s+([\d,]+\.\d{1,2}|[\d,]+)',
        caseSensitive: false,
      );
      amountMatch = amountActionRegex.firstMatch(sms);
    }

    double? amount;
    if (amountMatch != null) {
      final matchStr = amountMatch.group(1)?.replaceAll(',', '');
      if (matchStr != null) {
        amount = double.tryParse(matchStr);
      }
    }

    if (amount == null) return null;

    // 4. Vendor Extraction
    String vendor = 'Unknown';

    // Ordered by precedence. It captures the string after the keyword until it hits
    // trailing junk like date, ref, upi, using, or punctuation.
    final List<RegExp> vendorPatterns = [
      RegExp(
        r'(?:paid to|sent to|transfer to|trf to|to)\s+([A-Za-z0-9\s&*@\-]+?)(?=(?:\s+(?:on|ref|upi|at|using|via|date))|\.|$)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:at|on|vpa)\s+([A-Za-z0-9\s&*@\-]+?)(?=(?:\s+(?:on|ref|upi|at|using|via|date))|\.|$)',
        caseSensitive: false,
      ),
      RegExp(
        r'by\s+([A-Za-z0-9\s&*@\-]+?)(?=(?:\s+(?:on|ref|upi|at|using|via|date))|\.|$)',
        caseSensitive: false,
      ),
    ];

    for (var pattern in vendorPatterns) {
      final match = pattern.firstMatch(sms);
      if (match != null) {
        final extracted = match.group(1)?.trim();
        if (extracted != null && extracted.isNotEmpty) {
          vendor = extracted;
          // Clean up trailing chunks manually if regex lookahead missed something
          final junkWords = [
            ' on ',
            ' ref no ',
            ' upi id ',
            ' using ',
            ' via ',
          ];
          for (var junk in junkWords) {
            final junkIndex = vendor.toLowerCase().indexOf(junk);
            if (junkIndex != -1) {
              vendor = vendor.substring(0, junkIndex).trim();
            }
          }
          break; // Stop at the first valid vendor match
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

// -----------------------------------------------------------------------------
// Testing Suite
// -----------------------------------------------------------------------------
void main() {
  final testMessages = [
    // 1. Standard UPI Debit with "paid to" and extra junk
    "Dear User, Rs. 1,250.50 has been debited from A/c XX456 on 12-Oct-23. Paid to Amazon India via UPI ref no 123456789.",

    // 2. SBI format with no currency symbol and "trf to"
    "Dear UPI user A/C X7953 debited by 40.0 on date 07Dec25 trf to MUNEER N P Refno 115280257841 If not u? call-1800111109 for other services-18001234-SBI",

    // 3. Standard Credit with "at"
    "Your a/c no. X1234 is credited with INR 5,000.00 on 24/11/23 at INDUSIND BANK. Total Bal: INR 15,000.00",

    // 4. Blacklist Trigger: Contains "paid" and amount, but also "recharge" and "due"
    "Reminder: Your mobile recharge of Rs 299 is due today. It has not been paid yet.",

    // 5. Ambiguous: Contains both 'debited' and 'credited'
    "An amount of Rs 500 debited from A/C 1234 was credited back due to a failed transaction.",
  ];

  print('--- Running SmsParser Tests ---\n');
  for (int i = 0; i < testMessages.length; i++) {
    print('Test Message ${i + 1}:');
    print('SMS: "${testMessages[i]}"');
    final result = SmsParser.parseSms(testMessages[i]);

    if (result == null) {
      print('Result: NULL (Ignored, Error, or Blacklisted)\n');
    } else {
      print('Result:');
      print('  Type:   ${result.transactionType}');
      print('  Amount: ${result.amount}');
      print('  Vendor: ${result.vendor}\n');
    }
  }
}
