hereimport 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class Db {
  static Database? _d;
  static Future<Database> get _db async {
    _d ??= await openDatabase(join(await getDatabasesPath(), 'meter.db'), version: 2,
        onCreate: (db, v) async {
      await db.execute('CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, phone TEXT, cc TEXT)');
      await db.execute('CREATE TABLE readings(id INTEGER PRIMARY KEY AUTOINCREMENT, customer_id INTEGER, type TEXT, prev REAL, curr REAL, rate REAL, fee REAL, total REAL, date TEXT, paid REAL DEFAULT 0)');
      await db.execute('CREATE TABLE payments(id INTEGER PRIMARY KEY AUTOINCREMENT, reading_id INTEGER, amount REAL, method TEXT, date TEXT)');
    }, onUpgrade: (db, o, n) async {
      if (o < 2) {
        await db.execute('ALTER TABLE readings ADD COLUMN paid REAL DEFAULT 0');
        await db.execute('CREATE TABLE payments(id INTEGER PRIMARY KEY AUTOINCREMENT, reading_id INTEGER, amount REAL, method TEXT, date TEXT)');
      }
    });
    return _d!;
  }

  static Future<List<Map<String, dynamic>>> customers(String q) async =>
      (await _db).query('customers', where: 'name LIKE ? OR phone LIKE ?', whereArgs: ['%$q%', '%$q%'], orderBy: 'name');

  static Future<void> addCustomer(String name, String phone, String cc) async =>
      (await _db).insert('customers', {'name': name, 'phone': phone, 'cc': cc});

  static Future<void> deleteCustomer(int id) async {
    final d = await _db;
    await d.rawDelete('DELETE FROM payments WHERE reading_id IN (SELECT id FROM readings WHERE customer_id=?)', [id]);
    await d.delete('readings', where: 'customer_id=?', whereArgs: [id]);
    await d.delete('customers', where: 'id=?', whereArgs: [id]);
  }

  static Future<Map<String, dynamic>?> last(int cid, String type) async {
    final r = await (await _db).query('readings',
        where: 'customer_id=? AND type=?', whereArgs: [cid, type], orderBy: 'id DESC', limit: 1);
    return r.isEmpty ? null : r.first;
  }

  static Future<void> addReading(Map<String, dynamic> m) async => (await _db).insert('readings', m);

  /// كل الفواتير مع بيانات العميل (أو فواتير عميل واحد)
  static Future<List<Map<String, dynamic>>> invoices({int? cid}) async => (await _db).rawQuery(
      'SELECT r.*, c.name, c.phone, c.cc FROM readings r JOIN customers c ON c.id=r.customer_id '
      '${cid != null ? 'WHERE r.customer_id=$cid ' : ''}ORDER BY r.id DESC');

  static Future<void> addPayment(int rid, double amount, String method, String date) async {
    final d = await _db;
    await d.insert('payments', {'reading_id': rid, 'amount': amount, 'method': method, 'date': date});
    await d.rawUpdate('UPDATE readings SET paid = paid + ? WHERE id=?', [amount, rid]);
  }

  static Future<Map<String, num>> stats() async {
    final d = await _db;
    final r = (await d.rawQuery(
        'SELECT COALESCE(SUM(total),0) t, COALESCE(SUM(paid),0) p, COUNT(*) n, '
        'COALESCE(SUM(CASE WHEN paid < total-0.005 THEN 1 ELSE 0 END),0) u FROM readings')).first;
    final c = Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM customers')) ?? 0;
    return {'t': r['t'] as num, 'p': r['p'] as num, 'n': r['n'] as num, 'u': r['u'] as num, 'c': c};
  }
}
