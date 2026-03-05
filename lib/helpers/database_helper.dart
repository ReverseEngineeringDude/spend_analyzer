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
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
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

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      var tableInfo = await db.rawQuery('PRAGMA table_info(expenses)');
      bool columnExists = tableInfo.any(
        (col) => col['name'] == 'transactionType',
      );
      if (!columnExists) {
        await db.execute(
          "ALTER TABLE expenses ADD COLUMN transactionType TEXT NOT NULL DEFAULT 'debit'",
        );
      }
    }
  }

  Future<int> insertTransaction(TransactionModel transaction) async {
    Database db = await database;
    return await db.insert('expenses', transaction.toMap());
  }

  Future<int> updateTransaction(TransactionModel transaction) async {
    Database db = await database;
    return await db.update(
      'expenses',
      transaction.toMap(),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  Future<void> deleteMultipleTransactions(List<int> ids) async {
    Database db = await database;
    await db.transaction((txn) async {
      for (int id in ids) {
        await txn.delete('expenses', where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  Future<void> updateTransactionCategories(Map<int, String> categoryMap) async {
    Database db = await database;
    await db.transaction((txn) async {
      for (final entry in categoryMap.entries) {
        await txn.update(
          'expenses',
          {'category': entry.value},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }
    });
  }

  Future<List<TransactionModel>> getAllTransactions(DateTime month) async {
    Database db = await database;
    final startOfMonth = DateTime(month.year, month.month, 1).toIso8601String();
    final endOfMonth = DateTime(
      month.year,
      month.month + 1,
      0,
    ).toIso8601String();

    final List<Map<String, dynamic>> maps = await db.query(
      'expenses',
      orderBy: 'date DESC',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startOfMonth, endOfMonth],
    );

    return List.generate(maps.length, (i) {
      return TransactionModel.fromMap(maps[i]);
    });
  }

  Future<double> getMonthlyDebits(DateTime month) async {
    Database db = await database;
    final startOfMonth = DateTime(month.year, month.month, 1).toIso8601String();
    final endOfMonth = DateTime(
      month.year,
      month.month + 1,
      0,
    ).toIso8601String();

    final result = await db.rawQuery(
      "SELECT SUM(amount) as total FROM expenses WHERE transactionType = 'debit' AND date >= ? AND date <= ?",
      [startOfMonth, endOfMonth],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getMonthlyCredits(DateTime month) async {
    Database db = await database;
    final startOfMonth = DateTime(month.year, month.month, 1).toIso8601String();
    final endOfMonth = DateTime(
      month.year,
      month.month + 1,
      0,
    ).toIso8601String();

    final result = await db.rawQuery(
      "SELECT SUM(amount) as total FROM expenses WHERE transactionType = 'credit' AND date >= ? AND date <= ?",
      [startOfMonth, endOfMonth],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }
}
