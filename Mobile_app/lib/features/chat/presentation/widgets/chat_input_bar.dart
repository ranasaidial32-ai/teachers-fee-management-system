/// features/chat/presentation/widgets/chat_input_bar.dart
/// Chat message composition bar.
///
/// PRD Reference: Section 06 — Supported Message Types
///   Text, Images, Files, Folders (ZIP), Voice recordings
///
/// FEATURES:
///   Text input with send button
///   Attachment picker (image, file, voice)
///   File upload to R2 via /files/upload
///   Voice recording sheet (long-press mic)
///   Emoji button (opens keyboard emoji panel)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_theme.dart';
import 'voice_recorder_sheet.dart';

class ChatInputBar extends ConsumerStatefulWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.batchId,
    required this.isTeacher,
    required this.onSend,
    required this.onTyping,
    required this.onFileSent,
  });

  final TextEditingController controller;
  final FocusNode             focusNode;
  final String                batchId;
  final bool                  isTeacher;
  final VoidCallback          onSend;
  final VoidCallback          onTyping;
  final void Function(String fileRecordId, String type, String metadata) onFileSent;

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  bool _hasText       = false;
  bool _isUploading   = false;
  double _uploadProgress = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    if (hasText) widget.onTyping();
  }

  // ── Attachment Picker Sheet ────────────────────────────────────────────────
  void _showAttachmentPicker() {
    showModalBottomSheet(
      context:       context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width:  40,
                height: 4,
                decoration: BoxDecoration(
                  color:        Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Share',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _AttachOption(
                    icon:    Icons.image_outlined,
                    label:   'Image',
                    color:   Colors.blue,
                    onTap:   () {
                      Navigator.pop(ctx);
                      _pickImage();
                    },
                  ),
                  _AttachOption(
                    icon:    Icons.insert_drive_file_outlined,
                    label:   'File',
                    color:   Colors.orange,
                    onTap:   () {
                      Navigator.pop(ctx);
                      _pickFile();
                    },
                  ),
                  _AttachOption(
                    icon:    Icons.folder_zip_outlined,
                    label:   'Folder',
                    color:   Colors.purple,
                    onTap:   () {
                      Navigator.pop(ctx);
                      _pickFile(folderMode: true);
                    },
                  ),
                  _AttachOption(
                    icon:    Icons.mic_outlined,
                    label:   'Voice',
                    color:   AppTheme.errorRed,
                    onTap:   () {
                      Navigator.pop(ctx);
                      _showVoiceRecorder();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Image Picker ──────────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image  = await picker.pickImage(
      source:     ImageSource.gallery,
      imageQuality: 85,
    );
    if (image == null) return;

    // Compress before upload (PRD Section 11: "compress images before upload")
    final compressed = await FlutterImageCompress.compressWithFile(
      image.path,
      quality: 75,
    );

    if (compressed == null) return;

    await _uploadBytes(
      bytes:        compressed,
      fileName:     image.name,
      mimeType:     'image/jpeg',
      messageType:  'image',
    );
  }

  // ── File Picker ───────────────────────────────────────────────────────────
  Future<void> _pickFile({bool folderMode = false}) async {
    final result = await FilePicker.platform.pickFiles(
      type:              FileType.custom,
      allowedExtensions: folderMode
          ? ['zip']
          : ['pdf', 'docx', 'xlsx', 'zip'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    // Enforce 25 MB limit (PRD Section 11)
    if (file.size > AppConstants.maxFileSizeBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'File too large. Maximum size is 25 MB.',
            ),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
      return;
    }

    await _uploadBytes(
      bytes:       file.bytes!,
      fileName:    file.name,
      mimeType:    file.extension != null
                   ? 'application/${file.extension}'
                   : 'application/octet-stream',
      messageType: folderMode ? 'folder' : 'file',
    );
  }

  // ── Upload to R2 ──────────────────────────────────────────────────────────
  Future<void> _uploadBytes({
    required List<int> bytes,
    required String    fileName,
    required String    mimeType,
    required String    messageType,
  }) async {
    setState(() {
      _isUploading    = true;
      _uploadProgress = 0;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final formData  = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename:    fileName,
          contentType: DioMediaType.parse(mimeType),
        ),
        'batch_id': widget.batchId,
        'type':     messageType,
      });

      final response = await apiClient.uploadFile(
        ApiEndpoints.fileUpload,
        formData,
        onSendProgress: (sent, total) {
          if (total > 0 && mounted) {
            setState(() => _uploadProgress = sent / total);
          }
        },
      );

      if (response.statusCode == 201) {
        final fileData = response.data['data']['file_record']
            as Map<String, dynamic>;
        final fileRecordId = fileData['id'] as String;

        // Build metadata for socket message content
        final metadata = jsonEncode({
          'original_name': fileData['original_name'],
          'mime_type':     fileData['mime_type'],
          'size_bytes':    fileData['size_bytes'],
          'signed_url':    fileData['signed_url'],
          'expires_at':    fileData['expires_at'],
        });

        widget.onFileSent(fileRecordId, messageType, metadata);
      } else {
        _showUploadError('Upload failed. Please try again.');
      }
    } catch (e) {
      _showUploadError('Upload failed: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading    = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  // ── Voice Recorder ────────────────────────────────────────────────────────
  void _showVoiceRecorder() {
    showModalBottomSheet(
      context:     context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => VoiceRecorderSheet(
        batchId:    widget.batchId,
        onVoiceSent: (fileRecordId, metadata) {
          widget.onFileSent(fileRecordId, 'voice', metadata);
        },
      ),
    );
  }

  void _showUploadError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.errorRed),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color:  Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Upload progress bar
            if (_isUploading)
              LinearProgressIndicator(
                value:     _uploadProgress > 0 ? _uploadProgress : null,
                color:     AppTheme.primaryTeal,
                minHeight: 2,
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [

                  // Attachment button
                  IconButton(
                    icon:      const Icon(Icons.attach_file_rounded),
                    onPressed: _isUploading ? null : _showAttachmentPicker,
                    color:     theme.colorScheme.onSurface.withOpacity(0.5),
                  ),

                  // Text input
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: TextField(
                        controller:     widget.controller,
                        focusNode:      widget.focusNode,
                        maxLines:       null,
                        keyboardType:   TextInputType.multiline,
                        textCapitalization:
                            TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText:    'Type a message...',
                          filled:      true,
                          fillColor:   theme.colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide:   BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical:   10,
                          ),
                          isDense: true,
                        ),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize:   14,
                        ),
                        onSubmitted: (_) => widget.onSend(),
                      ),
                    ),
                  ),

                  const SizedBox(width: 4),

                  // Send / Mic button
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _hasText
                        ? IconButton(
                            key:       const ValueKey('send'),
                            icon:      const Icon(Icons.send_rounded),
                            color:     AppTheme.primaryTeal,
                            onPressed: widget.onSend,
                          )
                        : GestureDetector(
                            key:       const ValueKey('mic'),
                            onLongPress: _showVoiceRecorder,
                            child: IconButton(
                              icon:    const Icon(Icons.mic_outlined),
                              color:   theme.colorScheme.onSurface.withOpacity(0.5),
                              onPressed: _showVoiceRecorder,
                            ),
                          ),
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

// ── Attachment Option ─────────────────────────────────────────────────────────

class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData   icon;
  final String     label;
  final Color      color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      children: [
        Container(
          width:  56,
          height: 56,
          decoration: BoxDecoration(
            color:        color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize:   12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}