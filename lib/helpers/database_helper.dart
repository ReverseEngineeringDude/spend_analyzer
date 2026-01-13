import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:spend_analyzer/models/transaction_model.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'spend_analyzer.db');
    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.execute('DROP TABLE IF EXISTS expenses');
        await _onCreate(db, newVersion);
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE expenses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        vendor TEXT NOT NULL,
        category TEXT,
        date TEXT NOT NULL,
        rawSms TEXT,
        source TEXT NOT NULL,
        transactionType TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertTransaction(TransactionModel transaction) async {
    Database db = await database;
    return await db.insert('expenses', transaction.toMap());
  }

  Future<Map<String, List<TransactionModel>>> getAllTransactions() async {
    Database db = await database;
    final List<Map<String, dynamic>> maps =
        await db.query('expenses', orderBy: 'date DESC');

    final transactions = List.generate(maps.length, (i) {
      return TransactionModel.fromMap(maps[i]);
    });

    final Map<String, List<TransactionModel>> groupedTransactions = {};
    for (var transaction in transactions) {
      final monthYear = DateFormat('MMMM yyyy').format(transaction.date);
      if (groupedTransactions[monthYear] == null) {
        groupedTransactions[monthYear] = [];
      }
      groupedTransactions[monthYear]!.add(transaction);
    }
    return groupedTransactions;
  }

  Future<double> getMonthlyDebits(String? month, String? year) async {
    Database db = await database;
    final targetMonth = month ?? DateTime.now().month.toString().padLeft(2, '0');
    final targetYear = year ?? DateTime.now().year.toString();
    final result = await db.rawQuery(
      "SELECT SUM(amount) as total FROM expenses WHERE transactionType = 'debit' AND strftime('%m', date) = ? AND strftime('%Y', date) = ?",
      [targetMonth, targetYear],
    );
    return (result.first['total'] as double?) ?? 0.0;
  }

  Future<double> getMonthlyCredits(String? month, String? year) async {
    Database db = await database;
    final targetMonth = month ?? DateTime.now().month.toString().padLeft(2, '0');
    final targetYear = year ?? DateTime.now().year.toString();
    final result = await db.rawQuery(
      "SELECT SUM(amount) as total FROM expenses WHERE transactionType = 'credit' AND strftime('%m', date) = ? AND strftime('%Y', date) = ?",
      [targetMonth, targetYear],
    );
    return (result.first['total'] as double?) ?? 0.0;
  }

  Future<void> updateTransaction(TransactionModel transaction) async {
    Database db = await database;
    await db.update(
      'expenses',
      transaction.toMap(),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  Future<void> deleteTransaction(int id) async {
    Database db = await database;
    await db.delete(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteMultipleTransactions(List<int> ids) async {
    Database db = await database;
    await db.transaction((txn) async {
      var batch = txn.batch();
      for (var id in ids) {
        batch.delete('expenses', where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit();
    });
  }
}
