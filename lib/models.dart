enum MsgKind { text, image, file, voice }

class FileInfo {
  const FileInfo({
    required this.path,
    required this.name,
    required this.mime,
    required this.size,
  });

  final String path; // مسار الملف المشفّر في Storage
  final String name;
  final String mime;
  final int size;

  Map<String, dynamic> toJson() => {'p': path, 'n': name, 'm': mime, 's': size};

  factory FileInfo.fromJson(Map<String, dynamic> j) => FileInfo(
        path: j['p'] as String,
        name: (j['n'] ?? 'file') as String,
        mime: (j['m'] ?? 'application/octet-stream') as String,
        size: (j['s'] ?? 0) as int,
      );
}

/// محتوى الرسالة الحقيقي. بيتحوّل JSON وبعدين بيتشفّر قبل ما يطلع من الموبايل.
class Payload {
  const Payload({
    this.kind = MsgKind.text,
    this.text = '',
    this.replyId,
    this.replyPreview,
    this.file,
    this.durationMs = 0,
  });

  final MsgKind kind;
  final String text;
  final String? replyId;
  final String? replyPreview;
  final FileInfo? file;
  final int durationMs;

  static const empty = Payload();

  Map<String, dynamic> toJson() => {
        'k': kind.name,
        't': text,
        if (replyId != null) 'r': {'i': replyId, 'p': replyPreview ?? ''},
        if (file != null) 'f': file!.toJson(),
        if (durationMs > 0) 'd': durationMs,
      };

  factory Payload.fromJson(Map<String, dynamic> j) {
    final r = j['r'] as Map<String, dynamic>?;
    final f = j['f'] as Map<String, dynamic>?;
    return Payload(
      kind: MsgKind.values.firstWhere(
        (k) => k.name == j['k'],
        orElse: () => MsgKind.text,
      ),
      text: (j['t'] ?? '') as String,
      replyId: r?['i'] as String?,
      replyPreview: r?['p'] as String?,
      file: f == null ? null : FileInfo.fromJson(f),
      durationMs: (j['d'] ?? 0) as int,
    );
  }

  Payload withText(String newText) => Payload(
        kind: kind,
        text: newText,
        replyId: replyId,
        replyPreview: replyPreview,
        file: file,
        durationMs: durationMs,
      );

  String get preview {
    switch (kind) {
      case MsgKind.text:
        return text.length > 80 ? '${text.substring(0, 80)}…' : text;
      case MsgKind.image:
        return '📷 صورة';
      case MsgKind.voice:
        return '🎤 رسالة صوتية';
      case MsgKind.file:
        return '📎 ${file?.name ?? 'ملف'}';
    }
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sender,
    required this.ts,
    required this.pending,
    required this.edited,
    required this.deleted,
    required this.reactions,
    required this.payload,
    this.decryptFailed = false,
  });

  final String id;
  final String sender;
  final DateTime ts;
  final bool pending;
  final bool edited;
  final bool deleted;
  final Map<String, String> reactions; // uid -> emoji
  final Payload payload;
  final bool decryptFailed;
}

String fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
