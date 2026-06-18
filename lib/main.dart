import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const JamiyatiApp());

const _bg = Color(0xff101820);
const _card = Color(0xff17232e);
const _accent = Color(0xff22c7a9);
const _warn = Color(0xffffb84d);
const _danger = Color(0xffff6b6b);

String newId() => DateTime.now().microsecondsSinceEpoch.toString();

String money(num v, String c) => '${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2)} $c';

DateTime monthDate(DateTime start, int offset) => DateTime(start.year, start.month + offset, 1);
String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
String monthLabel(DateTime d) => '${d.month.toString().padLeft(2, '0')} / ${d.year}';
DateTime parseMonthKey(String k) {
  final p = k.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), 1);
}

class Member {
  String id, name, phone, note;
  int turn;
  bool active;
  Member({required this.id, required this.name, this.phone = '', this.note = '', required this.turn, this.active = true});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone, 'note': note, 'turn': turn, 'active': active};
  factory Member.fromJson(Map<String, dynamic> j) => Member(id: '${j['id']}', name: j['name'] ?? '', phone: j['phone'] ?? '', note: j['note'] ?? '', turn: j['turn'] ?? 1, active: j['active'] ?? true);
}

class Payment {
  String id, associationId, memberId, month, date, note;
  double amount;
  Payment({required this.id, required this.associationId, required this.memberId, required this.month, required this.amount, required this.date, this.note = ''});
  Map<String, dynamic> toJson() => {'id': id, 'associationId': associationId, 'memberId': memberId, 'month': month, 'amount': amount, 'date': date, 'note': note};
  factory Payment.fromJson(Map<String, dynamic> j) => Payment(id: '${j['id']}', associationId: '${j['associationId']}', memberId: '${j['memberId']}', month: j['month'] ?? '', amount: (j['amount'] ?? 0).toDouble(), date: j['date'] ?? '', note: j['note'] ?? '');
}

class Association {
  String id, name, startDate, currency, note;
  double monthlyAmount;
  int months;
  bool archived;
  List<Member> members;
  Association({required this.id, required this.name, required this.startDate, required this.monthlyAmount, this.currency = 'دينار', required this.months, this.note = '', this.archived = false, List<Member>? members}) : members = members ?? [];
  DateTime get start => DateTime.tryParse(startDate) ?? DateTime.now();
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'startDate': startDate, 'monthlyAmount': monthlyAmount, 'currency': currency, 'months': months, 'note': note, 'archived': archived, 'members': members.map((e) => e.toJson()).toList()};
  factory Association.fromJson(Map<String, dynamic> j) => Association(id: '${j['id']}', name: j['name'] ?? '', startDate: j['startDate'] ?? DateTime.now().toIso8601String(), monthlyAmount: (j['monthlyAmount'] ?? 0).toDouble(), currency: j['currency'] ?? 'دينار', months: j['months'] ?? 1, note: j['note'] ?? '', archived: j['archived'] ?? false, members: (j['members'] as List? ?? []).map((e) => Member.fromJson(Map<String, dynamic>.from(e))).toList());
}

