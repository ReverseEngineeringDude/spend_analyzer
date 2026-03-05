import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spend_analyzer/models/transaction_model.dart';

class AiService {
  static final AiService _instance = AiService._internal();
  factory AiService() => _instance;
  AiService._internal();

  Future<Map<int, String>> categorizeTransactions(
    List<TransactionModel> transactions,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key') ?? '';

    if (apiKey.isEmpty) {
      throw Exception(
        'API Key not configured. Please add it in Profile Settings.',
      );
    }

    final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);

    if (transactions.isEmpty) return {};

    // Prepare prompt data
    final transactionsData = transactions
        .map(
          (t) => {
            'id': t.id,
            'vendor': t.vendor,
            'amount': t.amount,
            'type': t.transactionType,
            'rawSms': t.rawSms ?? '',
          },
        )
        .toList();

    final prompt =
        '''
      You are an intelligent financial categorization assistant. I am providing you with a list of transactions in JSON format.
      Your task is to assign a single category string to each transaction id.
      
      The available categories are strictly: ["Shopping", "Bills", "Transport", "Food", "Entertainment", "Health", "Others"]

      Analyze the vendor name and optionally the rawSms to determine the most fitting category.
      If it is a credit (income), just use "Others" or leave it. We mainly care about expenses.

      Return a JSON object where keys are the transaction IDs (as strings) and values are the chosen category strings.
      Do not wrap it in markdown block quotes (```json), return raw JSON only.

      Input data:
      ${jsonEncode(transactionsData)}
    ''';

    try {
      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);

      if (response.text == null || response.text!.isEmpty) {
        throw Exception("Empty response from Gemini.");
      }

      // Clean up potential markdown formatting from Gemini
      String rawJson = response.text!.trim();
      if (rawJson.startsWith('```json')) {
        rawJson = rawJson.substring(7);
      }
      if (rawJson.endsWith('```')) {
        rawJson = rawJson.substring(0, rawJson.length - 3);
      }

      final Map<String, dynamic> decodedJson = jsonDecode(rawJson.trim());

      final Map<int, String> categoryMap = {};
      decodedJson.forEach((key, value) {
        final id = int.tryParse(key);
        if (id != null && value is String) {
          categoryMap[id] = value;
        }
      });
      return categoryMap;
    } catch (e) {
      throw Exception('Failed to categorize: $e');
    }
  }
}
