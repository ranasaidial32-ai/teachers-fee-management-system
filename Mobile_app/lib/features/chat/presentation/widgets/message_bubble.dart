library;

/// features/chat/presentation/widgets/message_bubble.dart
/// Adds: double-tick delivery indicator + reader avatar row with 9+ logic.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/chat_repository.dart';
import '../../presentation/pages/chat_page.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isOwn,
    required this.showAvatar,
    required this.isTeacher,
    required this.batchId,
    required this.chatRepository,
    this.onLongPress,
  });

  final ChatMessage    message;
  final bool           isOwn;
  final bool           showAvatar;
  final bool           isTeacher;
  final String         batchId;
  final ChatRepository chatRepository;
  final VoidCallback?  onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: 4,
          left:   isOwn ? 48 : 0,
          right:  isOwn ? 0  : 48,
        ),
        child: Row(
          mainAxisAlignment:
              isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Avatar for other user
            if (!isOwn) ...[
              showAvatar
                  ? CircleAvatar(
                      radius:          16,
                      backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.15),
                      child: Text(
                        message.senderName.isNotEmpty
                            ? message.senderName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize:   12,
                          fontWeight: FontWeight.w700,
                          color:      AppTheme.primaryTeal,
                        ),
                      ),
                    )
                  : const SizedBox(width: 32),
              const SizedBox(width: 6),
            ],

            // Bubble + status row
            Flexible(
              child: Column(
                crossAxisAlignment: isOwn
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  // Sender name
                  if (!isOwn && showAvatar) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      child: Text(
                        message.senderRole == AppConstants.roleTeacher
                            ? '${message.senderName} 👨‍🏫'
                            : message.senderName,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color:      AppTheme.primaryTeal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],

                  // Bubble content
                  _BubbleContent(
                    message: message,
                    isOwn:   isOwn,
                    theme:   theme,
                  ),

                  const SizedBox(height: 3),

                  // ── Status Row: timestamp + ticks + reader avatars ────────
                  _StatusRow(
                    message:        message,
                    isOwn:          isOwn,
                    isTeacher:      isTeacher,
                    batchId:        batchId,
                    chatRepository: chatRepository,
                    theme:          theme,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status Row ────────────────────────────────────────────────────────────────
/// Shows: timestamp | delivery ticks | reader avatars

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.message,
    required this.isOwn,
    required this.isTeacher,
    required this.batchId,
    required this.chatRepository,
    required this.theme,
  });

  final ChatMessage    message;
  final bool           isOwn;
  final bool           isTeacher;
  final String         batchId;
  final ChatRepository chatRepository;
  final ThemeData      theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize:    MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Timestamp / optimistic clock
        if (message.isOptimistic)
          const Icon(Icons.access_time_rounded, size: 10, color: Colors.grey)
        else
          Text(
            timeago.format(message.createdAt, locale: 'en_short'),
            style: theme.textTheme.labelSmall?.copyWith(
              color:    theme.colorScheme.onSurface.withValues(alpha: 0.4),
              fontSize: 10,
            ),
          ),

        // ── Delivery ticks (own messages only) ──────────────────────────────
        if (isOwn && !message.isOptimistic && !message.isDeleted) ...[
          const SizedBox(width: 4),
          _DeliveryTicks(message: message),
        ],

        // ── Reader avatars (own messages, teacher view) ────────────────────
        // Show readers beneath sender's own bubble
        if (isOwn && !message.isDeleted && message.readerCount > 0) ...[
          const SizedBox(width: 6),
          _ReaderAvatarRow(
            message:        message,
            isTeacher:      isTeacher,
            batchId:        batchId,
            chatRepository: chatRepository,
          ),
        ],
      ],
    );
  }
}

// ── Delivery Ticks ────────────────────────────────────────────────────────────
/// Single tick  = sent (optimistic resolved)
/// Double tick  = delivered to ≥1 student device (downloaded)
/// Double blue  = at least one student has read it

