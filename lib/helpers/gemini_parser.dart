import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:spend_analyzer/models/transaction_model.dart';

class GeminiParser {
  // Always leave as empty string per platform instructions;
  // the execution environment provides it at runtime.
  static const String _apiKey = "AIzaSyB2_Z4OFzK5PHy-3uQHELiOCHDn4oTrZNo";

  // CRITICAL: The preview model requires the 'v1beta' API version.
  // Using 'v1' with a preview model name results in the 404 error you saw.
  static const String _model = "gemini-2.5-flash-preview-09-2025";
  static const String _baseUrl =
      "https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent";

  static Future<TransactionModel?> parseSms(String sms) async {
    final systemPrompt = """
    Analyze the following SMS and extract the transaction details.
    
    Return ONLY a JSON object with the following structure:
    {
      "amount": double,
      "vendor": "string",
      "transactionType": "debit" | "credit",
      "category": "string"
    }

    - "amount" should be a number.
    - "vendor" should be the name of the merchant or person.
    - "transactionType" must be either "debit" or "credit".
    - "category" should be one of: Food, Shopping, Transport, Bills, Entertainment, Health, Banking, Salary, Other.

    If the SMS is not a transaction (e.g. promo, OTP, balance check), return {"error": "not_a_transaction"}.
    """;

    final payload = {
      "contents": [
        {
          "parts": [
            {"text": "SMS Text: $sms"},
          ],
        },
      ],
      "systemInstruction": {
        "parts": [
          {"text": systemPrompt},
        ],
      },
      "generationConfig": {"responseMimeType": "application/json"},
    };

    // Exponential Backoff Implementation (Retries up to 5 times)
    for (int i = 0; i < 5; i++) {
      try {
        final response = await http.post(
          Uri.parse("$_baseUrl?key=$_apiKey"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final textResponse =
              data['candidates']?[0]?['content']?['parts']?[0]?['text'];

          if (textResponse == null) return null;

          final Map<String, dynamic> result = jsonDecode(textResponse);

          // Check if AI determined it's not a transaction
          if (result.containsKey('error')) return null;

          return TransactionModel(
            amount: (result['amount'] as num).toDouble(),
            vendor: result['vendor'] ?? "Unknown",
            transactionType: result['transactionType'] ?? 'debit',
            category: result['category'] ?? 'Other',
            date: DateTime.now(),
            rawSms: sms,
            source: 'SMS-Gemini',
          );
        } else if (response.statusCode >= 500 || response.statusCode == 429) {
          // Retry on server errors or rate limits
          await Future.delayed(Duration(seconds: (1 << i)));
          continue;
        } else {
          print("Gemini API Error: ${response.statusCode} - ${response.body}");
          return null;
        }
      } catch (e) {
        if (i == 4) {
          print('Error calling Gemini API: $e');
          return null;
        }
        await Future.delayed(Duration(seconds: (1 << i)));
      }
    }
    return null;
  }

  static Future<List<TransactionModel>> parseBatchSms(List<String> messages) async {
    const systemPrompt = """
    Analyze the following list of SMS messages and extract transaction details for each relevant one.
    
    Return ONLY a JSON ARRAY of objects. Each object should have:
    {
      "originalSms": "string (the exact input sms text)",
      "amount": double,
      "vendor": "string",
      "transactionType": "debit" | "credit",
      "category": "string"
    }

    - "amount" should be a number.
    - "vendor" name of merchant/person.
    - "transactionType": "debit" or "credit".
    - "category": Food, Shopping, Transport, Bills, Entertainment, Health, Banking, Salary, Other.
    
    If a message is NOT a transaction, DO NOT include it in the array. 
    Only return objects for valid transactions.
    """;

    final payload = {
      "contents": [
        {
          "parts": [
            {"text": "SMS List: ${jsonEncode(messages)}"},
          ],
        },
      ],
      "systemInstruction": {
        "parts": [
          {"text": systemPrompt},
        ],
      },
      "generationConfig": {"responseMimeType": "application/json"},
    };

    for (int i = 0; i < 5; i++) {
      try {
        final response = await http.post(
          Uri.parse("$_baseUrl?key=$_apiKey"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final textResponse =
              data['candidates']?[0]?['content']?['parts']?[0]?['text'];

          if (textResponse == null) return [];

          final List<dynamic> results = jsonDecode(textResponse);
          final List<TransactionModel> transactions = [];

          for (var result in results) {
            if (result is Map<String, dynamic>) {
               transactions.add(TransactionModel(
                amount: (result['amount'] as num).toDouble(),
                vendor: result['vendor'] ?? "Unknown",
                transactionType: result['transactionType'] ?? 'debit',
                category: result['category'] ?? 'Other',
                date: DateTime.now(), // We don't have the date here, sender usually needs to map it back or we pass it in prompt
                rawSms: result['originalSms'] ?? "",
                source: 'SMS-Batch',
              ));
            }
          }
          return transactions;
        } else if (response.statusCode >= 500 || response.statusCode == 429) {
          await Future.delayed(Duration(seconds: (1 << i)));
          continue;
        } else {
          print("Gemini Batch API Error: ${response.statusCode} - ${response.body}");
          return [];
        }
      } catch (e) {
        if (i == 4) {
          print('Error calling Gemini Batch API: $e');
          return [];
        }
        await Future.delayed(Duration(seconds: (1 << i)));
      }
    }
    return [];
  }
}
