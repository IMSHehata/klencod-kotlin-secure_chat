import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../models.dart';
import '../services/chat_service.dart';
import '../services/crypto_service.dart';
import '../services/temp_files.dart';
import 'widgets.dart';

const _maxBytes = 25 * 1024 * 1024;
const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.myUid,
    required this.partnerUid,
    required this.partnerName,
    required this.keyStatus,
  });

  final String myUid;
  final String partnerUid;
  final String partnerName;
  final KeyStatus keyStatus;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late final ChatService _svc;
  StreamSubscription? _msgSub;
  StreamSubscription? _chatSub;

  List<ChatMessage> _messages = const [];
  Map<String, dynamic> _chat = const {};
  String? _error;

  final _input = TextEditingController();
  final _focus = FocusNode();
  ChatMessage? _reply;
  ChatMessage? _editing;

  bool _uploading = false;
  bool _foreground = true;
  bool _keyBanner = false;
  DateTime? _lastRead;

  final _recorder = AudioRecorder();
  bool _recording = false;
  int _recSecs = 0;
  Timer? _recTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _svc = ChatService(myUid: widget.myUid, partnerUid: widget.partnerUid);
    _keyBanner = widget.keyStatus == KeyStatus.changed;
    _start();
  }

  Future<void> _start() async {
    try {
      await _svc.ensureChat();
      _chatSub = _svc.chatStream().listen((s) {
        if (mounted) setState(() => _chat = s.data() ?? {});
      }, onError: _onErr);
      _msgSub = _svc.messages().listen((list) {
        if (!mounted) return;
        setState(() {
          _messages = list;
          _error = null;
        });
        _maybeMarkRead();
      }, onError: _onErr);
    } catch (e) {
      _onErr(e);
    }
  }

  void _onErr(Object e) {
    if (mounted) setState(() => _error = '$e');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _lastRead = null;
      _maybeMarkRead();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _msgSub?.cancel();
    _chatSub?.cancel();
    _recTimer?.cancel();
    _recorder.dispose();
    _input.dispose();
    _focus.dispose();
    TempFiles.clear();
    super.dispose();
  }

  // ---------------- حالات مساعدة ----------------

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  void _guard(Future<void> f) {
    f.catchError((Object e) {
      _toast('تعذّر التنفيذ: $e');
    });
  }

  void _maybeMarkRead() {
    if (!_foreground) return;
    ChatMessage? newest;
    for (final m in _messages) {
      if (m.sender != widget.myUid && !m.pending) {
        newest = m;
        break;
      }
    }
    if (newest == null) return;
    if (_lastRead == null || newest.ts.isAfter(_lastRead!)) {
      _lastRead = newest.ts;
      _svc.markRead().catchError((Object _) {});
    }
  }

  DateTime? get _partnerReadAt {
    final read = _chat['read'];
    if (read is Map) {
      final t = read[widget.partnerUid];
      if (t is Timestamp) return t.toDate();
    }
    return null;
  }

  String? get _pinnedId => _chat['pinnedId'] as String?;

  ChatMessage? get _pinnedMessage {
    final id = _pinnedId;
    if (id == null) return null;
    for (final m in _messages) {
      if (m.id == id && !m.deleted) return m;
    }
    return null;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ---------------- إرسال ----------------

  void _startReply(ChatMessage m) {
    if (m.deleted || m.pending) return;
    setState(() {
      _reply = m;
      _editing = null;
    });
    _focus.requestFocus();
  }

  void _startEdit(ChatMessage m) {
    setState(() {
      _editing = m;
      _reply = null;
      _input.text = m.payload.text;
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    });
    _focus.requestFocus();
  }

  void _cancelCompose() {
    setState(() {
      _reply = null;
      _editing = null;
      _input.clear();
    });
  }

  void _sendText() {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    final editing = _editing;
    if (editing != null) {
      if (t != editing.payload.text) _guard(_svc.edit(editing, t));
    } else {
      final r = _reply;
      _guard(_svc.send(Payload(
        text: t,
        replyId: r?.id,
        replyPreview: r?.payload.preview,
      )));
    }
    setState(() {
      _reply = null;
      _editing = null;
      _input.clear();
    });
  }

  String _mimeFor(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'mp4':
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _pickAndSend() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final path = f.path;
    if (path == null) return;
    if (f.size > _maxBytes) {
      _toast('الملف أكبر من 25 ميجا');
      return;
    }
    final ext = (f.extension ?? '').toLowerCase();
    final isImage = const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'].contains(ext);
    final r = _reply;
    setState(() => _uploading = true);
    try {
      final bytes = await File(path).readAsBytes();
      final info = await _svc.upload(bytes: bytes, name: f.name, mime: _mimeFor(ext));
      await _svc.send(Payload(
        kind: isImage ? MsgKind.image : MsgKind.file,
        file: info,
        replyId: r?.id,
        replyPreview: r?.payload.preview,
      ));
      if (mounted) setState(() => _reply = null);
    } catch (e) {
      _toast('فشل الإرسال: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---------------- التسجيل الصوتي ----------------

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        _toast('محتاج صلاحية الميكروفون');
        return;
      }
      final path = await TempFiles.newPath('rec_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      _recSecs = 0;
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recSecs++);
      });
      setState(() => _recording = true);
    } catch (e) {
      _toast('تعذّر بدء التسجيل: $e');
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    _recTimer?.cancel();
    final secs = _recSecs;
    String? path;
    try {
      if (send) {
        path = await _recorder.stop();
      } else {
        await _recorder.cancel();
      }
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
    if (!send || path == null) return;
    if (secs < 1) {
      _toast('التسجيل قصير جداً');
      try {
        await File(path).delete();
      } catch (_) {}
      return;
    }
    final r = _reply;
    if (mounted) setState(() => _uploading = true);
    try {
      final bytes = await File(path).readAsBytes();
      final info = await _svc.upload(bytes: bytes, name: 'voice.m4a', mime: 'audio/mp4');
      await _svc.send(Payload(
        kind: MsgKind.voice,
        file: info,
        durationMs: secs * 1000,
        replyId: r?.id,
        replyPreview: r?.payload.preview,
      ));
      if (mounted) setState(() => _reply = null);
    } catch (e) {
      _toast('فشل إرسال الصوت: $e');
    } finally {
      try {
        await File(path).delete(); // مسح التسجيل غير المشفّر من الجهاز
      } catch (_) {}
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---------------- قائمة الرسالة ----------------

  void _showActions(ChatMessage m) {
    if (m.deleted) return;
    final mine = m.sender == widget.myUid;
    final pinned = _pinnedId == m.id;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        void run(VoidCallback fn) {
          Navigator.pop(ctx);
          fn();
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final e in _quickReactions)
                      InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => run(() => _guard(_svc.react(m, e))),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: m.reactions[widget.myUid] == e
                              ? BoxDecoration(
                                  color: Theme.of(ctx).colorScheme.primaryContainer,
                                  shape: BoxShape.circle,
                                )
                              : null,
                          child: Text(e, style: const TextStyle(fontSize: 26)),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('رد'),
                onTap: () => run(() => _startReply(m)),
              ),
              if (m.payload.kind == MsgKind.text)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('نسخ'),
                  onTap: () => run(() {
                    Clipboard.setData(ClipboardData(text: m.payload.text));
                    _toast('اتنسخت');
                  }),
                ),
              ListTile(
                leading: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin),
                title: Text(pinned ? 'إلغاء التثبيت' : 'تثبيت'),
                onTap: () => run(() => _guard(_svc.pin(pinned ? null : m.id))),
              ),
              if (mine && m.payload.kind == MsgKind.text)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('تعديل'),
                  onTap: () => run(() => _startEdit(m)),
                ),
              if (mine)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('حذف للطرفين', style: TextStyle(color: Colors.red)),
                  onTap: () => run(() => _confirmDelete(m)),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الرسالة؟'),
        content: const Text('هتتمسح عندك وعند الطرف التاني.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) _guard(_svc.deleteForEveryone(m, pinnedId: _pinnedId));
  }

  void _showSafetyNumber() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('كود الأمان'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'قارن الكود ده مع الكود اللي عند الطرف التاني (بالتليفون أو وش لوش). '
              'لو متطابقين يبقى الشات مفيش حد في النص.',
            ),
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                CryptoService.instance.safetyNumber,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 20,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام'))],
      ),
    );
  }

  // ---------------- الواجهة ----------------

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final partnerRead = _partnerReadAt;
    final pinned = _pinnedMessage;
    final initial = widget.partnerName.isEmpty ? '?' : String.fromCharCode(widget.partnerName.runes.first).toUpperCase();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white24,
              child: Text(initial, style: const TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.partnerName, style: const TextStyle(fontSize: 17), overflow: TextOverflow.ellipsis),
                  const Text('🔒 مشفّرة من طرف لطرف', style: TextStyle(fontSize: 11, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'كود الأمان',
            icon: const Icon(Icons.verified_user_outlined),
            onPressed: _showSafetyNumber,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') FirebaseAuth.instance.signOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('تسجيل خروج')),
            ],
          ),
        ],
      ),
      body: Container(
        color: dark ? const Color(0xFF0B141A) : const Color(0xFFECE5DD),
        child: Column(
          children: [
            if (_keyBanner)
              MaterialBanner(
                backgroundColor: Colors.amber.shade100,
                content: const Text(
                  'مفتاح التشفير بتاع الطرف التاني اتغيّر (ممكن يكون مسح التطبيق وسطّبه تاني). '
                  'قارن كود الأمان معاه قبل ما تبعت حاجة حساسة.',
                  style: TextStyle(color: Colors.black87),
                ),
                actions: [
                  TextButton(onPressed: _showSafetyNumber, child: const Text('عرض الكود')),
                  TextButton(
                    onPressed: () async {
                      await CryptoService.instance.acceptPartnerKey(widget.myUid);
                      if (mounted) setState(() => _keyBanner = false);
                    },
                    child: const Text('تم التأكد'),
                  ),
                ],
              ),
            if (pinned != null) _pinnedBar(pinned, dark),
            Expanded(child: _messageList(partnerRead)),
            if (_uploading) const LinearProgressIndicator(minHeight: 2),
            _composer(dark),
          ],
        ),
      ),
    );
  }

  Widget _pinnedBar(ChatMessage m, bool dark) {
    return Material(
      color: dark ? const Color(0xFF1F2C34) : Colors.white,
      child: InkWell(
        onLongPress: () => _guard(_svc.pin(null)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.push_pin, size: 18, color: Color(0xFF008069)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m.payload.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'إلغاء التثبيت',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _guard(_svc.pin(null)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageList(DateTime? partnerRead) {
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('مشكلة في الاتصال أو الصلاحيات:\n$_error', textAlign: TextAlign.center),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '🔒 الرسايل هنا مشفّرة من طرف لطرف.\nابدأ المحادثة!',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        final older = i + 1 < _messages.length ? _messages[i + 1] : null;
        final showDate = older == null || !_sameDay(m.ts, older.ts);
        final mine = m.sender == widget.myUid;
        final read = partnerRead != null && !partnerRead.isBefore(m.ts);

        Widget bubble = MessageBubble(
          message: m,
          mine: mine,
          partnerRead: read,
          pinned: _pinnedId == m.id,
          svc: _svc,
          onLongPress: () => _showActions(m),
        );

        if (!m.deleted && !m.pending) {
          bubble = Dismissible(
            key: ValueKey('d_${m.id}'),
            direction: DismissDirection.horizontal,
            confirmDismiss: (_) async {
              _startReply(m);
              return false;
            },
            background: const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Icon(Icons.reply)),
            ),
            secondaryBackground: const Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Icon(Icons.reply)),
            ),
            child: bubble,
          );
        }

        return Column(
          children: [
            if (showDate) DateChip(date: m.ts),
            bubble,
          ],
        );
      },
    );
  }

  Widget _composer(bool dark) {
    final cs = Theme.of(context).colorScheme;
    final hasText = _input.text.trim().isNotEmpty;
    final barColor = dark ? const Color(0xFF1F2C34) : Colors.white;

    if (_recording) {
      final mm = (_recSecs ~/ 60).toString();
      final ss = (_recSecs % 60).toString().padLeft(2, '0');
      return SafeArea(
        top: false,
        child: Container(
          color: barColor,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _stopRecording(send: false),
              ),
              const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
              const SizedBox(width: 6),
              Text('$mm:$ss', style: const TextStyle(fontSize: 16)),
              const Expanded(child: Text('  بيتسجّل…', style: TextStyle(color: Colors.grey))),
              CircleAvatar(
                backgroundColor: const Color(0xFF008069),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: () => _stopRecording(send: true),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final banner = _editing != null || _reply != null;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (banner)
            Container(
              color: barColor,
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  Icon(_editing != null ? Icons.edit : Icons.reply, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _editing != null ? 'تعديل الرسالة' : _reply!.payload.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _cancelCompose,
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            focusNode: _focus,
                            minLines: 1,
                            maxLines: 5,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              hintText: 'اكتب رسالة',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                        ),
                        if (_editing == null)
                          IconButton(
                            tooltip: 'إرفاق',
                            icon: const Icon(Icons.attach_file),
                            onPressed: _uploading ? null : _pickAndSend,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF008069),
                  child: IconButton(
                    icon: Icon(
                      hasText ? Icons.send : Icons.mic,
                      color: Colors.white,
                    ),
                    onPressed: hasText
                        ? _sendText
                        : (_editing != null || _uploading ? null : _startRecording),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
