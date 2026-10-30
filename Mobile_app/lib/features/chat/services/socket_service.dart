/// features/chat/services/socket_service.dart
/// Adds: message_delivered emit, read_update stream, delivery_update stream,
///       message_auto_deleted stream.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

import '../../../core/constants/app_constants.dart';
import '../../../core/services/storage_service.dart';

// ── Event Models ──────────────────────────────────────────────────────────────

class SocketMessage {
  const SocketMessage({
    required this.id,
    required this.batchId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.type,
    required this.content,
    required this.createdAt,
    this.signalMessageKey,
    this.file,
    this.clientMessageId,
    this.totalStudents = 0,
    this.downloadedCount = 0,
    this.readerCount = 0,
    this.firstReader,
  });

  final String   id;
  final String   batchId;
  final String   senderId;
  final String   senderName;
  final String   senderRole;
  final String   type;
  final String   content;
  final DateTime createdAt;
  final String?  signalMessageKey;
  final Map<String, dynamic>? file;
  final String?  clientMessageId;

  // ── Delivery tracking fields ───────────────────────────────────────────────
  final int                   totalStudents;
  final int                   downloadedCount;
  final int                   readerCount;
  final Map<String, dynamic>? firstReader; // { id, name }

  factory SocketMessage.fromJson(Map<String, dynamic> json) {
    final msg    = json['message'] as Map<String, dynamic>;
    final sender = msg['sender']  as Map<String, dynamic>? ?? {};

    return SocketMessage(
      id:               msg['id']           as String,
      batchId:          msg['batch_id']     as String,
      senderId:         sender['id']        as String? ?? '',
      senderName:       sender['name']      as String? ?? 'Unknown',
      senderRole:       sender['role']      as String? ?? 'student',
      type:             msg['type']         as String,
      content:          msg['content']      as String,
      createdAt:        DateTime.parse(msg['created_at'] as String),
      signalMessageKey: msg['signal_message_key'] as String?,
      file:             msg['file']         as Map<String, dynamic>?,
      clientMessageId:  json['client_message_id'] as String?,
      totalStudents:    (json['total_students']  as int?) ?? 0,
      downloadedCount:  (json['downloaded_count'] as int?) ?? 0,
      readerCount:      (json['reader_count']    as int?) ?? 0,
      firstReader:      json['first_reader']     as Map<String, dynamic>?,
    );
  }
}

/// Fired when server broadcasts updated download count
class DeliveryUpdate {
  const DeliveryUpdate({
    required this.messageId,
    required this.batchId,
    required this.downloadedCount,
    required this.totalStudents,
  });
  final String messageId;
  final String batchId;
  final int    downloadedCount;
  final int    totalStudents;
}

/// Fired when a student reads a message — updates reader avatar row
class ReadUpdate {
  const ReadUpdate({
    required this.messageId,
    required this.batchId,
    required this.readerCount,
    this.firstReader,
    required this.readBy,
  });
  final String                messageId;
  final String                batchId;
  final int                   readerCount;
  final Map<String, dynamic>? firstReader;
  final Map<String, dynamic>  readBy;
}

class TypingEvent {
  const TypingEvent({
    required this.batchId,
    required this.userId,
    required this.userName,
    required this.isTyping,
  });
  final String batchId;
  final String userId;
  final String userName;
  final bool   isTyping;
}

class PresenceEvent {
  const PresenceEvent({
    required this.userId,
    required this.userName,
    required this.isOnline,
  });
  final String userId;
  final String userName;
  final bool   isOnline;
}

enum SocketConnectionState { disconnected, connecting, connected, error }

// ── Socket Service ────────────────────────────────────────────────────────────

class SocketService {
  SocketService({required this.storageService});

  final StorageService storageService;
  sio.Socket?          _socket;

  // ── Stream Controllers ─────────────────────────────────────────────────────
  final _messageController       = StreamController<SocketMessage>.broadcast();
  final _typingController        = StreamController<TypingEvent>.broadcast();
  final _presenceController      = StreamController<PresenceEvent>.broadcast();
  final _connectionController    = StreamController<SocketConnectionState>.broadcast();
  final _deletedMsgController    = StreamController<Map<String, dynamic>>.broadcast();
  final _autoDeletedController   = StreamController<Map<String, dynamic>>.broadcast();
  final _keyBundleController     = StreamController<Map<String, dynamic>>.broadcast();
  final _memberController        = StreamController<Map<String, dynamic>>.broadcast();
  final _fileSharedController    = StreamController<Map<String, dynamic>>.broadcast();
  final _deliveryUpdateController = StreamController<DeliveryUpdate>.broadcast();
  final _readUpdateController    = StreamController<ReadUpdate>.broadcast();

