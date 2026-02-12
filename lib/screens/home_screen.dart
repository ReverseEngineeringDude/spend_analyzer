// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:spend_analyzer/helpers/database_helper.dart';
import 'package:spend_analyzer/helpers/sms_parser.dart';
import 'package:spend_analyzer/helpers/gemini_parser.dart';
import 'package:spend_analyzer/models/transaction_model.dart';
import 'package:spend_analyzer/helpers/category_helper.dart';
import 'package:another_telephony/telephony.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

@pragma('vm:entry-point')
Future<void> onBackgroundMessage(SmsMessage message) async {
  final transaction = await SmsParser.parseSmsWithGemini(message.body ?? "");
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
  String? _selectedCategoryFilter;

  // Theme Constants - Refined for a modern "Slate & Indigo" look
  final Color primaryDark = const Color(0xFF1E1E2C); // Darker, richer background
  final Color accentIndigo = const Color(0xFF6C63FF); // More vibrant indigo
  final Color surfaceColor = const Color(0xFFF4F7FE); // Very light cool grey/blue
  final Color cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _initTelephony();
  }

  void _onRefresh() async {
    _loadAllData();
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
        onNewMessage: (SmsMessage message) async {
          final transaction = await SmsParser.parseSmsWithGemini(
            message.body ?? "",
          );
          if (transaction != null) {
            await DatabaseHelper().insertTransaction(transaction);
            _loadAllData();
          }
        },
        onBackgroundMessage: onBackgroundMessage,
      );
    }
  }

  void _loadTransactions() {
    setState(() {
      _transactionsFuture = DatabaseHelper().getAllTransactions(_selectedMonth);
    });
  }

  void _importSms() async {
    if (!mounted) return;

    // 1. Setup Progress Notifiers
    final ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
    final ValueNotifier<String> statusNotifier = ValueNotifier("Reading SMS inbox...");

    // 2. Show Progress Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Syncing with AI"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            ValueListenableBuilder<double>(
              valueListenable: progressNotifier,
              builder: (context, value, child) => LinearProgressIndicator(
                value: value,
                backgroundColor: Colors.grey[200],
                color: accentIndigo,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<String>(
              valueListenable: statusNotifier,
              builder: (context, value, child) => Text(
                value,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      // 3. Get messages
      List<SmsMessage> messages = await telephony.getInboxSms(
        columns: [SmsColumn.BODY, SmsColumn.DATE],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      // 4. Chunking Logic
      // Process potentially all messages or a larger subset now that we have batching + progress
      // Let's take recent 100 for better demo, or keep it safe.
      // User asked for "already spends list using sms reading ai automatic", implying full history or reasonable amount.
      // Let's bump limit to 200 for now.
      if (messages.length > 200) {
        messages = messages.sublist(0, 200);
      }

      const int chunkSize = 20;
      int totalChunks = (messages.length / chunkSize).ceil();
      if (totalChunks == 0) totalChunks = 1; // avoid div by zero

      for (var i = 0; i < messages.length; i += chunkSize) {
        if (!mounted) break;
        
        final int currentChunkIndex = (i / chunkSize).floor() + 1;
        progressNotifier.value = currentChunkIndex / totalChunks;
        statusNotifier.value = "Analyzing batch $currentChunkIndex of $totalChunks...";

        final end = (i + chunkSize < messages.length) ? i + chunkSize : messages.length;
        final chunk = messages.sublist(i, end);
        final List<String> bodies = chunk.map((m) => m.body ?? "").where((b) => b.isNotEmpty).toList();

        if (bodies.isEmpty) continue;

        // 5. Batch Process
        final transactions = await GeminiParser.parseBatchSms(bodies);

        // 6. Insert
        for (var transaction in transactions) {
          await DatabaseHelper().insertTransaction(transaction);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      // 7. Close Dialog & Refresh
      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        _loadAllData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync complete!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
                  final Map<String, List<TransactionModel>> grouped = {};
                  for (var t in transactions) {
                    final cat = t.category ?? CategoryHelper.other;
                    if (_selectedCategoryFilter != null && cat != _selectedCategoryFilter) {
                      continue;
                    }
                    if (!grouped.containsKey(cat)) grouped[cat] = [];
                    grouped[cat]!.add(t);
                  }

                  // Sort categories by total value (optional) or just use keys
                  final sortedKeys = grouped.keys.toList();
                  
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                    physics: const BouncingScrollPhysics(),
                    children: sortedKeys.map((cat) {
                      final txs = grouped[cat]!;
                      double total = 0;
                      for(var t in txs) {
                         if(t.transactionType == 'debit') {
                           total += t.amount;
                         } else {
                           total += t.amount;
                         }
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: CategoryHelper.getColor(cat).withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    CategoryHelper.getIcon(cat),
                                    color: CategoryHelper.getColor(cat),
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  cat,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: primaryDark,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  "₹${total.toStringAsFixed(0)}",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: primaryDark.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...txs.map((tx) {
                             return Padding(
                               padding: const EdgeInsets.only(bottom: 12.0),
                               child: _ModernTransactionCard(
                                  transaction: tx,
                                  isSelected: _selectedTransactions.contains(tx.id),
                                  isSelectionMode: _isSelectionMode,
                                  onTap: () => _handleTransactionTap(tx),
                                  onLongPress: () => _handleTransactionLongPress(tx),
                                ),
                             );
                          }),
                        ],
                      );
                    }).toList(),
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
      backgroundColor: Colors.transparent.withValues(alpha: 0.0),
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
        IconButton(
          icon: const Icon(Icons.sync, color: Colors.white),
          onPressed: _importSms,
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
    return Stack(
      children: [
        Container(
          height: 320,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryDark, const Color(0xFF2D2B55)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(40),
              bottomRight: Radius.circular(40),
            ),
          ),
        ),
        Positioned(
          top: -100,
          right: -100,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentIndigo.withValues(alpha: 0.15),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                const SizedBox(height: 10),
                _buildMonthSelector(),
                const SizedBox(height: 24),
                 Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
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
                              "Total Balance",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                shadows: [
                                  Shadow(
                                    color: Colors.black45,
                                    offset: Offset(0, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.wallet_rounded,
                              color: Colors.white,
                              shadows: [
                                  Shadow(
                                    color: Colors.black45,
                                    offset: Offset(0, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "₹${balance.toStringAsFixed(2)}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            shadows: [
                              Shadow(
                                color: Colors.black45,
                                offset: Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            _buildQuickStat(
                              "Income",
                              _monthlyCredits,
                              Icons.arrow_downward_rounded,
                              const Color(0xFF69F0AE),
                            ),
                            const SizedBox(width: 16),
                            _buildQuickStat(
                              "Expense",
                              _monthlyDebits,
                              Icons.arrow_upward_rounded,
                              const Color(0xFFFF8A80),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                _buildCategoryFilters(),
              ],
            ),
          ),
        ),
      ],
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
                  style: const TextStyle(
                    color: Colors.white, 
                    fontSize: 11, 
                    fontWeight: FontWeight.w600,
                    shadows: [
                      Shadow(
                        color: Colors.black45,
                        offset: Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
                Text(
                  "₹${amount.toStringAsFixed(0)}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
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

  Widget _buildCategoryFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildFilterChip("All", null),
          ...CategoryHelper.allCategories.map((cat) => _buildFilterChip(cat, cat)),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? category) {
    final bool isSelected = _selectedCategoryFilter == category;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: FilterChip(
          label: Text(label),
          selected: isSelected,
          onSelected: (bool selected) {
            setState(() {
               if (category == null) {
                 _selectedCategoryFilter = null;
               } else if (_selectedCategoryFilter == category) {
                 _selectedCategoryFilter = null;
               } else {
                 _selectedCategoryFilter = category;
               }
            });
          },
          backgroundColor: Colors.black.withValues(alpha: 0.2), // Darker glass for contrast
          selectedColor: accentIndigo, 
          checkmarkColor: Colors.white,
          labelStyle: TextStyle(
            color: Colors.white, // Always white
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
            shadows: const [
              Shadow(
                color: Colors.black45,
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isSelected ? Colors.transparent : Colors.white30,
              width: 1,
            ),
          ),
          showCheckmark: false,
          elevation: isSelected ? 4 : 0,
          shadowColor: accentIndigo.withValues(alpha: 0.4),
        ),
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
    String category = transaction?.category ?? CategoryHelper.other;

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
                    value: category,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: CategoryHelper.allCategories.map((String cat) {
                      return DropdownMenuItem(
                        value: cat,
                        child: Row(
                          children: [
                            Icon(
                              CategoryHelper.getIcon(cat),
                              color: CategoryHelper.getColor(cat),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(cat),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setDialogState(() {
                        category = newValue!;
                      });
                    },
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
                          category: category,
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
                          category: category,
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

    return Container(
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF0F4FF) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF909090).withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 0,
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    CategoryHelper.getIcon(transaction.category ?? CategoryHelper.other), 
                    color: statusColor, 
                    size: 24
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.vendor,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Color(0xFF2D3748),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
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
                              fontWeight: FontWeight.w500,
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
                      "${isDebit ? '-' : '+'} ₹${transaction.amount.toStringAsFixed(0)}",
                      style: TextStyle(
                        fontFamily: 'monospace', // Makes numbers align better if used consistently
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: isDebit ? const Color(0xFFE53E3E) : const Color(0xFF38A169),
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (transaction.source == 'SMS' || transaction.source == 'SMS-Batch')
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(Icons.sms_rounded, size: 12, color: Colors.grey[300]),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

  }


}
