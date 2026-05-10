import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const CodeCollectorApp());

class CodeCollectorApp extends StatelessWidget {
  const CodeCollectorApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'جامع الأكواد',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _sourcePath;
  String? _outputPath;
  bool _isZip = false;
  bool _loading = false;
  String _log = 'مرحباً بك في جامع الأكواد';

  Set<String> _selectedExtensions = {
    '.py', '.dart', '.js', '.html', '.css', '.md',
    '.java', '.ts', '.json', '.xml', '.yml', '.yaml'
  };
  final TextEditingController _customExtController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  void _requestPermissions() async {
    // فقط للتأكد من أن التطبيق يطلب الصلاحيات عند التشغيل
    if (Platform.isAndroid) {
      // في Android 13+ تختلف الصلاحيات، لكن file_picker سيتولى ذلك.
      _log = 'تم طلب الصلاحيات تلقائياً عند الحاجة';
    }
  }

  void _addCustomExtension() {
    String ext = _customExtController.text.trim();
    if (ext.isEmpty) return;
    if (!ext.startsWith('.')) ext = '.$ext';
    setState(() {
      _selectedExtensions.add(ext);
      _customExtController.clear();
      _log = '✓ تمت إضافة الامتداد $ext';
    });
  }

  void _toggleExtension(String ext) {
    setState(() {
      if (_selectedExtensions.contains(ext))
        _selectedExtensions.remove(ext);
      else
        _selectedExtensions.add(ext);
    });
  }

  Future<void> _pickSource() async {
    if (_isZip) {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (res != null) setState(() {
        _sourcePath = res.files.single.path;
        _log = '✅ المصدر: ملف ZIP';
      });
    } else {
      final String? dir = await FilePicker.platform.getDirectoryPath();
      if (dir != null) setState(() {
        _sourcePath = dir;
        _log = '✅ المصدر: مجلد';
      });
    }
  }

  Future<void> _pickOutput() async {
    try {
      // مسار افتراضي آمن
      Directory? downloadDir;
      if (Platform.isAndroid) {
        try {
          downloadDir = await getExternalStorageDirectory();
        } catch (e) {
          _log = '⚠️ فشل الحصول على مسار التخزين، سنستخدم مجلد المستندات';
        }
      }
      String initialPath = downloadDir?.path ?? '/storage/emulated/0/Download';
      
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'اختر مكان حفظ الملف النصي',
        fileName: 'collected_${DateTime.now().millisecondsSinceEpoch}.txt',
        initialDirectory: initialPath,
        allowedExtensions: ['txt'],
        type: FileType.custom,
      );
      if (result != null) {
        setState(() {
          _outputPath = result;
          _log = '💾 مسار الحفظ: $_outputPath';
        });
      } else {
        setState(() => _log = '⚠️ لم يتم اختيار مسار، استخدم المسار الافتراضي');
        // تعيين مسار افتراضي لتجنب الانهيار
        final fallback = '/storage/emulated/0/Download/collected_${DateTime.now().millisecondsSinceEpoch}.txt';
        setState(() {
          _outputPath = fallback;
          _log = '⚠️ تم استخدام المسار الافتراضي: $_outputPath';
        });
      }
    } catch (e) {
      setState(() {
        _log = '❌ خطأ في اختيار المسار: $e\nسيتم استخدام مسار افتراضي';
        _outputPath = '/storage/emulated/0/Download/collected_${DateTime.now().millisecondsSinceEpoch}.txt';
      });
    }
  }

  Future<void> _startCollecting() async {
    if (_sourcePath == null || _outputPath == null) {
      setState(() => _log = '⚠️ حدد المصدر ومسار الحفظ');
      return;
    }
    if (_selectedExtensions.isEmpty) {
      setState(() => _log = '⚠️ اختر امتداداً واحداً على الأقل');
      return;
    }
    setState(() { _loading = true; _log = '⏳ جاري جمع الملفات...'; });
    try {
      final files = <({String path, String content})>[];
      if (_isZip) {
        final bytes = await File(_sourcePath!).readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final f in archive.files) {
          if (!f.isFile) continue;
          final ext = _getExtension(f.name);
          if (_selectedExtensions.contains(ext)) {
            String content = String.fromCharCodes(f.content as List<int>);
            if (content.isEmpty) content = '[ملف فارغ]';
            files.add((path: f.name, content: content));
          }
        }
      } else {
        final dir = Directory(_sourcePath!);
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            final ext = _getExtension(entity.path);
            if (_selectedExtensions.contains(ext)) {
              String content = await entity.readAsString(encoding: utf8);
              if (content.isEmpty) content = '[ملف فارغ]';
              final rel = entity.path.substring(_sourcePath!.length + 1);
              files.add((path: rel, content: content));
            }
          }
        }
      }
      if (files.isEmpty) throw Exception('لا توجد ملفات بالامتدادات المحددة');
      final out = File(_outputPath!);
      final buffer = StringBuffer();
      buffer.writeln('📦 عدد الملفات: ${files.length}');
      buffer.writeln('=' * 60);
      for (final f in files) {
        buffer.writeln('\n📄 ${f.path}');
        buffer.writeln('-' * 50);
        buffer.write(f.content);
        buffer.writeln();
      }
      await out.writeAsString(buffer.toString());
      setState(() => _log = '✅ تم الحفظ (${files.length} ملف) في: $_outputPath');
      await Share.shareXFiles([XFile(_outputPath!)], text: 'تم تجميع الأكواد');
    } catch (e) {
      setState(() => _log = '❌ خطأ: $e');
    } finally { setState(() => _loading = false); }
  }

  String _getExtension(String path) {
    final i = path.lastIndexOf('.');
    return i == -1 ? '' : path.substring(i).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📦 جامع الأكواد'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('📂 مجلد')),
              ButtonSegment(value: true, label: Text('📦 ZIP')),
            ],
            selected: {_isZip},
            onSelectionChanged: (s) => setState(() { _isZip = s.first; _sourcePath = null; }),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 50, child: ListView(
            scrollDirection: Axis.horizontal,
            children: _selectedExtensions.map((e) => FilterChip(label: Text(e), selected: true, onSelected: (_) => _toggleExtension(e))).toList(),
          )),
          Row(children: [
            Expanded(child: TextField(controller: _customExtController, decoration: const InputDecoration(hintText: 'مثل .cpp'))),
            IconButton(icon: const Icon(Icons.add), onPressed: _addCustomExtension),
          ]),
          OutlinedButton(onPressed: _pickSource, child: Text(_sourcePath == null ? 'اختر المصدر' : '✓ تم')),
          OutlinedButton(onPressed: _pickOutput, child: Text(_outputPath == null ? 'اختر الحفظ' : '✓ تم')),
          ElevatedButton(onPressed: _loading ? null : _startCollecting, child: _loading ? const CircularProgressIndicator() : const Text('🚀 ابدأ')),
          Expanded(child: Container(padding: const EdgeInsets.all(10), color: Colors.grey[100], child: SelectableText(_log))),
        ]),
      ),
    );
  }
}