  // ── Public Streams ─────────────────────────────────────────────────────────
  Stream<SocketMessage>         get messages         => _messageController.stream;
  Stream<TypingEvent>           get typingEvents     => _typingController.stream;
  Stream<PresenceEvent>         get presenceEvents   => _presenceController.stream;
  Stream<SocketConnectionState> get connectionState  => _connectionController.stream;
  Stream<Map<String, dynamic>>  get deletedMessages  => _deletedMsgController.stream;
  Stream<Map<String, dynamic>>  get autoDeletedMessages => _autoDeletedController.stream;
  Stream<Map<String, dynamic>>  get keyBundles       => _keyBundleController.stream;
  Stream<Map<String, dynamic>>  get memberEvents     => _memberController.stream;
  Stream<Map<String, dynamic>>  get fileShared       => _fileSharedController.stream;
  Stream<DeliveryUpdate>        get deliveryUpdates  => _deliveryUpdateController.stream;
  Stream<ReadUpdate>            get readUpdates      => _readUpdateController.stream;

  SocketConnectionState _currentState = SocketConnectionState.disconnected;
  SocketConnectionState get currentState => _currentState;
  bool get isConnected => _currentState == SocketConnectionState.connected;

  // ── Connect ────────────────────────────────────────────────────────────────
  Future<void> connect() async {
    if (_currentState == SocketConnectionState.connected ||
        _currentState == SocketConnectionState.connecting) return;

    _setConnectionState(SocketConnectionState.connecting);

    try {
      final token = await storageService.getAccessToken();
      if (token == null) {
        _setConnectionState(SocketConnectionState.error);
        return;
      }

      final baseUrl = kDebugMode
          ? AppConstants.socketBaseUrl
          : AppConstants.socketBaseUrlProd;

      _socket = sio.io(
        baseUrl,
        sio.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .setAuth({'token': token})
            .enableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(10)
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(10000)
            .setTimeout(AppConstants.socketConnectTimeout)
            .build(),
      );

      _registerEventHandlers();
      _socket!.connect();
    } catch (e) {
      debugPrint('Socket connect error: $e');
      _setConnectionState(SocketConnectionState.error);
    }
  }

  // ── Event Handlers ─────────────────────────────────────────────────────────
  void _registerEventHandlers() {
    if (_socket == null) return;

    _socket!.onConnect((_) {
      debugPrint('Socket connected: ${_socket!.id}');
      _setConnectionState(SocketConnectionState.connected);
    });

    _socket!.onDisconnect((reason) {
      debugPrint('Socket disconnected: $reason');
      _setConnectionState(SocketConnectionState.disconnected);
    });

    _socket!.onConnectError((error) {
      debugPrint('Socket connect error: $error');
      _setConnectionState(SocketConnectionState.error);
    });

    _socket!.onError((error) => debugPrint('Socket error: $error'));

    // ── Chat Events ────────────────────────────────────────────────────────
    _socket!.on('new_message', (data) {
      try {
        final json    = Map<String, dynamic>.from(data as Map);
        final message = SocketMessage.fromJson(json);
        _messageController.add(message);
      } catch (e) {
        debugPrint('Error parsing new_message: $e');
      }
    });

    _socket!.on('message_deleted', (data) {
      _deletedMsgController.add(Map<String, dynamic>.from(data as Map));
    });

    // Auto-deleted after 99% delivery
    _socket!.on('message_auto_deleted', (data) {
      _autoDeletedController.add(Map<String, dynamic>.from(data as Map));
    });

    // ── Delivery Updates ───────────────────────────────────────────────────
    _socket!.on('delivery_update', (data) {
      try {
        final d = Map<String, dynamic>.from(data as Map);
        _deliveryUpdateController.add(DeliveryUpdate(
          messageId:       d['message_id']     as String,
          batchId:         d['batch_id']       as String,
          downloadedCount: (d['downloaded_count'] as int?) ?? 0,
          totalStudents:   (d['total_students']   as int?) ?? 0,
        ));
      } catch (e) {
        debugPrint('Error parsing delivery_update: $e');
      }
    });

    // ── Read Updates ───────────────────────────────────────────────────────
    _socket!.on('read_update', (data) {
      try {
        final d = Map<String, dynamic>.from(data as Map);
        _readUpdateController.add(ReadUpdate(
          messageId:   d['message_id']  as String,
          batchId:     d['batch_id']    as String,
          readerCount: (d['reader_count'] as int?) ?? 0,
          firstReader: d['first_reader'] as Map<String, dynamic>?,
          readBy:      Map<String, dynamic>.from(d['read_by'] as Map),
        ));
      } catch (e) {
        debugPrint('Error parsing read_update: $e');
      }
    });

    // ── Typing ─────────────────────────────────────────────────────────────
    _socket!.on('user_typing', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      _typingController.add(TypingEvent(
        batchId:  d['batch_id']  as String,
        userId:   d['user_id']   as String,
        userName: d['user_name'] as String,
        isTyping: true,
      ));
    });