class Store extends ChangeNotifier {
  List<Association> associations = [];
  List<Payment> payments = [];
  String passcode = '';
  bool locked = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('jamiyati_data');
    if (raw != null && raw.isNotEmpty) {
      final j = jsonDecode(raw);
      associations = (j['associations'] as List? ?? []).map((e) => Association.fromJson(Map<String, dynamic>.from(e))).toList();
      payments = (j['payments'] as List? ?? []).map((e) => Payment.fromJson(Map<String, dynamic>.from(e))).toList();
      passcode = j['passcode'] ?? '';
      locked = passcode.isNotEmpty;
    }
    notifyListeners();
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('jamiyati_data', jsonEncode(exportMap()));
    notifyListeners();
  }

  Map<String, dynamic> exportMap() => {'version': 1, 'passcode': passcode, 'associations': associations.map((e) => e.toJson()).toList(), 'payments': payments.map((e) => e.toJson()).toList()};
  Future<bool> importJson(String text) async {
    try {
      final j = jsonDecode(text);
      associations = (j['associations'] as List? ?? []).map((e) => Association.fromJson(Map<String, dynamic>.from(e))).toList();
      payments = (j['payments'] as List? ?? []).map((e) => Payment.fromJson(Map<String, dynamic>.from(e))).toList();
      passcode = j['passcode'] ?? '';
      locked = passcode.isNotEmpty;
      await save();
      return true;
    } catch (_) { return false; }
  }

  Association? byId(String id) => associations.where((e) => e.id == id).cast<Association?>().firstOrNull;
  List<Payment> monthPayments(String aid, String month) => payments.where((p) => p.associationId == aid && p.month == month).toList();
  bool isPaid(String aid, String mid, String month) => payments.any((p) => p.associationId == aid && p.memberId == mid && p.month == month);
  void togglePayment(Association a, Member m, String month) {
    final i = payments.indexWhere((p) => p.associationId == a.id && p.memberId == m.id && p.month == month);
    if (i >= 0) { payments.removeAt(i); } else { payments.add(Payment(id: newId(), associationId: a.id, memberId: m.id, month: month, amount: a.monthlyAmount, date: DateTime.now().toIso8601String())); }
    save();
  }

  int currentOffset(Association a) {
    final now = DateTime.now();
    final s = DateTime(a.start.year, a.start.month, 1);
    final diff = (now.year - s.year) * 12 + now.month - s.month;
    return diff.clamp(0, (a.months - 1).clamp(0, 9999)).toInt();
  }

  Member? roleMember(Association a, int offset) {
    if (a.members.isEmpty) return null;
    final sorted = [...a.members]..sort((x, y) => x.turn.compareTo(y.turn));
    return sorted[offset % sorted.length];
  }
}

extension FirstOrNull<E> on Iterable<E> { E? get firstOrNull => isEmpty ? null : first; }

class JamiyatiApp extends StatefulWidget { const JamiyatiApp({super.key}); @override State<JamiyatiApp> createState() => _JamiyatiAppState(); }
class _JamiyatiAppState extends State<JamiyatiApp> {
  final store = Store();
  @override void initState() { super.initState(); store.load(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: store, builder: (_, __) => MaterialApp(debugShowCheckedModeBanner: false, title: 'جمعيتي', locale: const Locale('ar'), theme: ThemeData(useMaterial3: true, fontFamily: 'Arial', scaffoldBackgroundColor: _bg, colorScheme: ColorScheme.fromSeed(seedColor: _accent, brightness: Brightness.dark)), home: Directionality(textDirection: TextDirection.rtl, child: store.locked ? LockPage(store: store) : HomePage(store: store))));
}

class LockPage extends StatefulWidget { final Store store; const LockPage({super.key, required this.store}); @override State<LockPage> createState() => _LockPageState(); }
class _LockPageState extends State<LockPage> { final c = TextEditingController(); String err=''; @override Widget build(BuildContext context)=>Scaffold(body: Center(child: CardBox(child: Column(mainAxisSize: MainAxisSize.min, children:[const Icon(Icons.lock, size:60, color:_accent), const SizedBox(height:12), const Text('جمعيتي محمي برمز دخول', style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)), Field(c,'رمز الدخول', keyboard: TextInputType.number, obscure:true), if(err.isNotEmpty) Text(err, style: const TextStyle(color:_danger)), BigButton('دخول', Icons.login, (){ if(c.text.trim()==widget.store.passcode){ widget.store.locked=false; widget.store.notifyListeners(); } else { setState(()=>err='رمز غير صحيح'); }} )])))); }

