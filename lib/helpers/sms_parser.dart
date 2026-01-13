import 'package:spend_analyzer/models/transaction_model.dart';

class SmsParser {
  static TransactionModel? parseSms(String sms) {
    final keywords = ['spent', 'debited', 'paid'];
    if (!keywords.any((keyword) => sms.toLowerCase().contains(keyword))) {
      return null;
    }

    // Regex to find amount (handles integers and decimals)
    final amountRegex = RegExp(r'(?:rs|inr|\$|eur|£)\.?\s*([\d,]+\.?\d*)', caseSensitive: false);
    final amountMatch = amountRegex.firstMatch(sms);
    double? amount;
    if (amountMatch != null) {
      amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    }

    if (amount == null) return null;

    // Regex to find vendor
    // This is a simple example, a more robust solution would be needed for real-world scenarios
    final vendorRegex = RegExp(r'(?:at|to|on)\s+([a-z0-9\s]+)(?:\s+on|\s+at)', caseSensitive: false);
    final vendorMatch = vendorRegex.firstMatch(sms);
    String vendor = 'Unknown';
    if (vendorMatch != null) {
      vendor = vendorMatch.group(1)!.trim();
    } else {
        final vendorRegex2 = RegExp(r'by\s+([a-z0-9\s]+)(?:\s+on)', caseSensitive: false);
        final vendorMatch2 = vendorRegex2.firstMatch(sms);
        if (vendorMatch2 != null) {
            vendor = vendorMatch2.group(1)!.trim();
        }
    }


    return TransactionModel(
      amount: amount,
      vendor: vendor,
      date: DateTime.now(),
      rawSms: sms,
      source: 'SMS',
    );
  }
}
