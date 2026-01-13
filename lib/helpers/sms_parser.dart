import 'package:intl/intl.dart';
import 'package:spend_analyzer/models/transaction_model.dart';

class SmsParser {
  static TransactionModel? parseSms(String sms) {
    final debitKeywords = ['spent', 'debited', 'paid', 'charged'];
    final creditKeywords = ['credited', 'received', 'refund'];

    String? transactionType;

    if (debitKeywords.any((keyword) => sms.toLowerCase().contains(keyword))) {
      transactionType = 'debit';
    } else if (creditKeywords.any((keyword) => sms.toLowerCase().contains(keyword))) {
      transactionType = 'credit';
    }

    if (transactionType == null) {
      return null;
    }

    // Regex to find amount - more specific
    final amountRegex = RegExp(r'(?:rs|inr|\$|eur|£|sgd|recharge of)\.?\s*([\d,]+\.?\d+)', caseSensitive: false);
    final amountMatch = amountRegex.firstMatch(sms);
    double? amount;
    if (amountMatch != null) {
      amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    }

    if (amount == null) return null;

    // Regex to find vendor - more greedy
    final vendorRegex = RegExp(r'(?:at|to|on|by|for)\s+([a-z0-9\s.-]+?)(?=\s+on\s|\s+at\s|\s+for\s|Ref No|\.|$)', caseSensitive: false);
    final vendorMatch = vendorRegex.firstMatch(sms);
    String vendor = 'Unknown';
    if (vendorMatch != null) {
      vendor = vendorMatch.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
    }

    // Regex for date and time
    DateTime date = DateTime.now();
    final dateRegex = RegExp(r'(\d{1,2}-\d{1,2}-\d{2,4}|\d{1,2}\/\d{1,2}\/\d{2,4}|\d{1,2}\s(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s\d{2,4})', caseSensitive: false);
    final dateMatch = dateRegex.firstMatch(sms);
    if (dateMatch != null) {
      try {
        date = DateFormat("dd-MM-yyyy").parse(dateMatch.group(1)!.replaceAll('/', '-'));
      } catch (e) {
        try {
          date = DateFormat("dd MMM yyyy").parse(dateMatch.group(1)!);
        } catch (e) {
          // Could not parse date, use current date
        }
      }
    }


    return TransactionModel(
      amount: amount,
      vendor: vendor,
      date: date,
      rawSms: sms,
      source: 'SMS',
      transactionType: transactionType,
    );
  }
}

