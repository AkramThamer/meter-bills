import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class Db {
  static Database? _d;
  static Future<Database> get _db async {
    _d ??= await openDatabase(join(await getDatabasesPath(), 'meter.db'), version: 1,
        onCreate: (db, v) async {
      await db.execute(
          'CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, phone TEXT, cc TEXT)');
      await db.execute(
          'CREATE TABLE readings(id INTEGER PRIMARY KEY AUTOINCREMENT, customer_id INTEGER, type TEXT, prev REAL, curr REAL, rate REAL, fee REAL, total REAL, date TEXT)');
    });
    return _d!;
  }

  static Future<List<Map<String, dynamic>>> customers(String q) async =>
      (await _db).query('customers', where: 'name LIKE ? OR phone LIKE ?', whereArgs: ['%$q%', '%$q%'], orderBy: 'name');

  static Future<void> addCustomer(String name, String phone, String cc) async =>
      (await _db).insert('customers', {'name': name, 'phone': phone, 'cc': cc});

  static Future<void> deleteCustomer(int id) async {
    final d = await _db;
    await d.delete('readings', where: 'customer_id=?', whereArgs: [id]);
    await d.delete('customers', where: 'id=?', whereArgs: [id]);
  }

  /// آخر قراءة مسجلة للعميل لهذا النوع (كهرباء/مياه)
  static Future<Map<String, dynamic>?> last(int cid, String type) async {
    final r = await (await _db).query('readings',
        where: 'customer_id=? AND type=?', whereArgs: [cid, type], orderBy: 'id DESC', limit: 1);
    return r.isEmpty ? null : r.first;
  }

  static Future<void> addReading(Map<String, dynamic> m) async => (await _db).insert('readings', m);

  static Future<List<Map<String, dynamic>>> readings(int cid) async =>
      (await _db).query('readings', where: 'customer_id=?', whereArgs: [cid], orderBy: 'id DESC');
}
