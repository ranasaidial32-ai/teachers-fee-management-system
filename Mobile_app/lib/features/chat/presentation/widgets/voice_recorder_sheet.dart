/// features/chat/presentation/widgets/voice_recorder_sheet.dart
/// Voice recording bottom sheet for chat voice notes.
///
/// PRD Reference: Section 06 — Supported Message Types
///   "Voice recordings (AAC / OGG)"
///
/// FEATURES:
///   Waveform visualisation during recording
///   Max duration: 5 minutes (AppConstants.maxVoiceRecordSeconds)
///   Uploads AAC file to R2 via /files/upload
///   Returns file_record_id to ChatInputBar

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_theme.dart';

class VoiceRecorderSheet extends ConsumerStatefulWidget {
  const VoiceRecorderSheet({
    super.key,
    required this.batchId,
    required this.onVoiceSent,
  });

  final String batchId;
  final void Function(String fileRecordId, String metadata) onVoiceSent;

  @override
  ConsumerState<VoiceRecorderSheet> createState() =>
      _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends ConsumerState<VoiceRecorderSheet> {
  final _recorder  = AudioRecorder();
  bool   _isRecording  = false;
  bool   _isUploading  = false;
  int    _seconds       = 0;
  Timer? _timer;
  String? _recordedPath;

  @override
  void initState() {
    super.initState();
    _startRecording();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';

    await _recorder.start(
      const RecordConfig(
        encoder:    AudioEncoder.aacLc,
        bitRate:    128000,
        sampleRate: 44100,
      ),
      path: path,
    );

    setState(() {
      _isRecording  = true;
      _recordedPath = path;
      _seconds      = 0;
    });

    // Countdown timer
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _seconds++);

      // Auto-stop at max duration
      if (_seconds >= AppConstants.maxVoiceRecordSeconds) {
        _stopAndUpload();
      }
    });
  }

  Future<void> _stopAndUpload() async {
    _timer?.cancel();
    if (!_isRecording) return;

    final path = await _recorder.stop();
    setState(() => _isRecording = false);

    if (path == null) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isUploading = true);

    try {
      final file      = File(path);
      final bytes     = await file.readAsBytes();
      final fileName  = 'voice_${DateTime.now().millisecondsSinceEpoch}.aac';

      final apiClient = ref.read(apiClientProvider);
      final formData  = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename:    fileName,
          contentType: DioMediaType('audio', 'aac'),
        ),
        'batch_id': widget.batchId,
        'type':     'voice',
      });

      final response = await apiClient.uploadFile(
        ApiEndpoints.fileUpload,
        formData,
      );

      if (response.statusCode == 201 && mounted) {
        final fileData     = response.data['data']['file_record']
            as Map<String, dynamic>;
        final fileRecordId = fileData['id'] as String;
        final metadata     = jsonEncode({
          'original_name': fileData['original_name'],
          'mime_type':     'audio/aac',
          'size_bytes':    fileData['size_bytes'],
          'signed_url':    fileData['signed_url'],
          'duration_secs': _seconds,
        });

        widget.onVoiceSent(fileRecordId, metadata);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:         Text('Upload failed: ${e.toString()}'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final maxSecs = AppConstants.maxVoiceRecordSeconds;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width:  40,
            height: 4,
            decoration: BoxDecoration(
              color:        Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const SizedBox(height: 24),

          Text(
            _isUploading ? 'Uploading...' : 'Recording',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 24),

          // Recording indicator
          if (_isRecording) ...[
            Container(
              width:  80,
              height: 80,
              decoration: BoxDecoration(
                color:        AppTheme.errorRed.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: AppTheme.errorRed,
                size:  40,
              ),
            ),
            const SizedBox(height: 16),

            // Timer
            Text(
              _formatDuration(_seconds),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight:  FontWeight.w700,
                color:       AppTheme.errorRed,
                fontFeatures: const [],
              ),
            ),

            const SizedBox(height: 8),

            // Progress bar
            LinearProgressIndicator(
              value:            _seconds / maxSecs,
              backgroundColor:  Colors.grey.shade200,
              color:            AppTheme.errorRed,
            ),

            const SizedBox(height: 4),
            Text(
              'Max ${maxSecs ~/ 60} min',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 24),

            // Stop button
            ElevatedButton.icon(
              onPressed:       _stopAndUpload,
              icon:            const Icon(Icons.stop_rounded),
              label:           const Text('Stop & Send'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorRed,
                minimumSize:     const Size(200, 52),
              ),
            ),
          ] else if (_isUploading) ...[
            const CircularProgressIndicator(color: AppTheme.primaryTeal),
          ],

          const SizedBox(height: 16),

          // Cancel
          TextButton(
            onPressed: () {
              _timer?.cancel();
              _recorder.stop();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}