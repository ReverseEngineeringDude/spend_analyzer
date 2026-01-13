import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spend_analyzer/helpers/database_helper.dart';
import 'package:spend_analyzer/helpers/sms_parser.dart';
import 'package:spend_analyzer/models/transaction_model.dart';
import 'package:another_telephony/telephony.dart';
import 'package:liquid_pull_to_refresh/liquid_pull_to_refresh.dart';

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
  Future<Map<String, List<TransactionModel>>>? _transactionsFuture;
  final Telephony telephony = Telephony.instance;
  double _monthlyDebits = 0.0;
  double _monthlyCredits = 0.0;
  bool _isSelectionMode = false;
  final Set<int> _selectedTransactions = {};
  bool _isLoading = true;
  String? _selectedMonth;
  List<String> _availableMonths = [];

  // Theme Constants
  final Color primaryDark = const Color(0xFF0F172A);
  final Color accentIndigo = const Color(0xFF6366F1);
  final Color surfaceColor = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _initApp();
    _initTelephony();
  }

  void _initApp() async {
    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = prefs.getBool('isFirstLaunch') ?? true;
    if (isFirstLaunch) {
      await _importSms();
      await prefs.setBool('isFirstLaunch', false);
    }
    _loadAllData();
    setState(() {
      _isLoading = false;
    });
  }

  void _loadAllData() {
    _loadTransactions();
    _loadDashboardData(_selectedMonth);
  }

  void _loadDashboardData(String? monthYear) async {
    if (monthYear == null) {
      setState(() {
        _monthlyDebits = 0.0;
        _monthlyCredits = 0.0;
      });
      return;
    }

    final monthParts = monthYear.split(' ');
    final monthName = monthParts[0];
    final year = monthParts[1];

    final monthNumber = DateFormat('MMMM').parse(monthName).month.toString().padLeft(2, '0');

    final debits = await DatabaseHelper().getMonthlyDebits(monthNumber, year);
    final credits = await DatabaseHelper().getMonthlyCredits(monthNumber, year);
    setState(() {
      _monthlyDebits = debits;
      _monthlyCredits = credits;
    });
  }

  void _initTelephony() async {
    final permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
    if (permissionsGranted ?? false) {
      telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) {
          final transaction = SmsParser.parseSms(message.body ?? "");
          if (transaction != null) {
            DatabaseHelper().insertTransaction(transaction).then((_) {
              _loadAllData();
            });
          }
        },
        onBackgroundMessage: onBackgroundMessage,
      );
    }
  }

  void _loadTransactions() {
    var future = DatabaseHelper().getAllTransactions();
    future.then((groupedTransactions) {
      final months = groupedTransactions.keys.toList();
      months.sort((a, b) {
        final DateFormat formatter = DateFormat('MMMM yyyy');
        return formatter.parse(b).compareTo(formatter.parse(a));
      }); // Sort months in descending order
      final currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
      setState(() {
        _availableMonths = months;
        if (months.contains(currentMonth)) {
          _selectedMonth = currentMonth;
        } else if (months.isNotEmpty) {
          _selectedMonth = months.first;
        } else {
          _selectedMonth = null;
        }
        _loadDashboardData(_selectedMonth); // Reload dashboard with the selected month
      });
    });
    setState(() {
      _transactionsFuture = future;
    });
  }

  Future<void> _importSms() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Importing transactions from SMS...'),
          duration: Duration(seconds: 2)),
    );
    List<SmsMessage> messages = await telephony.getInboxSms(
        columns: [SmsColumn.BODY, SmsColumn.DATE],
        filter: SmsFilter.where(SmsColumn.BODY)
            .like('%spent%')
            .or(SmsColumn.BODY)
            .like('%debited%')
            .or(SmsColumn.BODY)
            .like('%paid%')
            .or(SmsColumn.BODY)
            .like('%charged%')
            .or(SmsColumn.BODY)
            .like('%credited%')
            .or(SmsColumn.BODY)
            .like('%received%')
            .or(SmsColumn.BODY)
            .like('%refund%'),
        sortOrder: [
          OrderBy(SmsColumn.DATE, sort: Sort.DESC),
        ]);

    for (var message in messages) {
      final transaction = SmsParser.parseSms(message.body ?? "");
      if (transaction != null) {
        await DatabaseHelper().insertTransaction(transaction);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surfaceColor,
      extendBodyBehindAppBar: true,
      appBar: _isSelectionMode ? _buildContextualAppBar() : _buildModernAppBar(),
      body: Column(
        children: [
          _buildHeroHeader(),
          Expanded(
            child: LiquidPullToRefresh(
              color: accentIndigo,
              backgroundColor: Colors.white,
              showChildOpacityTransition: false,
              onRefresh: () async {
                _loadAllData();
              },
              child: _isLoading
                  ? _buildLoadingState()
                  : FutureBuilder<Map<String, List<TransactionModel>>>(
                      future: _transactionsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return _buildLoadingState();
                        } else if (snapshot.hasError) {
                          return _buildErrorState(snapshot.error.toString());
                        } else if (!snapshot.hasData ||
                            snapshot.data!.isEmpty ||
                            _selectedMonth == null) {
                          return _buildEmptyState();
                        }

                        final groupedTransactions = snapshot.data!;
                        final transactions =
                            groupedTransactions[_selectedMonth] ?? [];

                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                          itemCount: transactions.length,
                          itemBuilder: (context, index) {
                            final tx = transactions[index];
                            return _ModernTransactionCard(
                              transaction: tx,
                              isSelected:
                                  _selectedTransactions.contains(tx.id),
                              isSelectionMode: _isSelectionMode,
                              onTap: () => _handleTransactionTap(tx),
                              onLongPress: () =>
                                  _handleTransactionLongPress(tx),
                            );
                          },
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: _isSelectionMode ? null : _buildFab(),
    );
  }

  PreferredSizeWidget _buildModernAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: const Text(
        'Overview',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          fontSize: 24,
        ),
      ),
    );
  }

  AppBar _buildContextualAppBar() {
    return AppBar(
      backgroundColor: accentIndigo,
      elevation: 4,
      title: Text(
        '${_selectedTransactions.length} Selected',
        style:
            const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
      ),
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: () {
          setState(() {
            _isSelectionMode = false;
            _selectedTransactions.clear();
          });
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all_rounded, color: Colors.white),
          onPressed: () async {
            final transactionsMap = await _transactionsFuture;
            final allIds = transactionsMap?[_selectedMonth]
                ?.map((tx) => tx.id!)
                .toList();
            setState(() {
              if (_selectedTransactions.length == allIds?.length) {
                _selectedTransactions.clear();
              } else {
                _selectedTransactions.addAll(allIds ?? []);
              }
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white),
          onPressed: _showMultiDeleteConfirmationDialog,
        ),
      ],
    );
  }

  Widget _buildHeroHeader() {
    final balance = _monthlyCredits - _monthlyDebits;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 100, 24, 40),
      decoration: BoxDecoration(
        color: primaryDark,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primaryDark, const Color(0xFF1E293B)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Total Balance",
                style: TextStyle(
                    color: Colors.white60,
                    fontSize: 16,
                    fontWeight: FontWeight.w500),
              ),
              if (_availableMonths.isNotEmpty)
                DropdownButton<String>(
                  value: _selectedMonth,
                  dropdownColor: primaryDark,
                  style: const TextStyle(color: Colors.white),
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                  underline: Container(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedMonth = newValue!;
                      _loadDashboardData(_selectedMonth); // Reload dashboard data when month changes
                    });
                  },
                  items: _availableMonths
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "₹${balance.toStringAsFixed(2)}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              _buildStatItem("Income ", _monthlyCredits,
                  Icons.arrow_downward, Colors.lightBlueAccent),
              const SizedBox(width: 24),
              _buildStatItem("Expenses ", _monthlyDebits,
                  Icons.arrow_upward, Colors.pinkAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      String label, double amount, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(13),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withAlpha(26)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              child: Text(
                "₹${amount.toStringAsFixed(0)}",
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFab() {
    return FloatingActionButton.extended(
      onPressed: () => _showManualEntryDialog(null),
      backgroundColor: accentIndigo,
      elevation: 8,
      icon: const Icon(Icons.add_rounded, color: Colors.white),
      label: const Text("Add Transaction",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }

  void _handleTransactionTap(TransactionModel tx) {
    if (_isSelectionMode) {
      setState(() {
        if (_selectedTransactions.contains(tx.id)) {
          _selectedTransactions.remove(tx.id);
        } else {
          _selectedTransactions.add(tx.id!);
        }
        if (_selectedTransactions.isEmpty) _isSelectionMode = false;
      });
    } else {
      _showManualEntryDialog(tx);
    }
  }

  void _handleTransactionLongPress(TransactionModel tx) {
    setState(() {
      _isSelectionMode = true;
      _selectedTransactions.add(tx.id!);
    });
  }

  Widget _buildLoadingState() =>
      const Center(child: CircularProgressIndicator());
  Widget _buildEmptyState() =>
      const Center(child: Text("No transactions yet. Pull to refresh!"));
  Widget _buildErrorState(String error) => Center(child: Text("Error: $error"));

  void _showMultiDeleteConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete Selected?'),
        content: Text(
            'This will permanently remove ${_selectedTransactions.length} transactions.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final nav = Navigator.of(context);
              await DatabaseHelper()
                  .deleteMultipleTransactions(_selectedTransactions.toList());
              setState(() {
                _isSelectionMode = false;
                _selectedTransactions.clear();
              });
              _loadAllData();
              nav.pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showManualEntryDialog(TransactionModel? transaction) {
    final amountController =
        TextEditingController(text: transaction?.amount.toString());
    final vendorController = TextEditingController(text: transaction?.vendor);
    String transactionType = transaction?.transactionType ?? 'debit';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(
                  transaction == null ? 'New Transaction' : 'Edit Transaction'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: vendorController,
                    decoration: InputDecoration(
                      labelText: 'Vendor / Description',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: transactionType,
                    decoration: InputDecoration(
                      labelText: 'Type',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (String? newValue) {
                      setDialogState(() {
                        transactionType = newValue!;
                      });
                    },
                    items: <String>['debit', 'credit']
                        .map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child:
                            Text(value[0].toUpperCase() + value.substring(1)),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentIndigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final amount = double.tryParse(amountController.text);
                    final vendor = vendorController.text;
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);

                    if (amount == null || vendor.isEmpty) {
                      messenger.showSnackBar(
                        const SnackBar(
                            content:
                                Text('Please enter a valid amount and vendor.')),
                      );
                      return;
                    }

                    try {
                      if (transaction == null) {
                        final newTransaction = TransactionModel(
                          amount: amount,
                          vendor: vendor,
                          date: DateTime.now(),
                          source: 'Manual',
                          transactionType: transactionType,
                        );
                        await DatabaseHelper()
                            .insertTransaction(newTransaction);
                      } else {
                        final updatedTransaction = TransactionModel(
                          id: transaction.id,
                          amount: amount,
                          vendor: vendor,
                          date: transaction.date,
                          source: transaction.source,
                          rawSms: transaction.rawSms,
                          category: transaction.category,
                          transactionType: transactionType,
                        );
                        await DatabaseHelper()
                            .updateTransaction(updatedTransaction);
                      }
                      _loadAllData();
                      navigator.pop();
                    } catch (e) {
                      messenger.showSnackBar(
                        const SnackBar(
                            content: Text('Failed to save transaction.')),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ModernTransactionCard extends StatelessWidget {
  final TransactionModel transaction;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ModernTransactionCard({
    required this.transaction,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDebit = transaction.transactionType == 'debit';
    final Color statusColor =
        isDebit ? const Color(0xFFE11D48) : const Color(0xFF10B981);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildIcon(isDebit, statusColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.vendor,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: -0.2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('dd MMM • hh:mm a').format(transaction.date),
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "${isDebit ? '-' : '+'} ₹${transaction.amount.toStringAsFixed(2)}",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: statusColor,
                      ),
                    ),
                    if (transaction.source != 'SMS')
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(4)),
                        child: Text("Manual",
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey[600])),
                      )
                  ],
                ),
                if (isSelectionMode) ...[
                  const SizedBox(width: 12),
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_off_rounded,
                    color: isSelected ? const Color(0xFF6366F1) : Colors.grey[300],
                  )
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(bool isDebit, Color color) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        isDebit
            ? Icons.shopping_bag_outlined
            : Icons.account_balance_wallet_outlined,
        color: color,
        size: 24,
      ),
    );
  }
}