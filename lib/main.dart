import 'dart:math';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'db.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'فواتير العدادات',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
        builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const Home(),
      );
}

String f(num d) => d.toStringAsFixed(2);
double dd(Object? v) => (v as num?)?.toDouble() ?? 0;
String today() => DateTime.now().toString().substring(0, 10);

String status(Map r) {
  final t = dd(r['total']), p = dd(r['paid']);
  return p >= t - 0.005 ? 'مدفوعة' : (p > 0 ? 'جزئية' : 'غير مدفوعة');
}

Color statusColor(String s) => s == 'مدفوعة' ? Colors.green : (s == 'جزئية' ? Colors.orange : Colors.red);

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

/// بطاقة فاتورة (تُستخدم في قائمة الفواتير وسجل العميل)
Widget invoiceTile(BuildContext context, Map<String, dynamic> r, VoidCallback reload) {
  final s = status(r);
  final rem = dd(r['total']) - dd(r['paid']);
  final elec = r['type'] == 'كهرباء';
  return ListTile(
    leading: CircleAvatar(
      backgroundColor: (elec ? Colors.amber : Colors.blue).withOpacity(0.2),
      child: Icon(elec ? Icons.bolt : Icons.water_drop, color: elec ? Colors.amber[800] : Colors.blue),
    ),
    title: Text('${r['name']} - ${r['type']}'),
    subtitle: Text('${r['date']} • الإجمالي ${f(dd(r['total']))} • المتبقي ${f(max(0, rem))}'),
    trailing: Chip(
      label: Text(s, style: const TextStyle(fontSize: 11, color: Colors.white)),
      backgroundColor: statusColor(s),
      padding: EdgeInsets.zero,
    ),
    onTap: () => openInvoice(context, r, reload),
  );
}

