import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../models.dart';
import '../services/chat_service.dart';
import '../services/temp_files.dart';

final _timeFmt = DateFormat('h:mm a', 'ar');

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.partnerRead,
    required this.pinned,
    required this.svc,
    required this.onLongPress,
  });

  final ChatMessage message;
  final bool mine;
  final bool partnerRead;
  final bool pinned;
  final ChatService svc;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = mine
        ? (dark ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3))
        : (dark ? const Color(0xFF202C33) : Colors.white);
    final fg = dark ? const Color(0xFFE9EDEF) : const Color(0xFF111B21);
    final sub = dark ? const Color(0xFF8696A0) : const Color(0xFF667781);
    final m = message;
    final p = m.payload;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: Radius.circular(mine ? 12 : 2),
      bottomRight: Radius.circular(mine ? 2 : 12),
    );

    Widget body;
    if (m.deleted) {
      body = Text('🚫 تم حذف هذه الرسالة',
          style: TextStyle(color: sub, fontStyle: FontStyle.italic));
    } else if (m.decryptFailed) {
      body = Text('⚠️ تعذّر فك تشفير الرسالة (مفتاح مختلف)',
          style: TextStyle(color: sub, fontStyle: FontStyle.italic));
    } else {
      switch (p.kind) {
        case MsgKind.text:
          body = Text(p.text, style: TextStyle(color: fg, fontSize: 16));
          break;
        case MsgKind.image:
          body = _ImageView(svc: svc, file: p.file!);
          break;
        case MsgKind.file:
          body = _FileTile(svc: svc, file: p.file!, fg: fg, sub: sub);
          break;
        case MsgKind.voice:
          body = VoiceBubble(svc: svc, file: p.file!, durationMs: p.durationMs, fg: fg);
          break;
      }
    }

    Widget? tick;
    if (mine && !m.deleted) {
      tick = m.pending
          ? Icon(Icons.access_time, size: 14, color: sub)
          : Icon(Icons.done_all,
              size: 16, color: partnerRead ? const Color(0xFF53BDEB) : sub);
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: m.pending ? null : onLongPress,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
            decoration: BoxDecoration(color: bg, borderRadius: radius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!m.deleted && p.replyId != null) _ReplyQuote(text: p.replyPreview ?? '', mine: mine, fg: fg, sub: sub),
                body,
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (pinned) Padding(
                      padding: const EdgeInsetsDirectional.only(end: 4),
                      child: Icon(Icons.push_pin, size: 12, color: sub),
                    ),
                    if (m.edited && !m.deleted)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 4),
                        child: Text('معدّلة', style: TextStyle(fontSize: 11, color: sub)),
                      ),
                    Text(_timeFmt.format(m.ts), style: TextStyle(fontSize: 11, color: sub)),
                    if (tick != null) ...[const SizedBox(width: 3), tick],
                  ],
                ),
                if (m.reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 4,
                      children: [
                        for (final e in _groupReactions(m.reactions).entries)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: dark ? const Color(0xFF2A3942) : const Color(0xFFF0F2F5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(e.value > 1 ? '${e.key} ${e.value}' : e.key,
                                style: const TextStyle(fontSize: 13)),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Map<String, int> _groupReactions(Map<String, String> r) {
    final out = <String, int>{};
    for (final e in r.values) {
      out[e] = (out[e] ?? 0) + 1;
    }
    return out;
  }
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({required this.text, required this.mine, required this.fg, required this.sub});
  final String text;
  final bool mine;
  final Color fg;
  final Color sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: const Color(0x14000000),
        borderRadius: BorderRadius.circular(6),
        border: const Border(right: BorderSide(color: Color(0xFF06CF9C), width: 3)),
      ),
      child: Text(text.isEmpty ? '…' : text,
          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: sub, fontSize: 13)),
    );
  }
}

class _ImageView extends StatelessWidget {
  const _ImageView({required this.svc, required this.file});
  final ChatService svc;
  final FileInfo file;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: svc.media(file.path),
      builder: (context, snap) {
        if (snap.hasError) {
          return const SizedBox(
            width: 200,
            height: 120,
            child: Center(child: Icon(Icons.broken_image_outlined, size: 40)),
          );
        }
        if (!snap.hasData) {
          return const SizedBox(
            width: 200,
            height: 200,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final bytes = snap.data!;
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(backgroundColor: Colors.black),
              body: Center(child: InteractiveViewer(child: Image.memory(bytes))),
            ),
          )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, fit: BoxFit.cover, width: 240, gaplessPlayback: true),
          ),
        );
      },
    );
  }
}

class _FileTile extends StatefulWidget {
  const _FileTile({required this.svc, required this.file, required this.fg, required this.sub});
  final ChatService svc;
  final FileInfo file;
  final Color fg;
  final Color sub;

  @override
  State<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<_FileTile> {
  bool _busy = false;

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      final bytes = await widget.svc.media(widget.file.path);
      final f = await TempFiles.write(widget.file.name, bytes);
      await OpenFilex.open(f.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذّر فتح الملف: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    return InkWell(
      onTap: _busy ? null : _open,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _busy
              ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.insert_drive_file_rounded, size: 34, color: widget.sub),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.fg)),
                Text(fmtSize(f.size), style: TextStyle(color: widget.sub, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VoiceBubble extends StatefulWidget {
  const VoiceBubble({
    super.key,
    required this.svc,
    required this.file,
    required this.durationMs,
    required this.fg,
  });
  final ChatService svc;
  final FileInfo file;
  final int durationMs;
  final Color fg;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription>[];
  bool _loading = false;
  bool _playing = false;
  bool _started = false;
  Duration _pos = Duration.zero;
  late Duration _dur = Duration(milliseconds: widget.durationMs);
  String? _path;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPositionChanged.listen((d) {
      if (mounted) setState(() => _pos = d);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted && d > Duration.zero) setState(() => _dur = d);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _started = false;
          _pos = Duration.zero;
        });
      }
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    try {
      if (_path == null) {
        setState(() => _loading = true);
        final bytes = await widget.svc.media(widget.file.path);
        final f = await TempFiles.write('v_${widget.file.path.hashCode}.m4a', bytes);
        _path = f.path;
      }
      if (_started) {
        await _player.resume();
      } else {
        await _player.play(DeviceFileSource(_path!));
        _started = true;
      }
      if (mounted) setState(() => _playing = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذّر تشغيل الصوت: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _dur.inMilliseconds > 0
        ? (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return SizedBox(
      width: 210,
      child: Row(
        children: [
          _loading
              ? const SizedBox(width: 36, height: 36, child: Padding(
                  padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                      size: 36, color: widget.fg),
                  onPressed: _toggle,
                ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: progress, minHeight: 3),
                const SizedBox(height: 4),
                Text(_fmt(_playing || _pos > Duration.zero ? _pos : _dur),
                    style: TextStyle(fontSize: 11, color: widget.fg)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DateChip extends StatelessWidget {
  const DateChip({super.key, required this.date});
  final DateTime date;

  String _label() {
    final now = DateTime.now();
    final d = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'النهارده';
    if (diff == 1) return 'امبارح';
    return DateFormat('EEEE d MMMM', 'ar').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1F2C34) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(_label(),
            style: TextStyle(fontSize: 12, color: dark ? const Color(0xFF8696A0) : const Color(0xFF54656F))),
      ),
    );
  }
}
