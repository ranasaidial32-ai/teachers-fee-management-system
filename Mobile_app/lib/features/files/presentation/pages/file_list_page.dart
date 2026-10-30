/// features/files/presentation/pages/file_list_page.dart
/// Downloaded and available file browser for a batch.
///
/// PRD Reference: Section 07 — File Storage Architecture
///   "Students continue to view the file from local storage"
///   "Files deleted from server after 12h but persist locally"
///
/// PRD Reference: Section 02 — Student Role
///   "View local file cache offline"
///
/// SECTIONS:
///   Recent (from server — signed URL valid)
///   Downloaded (local cache — always available offline)
///
/// Files expired from R2 show "Offline only" badge.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/providers.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/file_tile.dart';

class FileListPage extends ConsumerWidget {
  const FileListPage({super.key, required this.batchId});
  final String batchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage        = ref.watch(storageServiceProvider);
    final downloads      = storage.getPendingDownloads();
    final theme          = Theme.of(context);

    // Load downloaded file metadata from Hive
    final downloadedFiles = _getDownloadedFiles(storage);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Files'),
      ),
      body: downloadedFiles.isEmpty
          ? _EmptyFilesState()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [

                // ── Downloaded Files ───────────────────────────────────────
                Text(
                  'Downloaded Files',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color:      AppTheme.primaryTeal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),

                ...downloadedFiles.asMap().entries.map((e) {
                  final file = e.value;
                  return FileTile(
                    fileName:  file['file_name']   as String? ?? 'File',
                    localPath: file['local_path']  as String? ?? '',
                    sizeBytes: file['size_bytes']  as int?    ?? 0,
                    downloadedAt: file['downloaded_at'] as String? ?? '',
                    isOnServer: false,
                  ).animate(delay: (e.key * 50).ms).fadeIn();
                }),
              ],
            ),
    );
  }

  List<Map<String, dynamic>> _getDownloadedFiles(StorageService storage) {
    // Reads from Hive downloads box (keys prefixed with 'done_')
    return storage.getPendingDownloads()
        .where((d) => d.containsKey('local_path'))
        .toList();
  }
}

class _EmptyFilesState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.folder_open_rounded,
          size:  64,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.15),
        ),
        const SizedBox(height: 16),
        Text(
          'No files yet',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Files shared in chat will appear here.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
        ),
      ],
    ),
  );
}