class HomePage extends StatefulWidget { final Store store; const HomePage({super.key, required this.store}); @override State<HomePage> createState()=>_HomePageState(); }
class _HomePageState extends State<HomePage> {
  int tab=0;
  @override Widget build(BuildContext context){ final pages=[Dashboard(store:widget.store), AssociationsPage(store:widget.store), ReportsPage(store:widget.store), SettingsPage(store:widget.store)]; return Scaffold(appBar: AppBar(title: const Text('جمعيتي'), centerTitle:true, backgroundColor:_bg, actions:[IconButton(onPressed:()=>openAssocForm(context, widget.store, null), icon: const Icon(Icons.add_circle, color:_accent))]), body: pages[tab], bottomNavigationBar: NavigationBar(selectedIndex:tab, onDestinationSelected:(v)=>setState(()=>tab=v), destinations: const [NavigationDestination(icon:Icon(Icons.dashboard), label:'الرئيسية'), NavigationDestination(icon:Icon(Icons.groups), label:'الجمعيات'), NavigationDestination(icon:Icon(Icons.summarize), label:'التقارير'), NavigationDestination(icon:Icon(Icons.settings), label:'الإعدادات')]), floatingActionButton: tab==1?FloatingActionButton(onPressed:()=>openAssocForm(context, widget.store, null), child: const Icon(Icons.add)):null); }
}

class Dashboard extends StatelessWidget { final Store store; const Dashboard({super.key, required this.store}); @override Widget build(BuildContext context){ final active=store.associations.where((a)=>!a.archived).toList(); int overdue=0; double monthly=0; String next='لا يوجد'; for(final a in active){ monthly += a.monthlyAmount*a.members.length; final mk=monthKey(monthDate(a.start, store.currentOffset(a))); overdue += a.members.where((m)=>!store.isPaid(a.id,m.id,mk)).length; next = store.roleMember(a, store.currentOffset(a))?.name ?? next; } return ListView(padding: const EdgeInsets.all(16), children:[const Text('نظرة عامة', style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)), const SizedBox(height:12), Wrap(spacing:10, runSpacing:10, children:[StatCard('الجمعيات النشطة','${active.length}',Icons.groups,_accent),StatCard('إجمالي الشهر',money(monthly, active.firstOrNull?.currency ?? ''),Icons.payments,_warn),StatCard('المتأخرون','${overdue}',Icons.warning,_danger),StatCard('الدور الحالي',next,Icons.person,_accent)]), const SizedBox(height:16), BigButton('إنشاء جمعية جديدة', Icons.add, ()=>openAssocForm(context, store, null)), const SizedBox(height:10), CardBox(child: Text('التنبيهات الداخلية: لديك $overdue عضو غير مسدد في الشهر الحالي. افتح تفاصيل الجمعية لإرسال تذكير واتساب.', style: const TextStyle(fontSize:16))) ]); }}

class AssociationsPage extends StatelessWidget { final Store store; const AssociationsPage({super.key, required this.store}); @override Widget build(BuildContext context){ final list=[...store.associations]..sort((a,b)=>a.archived==b.archived?b.id.compareTo(a.id):a.archived?1:-1); if(list.isEmpty) return Empty(msg:'لا توجد جمعيات بعد', action:()=>openAssocForm(context, store, null)); return ListView.builder(padding: const EdgeInsets.all(12), itemCount:list.length, itemBuilder:(_,i){ final a=list[i]; final off=store.currentOffset(a); final mk=monthKey(monthDate(a.start, off)); final paid=a.members.where((m)=>store.isPaid(a.id,m.id,mk)).length; return CardBox(margin: const EdgeInsets.only(bottom:10), child: ListTile(onTap:()=>Navigator.push(context, MaterialPageRoute(builder:(_)=>AssociationDetails(store:store, associationId:a.id))), title:Text(a.name, style: const TextStyle(fontWeight:FontWeight.bold,fontSize:18)), subtitle:Text('${a.members.length} أعضاء | ${money(a.monthlyAmount,a.currency)} | الشهر ${off+1}/${a.months}\nالمدفوع هذا الشهر: $paid / ${a.members.length}${a.archived?' | مؤرشفة':''}'), trailing: const Icon(Icons.chevron_left))); }); }}