Future<void> openInvoice(BuildContext context, Map<String, dynamic> r, VoidCallback done) async {
  final total = dd(r['total']), paid = dd(r['paid']), rem = total - paid;
  final amountC = TextEditingController(text: rem > 0.005 ? f(rem) : '');
  final msg = ScaffoldMessenger.of(context);
  String method = 'نقداً';
  final cc = '${r['cc']}', phone = '${r['phone']}', name = '${r['name']}', type = '${r['type']}';
  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text('$name - $type'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('الإجمالي: ${f(total)}'),
            Text('المدفوع: ${f(paid)}'),
            Text('المتبقي: ${f(max(0, rem))}', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (rem > 0.005) ...[
              const SizedBox(height: 12),
              TextField(
                controller: amountC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'مبلغ السداد', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: method,
                isExpanded: true,
                items: ['نقداً', 'تحويل بنكي', 'بطاقة', 'سداد']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => set(() => method = v!),
              ),
            ] else
              const Padding(padding: EdgeInsets.only(top: 12), child: Text('✔ الفاتورة مسددة بالكامل')),
          ]),
        ),
        actions: [
          if (rem > 0.005)
            TextButton.icon(
              icon: const Icon(Icons.notifications_active),
              label: const Text('تذكير'),
              onPressed: () => sendWhatsApp(cc, phone,
                  'تذكير بسداد فاتورة $type\nالعميل: $name\nالمبلغ المتبقي: ${f(rem)}\nنرجو السداد في أقرب وقت، شكراً لكم'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          if (rem > 0.005)
            FilledButton(
              onPressed: () async {
                final a = double.tryParse(amountC.text.trim());
                if (a == null || a <= 0) return;
                final pay = min(a, rem);
                await Db.addPayment(r['id'] as int, pay, method, today());
                if (ctx.mounted) Navigator.pop(ctx);
                done();
                final receipt = 'إيصال سداد\nالتاريخ: ${today()}\nالعميل: $name\nالفاتورة: $type\n'
                    'المبلغ المدفوع: ${f(pay)}\nطريقة الدفع: $method\nالمتبقي: ${f(max(0, rem - pay))}\nشكراً لكم';
                msg.showSnackBar(SnackBar(
                  content: const Text('تم تسجيل السداد'),
                  duration: const Duration(seconds: 8),
                  action: SnackBarAction(label: 'إرسال الإيصال', onPressed: () => sendWhatsApp(cc, phone, receipt)),
                ));
              },
              child: const Text('تسجيل السداد'),
            ),
        ],
      ),
    ),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int i = 0;
  static const titles = ['لوحة المتابعة', 'العملاء', 'الفواتير'];
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(titles[i])),
        body: [const DashboardPage(), const CustomersPage(), const InvoicesPage()][i],
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (v) => setState(() => i = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.people), label: 'العملاء'),
            NavigationDestination(icon: Icon(Icons.receipt_long), label: 'الفواتير'),
          ],
        ),
      );
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  Widget box(String t, String v, IconData ic, Color c) => Card(
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ic, color: c, size: 30),
            const SizedBox(height: 8),
            Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(t),
          ]),
        ),
      );
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, num>>(
        future: Db.stats(),
        builder: (_, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final m = s.data!;
          return ListView(padding: const EdgeInsets.all(12), children: [
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              box('إجمالي الفواتير', f(m['t']!), Icons.request_quote, Colors.teal),
              box('المحصّل', f(m['p']!), Icons.payments, Colors.green),
              box('المتبقي', f(m['t']! - m['p']!), Icons.account_balance_wallet, Colors.red),
              box('فواتير غير مسددة', '${m['u']}', Icons.pending_actions, Colors.orange),
              box('عدد الفواتير', '${m['n']}', Icons.receipt_long, Colors.blueGrey),
              box('عدد العملاء', '${m['c']}', Icons.people, Colors.indigo),
            ]),
          ]);
        },
      );
}

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});
  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  String filter = 'الكل';
  List<Map<String, dynamic>> items = [];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    final r = await Db.invoices();
    setState(() => items = r);
  }
  @override
  Widget build(BuildContext context) {
    final list = filter == 'الكل' ? items : items.where((r) => status(r) == filter).toList();
    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        child: Row(
          children: ['الكل', 'غير مدفوعة', 'جزئية', 'مدفوعة']
              .map((e) => Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(label: Text(e), selected: filter == e, onSelected: (_) => setState(() => filter = e)),
                  ))
              .toList(),
        ),
      ),
      Expanded(
        child: list.isEmpty
            ? const Center(child: Text('لا توجد فواتير'))
            : ListView.builder(itemCount: list.length, itemBuilder: (_, i) => invoiceTile(context, list[i], load)),
      ),
    ]);
  }
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
          TextField(controller: n, decoration: const InputDecoration(labelText: 'الاسم', prefixIcon: Icon(Icons.person))),
          TextField(controller: p, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الجوال', prefixIcon: Icon(Icons.phone))),
          TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مفتاح الدولة', prefixIcon: Icon(Icons.public))),
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
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(c['name']),
                        subtitle: Text(c['phone']),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('حذف العميل؟'),
                                content: const Text('سيتم حذف جميع فواتيره ومدفوعاته.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
                                ],
                              ),
                            );
                            if (ok == true) { await Db.deleteCustomer(c['id']); load(); }
                          },
                        ),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => BillPage(customer: c)));
                        },
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
    final h = await Db.invoices(cid: widget.customer['id']);
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

  String? get text {
    final p = n(prevC), c = n(currC), r = n(rateC), fe = n(feeC) ?? 0;
    if (p == null || c == null || r == null || c < p) return null;
    return invoiceText(widget.customer['name'], type, p, c, r, fe, today());
  }

  Future<void> save() async {
    final p = n(prevC)!, c = n(currC)!, r = n(rateC)!, fe = n(feeC) ?? 0;
    await Db.addReading({
      'customer_id': widget.customer['id'], 'type': type, 'prev': p, 'curr': c,
      'rate': r, 'fee': fe, 'total': (c - p) * r + fe, 'date': today(), 'paid': 0.0,
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الفاتورة')));
    load();
  }

  Widget field(String l, TextEditingController c, IconData ic, {String? helper}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: l, helperText: helper, prefixIcon: Icon(ic), border: const OutlineInputBorder()),
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
        field('القراءة السابقة', prevC, Icons.history, helper: auto ? 'جُلبت تلقائياً من آخر قراءة' : 'أول مرة: أدخل القراءة الابتدائية'),
        const SizedBox(height: 12),
        field('القراءة الحالية', currC, Icons.speed),
        const SizedBox(height: 12),
        field('سعر الوحدة', rateC, Icons.sell),
        const SizedBox(height: 12),
        field('رسوم ثابتة', feeC, Icons.add_card),
        const SizedBox(height: 12),
        if (t != null) ...[
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(t))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton.icon(onPressed: () => sendSms(cust['phone'], t), icon: const Icon(Icons.sms), label: const Text('SMS')),
            FilledButton.icon(onPressed: () => sendWhatsApp(cust['cc'], cust['phone'], t), icon: const Icon(Icons.chat), label: const Text('واتساب')),
            OutlinedButton.icon(onPressed: save, icon: const Icon(Icons.save), label: const Text('حفظ الفاتورة')),
          ]),
        ] else
          const Text('أدخل القراءة الحالية والسعر (الحالية ≥ السابقة)'),
        const Divider(height: 32),
        const Text('فواتير العميل (اضغط على فاتورة للسداد)', style: TextStyle(fontWeight: FontWeight.bold)),
        ...history.map((h) => invoiceTile(context, h, load)),
      ]),
    );
  }
}
