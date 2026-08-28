import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const SalaryApp());
}

enum AppThemeColor {
  gold('ゴールド', Color(0xFFC5A059)),
  navy('ネイビー', Color(0xFF1B365D)),
  emerald('エメラルド', Color(0xFF0F5257)),
  wine('ワインレッド', Color(0xFF722F37)),
  slate('スレート', Color(0xFF4A5568));

  final String label;
  final Color color;
  const AppThemeColor(this.label, this.color);
}

// 金額フォーマットユーティリティ
String formatCurrency(int amount) {
  return amount.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
}

// 3桁カンマ入力用フォーマッター
class ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final cleanText = newValue.text.replaceAll(',', '');
    final number = int.tryParse(cleanText);
    if (number == null) return oldValue;

    final formatted = formatCurrency(number);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// データモデル
class SalaryRecord {
  String id;
  int year;
  int month;
  String payGradeRaw;
  bool isBonus;
  int grossPay;
  int deduction;
  int? personalAccount;
  int? livingAccount;
  int? welfareDeduction;

  SalaryRecord({
    required this.id,
    required this.year,
    required this.month,
    required this.payGradeRaw,
    required this.isBonus,
    required this.grossPay,
    required this.deduction,
    this.personalAccount,
    this.livingAccount,
    this.welfareDeduction,
  });

  String get monthText => '$year-$month';
  int get yearMonthValue => year * 100 + month;
  int get takeHomePay => grossPay - deduction;

  String get formattedPayGrade {
    final parts = payGradeRaw.split(',').map((e) => e.trim()).toList();
    if (parts.length == 3 && parts.every((e) => e.isNotEmpty)) {
      return '${parts[0]}表 ${parts[1]}級 ${parts[2]}号給';
    }
    return payGradeRaw;
  }

  // Web保存用の相互変換メソッド
  factory SalaryRecord.fromMap(Map<String, dynamic> map) {
    return SalaryRecord(
      id: map['id'],
      year: map['year'],
      month: map['month'],
      payGradeRaw: map['payGradeRaw'] ?? '',
      isBonus: map['isBonus'] == 1 || map['isBonus'] == true,
      grossPay: map['grossPay'],
      deduction: map['deduction'],
      personalAccount: map['personalAccount'],
      livingAccount: map['livingAccount'],
      welfareDeduction: map['welfareDeduction'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'year': year,
      'month': month,
      'payGradeRaw': payGradeRaw,
      'isBonus': isBonus,
      'grossPay': grossPay,
      'deduction': deduction,
      'personalAccount': personalAccount,
      'livingAccount': livingAccount,
      'welfareDeduction': welfareDeduction,
    };
  }
}

// ブラウザ/Web用ストレージ管理クラス
class StorageHelper {
  static const String _key = 'salary_records_data';

  // 全件読み込み
  static Future<List<SalaryRecord>> getAllRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_key);
    if (jsonString == null) return [];

    final List<dynamic> jsonList = jsonDecode(jsonString);
    final records = jsonList.map((json) => SalaryRecord.fromMap(json)).toList();
    records.sort((a, b) => a.yearMonthValue.compareTo(b.yearMonthValue));
    return records;
  }

  // 保存・更新
  static Future<void> saveRecord(SalaryRecord record) async {
    final records = await getAllRecords();
    final index = records.indexWhere((r) => r.id == record.id);
    if (index >= 0) {
      records[index] = record;
    } else {
      records.add(record);
    }
    await _saveAll(records);
  }

  // 削除
  static Future<void> deleteRecord(String id) async {
    final records = await getAllRecords();
    records.removeWhere((r) => r.id == id);
    await _saveAll(records);
  }

  static Future<void> _saveAll(List<SalaryRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = records.map((r) => r.toMap()).toList();
    await prefs.setString(_key, jsonEncode(jsonList));
  }
}

class SalaryApp extends StatefulWidget {
  const SalaryApp({super.key});

  @override
  State<SalaryApp> createState() => _SalaryAppState();
}