class AssociationDetails extends StatefulWidget { final Store store; final String associationId; const AssociationDetails({super.key, required this.store, required this.associationId}); @override State<AssociationDetails> createState()=>_AssociationDetailsState(); }
class _AssociationDetailsState extends State<AssociationDetails>{ int offset=0; @override void initState(){super.initState(); final a=widget.store.byId(widget.associationId); if(a!=null) offset=widget.store.currentOffset(a);} @override Widget build(BuildContext context){ final a=widget.store.byId(widget.associationId); if(a==null) return const Scaffold(body:Center(child:Text('الجمعية غير موجودة'))); final d=monthDate(a.start, offset); final mk=monthKey(d); final role=widget.store.roleMember(a, offset); final paid=a.members.where((m)=>widget.store.isPaid(a.id,m.id,mk)).length; return Scaffold(appBar:AppBar(title:Text(a.name), backgroundColor:_bg, actions:[PopupMenuButton<String>(onSelected:(v){ if(v=='edit') openAssocForm(context, widget.store, a); if(v=='archive'){a.archived=!a.archived; widget.store.save(); setState((){});} if(v=='delete') confirm(context,'حذف الجمعية؟',(){widget.store.associations.removeWhere((x)=>x.id==a.id); widget.store.payments.removeWhere((p)=>p.associationId==a.id); widget.store.save(); Navigator.pop(context); Navigator.pop(context);});}, itemBuilder:(_)=>[const PopupMenuItem(value:'edit', child:Text('تعديل')), PopupMenuItem(value:'archive', child:Text(a.archived?'إلغاء الأرشفة':'أرشفة')), const PopupMenuItem(value:'delete', child:Text('حذف'))])]), body:ListView(padding: const EdgeInsets.all(12), children:[CardBox(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[Text('شهر ${monthLabel(d)}', style: const TextStyle(fontSize:20,fontWeight:FontWeight.bold)), Text('صاحب الدور: ${role?.name ?? 'غير محدد'}'), Text('المحصل: ${money(paid*a.monthlyAmount,a.currency)} من ${money(a.members.length*a.monthlyAmount,a.currency)}'), Row(children:[Expanded(child:BigButton('الشهر السابق',Icons.arrow_back, offset>0?()=>setState(()=>offset--):null)), const SizedBox(width:8), Expanded(child:BigButton('الشهر التالي',Icons.arrow_forward, offset<a.months-1?()=>setState(()=>offset++):null))])])), const SizedBox(height:10), BigButton('إضافة عضو', Icons.person_add, ()=>openMemberForm(context, widget.store, a, null)), const SizedBox(height:10), ...a.members.map((m){ final isPaid=widget.store.isPaid(a.id,m.id,mk); return CardBox(margin: const EdgeInsets.only(bottom:8), child:ListTile(title:Text('${m.turn}. ${m.name}', style: const TextStyle(fontWeight:FontWeight.bold)), subtitle:Text('${m.phone.isEmpty?'لا يوجد هاتف':m.phone}\n${isPaid?'تم الدفع':'غير مسدد'}'), leading:IconButton(icon:Icon(isPaid?Icons.check_circle:Icons.radio_button_unchecked, color:isPaid?_accent:_warn), onPressed:(){widget.store.togglePayment(a,m,mk); setState((){});}), trailing:Wrap(children:[IconButton(icon:const Icon(Icons.chat), onPressed:()=>sendReminder(a,m,mk)), IconButton(icon:const Icon(Icons.receipt_long), onPressed:()=>showText(context,'كشف ${m.name}', memberReport(widget.store,a,m))), IconButton(icon:const Icon(Icons.edit), onPressed:()=>openMemberForm(context,widget.store,a,m))] )));}), const SizedBox(height:10), BigButton('كشف الجمعية ونسخه', Icons.copy, ()=>showText(context,'كشف الجمعية', associationReport(widget.store,a))) ])); }}