class _DeliveryTicks extends StatelessWidget {
  const _DeliveryTicks({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bool anyDownloaded = message.downloadedCount > 0;
    final bool anyRead       = message.readerCount     > 0;

    // Choose tick colour
    final Color tickColor = anyRead
        ? AppTheme.primaryTeal          // Blue = read
        : anyDownloaded
            ? Colors.grey.shade500      // Grey double = delivered
            : Colors.grey.shade400;     // Grey single = sent only

    if (!anyDownloaded) {
      // Single tick — sent, not yet delivered
      return Icon(Icons.done_rounded, size: 14, color: tickColor);
    }

    // Double tick — delivered or read
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.done_rounded,     size: 14, color: tickColor),
        const SizedBox(width: -6),   // Overlap ticks like WhatsApp
        Icon(Icons.done_rounded,     size: 14, color: tickColor),
      ],
    );
  }
}

// ── Reader Avatar Row ─────────────────────────────────────────────────────────
/// Rules:
///  1 reader     → small circular avatar with initial
///  2–8 readers  → first reader avatar + count badge (e.g. "3")
///  9+ readers   → first reader avatar in circle + "9+" overlay
///  Teacher taps → opens full reader list bottom sheet

class _ReaderAvatarRow extends StatelessWidget {
  const _ReaderAvatarRow({
    required this.message,
    required this.isTeacher,
    required this.batchId,
    required this.chatRepository,
  });

  final ChatMessage    message;
  final bool           isTeacher;
  final String         batchId;
  final ChatRepository chatRepository;

  @override
  Widget build(BuildContext context) {
    final readerCount = message.readerCount;
    final firstReader = message.firstReader; // { id, name }
    final firstName   = (firstReader?['name'] as String? ?? '?');
    final initial     = firstName.isNotEmpty ? firstName[0].toUpperCase() : '?';

    final bool showNinePlus = readerCount >= 9;

    return GestureDetector(
      // Only teacher can tap to see full reader list
      onTap: isTeacher ? () => _showReaderList(context) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar with optional 9+ overlay
          Stack(
            clipBehavior: Clip.none,
            children: [
              // First reader avatar
              CircleAvatar(
                radius:          10,
                backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize:   8,
                    fontWeight: FontWeight.w700,
                    color:      AppTheme.primaryTeal,
                  ),
                ),
              ),

              // 9+ badge overlaid on the avatar
              if (showNinePlus)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color:  AppTheme.primaryTeal.withValues(alpha: 0.85),
                      shape:  BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text(
                        '9+',
                        style: TextStyle(
                          fontSize:   6,
                          fontWeight: FontWeight.w800,
                          color:      Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // Count label for 2–8 readers
          if (!showNinePlus && readerCount > 1) ...[
            const SizedBox(width: 3),
            Text(
              '$readerCount',
              style: TextStyle(
                fontSize:   10,
                fontWeight: FontWeight.w600,
                color:      AppTheme.primaryTeal.withValues(alpha: 0.8),
              ),
            ),
          ],

          // Tap hint for teacher (small chevron)
          if (isTeacher) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more_rounded,
              size:  12,
              color: AppTheme.primaryTeal.withValues(alpha: 0.5),
            ),
          ],
        ],
      ),
    );
  }

  // ── Reader List Bottom Sheet ──────────────────────────────────────────────
  void _showReaderList(BuildContext context) {
    showModalBottomSheet(
      context:     context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ReaderListSheet(
        batchId:        batchId,
        messageId:      message.id,
        readerCount:    message.readerCount,
        chatRepository: chatRepository,
      ),
    );
  }
}

// ── Reader List Bottom Sheet ──────────────────────────────────────────────────

class _ReaderListSheet extends StatefulWidget {
  const _ReaderListSheet({
    required this.batchId,
    required this.messageId,
    required this.readerCount,
    required this.chatRepository,
  });

  final String         batchId;
  final String         messageId;
  final int            readerCount;
  final ChatRepository chatRepository;

  @override
  State<_ReaderListSheet> createState() => _ReaderListSheetState();
}