class _SalaryAppState extends State<SalaryApp> {
  AppThemeColor _currentTheme = AppThemeColor.gold;

  void _changeTheme(AppThemeColor theme) {
    setState(() {
      _currentTheme = theme;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '給与明細管理',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _currentTheme.color,
          primary: _currentTheme.color,
        ),
        useMaterial3: true,
      ),
      home: MainTabScreen(
        currentTheme: _currentTheme,
        onThemeChanged: _changeTheme,
      ),
    );
  }
}

class MainTabScreen extends StatefulWidget {
  final AppThemeColor currentTheme;
  final ValueChanged<AppThemeColor> onThemeChanged;

  const MainTabScreen({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
  });

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _currentIndex = 0;
  List<SalaryRecord> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await StorageHelper.getAllRecords();
    setState(() {
      _records = records;
      _isLoading = false;
    });
  }

  Future<void> _addOrUpdateRecord(SalaryRecord record) async {
    await StorageHelper.saveRecord(record);
    await _loadRecords();
  }

  Future<void> _deleteRecord(String id) async {
    await StorageHelper.deleteRecord(id);
    await _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final pages = [
      ListScreen(
        records: _records,
        onSave: _addOrUpdateRecord,
        onDelete: _deleteRecord,
      ),
      SummaryScreen(records: _records),
      GraphScreen(records: _records),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('給与明細管理'),
        actions: [
          PopupMenuButton<AppThemeColor>(
            icon: const Icon(Icons.palette),
            tooltip: 'テーマカラー変更',
            onSelected: widget.onThemeChanged,
            itemBuilder: (context) => AppThemeColor.values.map((theme) {
              return PopupMenuItem<AppThemeColor>(
                value: theme,
                child: Row(
                  children: [
                    Icon(Icons.circle, color: theme.color, size: 20),
                    const SizedBox(width: 8),
                    Text(theme.label),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list_alt), label: '明細一覧'),
          NavigationDestination(icon: Icon(Icons.calculate), label: '期間集計(年収)'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: '推移グラフ'),
        ],
      ),
    );
  }
}

// 1. 明細一覧画面（年別アコーディオン対応）
class ListScreen extends StatelessWidget {
  final List<SalaryRecord> records;
  final Function(SalaryRecord) onSave;
  final Function(String) onDelete;

  const ListScreen({
    super.key,
    required this.records,
    required this.onSave,
    required this.onDelete,
  });

  void _showForm(BuildContext context, [SalaryRecord? existingRecord]) {
    final isEdit = existingRecord != null;
    final lastRecord = records.isNotEmpty ? records.last : null;

    DateTime selectedDate = isEdit
        ? DateTime(existingRecord.year, existingRecord.month)
        : (lastRecord != null
            ? DateTime(lastRecord.year, lastRecord.month)
            : DateTime.now());

    final defaultGrade = isEdit
        ? existingRecord.payGradeRaw
        : (lastRecord != null ? lastRecord.payGradeRaw : '');

    final gradeController = TextEditingController(text: defaultGrade);
    final grossController = TextEditingController(
        text: isEdit ? formatCurrency(existingRecord.grossPay) : '');
    final deductionController = TextEditingController(
        text: isEdit ? formatCurrency(existingRecord.deduction) : '');
    final personalController = TextEditingController(
        text: isEdit && existingRecord.personalAccount != null
            ? formatCurrency(existingRecord.personalAccount!)
            : '');
    final livingController = TextEditingController(
        text: isEdit && existingRecord.livingAccount != null
            ? formatCurrency(existingRecord.livingAccount!)
            : '');
    final welfareController = TextEditingController(
        text: isEdit && existingRecord.welfareDeduction != null
            ? formatCurrency(existingRecord.welfareDeduction!)
            : '');
    bool isBonus = isEdit ? existingRecord.isBonus : false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? '明細の編集' : '給与・ボーナス明細の追加',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                // ① 支給年月の選択ボタン（ピッカー対応）
                InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => MonthYearPicker(
                        initialDate: selectedDate,
                        onSelected: (int year, int month) {
                          setModalState(() {
                            selectedDate = DateTime(year, month);
                          });
                        },
                      ),
                    );
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '① 支給年月',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_month),
                    ),
                    child: Text(
                      '${selectedDate.year}年 ${selectedDate.month}月',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: gradeController,
                  decoration: const InputDecoration(
                    labelText: '② 表・級・号給',
                    hintText: '例: 8,2,24 （カンマ区切り）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  title: const Text('③ ボーナスとして登録する'),
                  value: isBonus,
                  activeColor: Colors.deepOrange,
                  onChanged: (val) =>
                      setModalState(() => isBonus = val ?? false),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: grossController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsFormatter()],
                  decoration: const InputDecoration(
                    labelText: '④ 総支給額 (円)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: deductionController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsFormatter()],
                  decoration: const InputDecoration(
                    labelText: '⑤ 控除額 (円)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),
                const Text('※以下は任意項目（省略可能）',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 5),
                TextField(
                  controller: personalController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsFormatter()],
                  decoration: const InputDecoration(
                    labelText: '⑥ 個人口座額 (円) [任意]',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: livingController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsFormatter()],
                  decoration: const InputDecoration(
                    labelText: '⑦ 生活口座振込額 (円) [任意]',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: welfareController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsFormatter()],
                  decoration: const InputDecoration(
                    labelText: '⑧ 厚生会引き落とし額 (円) [任意]',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      int parseCurrency(String text) {
                        return int.tryParse(text.replaceAll(',', '')) ?? 0;
                      }

                      final gross = parseCurrency(grossController.text);
                      final deduction = parseCurrency(deductionController.text);

                      if (gross < 0 || deduction < 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('総支給額・控除額を正しく入力してください')),
                        );
                        return;
                      }

                      final record = SalaryRecord(
                        id: isEdit
                            ? existingRecord.id
                            : DateTime.now().millisecondsSinceEpoch.toString(),
                        year: selectedDate.year,
                        month: selectedDate.month,
                        payGradeRaw: gradeController.text.trim(),
                        isBonus: isBonus,
                        grossPay: gross,
                        deduction: deduction,
                        personalAccount: personalController.text.isNotEmpty
                            ? parseCurrency(personalController.text)
                            : null,
                        livingAccount: livingController.text.isNotEmpty
                            ? parseCurrency(livingController.text)
                            : null,
                        welfareDeduction: welfareController.text.isNotEmpty
                            ? parseCurrency(welfareController.text)
                            : null,
                      );

                      onSave(record);
                      Navigator.pop(context);
                    },
                    child: Text(isEdit ? '更新する' : '保存する',
                        style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Scaffold(
        body: const Center(child: Text('データがありません。「＋」から追加してください。')),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showForm(context),
          child: const Icon(Icons.add),
        ),
      );
    }

    final Map<int, List<SalaryRecord>> groupedRecords = {};
    for (var r in records) {
      groupedRecords.putIfAbsent(r.year, () => []).add(r);
    }
    final sortedYears = groupedRecords.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      body: ListView.builder(
        itemCount: sortedYears.length,
        itemBuilder: (ctx, yearIndex) {
          final year = sortedYears[yearIndex];
          final yearRecords = groupedRecords[year]!;

          final yearTotalTakeHome =
              yearRecords.fold(0, (sum, r) => sum + r.takeHomePay);

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ExpansionTile(
              initiallyExpanded: yearIndex == 0,
              title: Text(
                '$year年',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '該当件数: ${yearRecords.length}件 / 手取り計: ¥${formatCurrency(yearTotalTakeHome)}',
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
              children: yearRecords.map((item) {
                return Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${item.month}月',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                                if (item.isBonus) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.deepOrange,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('ボーナス',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ]
                              ],
                            ),
                            Row(
                              children: [
                                Text(
                                  '手取り: ¥${formatCurrency(item.takeHomePay)}',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      size: 20, color: Colors.grey),
                                  tooltip: '編集',
                                  onPressed: () => _showForm(context, item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20, color: Colors.redAccent),
                                  tooltip: '削除',
                                  onPressed: () => onDelete(item.id),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (item.payGradeRaw.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(item.formattedPayGrade,
                              style: TextStyle(color: Colors.grey[700])),
                        ],
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('総支給額: ¥${formatCurrency(item.grossPay)}'),
                            Text('控除額: ¥${formatCurrency(item.deduction)}'),
                          ],
                        ),
                        if (item.personalAccount != null ||
                            item.livingAccount != null ||
                            item.welfareDeduction != null) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 12,
                            children: [
                              if (item.personalAccount != null)
                                Text('個人: ¥${formatCurrency(item.personalAccount!)}',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                              if (item.livingAccount != null)
                                Text('生活: ¥${formatCurrency(item.livingAccount!)}',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                              if (item.welfareDeduction != null)
                                Text('厚生会: ¥${formatCurrency(item.welfareDeduction!)}',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                            ],
                          )
                        ]
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// 2. 期間集計画面
class SummaryScreen extends StatefulWidget {
  final List<SalaryRecord> records;

  const SummaryScreen({super.key, required this.records});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  DateTime _startDate = DateTime(2026, 1);
  DateTime _endDate = DateTime(2026, 12);

  void _showMonthYearPicker(BuildContext context, bool isStart) {
    showDialog(
      context: context,
      builder: (BuildContext builder) {
        return MonthYearPicker(
          initialDate: isStart ? _startDate : _endDate,
          onSelected: (int year, int month) {
            setState(() {
              if (isStart) {
                _startDate = DateTime(year, month);
              } else {
                _endDate = DateTime(year, month);
              }
            });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final startVal = _startDate.year * 100 + _startDate.month;
    final endVal = _endDate.year * 100 + _endDate.month;

    final filtered = widget.records.where((r) {
      return r.yearMonthValue >= startVal && r.yearMonthValue <= endVal;
    }).toList();

    final totalGross = filtered.fold(0, (sum, r) => sum + r.grossPay);
    final totalTakeHome = filtered.fold(0, (sum, r) => sum + r.takeHomePay);
    final totalDeduction = filtered.fold(0, (sum, r) => sum + r.deduction);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => _showMonthYearPicker(context, true),
                      child: Text(
                        '開始: ${_startDate.year}年${_startDate.month}月',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text('〜', style: TextStyle(fontSize: 16)),
                  ),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => _showMonthYearPicker(context, false),
                      child: Text(
                        '終了: ${_endDate.year}年${_endDate.month}月',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        '期間集計結果',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text('対象件数: ${filtered.length} 件'),
                      const Divider(height: 20),
                      _buildSummaryRow('総支給額（年収換算）', totalGross, Colors.black, true),
                      const SizedBox(height: 8),
                      _buildSummaryRow(
                        '手取り合計',
                        totalTakeHome,
                        Theme.of(context).colorScheme.primary,
                        true,
                      ),
                      const SizedBox(height: 8),
                      _buildSummaryRow('控除合計', totalDeduction, Colors.red.shade700, false),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, int value, Color color, bool isBold) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(
          '¥${formatCurrency(value)}',
          style: TextStyle(
            fontSize: isBold ? 18 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }
}

// 3. 推移グラフ画面
class GraphScreen extends StatefulWidget {
  final List<SalaryRecord> records;

  const GraphScreen({super.key, required this.records});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  SalaryRecord? _selectedRecord;

  @override
  Widget build(BuildContext context) {
    final regularRecords = widget.records.where((r) => !r.isBonus).toList();
    final bonusRecords = widget.records.where((r) => r.isBonus).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              onTap: (_) => setState(() => _selectedRecord = null),
              tabs: const [
                Tab(text: '通常給与推移'),
                Tab(text: 'ボーナス推移'),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildChartArea(context, regularRecords, '通常給与'),
            _buildChartArea(context, bonusRecords, 'ボーナス'),
          ],
        ),
      ),
    );
  }

  Widget _buildChartArea(
      BuildContext context, List<SalaryRecord> targetRecords, String title) {
    if (targetRecords.isEmpty) {
      return Center(child: Text('$titleのデータがありません。'));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegend(Colors.blue.shade600, '総支給'),
              const SizedBox(width: 20),
              _buildLegend(Colors.teal, '手取り'),
            ],
          ),
          const SizedBox(height: 6),
          const Text('点をタップすると詳細を表示します',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final currentSize =
                    Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  onTapUp: (details) {
                    _handleTap(details.localPosition, currentSize, targetRecords);
                  },
                  child: CustomPaint(
                    size: currentSize,
                    painter: MultiLineChartPainter(
                      records: targetRecords,
                      selectedRecord: _selectedRecord,
                    ),
                  ),
                );
              },
            ),
          ),
          if (_selectedRecord != null &&
              targetRecords.any((r) => r.id == _selectedRecord!.id)) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 4,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_selectedRecord!.monthText} ${_selectedRecord!.isBonus ? "(ボーナス)" : ""}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        if (_selectedRecord!.payGradeRaw.isNotEmpty)
                          Text(_selectedRecord!.formattedPayGrade,
                              style: TextStyle(
                                  color: Colors.grey[700], fontSize: 12)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '総支給: ¥${formatCurrency(_selectedRecord!.grossPay)}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.blue.shade700),
                        ),
                        Text(
                          '手取り: ¥${formatCurrency(_selectedRecord!.takeHomePay)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.teal),
                        ),
                        Text('控除: ¥${formatCurrency(_selectedRecord!.deduction)}',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  void _handleTap(
      Offset tapPos, Size size, List<SalaryRecord> targetRecords) {
    if (targetRecords.isEmpty) return;

    final maxVal = targetRecords.fold(
        1, (max, r) => r.grossPay > max ? r.grossPay : max);

    const double paddingLeft = 45;
    const double paddingBottom = 30;
    const double paddingTop = 20;
    const double paddingRight = 20;

    final chartWidth = size.width - paddingLeft - paddingRight;
    final chartHeight = size.height - paddingTop - paddingBottom;

    final stepX = targetRecords.length == 1
        ? chartWidth / 2
        : chartWidth / (targetRecords.length - 1);

    SalaryRecord? closest;
    double minDistance = double.infinity;

    for (int i = 0; i < targetRecords.length; i++) {
      final item = targetRecords[i];
      final x = targetRecords.length == 1
          ? paddingLeft + chartWidth / 2
          : paddingLeft + (i * stepX);
      final yGross =
          paddingTop + chartHeight - ((item.grossPay / maxVal) * chartHeight);

      final distance = (Offset(x, yGross) - tapPos).distance;
      if (distance < 40 && distance < minDistance) {
        minDistance = distance;
        closest = item;
      }
    }

    setState(() {
      _selectedRecord = closest;
    });
  }
}

// カスタムペインター
class MultiLineChartPainter extends CustomPainter {
  final List<SalaryRecord> records;
  final SalaryRecord? selectedRecord;

  MultiLineChartPainter({
    required this.records,
    this.selectedRecord,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (records.isEmpty) return;

    const double paddingLeft = 45;
    const double paddingBottom = 30;
    const double paddingTop = 20;
    const double paddingRight = 20;

    final chartWidth = size.width - paddingLeft - paddingRight;
    final chartHeight = size.height - paddingTop - paddingBottom;

    final maxVal = records.fold(
        1, (max, r) => r.grossPay > max ? r.grossPay : max);

    final gridPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    for (int i = 0; i <= 3; i++) {
      final y = paddingTop + (chartHeight / 3) * i;
      canvas.drawLine(
          Offset(paddingLeft, y), Offset(size.width - paddingRight, y), gridPaint);
    }

    final grossPaint = Paint()
      ..color = Colors.blue.shade600
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final takeHomePaint = Paint()
      ..color = Colors.teal
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final stepX = records.length == 1
        ? chartWidth / 2
        : chartWidth / (records.length - 1);

    final List<Offset> grossPoints = [];
    final List<Offset> takeHomePoints = [];

    for (int i = 0; i < records.length; i++) {
      final item = records[i];

      final x = records.length == 1
          ? paddingLeft + chartWidth / 2
          : paddingLeft + (i * stepX);
      final yGross =
          paddingTop + chartHeight - ((item.grossPay / maxVal) * chartHeight);
      final yTakeHome = paddingTop +
          chartHeight -
          ((item.takeHomePay / maxVal) * chartHeight);

      grossPoints.add(Offset(x, yGross));
      takeHomePoints.add(Offset(x, yTakeHome));

      textPainter.text = TextSpan(
        text: item.monthText,
        style: const TextStyle(color: Colors.grey, fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(
          canvas, Offset(x - (textPainter.width / 2), size.height - 20));
    }

    if (grossPoints.length > 1) {
      final pathGross = Path()..moveTo(grossPoints[0].dx, grossPoints[0].dy);
      final pathTakeHome = Path()
        ..moveTo(takeHomePoints[0].dx, takeHomePoints[0].dy);

      for (int i = 1; i < grossPoints.length; i++) {
        pathGross.lineTo(grossPoints[i].dx, grossPoints[i].dy);
        pathTakeHome.lineTo(takeHomePoints[i].dx, takeHomePoints[i].dy);
      }

      canvas.drawPath(pathGross, grossPaint);
      canvas.drawPath(pathTakeHome, takeHomePaint);
    }

    for (int i = 0; i < records.length; i++) {
      final isSelected = selectedRecord?.id == records[i].id;

      if (isSelected) {
        canvas.drawCircle(grossPoints[i], 7, Paint()..color = Colors.blue.shade800);
        canvas.drawCircle(takeHomePoints[i], 7, Paint()..color = Colors.teal.shade800);

        final tooltipText =
            '総支給: ¥${formatCurrency(records[i].grossPay)}\n手取り: ¥${formatCurrency(records[i].takeHomePay)}';
        textPainter.text = TextSpan(
          text: tooltipText,
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        );
        textPainter.layout();

        final bgRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(grossPoints[i].dx, grossPoints[i].dy - 28),
            width: textPainter.width + 12,
            height: textPainter.height + 8,
          ),
          const Radius.circular(4),
        );

        canvas.drawRRect(bgRect, Paint()..color = Colors.black87);
        textPainter.paint(
            canvas,
            Offset(grossPoints[i].dx - (textPainter.width / 2),
                grossPoints[i].dy - 28 - (textPainter.height / 2)));
      } else {
        canvas.drawCircle(
            grossPoints[i], 4, Paint()..color = Colors.blue.shade600);
        canvas.drawCircle(
            takeHomePoints[i], 4, Paint()..color = Colors.teal);
      }
    }
  }

  @override
  bool shouldRepaint(covariant MultiLineChartPainter oldDelegate) => true;
}

class MonthYearPicker extends StatefulWidget {
  final DateTime initialDate;
  final Function(int year, int month) onSelected;

  const MonthYearPicker({
    super.key,
    required this.initialDate,
    required this.onSelected,
  });

  @override
  State<MonthYearPicker> createState() => _MonthYearPickerState();
}

class _MonthYearPickerState extends State<MonthYearPicker> {
  late int _selectedYear;
  late int _selectedMonth;

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialDate.year;
    _selectedMonth = widget.initialDate.month;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('年月を選択'),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DropdownButton<int>(
            value: _selectedYear,
            items: List.generate(10, (index) => DateTime.now().year - 5 + index)
                .map((y) => DropdownMenuItem(value: y, child: Text('$y年')))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedYear = val);
            },
          ),
          const SizedBox(width: 16),
          DropdownButton<int>(
            value: _selectedMonth,
            items: List.generate(12, (index) => index + 1)
                .map((m) => DropdownMenuItem(value: m, child: Text('$m月')))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedMonth = val);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSelected(_selectedYear, _selectedMonth);
            Navigator.pop(context);
          },
          child: const Text('決定'),
        ),
      ],
    );
  }
}