import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:spend_analyzer/helpers/database_helper.dart';
import 'package:spend_analyzer/helpers/sms_parser.dart';
import 'package:spend_analyzer/models/transaction_model.dart';
import 'package:another_telephony/telephony.dart';

@pragma('vm:entry-point')
Future<void> onBackgroundMessage(SmsMessage message) async {
  final transaction = SmsParser.parseSms(message.body ?? "");
  if (transaction != null) {
    await DatabaseHelper().insertTransaction(transaction);
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<TransactionModel>> _transactionsFuture;
  final Telephony telephony = Telephony.instance;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
    _initTelephony();
  }

  void _initTelephony() async {
    final permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
    if (permissionsGranted ?? false) {
      telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) {
          final transaction = SmsParser.parseSms(message.body ?? "");
          if (transaction != null) {
            DatabaseHelper().insertTransaction(transaction).then((_) {
              _loadTransactions();
            });
          }
        },
        onBackgroundMessage: onBackgroundMessage,
      );
    }
  }

  void _loadTransactions() {
    setState(() {
      _transactionsFuture = DatabaseHelper().getAllTransactions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spend Analyzer'),
      ),
      body: FutureBuilder<List<TransactionModel>>(
        future: _transactionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No transactions yet.'));
          }

          final transactions = snapshot.data!;
          return ListView.builder(
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final transaction = transactions[index];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    transaction.vendor.isNotEmpty ? transaction.vendor[0] : 'U',
                  ),
                ),
                title: Text(transaction.vendor),
                subtitle: Text(
                  DateFormat.yMMMd().add_jm().format(transaction.date),
                ),
                trailing: Text(
                  '₹${transaction.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showManualEntryDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showManualEntryDialog() {
    final amountController = TextEditingController();
    final vendorController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Transaction'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: vendorController,
                decoration: const InputDecoration(labelText: 'Vendor'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text);
                final vendor = vendorController.text;
                final navigator = Navigator.of(context);

                if (amount != null && vendor.isNotEmpty) {
                  final newTransaction = TransactionModel(
                    amount: amount,
                    vendor: vendor,
                    date: DateTime.now(),
                    source: 'Manual',
                  );
                  await DatabaseHelper().insertTransaction(newTransaction);
                  _loadTransactions();
                  navigator.pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}