class _ReaderListSheetState extends State<_ReaderListSheet> {
  bool                   _isLoading = true;
  List<MessageReader>    _readers   = [];
  String?                _error;

  @override
  void initState() {
    super.initState();
    _loadReaders();
  }

  Future<void> _loadReaders() async {
    final result = await widget.chatRepository.getMessageReaders(
      batchId:   widget.batchId,
      messageId: widget.messageId,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _readers   = result.data!.readers;
        _isLoading = false;
      });
    } else {
      setState(() {
        _error     = result.error;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand:          false,
      initialChildSize: 0.5,
      maxChildSize:     0.85,
      minChildSize:     0.3,
      builder: (_, controller) => Column(
        children: [
          // Handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color:        Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.done_all_rounded, color: AppTheme.primaryTeal),
                const SizedBox(width: 10),
                Text(
                  'Read by ${widget.readerCount} student${widget.readerCount != 1 ? "s" : ""}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    : _readers.isEmpty
                        ? const Center(child: Text('No readers yet.'))
                        : ListView.builder(
                            controller:  controller,
                            itemCount:   _readers.length,
                            itemBuilder: (_, i) {
                              final reader = _readers[i];
                              final initial = reader.studentName.isNotEmpty
                                  ? reader.studentName[0].toUpperCase()
                                  : '?';

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      AppTheme.primaryTeal.withValues(alpha: 0.15),
                                  child: Text(
                                    initial,
                                    style: const TextStyle(
                                      color:      AppTheme.primaryTeal,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  reader.studentName,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(reader.studentEmail),
                                trailing: Text(
                                  timeago.format(reader.readAt, locale: 'en_short'),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// ── Bubble Content ────────────────────────────────────────────────────────────

class _BubbleContent extends StatelessWidget {
  const _BubbleContent({
    required this.message,
    required this.isOwn,
    required this.theme,
  });

  final ChatMessage message;
  final bool        isOwn;
  final ThemeData   theme;

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) {
      return _buildContainer(
        child: Text(
          '[Message deleted by admin]',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize:   13,
            fontStyle:  FontStyle.italic,
            color: isOwn
                ? Colors.white60
                : theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      );
    }

    switch (message.type) {
      case 'text':   return _buildTextBubble(context);
      case 'image':  return _buildMediaBubble(context, isImage: true);
      case 'file':
      case 'folder': return _buildFileBubble(context);
      case 'voice':  return _buildVoiceBubble(context);
      default:       return _buildTextBubble(context);
    }
  }

  Widget _buildTextBubble(BuildContext context) => _buildContainer(
    child: Text(
      message.content,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize:   14,
        color: isOwn ? Colors.white : theme.colorScheme.onSurface,
      ),
    ),
  );

  Widget _buildMediaBubble(BuildContext context, {required bool isImage}) {
    final file            = message.file;
    final fileName        = file?['original_name']    as String? ?? 'Image';
    final fileRecordId    = file?['id']               as String? ?? '';
    final signedUrl       = file?['signed_url']       as String? ?? '';
    final isDeletedFromR2 = file?['is_deleted_from_r2'] as bool? ?? false;

    return _buildContainer(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: signedUrl.isNotEmpty && !isDeletedFromR2
            ? Image.network(
                signedUrl,
                width:  240,
                height: 180,
                fit:    BoxFit.cover,
                errorBuilder: (_, __, ___) => _FileCard(
                  fileName:     fileName,
                  fileRecordId: fileRecordId,
                  isOwn:        isOwn,
                ),
              )
            : _FileCard(
                fileName:     fileName,
                fileRecordId: fileRecordId,
                isOwn:        isOwn,
              ),
      ),
    );
  }

  Widget _buildFileBubble(BuildContext context) {
    final file         = message.file;
    final fileName     = file?['original_name'] as String? ?? 'File';
    final sizeBytes    = file?['size_bytes']    as int?    ?? 0;
    final fileRecordId = file?['id']            as String? ?? '';

    return _buildContainer(
      child: _FileCard(
        fileName:     fileName,
        fileRecordId: fileRecordId,
        sizeBytes:    sizeBytes,
        isOwn:        isOwn,
        icon:         _fileIcon(fileName),
      ),
    );
  }

  Widget _buildVoiceBubble(BuildContext context) {
    final fileRecordId = message.file?['id'] as String? ?? '';
    return _buildContainer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_rounded,
              color: isOwn ? Colors.white70 : AppTheme.primaryTeal, size: 20),
          const SizedBox(width: 8),
          Text(
            'Voice Message',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize:   13,
              color: isOwn ? Colors.white : theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          _PlayButton(fileRecordId: fileRecordId, isOwn: isOwn),
        ],
      ),
    );
  }

  Widget _buildContainer({required Widget child, EdgeInsets? padding}) =>
      Opacity(
        opacity: message.isOptimistic ? 0.6 : 1.0,
        child: Container(
          padding: padding ??
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isOwn
                ? AppTheme.primaryTeal
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.only(
              topLeft:     const Radius.circular(16),
              topRight:    const Radius.circular(16),
              bottomLeft:  Radius.circular(isOwn ? 16 : 4),
              bottomRight: Radius.circular(isOwn ? 4  : 16),
            ),
            border: isOwn
                ? null
                : Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color:      Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset:     const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      );

  IconData _fileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (ext == 'pdf')                    return Icons.picture_as_pdf_rounded;
    if (['docx', 'doc'].contains(ext))   return Icons.description_rounded;
    if (['xlsx', 'xls'].contains(ext))   return Icons.table_chart_rounded;
    if (ext == 'zip')                    return Icons.folder_zip_rounded;
    return Icons.insert_drive_file_rounded;
  }
}

// ── File Card ─────────────────────────────────────────────────────────────────

class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.fileName,
    required this.fileRecordId,
    required this.isOwn,
    this.sizeBytes,
    this.icon,
  });

  final String    fileName;
  final String    fileRecordId;
  final bool      isOwn;
  final int?      sizeBytes;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final storage   = StorageService();
    final localPath = storage.getLocalFilePath(fileRecordId);
    final isLocal   = localPath != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon ?? Icons.insert_drive_file_rounded,
          color: isOwn ? Colors.white70 : AppTheme.primaryTeal,
          size:  28,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize:   13,
                  fontWeight: FontWeight.w600,
                  color: isOwn ? Colors.white : null,
                ),
              ),
              if (sizeBytes != null && sizeBytes! > 0)
                Text(
                  _formatSize(sizeBytes!),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize:   11,
                    color: isOwn ? Colors.white60 : Colors.grey,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _openFile(context, localPath),
          child: Icon(
            isLocal ? Icons.open_in_new_rounded : Icons.download_rounded,
            color: isOwn ? Colors.white70 : AppTheme.primaryTeal,
            size:  20,
          ),
        ),
      ],
    );
  }

  Future<void> _openFile(BuildContext context, String? localPath) async {
    if (localPath == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File is being downloaded. Check back shortly.')),
        );
      }
      return;
    }
    final uri      = Uri.file(localPath);
    bool  launched = false;
    try {
      if (await canLaunchUrl(uri)) launched = await launchUrl(uri);
    } catch (_) { launched = false; }

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot open file: $localPath')),
      );
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024)         return '$bytes B';
    if (bytes < 1024 * 1024)  return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

// ── Play Button ───────────────────────────────────────────────────────────────

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.fileRecordId, required this.isOwn});
  final String fileRecordId;
  final bool   isOwn;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio playback coming in Phase 4')),
      );
    },
    child: Container(
      width:  32,
      height: 32,
      decoration: BoxDecoration(
        color: isOwn
            ? Colors.white.withValues(alpha: 0.2)
            : AppTheme.primaryTeal.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        size:  18,
        color: isOwn ? Colors.white : AppTheme.primaryTeal,
      ),
    ),
  );
}