class ReportsPage extends StatelessWidget { final Store store; const ReportsPage({super.key, required this.store}); @override Widget build(BuildContext context){ final overdue=<String>[]; for(final a in store.associations.where((x)=>!x.archived)){ final mk=monthKey(monthDate(a.start, store.currentOffset(a))); for(final m in a.members){ if(!store.isPaid(a.id,m.id,mk)) overdue.add('${a.name} - ${m.name} - ${money(a.monthlyAmount,a.currency)}'); }} return ListView(padding: const EdgeInsets.all(16), children:[const Text('التقارير', style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)), CardBox(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[const Text('المتأخرون الآن', style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)), const SizedBox(height:8), Text(overdue.isEmpty?'لا يوجد متأخرون':overdue.join('\n')), const SizedBox(height:8), BigButton('نسخ التقرير', Icons.copy, ()=>copyText(context, overdue.join('\n')))])), CardBox(child:Column(children:[BigButton('تقرير شامل لكل الجمعيات', Icons.description, ()=>showText(context,'تقرير شامل', allReport(store))), const SizedBox(height:8), BigButton('نسخ نسخة احتياطية JSON', Icons.backup, ()=>copyText(context, const JsonEncoder.withIndent('  ').convert(store.exportMap())))]))]); }}

class SettingsPage extends StatefulWidget { final Store store; const SettingsPage({super.key, required this.store}); @override State<SettingsPage> createState()=>_SettingsPageState(); }
class _SettingsPageState extends State<SettingsPage>{ final pass=TextEditingController(); final imp=TextEditingController(); @override Widget build(BuildContext context)=>ListView(padding: const EdgeInsets.all(16), children:[const Text('الإعدادات', style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)), CardBox(child:Column(children:[Field(pass,'رمز الدخول الجديد', keyboard:TextInputType.number), BigButton('حفظ رمز الدخول', Icons.lock, (){widget.store.passcode=pass.text.trim(); widget.store.locked=false; widget.store.save(); snack(context,'تم حفظ الرمز');}), BigButton('إلغاء رمز الدخول', Icons.lock_open, (){widget.store.passcode=''; widget.store.locked=false; widget.store.save(); snack(context,'تم الإلغاء');})])), CardBox(child:Column(children:[Field(imp,'لصق نسخة JSON للاسترجاع', maxLines:5), BigButton('استرجاع البيانات', Icons.restore, () async { final ok=await widget.store.importJson(imp.text.trim()); snack(context, ok?'تم الاسترجاع':'النص غير صحيح');})])), const Text('ملاحظة: النسخ الاحتياطي يتم بنسخ JSON وحفظه في واتساب أو ملف ملاحظات. هذا أكثر ثباتًا من الاعتماد على ملفات داخل WebView.')]); }
}

