// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:spend_analyzer/helpers/database_helper.dart';
import 'package:spend_analyzer/helpers/sms_parser.dart';
import 'package:spend_analyzer/models/transaction_model.dart';
import 'package:another_telephony/telephony.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spend_analyzer/helpers/ai_service.dart';

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
  double _monthlyDebits = 0.0;
  double _monthlyCredits = 0.0;
  bool _isSelectionMode = false;
  final Set<int> _selectedTransactions = {};
  final RefreshController _refreshController = RefreshController(
    initialRefresh: false,
  );
  DateTime _selectedMonth = DateTime.now();
  String _selectedCategory = 'All';
  bool _isCategorizing = false;
  final List<String> _categories = [
    'All',
    'Shopping',
    'Bills',
    'Transport',
    'Food',
    'Entertainment',
    'Health',
    'Others',
  ];

  // Theme Constants - Refined for a modern "Slate & Indigo" look
  final Color primaryDark = const Color(0xFF0F172A);
  final Color accentIndigo = const Color(0xFF6366F1);
  final Color surfaceColor = const Color(0xFFF1F5F9);
  final Color cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _initTelephony();
    _checkFirstStartSmsSync();
  }

  void _checkFirstStartSmsSync() async {
    final prefs = await SharedPreferences.getInstance();
    bool hasSynced = prefs.getBool('has_synced_first_start_sms') ?? false;
    if (!hasSynced) {
      await _importSmsForMonth(DateTime.now());
      await prefs.setBool('has_synced_first_start_sms', true);
    }
  }

  Future<void> _importSmsForMonth(DateTime targetMonth) async {
    final permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
    if (!(permissionsGranted ?? false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SMS Permissions denied by device.')),
        );
      }
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Syncing SMS for ${DateFormat('MMM yyyy').format(targetMonth)}...',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      List<SmsMessage> messages = await telephony.getInboxSms(
        columns: [SmsColumn.BODY, SmsColumn.DATE],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      if (messages.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No SMS messages found in Inbox.')),
          );
        }
        return;
      }

      final existingTxs = await DatabaseHelper().getAllTransactions(
        targetMonth,
      );
      final existingSignatures = existingTxs
          .map((t) => '${t.rawSms}_${t.date.millisecondsSinceEpoch}')
          .toSet();
      int importedCount = 0;

      for (var message in messages) {
        if (message.date == null) continue;
        final date = DateTime.fromMillisecondsSinceEpoch(message.date!);
        if (date.year == targetMonth.year && date.month == targetMonth.month) {
          final sig = '${message.body}_${date.millisecondsSinceEpoch}';
          if (existingSignatures.contains(sig)) continue;

          final transaction = SmsParser.parseSms(message.body ?? "");
          if (transaction != null) {
            final txWithDate = TransactionModel(
              id: transaction.id,
              amount: transaction.amount,
              vendor: transaction.vendor,
              category: transaction.category,
              date: date,
              rawSms: transaction.rawSms,
              source: transaction.source,
              transactionType: transaction.transactionType,
            );
            await DatabaseHelper().insertTransaction(txWithDate);
            existingSignatures.add(sig);
            importedCount++;
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Synced $importedCount new transactions.')),
        );
        _loadAllData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SMS Sync Error: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _onRefresh() async {
    await _importSmsForMonth(_selectedMonth);
    _refreshController.refreshCompleted();
  }

  void _loadAllData() {
    _loadTransactions();
    _loadDashboardData();
  }

  void _changeMonth(int month) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + month,
      );
      _loadAllData();
    });
  }

  void _loadDashboardData() async {
    final debits = await DatabaseHelper().getMonthlyDebits(_selectedMonth);
    final credits = await DatabaseHelper().getMonthlyCredits(_selectedMonth);
    if (mounted) {
      setState(() {
        _monthlyDebits = debits;
        _monthlyCredits = credits;
      });
    }
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
    setState(() {
      _transactionsFuture = DatabaseHelper()
          .getAllTransactions(_selectedMonth)
          .then((transactions) {
            if (_selectedCategory == 'All') {
              return transactions;
            } else {
              return transactions
                  .where((tx) => tx.category == _selectedCategory)
                  .toList();
            }
          });
    });
  }

  Future<void> _categorizeTransactions() async {
    final allTransactions = await DatabaseHelper().getAllTransactions(
      _selectedMonth,
    );
    // Only categorize debit transactions that don't have a specific category yet
    final uncategorized = allTransactions
        .where((t) => t.category == null && t.transactionType == 'debit')
        .toList();

    if (uncategorized.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All expenses are already categorized for this month!'),
        ),
      );
      return;
    }

    setState(() {
      _isCategorizing = true;
    });

    try {
      final categoryMap = await AiService().categorizeTransactions(
        uncategorized,
      );
      await DatabaseHelper().updateTransactionCategories(categoryMap);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully auto-categorized ${categoryMap.length} expenses!',
            ),
          ),
        );
        _loadAllData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to categorize: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCategorizing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surfaceColor,
      extendBodyBehindAppBar: true,
      appBar: _isSelectionMode
          ? _buildContextualAppBar()
          : _buildModernAppBar(),
      body: Column(
        children: [
          _buildHeroHeader(),
          _buildCategoryFilters(),
          Expanded(
            child: SmartRefresher(
              controller: _refreshController,
              onRefresh: _onRefresh,
              header: const WaterDropHeader(waterDropColor: Color(0xFF6366F1)),
              child: FutureBuilder<List<TransactionModel>>(
                future: _transactionsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildLoadingState();
                  } else if (snapshot.hasError) {
                    return _buildErrorState(snapshot.error.toString());
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return _buildEmptyState();
                  }

                  final transactions = snapshot.data!;
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                    physics: const BouncingScrollPhysics(),
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final tx = transactions[index];
                      return _ModernTransactionCard(
                        transaction: tx,
                        isSelected: _selectedTransactions.contains(tx.id),
                        isSelectionMode: _isSelectionMode,
                        onTap: () => _handleTransactionTap(tx),
                        onLongPress: () => _handleTransactionLongPress(tx),
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
      centerTitle: false,
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back,',
            style: TextStyle(color: Colors.white60, fontSize: 14),
          ),
          Text(
            'Spend Analyzer',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
      actions: [
        if (_isCategorizing)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
          )
        else
          TextButton.icon(
            onPressed: _categorizeTransactions,
            icon: const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
            label: const Text(
              "AI Categorize",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  AppBar _buildContextualAppBar() {
    return AppBar(
      backgroundColor: accentIndigo,
      elevation: 8,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      title: Text(
        '${_selectedTransactions.length} Selected',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: Colors.white),
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
            final transactions = await _transactionsFuture;
            setState(() {
              if (_selectedTransactions.length == transactions.length) {
                _selectedTransactions.clear();
              } else {
                _selectedTransactions.addAll(transactions.map((t) => t.id!));
              }
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
          onPressed: _showMultiDeleteConfirmationDialog,
        ),
      ],
    );
  }

  Widget _buildHeroHeader() {
    final balance = _monthlyCredits - _monthlyDebits;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 110, 24, 30),
      decoration: BoxDecoration(
        color: primaryDark,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: primaryDark.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildMonthSelector(),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accentIndigo, const Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: accentIndigo.withValues(alpha: 0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Current Balance",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white30,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "₹${balance.toStringAsFixed(2)}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _buildQuickStat(
                      "Income",
                      _monthlyCredits,
                      Icons.south_west_rounded,
                      const Color(0xFF34D399),
                    ),
                    const SizedBox(width: 20),
                    _buildQuickStat(
                      "Expense",
                      _monthlyDebits,
                      Icons.north_east_rounded,
                      const Color(0xFFFB7185),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilters() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = _selectedCategory == category;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedCategory = category;
                    _loadTransactions();
                  });
                }
              },
              backgroundColor: Colors.white,
              selectedColor: accentIndigo.withValues(alpha: 0.1),
              labelStyle: TextStyle(
                color: isSelected ? accentIndigo : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? accentIndigo
                      : Colors.grey.withValues(alpha: 0.2),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white54,
            size: 20,
          ),
          onPressed: () => _changeMonth(-1),
        ),
        Text(
          DateFormat('MMMM yyyy').format(_selectedMonth),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        IconButton(
          icon: const Icon(
            Icons.arrow_forward_ios_rounded,
            color: Colors.white54,
            size: 20,
          ),
          onPressed: () => _changeMonth(1),
        ),
      ],
    );
  }

  Widget _buildQuickStat(
    String label,
    double amount,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                Text(
                  "₹${amount.toStringAsFixed(0)}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFab() {
    return FloatingActionButton.extended(
      onPressed: () => _showManualEntryDialog(null),
      backgroundColor: accentIndigo,
      elevation: 6,
      highlightElevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      label: const Text(
        "New Entry",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
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

  // State Builders
  Widget _buildLoadingState() =>
      const Center(child: CircularProgressIndicator());
  Widget _buildEmptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.inbox_rounded, size: 64, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text(
          "No transactions recorded",
          style: TextStyle(
            color: Colors.grey[500],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
  Widget _buildErrorState(String error) => Center(child: Text("Oops! $error"));

  // Dialogs
  void _showMultiDeleteConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Confirm Delete'),
          ],
        ),
        content: Text(
          'Delete ${_selectedTransactions.length} items? This cannot be undone.',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              await DatabaseHelper().deleteMultipleTransactions(
                _selectedTransactions.toList(),
              );
              if (!mounted) return;
              Navigator.pop(context);
              setState(() {
                _isSelectionMode = false;
                _selectedTransactions.clear();
              });
              _loadAllData();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showManualEntryDialog(TransactionModel? transaction) {
    final amountController = TextEditingController(
      text: transaction?.amount.toString(),
    );
    final vendorController = TextEditingController(text: transaction?.vendor);
    String transactionType = transaction?.transactionType ?? 'debit';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              title: Text(
                transaction == null ? 'Add Transaction' : 'Edit Details',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixIcon: const Icon(Icons.currency_rupee_rounded),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: vendorController,
                    decoration: InputDecoration(
                      labelText: 'Vendor Name',
                      prefixIcon: const Icon(Icons.storefront_rounded),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: transactionType,
                    decoration: InputDecoration(
                      labelText: 'Transaction Type',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
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
                            child: Text(
                              value[0].toUpperCase() + value.substring(1),
                            ),
                          );
                        })
                        .toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentIndigo,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () async {
                    final amount = double.tryParse(amountController.text);
                    final vendor = vendorController.text;

                    if (amount == null || vendor.isEmpty) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please fill all fields.'),
                        ),
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
                        await DatabaseHelper().insertTransaction(
                          newTransaction,
                        );
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
                        await DatabaseHelper().updateTransaction(
                          updatedTransaction,
                        );
                      }
                      if (!mounted) return;
                      Navigator.of(context).pop();
                      _loadAllData();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Action failed.')),
                      );
                    }
                  },
                  child: const Text('Save Entry'),
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
    final Color statusColor = isDebit
        ? const Color(0xFFF43F5E)
        : const Color(0xFF10B981);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? const Color(0xFF6366F1) : Colors.white,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
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
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildAvatar(isDebit, statusColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.vendor,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                transaction.source == 'SMS'
                                    ? Icons.sms_outlined
                                    : Icons.edit_note_rounded,
                                size: 12,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat(
                                  'MMM dd • hh:mm a',
                                ).format(transaction.date),
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          if (transaction.category != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                transaction.category!,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
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
                        fontSize: 16,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
                if (isSelectionMode) ...[
                  const SizedBox(width: 12),
                  AnimatedScale(
                    scale: isSelected ? 1.1 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_off_rounded,
                      color: isSelected
                          ? const Color(0xFF6366F1)
                          : Colors.grey[300],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(bool isDebit, Color color) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        isDebit ? Icons.shopping_cart_outlined : Icons.payments_outlined,
        color: color,
        size: 20,
      ),
    );
  }
}
