class TransactionModel {
  int? id;
  double amount;
  String vendor;
  String? category;
  DateTime date;
  String? rawSms;
  String source;

  TransactionModel({
    this.id,
    required this.amount,
    required this.vendor,
    this.category,
    required this.date,
    this.rawSms,
    required this.source,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'vendor': vendor,
      'category': category,
      'date': date.toIso8601String(),
      'rawSms': rawSms,
      'source': source,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      amount: map['amount'],
      vendor: map['vendor'],
      category: map['category'],
      date: DateTime.parse(map['date']),
      rawSms: map['rawSms'],
      source: map['source'],
    );
  }
}