Future<void> openAssocForm(BuildContext context, Store store, Association? old) async { final name=TextEditingController(text:old?.name??''); final amount=TextEditingController(text:old?.monthlyAmount.toString()??''); final cur=TextEditingController(text:old?.currency??'دينار'); final months=TextEditingController(text:(old?.months??12).toString()); final note=TextEditingController(text:old?.note??''); DateTime start=old?.start??DateTime.now(); await showDialog(context:context,builder:(_)=>Dialog(child:Directionality(textDirection:TextDirection.rtl, child:Padding(padding: const EdgeInsets.all(16), child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min, children:[Text(old==null?'إنشاء جمعية':'تعديل جمعية', style: const TextStyle(fontSize:22,fontWeight:FontWeight.bold)), Field(name,'اسم الجمعية'), Field(amount,'قيمة الاشتراك', keyboard:TextInputType.number), Field(cur,'العملة'), Field(months,'عدد الأشهر', keyboard:TextInputType.number), Field(note,'ملاحظة', maxLines:2), BigButton('تاريخ البداية: ${monthLabel(start)}', Icons.date_range, () async { final picked=await showDatePicker(context:context, initialDate:start, firstDate:DateTime(2020), lastDate:DateTime(2040)); if(picked!=null) start=picked; }), BigButton('حفظ', Icons.save, (){ if(name.text.trim().isEmpty) return; final a=old??Association(id:newId(), name:'', startDate:start.toIso8601String(), monthlyAmount:0, months:1); a.name=name.text.trim(); a.monthlyAmount=double.tryParse(amount.text)??0; a.currency=cur.text.trim().isEmpty?'دينار':cur.text.trim(); a.months=int.tryParse(months.text)??1; a.startDate=start.toIso8601String(); a.note=note.text.trim(); if(old==null) store.associations.add(a); store.save(); Navigator.pop(context);})]))))); }

Future<void> openMemberForm(BuildContext context, Store store, Association a, Member? old) async { final name=TextEditingController(text:old?.name??''); final phone=TextEditingController(text:old?.phone??''); final turn=TextEditingController(text:(old?.turn??a.members.length+1).toString()); final note=TextEditingController(text:old?.note??''); await showDialog(context:context,builder:(_)=>Dialog(child:Directionality(textDirection:TextDirection.rtl, child:Padding(padding: const EdgeInsets.all(16), child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min, children:[Text(old==null?'إضافة عضو':'تعديل عضو', style: const TextStyle(fontSize:22,fontWeight:FontWeight.bold)), Field(name,'اسم العضو'), Field(phone,'رقم الهاتف للواتساب', keyboard:TextInputType.phone), Field(turn,'ترتيب الدور', keyboard:TextInputType.number), Field(note,'ملاحظة', maxLines:2), BigButton('حفظ', Icons.save, (){ if(name.text.trim().isEmpty) return; final m=old??Member(id:newId(), name:'', turn:1); m.name=name.text.trim(); m.phone=phone.text.trim(); m.turn=int.tryParse(turn.text)??1; m.note=note.text.trim(); if(old==null) a.members.add(m); a.members.sort((x,y)=>x.turn.compareTo(y.turn)); store.save(); Navigator.pop(context);}), if(old!=null) BigButton('حذف العضو', Icons.delete, (){a.members.removeWhere((x)=>x.id==old.id); store.payments.removeWhere((p)=>p.memberId==old.id); store.save(); Navigator.pop(context);}, danger:true)]))))); }

String associationReport(Store s, Association a){ final b=StringBuffer('كشف جمعية: ${a.name}\nالقسط: ${money(a.monthlyAmount,a.currency)}\nعدد الأعضاء: ${a.members.length}\n\n'); for(int i=0;i<a.months;i++){ final mk=monthKey(monthDate(a.start,i)); final role=s.roleMember(a,i); final paid=a.members.where((m)=>s.isPaid(a.id,m.id,mk)).length; b.writeln('${monthLabel(parseMonthKey(mk))} | الدور: ${role?.name??'-'} | المدفوع: $paid/${a.members.length}'); } return b.toString(); }
String memberReport(Store s, Association a, Member m){ final b=StringBuffer('كشف عضو: ${m.name}\nالجمعية: ${a.name}\n\n'); for(int i=0;i<a.months;i++){ final mk=monthKey(monthDate(a.start,i)); b.writeln('${monthLabel(parseMonthKey(mk))}: ${s.isPaid(a.id,m.id,mk)?'مدفوع':'غير مدفوع'}'); } return b.toString(); }
String allReport(Store s)=>s.associations.map((a)=>associationReport(s,a)).join('\n----------------\n');

