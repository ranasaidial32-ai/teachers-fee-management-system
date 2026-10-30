library;

/// features/files/presentation/widgets/file_tile.dart
/// File list item widget for the file browser.
///
/// PRD Reference: Section 07 — Smart File Sync

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/theme/app_theme.dart';

class FileTile extends StatelessWidget {
  const FileTile({
    super.key,
    required this.fileName,
    required this.localPath,
    required this.sizeBytes,
    required this.downloadedAt,
    required this.isOnServer,
  });

  final String fileName;
  final String localPath;
  final int    sizeBytes;
  final String downloadedAt;
  final bool   isOnServer;

  @override
  Widget build(BuildContext context) {
    final theme     = Theme.of(context);
    final ext       = fileName.split('.').last.toLowerCase();
    final icon      = _iconForExtension(ext);
    final iconColor = _colorForExtension(ext);

    DateTime? dlDate;
    try {
      dlDate = DateTime.parse(downloadedAt).toLocal();
    } catch (_) {}

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical:   8,
        ),
        leading: Container(
          width:  44,
          height: 44,
          decoration: BoxDecoration(
            // FIXED: withOpacity → withValues
            color:        iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(
          fileName,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_formatSize(sizeBytes)}  •  '
          '${dlDate != null ? timeago.format(dlDate) : ''}  •  '
          '${isOnServer ? 'On server' : 'Local only'}',
          style: theme.textTheme.bodySmall?.copyWith(
            // FIXED: withOpacity → withValues
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isOnServer)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical:   2,
                ),
                decoration: BoxDecoration(
                  // FIXED: withOpacity → withValues
                  color:        AppTheme.primaryTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Offline',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize:   10,
                    fontWeight: FontWeight.w600,
                    color:      AppTheme.primaryTeal,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              icon:      const Icon(Icons.open_in_new_rounded),
              onPressed: () => _openFile(context),
              tooltip:   'Open file',
            ),
          ],
        ),
      ),
    );
  }

  // FIXED: Replaced OpenFile.open() + ResultType with url_launcher
  Future<void> _openFile(BuildContext context) async {
    if (localPath.isEmpty) return;

    final uri = Uri.file(localPath);
    bool launched = false;

    try {
      if (await canLaunchUrl(uri)) {
        launched = await launchUrl(uri);
      }
    } catch (_) {
      launched = false;
    }

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot open: $localPath')),
      );
    }
  }

  IconData _iconForExtension(String ext) {
    switch (ext) {
      case 'pdf':                    return Icons.picture_as_pdf_rounded;
      case 'docx':
      case 'doc':                    return Icons.description_rounded;
      case 'xlsx':
      case 'xls':                    return Icons.table_chart_rounded;
      case 'zip':                    return Icons.folder_zip_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':                   return Icons.image_rounded;
      case 'aac':
      case 'ogg':
      case 'mp3':                    return Icons.audio_file_rounded;
      default:                       return Icons.insert_drive_file_rounded;
    }
  }

  Color _colorForExtension(String ext) {
    switch (ext) {
      case 'pdf':                    return Colors.red;
      case 'docx':
      case 'doc':                    return Colors.blue;
      case 'xlsx':
      case 'xls':                    return Colors.green;
      case 'zip':                    return Colors.purple;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':                   return Colors.orange;
      case 'aac':
      case 'ogg':
      case 'mp3':                    return Colors.teal;
      default:                       return Colors.grey;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024)        return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}