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
      version: 1,
      onCreate: _onCreate,
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
        source TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertTransaction(TransactionModel transaction) async {
    Database db = await database;
    return await db.insert('expenses', transaction.toMap());
  }

  Future<List<TransactionModel>> getAllTransactions() async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query('expenses', orderBy: 'date DESC');

    return List.generate(maps.length, (i) {
      return TransactionModel.fromMap(maps[i]);
    });
  }
}
