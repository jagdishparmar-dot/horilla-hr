/// One announcement from `GET /base/announcement-view`.
class AnnouncementItem {
  const AnnouncementItem({
    required this.id,
    required this.title,
    required this.content,
    required this.hasViewed,
    this.createdAt,
    this.expireDate,
    this.author,
    this.attachments = const [],
  });

  final int id;
  final String title;
  final List<AnnouncementBlock> content;
  final bool hasViewed;
  final DateTime? createdAt;
  final DateTime? expireDate;
  final String? author;
  final List<AnnouncementAttachment> attachments;

  factory AnnouncementItem.fromJson(Map<String, dynamic> json) {
    final blocks = json['content'];
    final files = json['attachments'];
    final author = json['author']?.toString().trim();
    return AnnouncementItem(
      id: json['id'] as int? ?? 0,
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : 'Announcement',
      content: blocks is List
          ? blocks
                .whereType<Map>()
                .map(
                  (block) => AnnouncementBlock.fromJson(
                    Map<String, dynamic>.from(block),
                  ),
                )
                .where((block) => block.text.isNotEmpty)
                .toList()
          : const [],
      hasViewed: json['has_viewed'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      expireDate: DateTime.tryParse(json['expire_date']?.toString() ?? ''),
      author: author == null || author.isEmpty ? null : author,
      attachments: files is List
          ? files
                .whereType<Map>()
                .map(
                  (file) => AnnouncementAttachment.fromJson(
                    Map<String, dynamic>.from(file),
                  ),
                )
                .where((file) => file.url.isNotEmpty)
                .toList()
          : const [],
    );
  }

  /// Plain-text body used on inbox rows. Bullets keep their marker.
  String get previewText {
    final lines = <String>[];
    for (final block in content) {
      if (block.type == 'bullet') {
        lines.add('• ${block.text}');
      } else {
        lines.add(block.text);
      }
    }
    if (lines.isEmpty) return 'No additional details.';
    return lines.join('\n');
  }
}

class AnnouncementBlock {
  const AnnouncementBlock({required this.type, required this.text});

  final String type;
  final String text;

  factory AnnouncementBlock.fromJson(Map<String, dynamic> json) {
    return AnnouncementBlock(
      type: json['type'] as String? ?? 'paragraph',
      text: (json['text'] as String? ?? '').trim(),
    );
  }
}

class AnnouncementAttachment {
  const AnnouncementAttachment({
    required this.name,
    required this.url,
    required this.isImage,
  });

  final String name;
  final String url;
  final bool isImage;

  factory AnnouncementAttachment.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String? ?? '').trim();
    final url = (json['url'] as String? ?? '').trim();
    return AnnouncementAttachment(
      name: name.isEmpty ? 'Attachment' : name,
      url: url,
      isImage: json['is_image'] as bool? ?? false,
    );
  }
}

/// One page of `GET /base/announcement-view`.
class AnnouncementPage {
  const AnnouncementPage({required this.items, this.next});

  final List<AnnouncementItem> items;
  final String? next;

  bool get hasNext => next != null && next!.isNotEmpty;

  factory AnnouncementPage.fromJson(Map<String, dynamic> json) {
    final rows = json['results'];
    final next = json['next']?.toString();
    return AnnouncementPage(
      items: rows is List
          ? rows
                .whereType<Map>()
                .map(
                  (row) =>
                      AnnouncementItem.fromJson(Map<String, dynamic>.from(row)),
                )
                .toList()
          : const [],
      next: next == null || next.isEmpty ? null : next,
    );
  }
}