    _socket!.on('user_stopped_typing', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      _typingController.add(TypingEvent(
        batchId:  d['batch_id'] as String,
        userId:   d['user_id']  as String,
        userName: '',
        isTyping: false,
      ));
    });

    // ── Presence ───────────────────────────────────────────────────────────
    _socket!.on('user_online', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      _presenceController.add(PresenceEvent(
        userId:   d['user_id']   as String,
        userName: d['user_name'] as String,
        isOnline: true,
      ));
    });

    _socket!.on('user_offline', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      _presenceController.add(PresenceEvent(
        userId:   d['user_id']   as String,
        userName: d['user_name'] as String,
        isOnline: false,
      ));
    });

    // ── Member & File Events ───────────────────────────────────────────────
    _socket!.on('member_joined',      (d) => _memberController.add(_toMap(d)));
    _socket!.on('member_removed',     (d) => _memberController.add(_toMap(d)));
    _socket!.on('enrolled_in_batch',  (d) => _memberController.add(_toMap(d)));
    _socket!.on('removed_from_batch', (d) => _memberController.add(_toMap(d)));
    _socket!.on('file_shared',        (d) => _fileSharedController.add(_toMap(d)));

    // ── Signal Protocol ────────────────────────────────────────────────────
    _socket!.on('key_bundle_received',  (d) => _keyBundleController.add(_toMap(d)));
    _socket!.on('key_bundle_requested', (d) => _keyBundleController.add(_toMap(d)));
  }

  // ── Emit Methods ──────────────────────────────────────────────────────────

  void sendMessage({
    required String batchId,
    required String type,
    required String encryptedContent,
    String?  signalMessageKey,
    String?  fileRecordId,
    String?  clientMessageId,
    Function(Map<String, dynamic>)? onAck,
  }) {
    if (!isConnected) {
      debugPrint('Cannot send — socket not connected');
      return;
    }

    final payload = {
      'batch_id': batchId,
      'type':     type,
      'content':  encryptedContent,
      if (signalMessageKey != null) 'signal_message_key': signalMessageKey,
      if (fileRecordId     != null) 'file_record_id':     fileRecordId,
      if (clientMessageId  != null) 'client_message_id':  clientMessageId,
    };

    _socket!.emitWithAck('send_message', payload, ack: (data) {
      if (data is Map) onAck?.call(Map<String, dynamic>.from(data));
    });
  }

  /// Call when a message is rendered on screen (student only)
  /// Triggers download ACK → server tracks delivery count
  void confirmDelivered(String messageId, String batchId) {
    _socket?.emit('message_delivered', {
      'message_id': messageId,
      'batch_id':   batchId,
    });
  }

  /// Call when a message scrolls into view (student only)
  /// Triggers read receipt → reader avatar appears for teacher
  void markRead(String batchId, String messageId) {
    _socket?.emit('message_read', {
      'batch_id':   batchId,
      'message_id': messageId,
    });
  }

  void sendKeyBundle({
    required String batchId,
    required String identityKey,
    required String signedPreKey,
    List<String> oneTimePreKeys = const [],
  }) {
    _socket?.emit('signal_key_bundle', {
      'batch_id':          batchId,
      'identity_key':      identityKey,
      'signed_pre_key':    signedPreKey,
      'one_time_pre_keys': oneTimePreKeys,
    });
  }

  void requestKeyBundle({required String batchId, required String targetUserId}) {
    _socket?.emit('request_key_bundle', {
      'batch_id':       batchId,
      'target_user_id': targetUserId,
    });
  }

  void startTyping(String batchId) =>
      _socket?.emit('typing_start', {'batch_id': batchId});

  void stopTyping(String batchId) =>
      _socket?.emit('typing_stop', {'batch_id': batchId});

  void joinBatch(String batchId) =>
      _socket?.emit('join_batch', {'batch_id': batchId});

  void leaveBatch(String batchId) =>
      _socket?.emit('leave_batch', {'batch_id': batchId});

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _setConnectionState(SocketConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _typingController.close();
    _presenceController.close();
    _connectionController.close();
    _deletedMsgController.close();
    _autoDeletedController.close();
    _keyBundleController.close();
    _memberController.close();
    _fileSharedController.close();
    _deliveryUpdateController.close();
    _readUpdateController.close();
  }

  void _setConnectionState(SocketConnectionState state) {
    _currentState = state;
    if (!_connectionController.isClosed) _connectionController.add(state);
  }

  Map<String, dynamic> _toMap(dynamic data) =>
      data is Map ? Map<String, dynamic>.from(data) : {};
}