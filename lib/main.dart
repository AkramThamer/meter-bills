import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'db.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'فواتير العدادات',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
        builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const CustomersPage(),
      );
}

String f(num d) => d.toStringAsFixed(2);

String invoiceText(String name, String type, double prev, double curr, double rate, double fee, String date) {
  final units = curr - prev;
  return 'فاتورة $type\nالتاريخ: $date\nالعميل: $name\n'
      'القراءة السابقة: ${f(prev)}\nالقراءة الحالية: ${f(curr)}\n'
      'الاستهلاك: ${f(units)} وحدة\nسعر الوحدة: ${f(rate)}\nرسوم ثابتة: ${f(fee)}\n'
      'الإجمالي المستحق: ${f(units * rate + fee)}\nشكراً لكم';
}

Future<void> sendSms(String phone, String text) =>
    launchUrl(Uri.parse('sms:$phone?body=${Uri.encodeComponent(text)}'));

Future<void> sendWhatsApp(String cc, String phone, String text) {
  var d = phone.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');
  if (!d.startsWith(cc)) d = cc + d;
  return launchUrl(Uri.parse('https://wa.me/$d?text=${Uri.encodeComponent(text)}'),
      mode: LaunchMode.externalApplication);
}

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});
  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  String q = '';
  List<Map<String, dynamic>> items = [];

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    final r = await Db.customers(q);
    setState(() => items = r);
  }

  Future<void> addDialog() async {
    final n = TextEditingController(), p = TextEditingController(), c = TextEditingController(text: '966');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('عميل جديد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: const InputDecoration(labelText: 'الاسم')),
          TextField(controller: p, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الجوال')),
          TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مفتاح الدولة')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && n.text.trim().isNotEmpty) {
      await Db.addCustomer(n.text.trim(), p.text.trim(), c.text.trim());
      load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('العملاء')),
        floatingActionButton: FloatingActionButton(onPressed: addDialog, child: const Icon(Icons.person_add)),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو الجوال', border: OutlineInputBorder()),
              onChanged: (v) { q = v; load(); },
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('لا يوجد عملاء، أضف عميلاً بالزر +'))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final c = items[i];
                      return ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(c['name']),
                        subtitle: Text(c['phone']),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await Db.deleteCustomer(c['id']);
                            load();
                          },
                        ),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BillPage(customer: c))),
                      );
                    },
                  ),
          ),
        ]),
      );
}

class BillPage extends StatefulWidget {
  final Map<String, dynamic> customer;
  const BillPage({super.key, required this.customer});
  @override
  State<BillPage> createState() => _BillPageState();
}

class _BillPageState extends State<BillPage> {
  String type = 'كهرباء';
  final prevC = TextEditingController(), currC = TextEditingController(),
      rateC = TextEditingController(), feeC = TextEditingController(text: '0');
  bool auto = false;
  List<Map<String, dynamic>> history = [];

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    final last = await Db.last(widget.customer['id'], type);
    final h = await Db.readings(widget.customer['id']);
    setState(() {
      history = h;
      currC.clear();
      auto = last != null;
      if (last != null) {
        prevC.text = '${last['curr']}';
        rateC.text = '${last['rate']}';
        feeC.text = '${last['fee']}';
      } else {
        prevC.clear();
      }
    });
  }

  double? n(TextEditingController c) => double.tryParse(c.text.trim());
  String get date => DateTime.now().toString().substring(0, 10);

  String? get text {
    final p = n(prevC), c = n(currC), r = n(rateC), fe = n(feeC) ?? 0;
    if (p == null || c == null || r == null || c < p) return null;
    return invoiceText(widget.customer['name'], type, p, c, r, fe, date);
  }

  Future<void> save() async {
    final p = n(prevC)!, c = n(currC)!, r = n(rateC)!, fe = n(feeC) ?? 0;
    await Db.addReading({
      'customer_id': widget.customer['id'], 'type': type, 'prev': p, 'curr': c,
      'rate': r, 'fee': fe, 'total': (c - p) * r + fe, 'date': date,
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ القراءة')));
    load();
  }

  Widget field(String l, TextEditingController c, {String? helper}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: l, helperText: helper, border: const OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final t = text;
    final cust = widget.customer;
    return Scaffold(
      appBar: AppBar(title: Text(cust['name'])),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'كهرباء', label: Text('كهرباء'), icon: Icon(Icons.bolt)),
            ButtonSegment(value: 'مياه', label: Text('مياه'), icon: Icon(Icons.water_drop)),
          ],
          selected: {type},
          onSelectionChanged: (s) { type = s.first; load(); },
        ),
        const SizedBox(height: 12),
        field('القراءة السابقة', prevC, helper: auto ? 'جُلبت تلقائياً من آخر قراءة' : 'أول مرة: أدخل القراءة الابتدائية'),
        const SizedBox(height: 12),
        field('القراءة الحالية', currC),
        const SizedBox(height: 12),
        field('سعر الوحدة', rateC),
        const SizedBox(height: 12),
        field('رسوم ثابتة', feeC),
        const SizedBox(height: 12),
        if (t != null) ...[
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(t))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton.icon(onPressed: () => sendSms(cust['phone'], t), icon: const Icon(Icons.sms), label: const Text('SMS')),
            FilledButton.icon(onPressed: () => sendWhatsApp(cust['cc'], cust['phone'], t), icon: const Icon(Icons.chat), label: const Text('واتساب')),
            OutlinedButton.icon(onPressed: save, icon: const Icon(Icons.save), label: const Text('حفظ القراءة')),
          ]),
        ] else
          const Text('أدخل القراءة الحالية والسعر (الحالية ≥ السابقة)'),
        const Divider(height: 32),
        const Text('سجل القراءات', style: TextStyle(fontWeight: FontWeight.bold)),
        ...history.map((h) => ListTile(
              dense: true,
              title: Text('${h['type']} | ${f(h['prev'])} ← ${f(h['curr'])}'),
              subtitle: Text('${h['date']}'),
              trailing: Text(f(h['total'])),
            )),
      ]),
    );
  }
}
