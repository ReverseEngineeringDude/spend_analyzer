// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:spend_analyzer/helpers/database_helper.dart';
import 'package:spend_analyzer/helpers/sms_parser.dart';
import 'package:spend_analyzer/helpers/ai_service.dart';
import 'package:spend_analyzer/models/transaction_model.dart';
import 'package:another_telephony/telephony.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fl_chart/fl_chart.dart';

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

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late Future<List<TransactionModel>> _transactionsFuture;
  final Telephony telephony = Telephony.instance;

  bool _isSelectionMode = false;
  final Set<int> _selectedTransactions = {};
  final RefreshController _refreshController = RefreshController(
    initialRefresh: false,
  );
  DateTime _selectedMonth = DateTime.now();
  String _selectedCategory = 'All';
  int _currentIndex = 0;
  String _geminiApiKey = '';
  String _themeStyle = 'Dark Olive';
  final TextEditingController _apiKeyController = TextEditingController();
  final ScrollController _dashboardScrollController = ScrollController();
  final ScrollController _profileScrollController = ScrollController();
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

  // Dynamic Theme Colors
  Color get bgDeep {
    if (_themeStyle == 'Dark Mode') return const Color(0xFF121212);
    if (_themeStyle == 'Light Mode') return const Color(0xFFF0F2F5);
    return const Color(0xFF181A16);
  }

  Color get bgCard {
    if (_themeStyle == 'Dark Mode') return const Color(0xFF1E1E1E);
    if (_themeStyle == 'Light Mode') return const Color(0xFFFFFFFF);
    return const Color(0xFF242720);
  }

  Color get bgCardRaised {
    if (_themeStyle == 'Dark Mode') return const Color(0xFF2C2C2C);
    if (_themeStyle == 'Light Mode') return const Color(0xFFE4E6EB);
    return const Color(0xFF2E3129);
  }

  Color get bgPill {
    if (_themeStyle == 'Dark Mode') return const Color(0xFF333333);
    if (_themeStyle == 'Light Mode') return const Color(0xFFD8DADF);
    return const Color(0xFF333629);
  }

  Color get accentGreen {
    if (_themeStyle == 'Dark Mode') return const Color(0xFF4CAF50);
    if (_themeStyle == 'Light Mode') return const Color(0xFF2E7D32);
    return const Color(0xFFC8D5A3);
  }

  Color get accentPeach {
    if (_themeStyle == 'Dark Mode') return const Color(0xFFFF8A65);
    if (_themeStyle == 'Light Mode') return const Color(0xFFD84315);
    return const Color(0xFFE8A598);
  }

  Color get accentGold {
    if (_themeStyle == 'Dark Mode') return const Color(0xFFFFB300);
    if (_themeStyle == 'Light Mode') return const Color(0xFFF57F17);
    return const Color(0xFFD4B483);
  }

  Color get accentPurple => const Color(0xFF9B8EC4);

  Color get textPrimary {
    if (_themeStyle == 'Light Mode') return const Color(0xFF1C1E21);
    return const Color(0xFFF5F2E8);
  }

  Color get textSecondary {
    if (_themeStyle == 'Light Mode') return const Color(0xFF65676B);
    return const Color(0xFF8A8C7E);
  }

  Color get textMuted {
    if (_themeStyle == 'Light Mode') return const Color(0xFF8D949E);
    return const Color(0xFF5A5C50);
  }

  Color get borderColor {
    if (_themeStyle == 'Dark Mode') return const Color(0xFF333333);
    if (_themeStyle == 'Light Mode') return const Color(0xFFCED0D4);
    return const Color(0xFF333629);
  }

  Color get debitRed => const Color(0xFFE8756A);
  Color get creditGreen => const Color(0xFF85C9A3);

  // Animation Controller for Hero
  late final AnimationController _heroAnimController;
  late final Animation<double> _heroFadeAnim;

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: textPrimary, fontSize: 13),
        ),
        backgroundColor: isError ? const Color(0xFF3A1A1A) : bgCardRaised,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isError
              ? BorderSide(color: debitRed.withValues(alpha: 0.4))
              : BorderSide(color: borderColor),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _heroAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _heroFadeAnim = CurvedAnimation(
      parent: _heroAnimController,
      curve: Curves.easeOut,
    );
    _heroAnimController.forward();

    _loadApiKey();
    _loadThemeStyle();
    _loadAllData();
    _initTelephony();
    _checkFirstStartSmsSync();
  }

  @override
  void dispose() {
    _heroAnimController.dispose();
    _apiKeyController.dispose();
    _dashboardScrollController.dispose();
    _profileScrollController.dispose();
    super.dispose();
  }

  void _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _geminiApiKey = prefs.getString('gemini_api_key') ?? '';
      _apiKeyController.text = _geminiApiKey;
    });
  }

  void _saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key);
    setState(() {
      _geminiApiKey = key;
    });
    _showSnack('API Key Saved');
  }

  void _loadThemeStyle() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeStyle = prefs.getString('theme_style') ?? 'Dark Olive';
    });
  }

  void _saveThemeStyle(String style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_style', style);
    setState(() {
      _themeStyle = style;
    });
    _showSnack('Appearance updated to $style');
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
      _showSnack('SMS Permissions denied by device.', isError: true);
      return;
    }

    _showSnack(
      'Syncing SMS for ${DateFormat('MMM yyyy').format(targetMonth)}...',
    );

    try {
      List<SmsMessage> messages = await telephony.getInboxSms(
        columns: [SmsColumn.BODY, SmsColumn.DATE],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      if (messages.isEmpty) {
        _showSnack('No SMS messages found in Inbox.', isError: true);
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
        _showSnack('Synced $importedCount new transactions.');
        _loadAllData();
      }
    } catch (e) {
      _showSnack('SMS Sync Error: $e', isError: true);
    }
  }

  void _onRefresh() async {
    await _importSmsForMonth(_selectedMonth);
    _refreshController.refreshCompleted();
  }

  void _loadAllData() {
    _loadTransactions();
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

  void _changeMonth(int month) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + month,
      );
      _loadAllData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDeep,
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: [_buildDashboardView(), _buildProfileView()],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigation(),
      floatingActionButton: _isSelectionMode ? null : _buildFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildDashboardView() {
    return SmartRefresher(
      controller: _refreshController,
      onRefresh: _onRefresh,
      header: WaterDropHeader(waterDropColor: accentGreen),
      child: SingleChildScrollView(
        controller: _dashboardScrollController,
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              _isSelectionMode
                  ? _buildContextualAppBar()
                  : _buildCustomAppBar(),
              const SizedBox(height: 16),
              _buildMonthSelector(),
              const SizedBox(height: 24),
              _buildSummaryHeroCard(),
              const SizedBox(height: 20),
              _buildMonthlyProfitsCard(),
              const SizedBox(height: 20),
              _buildWeeklyActivityCard(),
              const SizedBox(height: 20),
              _buildAiCatButton(),
              const SizedBox(height: 20),
              _buildCategoryFilters(),
              const SizedBox(height: 12),
              _buildTransactionsList(),
              const SizedBox(height: 100), // Bottom padding for nav overlap
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Dashboard",
              style: TextStyle(
                color: textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: bgCard,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor),
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                color: textPrimary,
                size: 20,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContextualAppBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.close_rounded, color: textPrimary),
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _selectedTransactions.clear();
                });
              },
            ),
            Text(
              '${_selectedTransactions.length} Selected',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: textPrimary,
                fontSize: 18,
              ),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.select_all_rounded, color: textPrimary),
              onPressed: () async {
                final transactions = await _transactionsFuture;
                setState(() {
                  if (_selectedTransactions.length == transactions.length) {
                    _selectedTransactions.clear();
                  } else {
                    _selectedTransactions.addAll(
                      transactions.map((t) => t.id!),
                    );
                  }
                });
              },
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: debitRed),
              onPressed: _showMultiDeleteConfirmationDialog,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryHeroCard() {
    return FutureBuilder<List<TransactionModel>>(
      future: _transactionsFuture,
      builder: (context, snapshot) {
        final txs = snapshot.data ?? [];
        double totalDebits = 0;
        double totalCredits = 0;
        int count = txs.length;

        final dailyCounts = <int, int>{};

        for (var tx in txs) {
          if (tx.transactionType == 'SPEND') {
            totalDebits += tx.amount;
          } else {
            totalCredits += tx.amount;
          }
          int dayIndex = tx.date.weekday - 1;
          dailyCounts[dayIndex] = (dailyCounts[dayIndex] ?? 0) + 1;
        }

        final balance = totalCredits - totalDebits;
        final isSurplus = balance >= 0;

        double maxCount = 0;
        dailyCounts.forEach((_, c) {
          if (c > maxCount) maxCount = c.toDouble();
        });
        if (maxCount == 0) maxCount = 5;

        List<FlSpot> spots = [];
        for (int i = 0; i < 7; i++) {
          spots.add(FlSpot(i.toDouble(), (dailyCounts[i] ?? 0).toDouble()));
        }

        return FadeTransition(
          opacity: _heroFadeAnim,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: bgCard,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "TOTAL BALANCE ($count TXNs)",
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 12,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      DateFormat('MMMM yyyy').format(_selectedMonth),
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "₹${NumberFormat('#,##,###.##').format(balance.abs())}",
                  style: TextStyle(
                    color: isSurplus ? accentGreen : textPrimary,
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2.0,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  height: 100,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: bgCardRaised,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: LineChart(
                          LineChartData(
                            gridData: const FlGridData(show: false),
                            titlesData: const FlTitlesData(show: false),
                            borderData: FlBorderData(show: false),
                            minY: 0,
                            maxY: maxCount * 1.5,
                            lineTouchData: const LineTouchData(enabled: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: spots,
                                isCurved: true,
                                curveSmoothness: 0.3,
                                color: accentGreen,
                                barWidth: 2.5,
                                isStrokeCapRound: true,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                    colors: [
                                      accentGreen.withValues(alpha: 0.15),
                                      Colors.transparent,
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.arrow_downward_rounded,
                                color: creditGreen,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "₹${NumberFormat('#,##,0').format(totalCredits)}",
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Icon(
                                Icons.arrow_upward_rounded,
                                color: debitRed,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "₹${NumberFormat('#,##,0').format(totalDebits)}",
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMonthlyProfitsCard() {
    return FutureBuilder<List<TransactionModel>>(
      future: _transactionsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildStaticMonthlyProfitsCard([], 0);
        }

        final txs = snapshot.data!;
        final categoryTotals = <String, double>{};
        double totalSpend = 0;

        for (var tx in txs) {
          if (tx.transactionType == 'SPEND') {
            final String cat = tx.category ?? 'Others';
            categoryTotals[cat] = (categoryTotals[cat] ?? 0) + tx.amount;
            totalSpend += tx.amount;
          }
        }

        if (totalSpend == 0) return _buildStaticMonthlyProfitsCard([], 0);

        final sortedCategories = categoryTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return _buildStaticMonthlyProfitsCard(sortedCategories, totalSpend);
      },
    );
  }

  Widget _buildStaticMonthlyProfitsCard(
    List<MapEntry<String, double>> sortedCategories,
    double totalSpend,
  ) {
    final Map<String, double> topCategories = {};

    for (int i = 0; i < sortedCategories.length; i++) {
      if (i < 3) {
        topCategories[sortedCategories[i].key] = sortedCategories[i].value;
      } else {
        topCategories['Others'] =
            (topCategories['Others'] ?? 0) + sortedCategories[i].value;
      }
    }

    List<Color> palette = [accentGreen, accentPeach, accentGold, accentPurple];
    List<PieChartSectionData> pieSections = [];
    List<Widget> legendItems = [];

    if (sortedCategories.isEmpty) {
      pieSections.add(
        PieChartSectionData(color: bgPill, value: 100, title: '', radius: 20),
      );
      legendItems.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: _buildLegendItem("No Data", bgPill, '0%'),
        ),
      );
    } else {
      int colorIndex = 0;
      topCategories.forEach((cat, amount) {
        final percentage = (amount / totalSpend) * 100;
        final color = palette[colorIndex % palette.length];

        pieSections.add(
          PieChartSectionData(
            color: color,
            value: percentage,
            title: '',
            radius: 20,
          ),
        );

        legendItems.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: _buildLegendItem(
              cat,
              color,
              '${percentage.toStringAsFixed(1)}%',
            ),
          ),
        );

        colorIndex++;
      });
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Monthly Breakdown",
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              Text(
                "This Month",
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 200,
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: PieChart(
                    PieChartData(
                      pieTouchData: PieTouchData(enabled: true),
                      centerSpaceRadius: 50,
                      sectionsSpace: 3,
                      sections: pieSections,
                    ),
                    duration: const Duration(milliseconds: 800),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: legendItems,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String title, Color color, String percent) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: bgPill,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            percent,
            style: TextStyle(
              color: accentGreen,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyActivityCard() {
    return FutureBuilder<List<TransactionModel>>(
      future: _transactionsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildStaticWeeklyActivityCard({}, 0);
        }

        // Key: weekday index (0=Mon ... 6=Sun)
        final dailyTotals = <int, double>{};
        double totalDebits = 0;
        for (var tx in snapshot.data!) {
          if (tx.transactionType == 'SPEND') {
            int dayIndex = tx.date.weekday - 1;
            dailyTotals[dayIndex] = (dailyTotals[dayIndex] ?? 0) + tx.amount;
            totalDebits += tx.amount;
          }
        }
        return _buildStaticWeeklyActivityCard(dailyTotals, totalDebits);
      },
    );
  }

  Widget _buildStaticWeeklyActivityCard(
    Map<int, double> dailyTotals,
    double totalDebits,
  ) {
    double maxDaily = 0;
    dailyTotals.forEach((_, amount) {
      if (amount > maxDaily) maxDaily = amount;
    });

    // Fallback if no spend to ensure chart lines draw
    if (maxDaily == 0) maxDaily = 100;

    List<BarChartGroupData> barGroups = [];
    for (int i = 0; i < 7; i++) {
      double amount = dailyTotals[i] ?? 0;
      bool isMax = amount == maxDaily && amount > 0;
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: amount,
              color: isMax ? accentGreen : bgPill,
              width: 12,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6),
              ),
            ),
          ],
        ),
      );
    }

    // Determine Y-axis interval statically, scale max to 1.2x top
    final double maxYAxis = maxDaily * 1.2;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Weekly Activity",
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Overview",
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                "₹${NumberFormat('#,##,0').format(totalDebits)}",
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 120,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxYAxis,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const days = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            days[value.toInt()],
                            style: TextStyle(
                              color: textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxYAxis / 4 > 0 ? maxYAxis / 4 : 10,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: borderColor,
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: barGroups,
              ),
              duration: const Duration(milliseconds: 600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: bgCard,
        border: Border(top: BorderSide(color: borderColor, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem(Icons.home_filled, 0),
          const SizedBox(width: 48), // Space for FAB
          _buildNavItem(Icons.person_rounded, 1),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, int index) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: isActive ? accentGreen : textMuted, size: 26),
          const SizedBox(height: 4),
          if (isActive)
            Container(
              width: 12,
              height: 4,
              decoration: BoxDecoration(
                color: accentGreen,
                borderRadius: BorderRadius.circular(4),
              ),
            )
          else
            const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        InkWell(
          onTap: () => _changeMonth(-1),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bgCard,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.chevron_left_rounded,
              color: textSecondary,
              size: 24,
            ),
          ),
        ),
        Column(
          children: [
            Text(
              DateFormat('MMMM').format(_selectedMonth).toUpperCase(),
              style: TextStyle(
                color: textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat('yyyy').format(_selectedMonth),
              style: TextStyle(
                color: textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        InkWell(
          onTap: () => _changeMonth(1),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bgCard,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.chevron_right_rounded,
              color: textSecondary,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileView() {
    return SingleChildScrollView(
      controller: _profileScrollController,
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Text(
              "Settings & Preferences",
              style: TextStyle(
                color: textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: bgCard,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.palette_rounded, color: accentGold, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        "Appearance",
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _themeStyle,
                    dropdownColor: bgCardRaised,
                    icon: Icon(
                      Icons.arrow_drop_down_rounded,
                      color: textSecondary,
                    ),
                    style: TextStyle(color: textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: bgCardRaised,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: ['Dark Olive', 'Dark Mode', 'Light Mode']
                        .map(
                          (style) => DropdownMenuItem(
                            value: style,
                            child: Text(style),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) _saveThemeStyle(value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: bgCard,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.vpn_key_rounded, color: accentGold, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        "Gemini API Configuration",
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Store your API key to enable AI auto-categorization of expenses.",
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    style: TextStyle(color: textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: "Enter AI API Key...",
                      hintStyle: TextStyle(color: textMuted),
                      filled: true,
                      fillColor: bgCardRaised,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: accentGreen, width: 1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () =>
                          _saveApiKey(_apiKeyController.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentGreen,
                        foregroundColor: bgDeep,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Save Key",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsList() {
    return FutureBuilder<List<TransactionModel>>(
      future: _transactionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: accentGreen,
              strokeWidth: 2,
            ),
          );
        } else if (snapshot.hasError) {
          return Center(
            child: Text(
              "ERROR: ${snapshot.error}",
              style: TextStyle(color: textSecondary),
            ),
          );
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 32),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: bgCardRaised,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: Icon(
                    Icons.receipt_long_rounded,
                    size: 36,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  "No Transactions",
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Your tracking history is empty.",
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        }

        final transactions = snapshot.data!;
        return ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
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
    );
  }

  Widget _buildAiCatButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => _runAiCategorization(),
        style: OutlinedButton.styleFrom(
          backgroundColor: accentPurple.withValues(alpha: 0.1),
          foregroundColor: accentPurple,
          side: BorderSide(
            color: accentPurple.withValues(alpha: 0.3),
            width: 1.5,
          ),
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 20),
            const SizedBox(width: 10),
            Text(
              "AI Categorize Transactions",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _runAiCategorization() async {
    if (_geminiApiKey.isEmpty) {
      _showSnack(
        'Please configure your Gemini API Key in Profile Settings first.',
        isError: true,
      );
      return;
    }

    _showSnack('Running AI categorization... Please wait.');

    try {
      final transactions = await DatabaseHelper().getAllTransactions(
        _selectedMonth,
      );
      if (transactions.isEmpty) {
        _showSnack('No transactions to categorize for this month.');
        return;
      }

      final aiService = AiService();
      final categoryMap = await aiService.categorizeTransactions(transactions);

      if (categoryMap.isEmpty) {
        _showSnack('No categories updated.');
        return;
      }

      int updateCount = 0;
      for (var tx in transactions) {
        // Only update if it actually categorized into a known category
        if (categoryMap.containsKey(tx.id) && categoryMap[tx.id] != 'Others') {
          final newCat = categoryMap[tx.id]!;
          if (_categories.contains(newCat)) {
            tx.category = newCat;
            await DatabaseHelper().updateTransaction(tx);
            updateCount++;
          }
        }
      }

      _showSnack('Successfully categorized $updateCount transactions!');
      _loadAllData();
    } catch (e) {
      _showSnack(e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  Widget _buildCategoryFilters() {
    IconData getIconForCategory(String cat) {
      switch (cat) {
        case 'Shopping':
          return Icons.shopping_bag_rounded;
        case 'Bills':
          return Icons.receipt_long_rounded;
        case 'Transport':
          return Icons.directions_car_rounded;
        case 'Food':
          return Icons.restaurant_rounded;
        case 'Entertainment':
          return Icons.movie_creation_rounded;
        case 'Health':
          return Icons.medical_services_rounded;
        default:
          return Icons.category_rounded;
      }
    }

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
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCategory = category;
                  _loadTransactions();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? accentGreen : bgCard,
                  borderRadius: BorderRadius.circular(20),
                  border: isSelected ? null : Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSelected && category != 'All') ...[
                      Icon(
                        getIconForCategory(category),
                        color: bgDeep,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      category.toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? bgDeep : textSecondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFab() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: accentGreen.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: () => _showManualEntryDialog(null),
        backgroundColor: accentGreen,
        elevation: 0,
        highlightElevation: 0,
        shape: const CircleBorder(),
        child: Icon(Icons.add_rounded, color: bgDeep, size: 28),
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

  // Dialogs
  void _showMultiDeleteConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: debitRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: debitRed,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Delete Items',
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Delete ${_selectedTransactions.length} items? This cannot be undone.',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textSecondary,
                        side: BorderSide(color: borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'CANCEL',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: debitRed,
                        foregroundColor: bgDeep,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
                      child: const Text(
                        'DELETE',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
            return Dialog(
              backgroundColor: bgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(color: borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction == null ? 'NEW ENTRY' : 'EDIT ENTRY',
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Custom Segmented Toggle
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: bgDeep,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(
                                () => transactionType = 'debit',
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: transactionType == 'debit'
                                      ? debitRed.withValues(alpha: 0.15)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: transactionType == 'debit'
                                      ? Border.all(
                                          color: debitRed.withValues(
                                            alpha: 0.5,
                                          ),
                                        )
                                      : Border.all(color: Colors.transparent),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.arrow_upward_rounded,
                                      size: 14,
                                      color: transactionType == 'debit'
                                          ? debitRed
                                          : textSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'SPEND',
                                      style: TextStyle(
                                        color: transactionType == 'debit'
                                            ? debitRed
                                            : textSecondary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(
                                () => transactionType = 'credit',
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: transactionType == 'credit'
                                      ? creditGreen.withValues(alpha: 0.15)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: transactionType == 'credit'
                                      ? Border.all(
                                          color: creditGreen.withValues(
                                            alpha: 0.5,
                                          ),
                                        )
                                      : Border.all(color: Colors.transparent),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.arrow_downward_rounded,
                                      size: 14,
                                      color: transactionType == 'credit'
                                          ? creditGreen
                                          : textSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'INCOME',
                                      style: TextStyle(
                                        color: transactionType == 'credit'
                                            ? creditGreen
                                            : textSecondary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    TextField(
                      controller: amountController,
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: InputDecoration(
                        labelText: 'AMOUNT',
                        labelStyle: TextStyle(
                          color: textSecondary,
                          fontSize: 13,
                          letterSpacing: 1.2,
                        ),
                        prefixIcon: const Icon(
                          Icons.currency_rupee_rounded,
                          size: 18,
                        ),
                        prefixIconColor: textSecondary,
                        filled: true,
                        fillColor: bgDeep,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: accentGreen),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: vendorController,
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        labelText: 'VENDOR NAME',
                        labelStyle: TextStyle(
                          color: textSecondary,
                          fontSize: 13,
                          letterSpacing: 1.2,
                        ),
                        prefixIcon: const Icon(
                          Icons.storefront_rounded,
                          size: 18,
                        ),
                        prefixIconColor: textSecondary,
                        filled: true,
                        fillColor: bgDeep,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: accentGreen),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textSecondary,
                              side: BorderSide(color: borderColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text(
                              'CANCEL',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: accentGreen,
                            ),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: bgDeep,
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              onPressed: () async {
                                final amount = double.tryParse(
                                  amountController.text,
                                );
                                final vendor = vendorController.text;

                                if (amount == null || vendor.isEmpty) {
                                  _showSnack(
                                    'Please fill all fields.',
                                    isError: true,
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
                                  _showSnack('Action failed.', isError: true);
                                }
                              },
                              child: const Text(
                                'SAVE',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
    // Dark Olive Fintech Colors
    final Color bgDeep = const Color(0xFF181A16);
    final Color bgCard = const Color(0xFF242720);
    final Color bgPill = const Color(0xFF333629);
    final Color accentGreen = const Color(0xFFC8D5A3);
    final Color textPrimary = const Color(0xFFF5F2E8);
    final Color textSecondary = const Color(0xFF8A8C7E);
    final Color textMuted = const Color(0xFF5A5C50);
    final Color borderColor = const Color(0xFF333629);
    final Color debitRed = const Color(0xFFE8756A);
    final Color creditGreen = const Color(0xFF85C9A3);

    final bool isDebit = transaction.transactionType == 'debit';
    final Color statusColor = isDebit ? debitRed : creditGreen;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? bgDeep : bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? accentGreen.withValues(alpha: 0.5) : borderColor,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(20),
          splashColor: accentGreen.withValues(alpha: 0.06),
          highlightColor: accentGreen.withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar Container
                CircleAvatar(
                  radius: 20,
                  backgroundColor: bgPill,
                  child: Text(
                    transaction.vendor.isNotEmpty
                        ? transaction.vendor[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Details Column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.vendor,
                        style: TextStyle(
                          color: textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM dd, yyyy').format(transaction.date),
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),

                // Amount Area
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "${isDebit ? '−' : ''}₹${NumberFormat('#,##,0').format(transaction.amount)}",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: bgPill,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        transaction.source.toUpperCase(),
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),

                // Selection Checkbox
                if (isSelectionMode) ...[
                  const SizedBox(width: 16),
                  AnimatedScale(
                    scale: isSelected ? 1.1 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isSelected ? accentGreen : Colors.transparent,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? null
                            : Border.all(color: borderColor, width: 2),
                      ),
                      child: isSelected
                          ? Icon(Icons.check_rounded, color: bgDeep, size: 16)
                          : null,
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
}