Future<void> sendReminder(Association a, Member m, String mk) async { final phone=m.phone.replaceAll(RegExp(r'[^0-9]'),''); final txt=Uri.encodeComponent('السلام عليكم، تذكير بدفع قسط جمعية ${a.name}\nالشهر: ${monthLabel(parseMonthKey(mk))}\nالمبلغ: ${money(a.monthlyAmount,a.currency)}\nوشكرًا'); final uri=Uri.parse(phone.isEmpty?'https://wa.me/?text=$txt':'https://wa.me/$phone?text=$txt'); await launchUrl(uri, mode: LaunchMode.externalApplication); }
void copyText(BuildContext c, String t){ Clipboard.setData(ClipboardData(text:t)); snack(c,'تم النسخ'); }
void showText(BuildContext c, String title, String text){ showDialog(context:c,builder:(_)=>Dialog(child:Directionality(textDirection:TextDirection.rtl, child:Padding(padding: const EdgeInsets.all(16), child:Column(mainAxisSize:MainAxisSize.min, children:[Text(title, style: const TextStyle(fontSize:20,fontWeight:FontWeight.bold)), const SizedBox(height:8), Flexible(child:SingleChildScrollView(child:SelectableText(text))), BigButton('نسخ', Icons.copy, ()=>copyText(c,text)), BigButton('إغلاق', Icons.close, ()=>Navigator.pop(c))])))); }
void confirm(BuildContext c, String msg, VoidCallback yes){ showDialog(context:c,builder:(_)=>AlertDialog(title:Text(msg), actions:[TextButton(onPressed:()=>Navigator.pop(c), child: const Text('لا')), FilledButton(onPressed:yes, child: const Text('نعم'))])); }
void snack(BuildContext c, String m)=>ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text(m)));

class Field extends StatelessWidget{ final TextEditingController c; final String label; final TextInputType? keyboard; final int maxLines; final bool obscure; const Field(this.c,this.label,{super.key,this.keyboard,this.maxLines=1,this.obscure=false}); @override Widget build(BuildContext context)=>Padding(padding: const EdgeInsets.symmetric(vertical:6), child:TextField(controller:c, keyboardType:keyboard, maxLines:maxLines, obscureText:obscure, decoration:InputDecoration(labelText:label, border:OutlineInputBorder(borderRadius:BorderRadius.circular(14)), filled:true, fillColor:_bg))); }
class CardBox extends StatelessWidget{ final Widget child; final EdgeInsets? margin; const CardBox({super.key, required this.child, this.margin}); @override Widget build(BuildContext context)=>Container(margin:margin??const EdgeInsets.symmetric(vertical:6), padding: const EdgeInsets.all(12), decoration:BoxDecoration(color:_card, borderRadius:BorderRadius.circular(20), border:Border.all(color:Colors.white10)), child:child); }
class BigButton extends StatelessWidget{ final String text; final IconData icon; final VoidCallback? onTap; final bool danger; const BigButton(this.text,this.icon,this.onTap,{super.key,this.danger=false}); @override Widget build(BuildContext context)=>Padding(padding: const EdgeInsets.symmetric(vertical:4), child:FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:danger?_danger:_accent, foregroundColor:Colors.black, minimumSize: const Size.fromHeight(46)), onPressed:onTap, icon:Icon(icon), label:Text(text))); }
class StatCard extends StatelessWidget{ final String title,value; final IconData icon; final Color color; const StatCard(this.title,this.value,this.icon,this.color,{super.key}); @override Widget build(BuildContext context)=>SizedBox(width:170, child:CardBox(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[Icon(icon,color:color), const SizedBox(height:8), Text(title), Text(value, style: const TextStyle(fontSize:20,fontWeight:FontWeight.bold))]))); }
class Empty extends StatelessWidget{ final String msg; final VoidCallback action; const Empty({super.key, required this.msg, required this.action}); @override Widget build(BuildContext context)=>Center(child:CardBox(child:Column(mainAxisSize:MainAxisSize.min, children:[Text(msg), BigButton('إضافة الآن',Icons.add,action)]))); }
