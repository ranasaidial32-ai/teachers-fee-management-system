/// features/chat/presentation/pages/chat_page.dart
/// Updated to handle delivery_update, read_update, message_auto_deleted events.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/chat_repository.dart';
import '../../services/socket_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input_bar.dart';

// ── Message Model ─────────────────────────────────────────────────────────────

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.batchId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.type,
    required this.content,
    required this.createdAt,
    this.file,
    this.isDeleted       = false,
    this.isOptimistic    = false,
    this.totalStudents   = 0,
    this.downloadedCount = 0,
    this.readerCount     = 0,
    this.firstReader,
  });

  final String   id;
  final String   batchId;
  final String   senderId;
  final String   senderName;
  final String   senderRole;
  final String   type;
  String         content;
  final DateTime createdAt;
  final Map<String, dynamic>? file;
  bool isDeleted;
  bool isOptimistic;

  // ── Delivery & Read tracking ───────────────────────────────────────────────
  int                   totalStudents;
  int                   downloadedCount;
  int                   readerCount;
  Map<String, dynamic>? firstReader; // { id, name }

  factory ChatMessage.fromSocketMessage(SocketMessage msg) => ChatMessage(
    id:               msg.id,
    batchId:          msg.batchId,
    senderId:         msg.senderId,
    senderName:       msg.senderName,
    senderRole:       msg.senderRole,
    type:             msg.type,
    content:          msg.content,
    createdAt:        msg.createdAt,
    file:             msg.file,
    totalStudents:    msg.totalStudents,
    downloadedCount:  msg.downloadedCount,
    readerCount:      msg.readerCount,
    firstReader:      msg.firstReader,
  );

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final sender  = json['sender']           as Map<String, dynamic>? ?? {};
    final summary = json['delivery_summary'] as Map<String, dynamic>? ?? {};

    return ChatMessage(
      id:               json['id']         as String,
      batchId:          json['batch_id']   as String,
      senderId:         sender['id']       as String? ?? '',
      senderName:       sender['name']     as String? ?? 'Unknown',
      senderRole:       sender['role']     as String? ?? 'student',
      type:             json['type']       as String,
      content:          json['content']    as String,
      createdAt:        DateTime.parse(json['created_at'] as String),
      file:             json['file']       as Map<String, dynamic>?,
      isDeleted:        json['is_deleted'] as bool? ?? false,
      totalStudents:   (summary['total_students']   as int?) ?? 0,
      downloadedCount: (summary['downloaded_count'] as int?) ?? 0,
      readerCount:     (summary['reader_count']     as int?) ?? 0,
      firstReader:      summary['first_reader']     as Map<String, dynamic>?,
    );
  }
}

// ── Chat State ────────────────────────────────────────────────────────────────

class _ChatState {
  const _ChatState({
    this.messages         = const [],
    this.isLoadingHistory = false,
    this.hasMoreHistory   = true,
    this.nextCursor,
    this.typingUsers      = const {},
    this.isSending        = false,
    this.error,
  });

  final List<ChatMessage> messages;
  final bool              isLoadingHistory;
  final bool              hasMoreHistory;
  final String?           nextCursor;
  final Set<String>       typingUsers;
  final bool              isSending;
  final String?           error;

  _ChatState copyWith({
    List<ChatMessage>? messages,
    bool?              isLoadingHistory,
    bool?              hasMoreHistory,
    String?            nextCursor,
    Set<String>?       typingUsers,
    bool?              isSending,
    String?            error,
    bool               clearError = false,
  }) =>
      _ChatState(
        messages:         messages         ?? this.messages,
        isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
        hasMoreHistory:   hasMoreHistory   ?? this.hasMoreHistory,
        nextCursor:       nextCursor       ?? this.nextCursor,
        typingUsers:      typingUsers      ?? this.typingUsers,
        isSending:        isSending        ?? this.isSending,
        error:            clearError ? null : error ?? this.error,
      );
}

// ── Chat Notifier ─────────────────────────────────────────────────────────────

class _ChatNotifier extends StateNotifier<_ChatState> {
  _ChatNotifier({
    required this.batchId,
    required this.chatRepository,
    required this.socketService,
    required this.currentUserId,
    required this.currentUserRole,
  }) : super(const _ChatState()) {
    _init();
  }

  final String          batchId;
  final ChatRepository  chatRepository;
  final SocketService   socketService;
  final String          currentUserId;
  final String          currentUserRole;

  StreamSubscription<SocketMessage>?        _messageSub;
  StreamSubscription<TypingEvent>?          _typingSub;
  StreamSubscription<Map<String, dynamic>>? _deletedSub;
  StreamSubscription<Map<String, dynamic>>? _autoDeletedSub;
  StreamSubscription<DeliveryUpdate>?       _deliverySub;
  StreamSubscription<ReadUpdate>?           _readSub;
  Timer?                                    _typingTimer;

  Future<void> _init() async {
    _messageSub     = socketService.messages.listen(_onNewMessage);
    _typingSub      = socketService.typingEvents.listen(_onTypingEvent);
    _deletedSub     = socketService.deletedMessages.listen(_onMessageDeleted);
    _autoDeletedSub = socketService.autoDeletedMessages.listen(_onAutoDeleted);
    _deliverySub    = socketService.deliveryUpdates.listen(_onDeliveryUpdate);
    _readSub        = socketService.readUpdates.listen(_onReadUpdate);
    await loadHistory();
  }

  // ── Load History ────────────────────────────────────────────────────────────
  Future<void> loadHistory({bool loadMore = false}) async {
    if (state.isLoadingHistory) return;
    if (loadMore && !state.hasMoreHistory) return;

    state = state.copyWith(isLoadingHistory: true);

    final result = await chatRepository.getMessages(
      batchId: batchId,
      before:  loadMore ? state.nextCursor : null,
      limit:   AppConstants.chatPageSize,
    );

    if (result.isSuccess) {
      final resp    = result.data!;
      final fetched = resp.messages
          .map((m) => ChatMessage.fromJson(m))
          .toList();

      final merged = loadMore
          ? [...state.messages, ...fetched]
          : fetched;

      state = state.copyWith(
        messages:         merged,
        isLoadingHistory: false,
        hasMoreHistory:   resp.hasMore,
        nextCursor:       resp.nextCursor,
      );
    } else {
      state = state.copyWith(
        isLoadingHistory: false,
        error:            result.error,
      );
    }
  }

  // ── New Message ─────────────────────────────────────────────────────────────
  void _onNewMessage(SocketMessage socketMsg) {
    if (socketMsg.batchId != batchId) return;

    final incoming = ChatMessage.fromSocketMessage(socketMsg);

    final optimisticIndex = state.messages.indexWhere(
      (m) => m.isOptimistic && m.id == socketMsg.clientMessageId,
    );

    List<ChatMessage> updated;
    if (optimisticIndex >= 0) {
      updated = [...state.messages];
      updated[optimisticIndex] = incoming;
    } else {
      if (state.messages.any((m) => m.id == incoming.id)) return;
      updated = [incoming, ...state.messages];
    }

    state = state.copyWith(messages: updated);

    // Student confirms delivery immediately on receive
    if (currentUserRole == AppConstants.roleStudent) {
      socketService.confirmDelivered(socketMsg.id, batchId);
      socketService.markRead(batchId, socketMsg.id);
    }
  }

  // ── Delivery Update ─────────────────────────────────────────────────────────
  void _onDeliveryUpdate(DeliveryUpdate event) {
    if (event.batchId != batchId) return;
    final updated = state.messages.map((m) {
      if (m.id == event.messageId) {
        m.downloadedCount = event.downloadedCount;
        m.totalStudents   = event.totalStudents;
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
  }

  // ── Read Update ─────────────────────────────────────────────────────────────
  void _onReadUpdate(ReadUpdate event) {
    if (event.batchId != batchId) return;
    final updated = state.messages.map((m) {
      if (m.id == event.messageId) {
        m.readerCount = event.readerCount;
        if (event.firstReader != null) {
          m.firstReader = event.firstReader;
        }
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
  }

  // ── Auto Deleted ────────────────────────────────────────────────────────────
  void _onAutoDeleted(Map<String, dynamic> data) {
    final msgId  = data['message_id'] as String?;
    final btchId = data['batch_id']   as String?;
    if (msgId == null || btchId != batchId) return;

    // Remove from local list (server has cleaned it up)
    final updated = state.messages.where((m) => m.id != msgId).toList();
    state = state.copyWith(messages: updated);
  }

  // ── Send Message ────────────────────────────────────────────────────────────
  Future<void> sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;

    final clientMsgId = const Uuid().v4();

    final optimistic = ChatMessage(
      id:           clientMsgId,
      batchId:      batchId,
      senderId:     currentUserId,
      senderName:   'You',
      senderRole:   currentUserRole,
      type:         'text',
      content:      text.trim(),
      createdAt:    DateTime.now(),
      isOptimistic: true,
    );

    state = state.copyWith(messages: [optimistic, ...state.messages]);

    socketService.sendMessage(
      batchId:          batchId,
      type:             'text',
      encryptedContent: text.trim(),
      clientMessageId:  clientMsgId,
      onAck: (ack) {
        if (!(ack['success'] as bool? ?? false)) {
          _removeOptimistic(clientMsgId);
        }
      },
    );
  }

  Future<void> sendFileMessage({
    required String fileRecordId,
    required String type,
    required String metadata,
  }) async {
    socketService.sendMessage(
      batchId:          batchId,
      type:             type,
      encryptedContent: metadata,
      fileRecordId:     fileRecordId,
    );
  }

  // ── Delete ──────────────────────────────────────────────────────────────────
  Future<void> deleteMessage(String messageId) async {
    if (currentUserRole != AppConstants.roleTeacher) return;

    final result = await chatRepository.deleteMessage(
      batchId:   batchId,
      messageId: messageId,
    );

    if (result.isSuccess) {
      final updated = state.messages.map((m) {
        if (m.id == messageId) {
          m.isDeleted = true;
          m.content   = '[Message deleted by admin]';
        }
        return m;
      }).toList();
      state = state.copyWith(messages: updated);
    }
  }

  // ── Typing ──────────────────────────────────────────────────────────────────
  void onTyping() {
    socketService.startTyping(batchId);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      socketService.stopTyping(batchId);
    });
  }

  void _onTypingEvent(TypingEvent event) {
    if (event.userId == currentUserId) return;
    if (event.batchId != batchId) return;
    final updated = Set<String>.from(state.typingUsers);
    if (event.isTyping) updated.add(event.userId);
    else updated.remove(event.userId);
    state = state.copyWith(typingUsers: updated);
  }

  void _onMessageDeleted(Map<String, dynamic> data) {
    final msgId  = data['message_id'] as String?;
    final btchId = data['batch_id']   as String?;
    if (msgId == null || btchId != batchId) return;

    final updated = state.messages.map((m) {
      if (m.id == msgId) {
        m.isDeleted = true;
        m.content   = '[Message deleted by admin]';
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
  }

  void _removeOptimistic(String clientMsgId) {
    final updated = state.messages
        .where((m) => !(m.isOptimistic && m.id == clientMsgId))
        .toList();
    state = state.copyWith(messages: updated);
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _typingSub?.cancel();
    _deletedSub?.cancel();
    _autoDeletedSub?.cancel();
    _deliverySub?.cancel();
    _readSub?.cancel();
    _typingTimer?.cancel();
    socketService.stopTyping(batchId);
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final _chatNotifierProvider = StateNotifierProvider.autoDispose
    .family<_ChatNotifier, _ChatState, String>(
  (ref, batchId) {
    final authState = ref.watch(authStateProvider);
    final socket    = ref.watch(socketServiceProvider);
    final chatRepo  = ChatRepository(apiClient: ref.watch(apiClientProvider));

    return _ChatNotifier(
      batchId:         batchId,
      chatRepository:  chatRepo,
      socketService:   socket,
      currentUserId:   authState.userId ?? '',
      currentUserRole: authState.role   ?? AppConstants.roleStudent,
    );
  },
);

// ── Chat Page ─────────────────────────────────────────────────────────────────

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    super.key,
    required this.batchId,
    required this.batchName,
  });

  final String batchId;
  final String batchName;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _scrollController = ScrollController();
  final _msgController    = TextEditingController();
  final _focusNode        = FocusNode();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(socketServiceProvider).joinBatch(widget.batchId);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _msgController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(_chatNotifierProvider(widget.batchId).notifier)
          .loadHistory(loadMore: true);
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();
    await ref.read(_chatNotifierProvider(widget.batchId).notifier)
        .sendTextMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(_chatNotifierProvider(widget.batchId));
    final authState = ref.watch(authStateProvider);
    final isTeacher = authState.isTeacher;
    final theme     = Theme.of(context);
    final currentId = authState.userId ?? '';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.batchName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (chatState.typingUsers.isNotEmpty)
              Text(
                'typing...',
                style: theme.textTheme.labelSmall?.copyWith(
                  color:     AppTheme.primaryTeal,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              Text(
                'Batch Chat',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon:      const Icon(Icons.folder_outlined),
            tooltip:   'Files',
            onPressed: () => context.go('/files/${widget.batchId}'),
          ),
        ],
      ),

      body: Column(
        children: [
          Expanded(
            child: chatState.messages.isEmpty && chatState.isLoadingHistory
                ? const Center(child: CircularProgressIndicator())
                : chatState.messages.isEmpty
                    ? _EmptyChatState()
                    : ListView.builder(
                        controller: _scrollController,
                        reverse:    true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical:   8,
                        ),
                        itemCount: chatState.messages.length +
                            (chatState.isLoadingHistory ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == chatState.messages.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child:   CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          }

                          final msg       = chatState.messages[index];
                          final isOwn     = msg.senderId == currentId;
                          final showAvatar = !isOwn &&
                              (index == chatState.messages.length - 1 ||
                               chatState.messages[index + 1].senderId !=
                                   msg.senderId);

                          return MessageBubble(
                            message:    msg,
                            isOwn:      isOwn,
                            showAvatar: showAvatar,
                            isTeacher:  isTeacher,
                            batchId:    widget.batchId,
                            chatRepository: ChatRepository(
                              apiClient: ref.read(apiClientProvider),
                            ),
                            onLongPress: isTeacher && !msg.isDeleted
                                ? () => _showDeleteDialog(context, msg.id)
                                : null,
                          ).animate(
                            delay: Duration(
                              milliseconds: index < 5 ? index * 30 : 0,
                            ),
                          ).fadeIn(duration: 200.ms);
                        },
                      ),
          ),

          ChatInputBar(
            controller: _msgController,
            focusNode:  _focusNode,
            batchId:    widget.batchId,
            isTeacher:  isTeacher,
            onSend:     _sendMessage,
            onTyping:   () => ref
                .read(_chatNotifierProvider(widget.batchId).notifier)
                .onTyping(),
            onFileSent: (fileRecordId, type, metadata) {
              ref.read(_chatNotifierProvider(widget.batchId).notifier)
                  .sendFileMessage(
                    fileRecordId: fileRecordId,
                    type:         type,
                    metadata:     metadata,
                  );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteDialog(BuildContext context, String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Delete Message'),
        content: const Text('Delete this message for everyone?\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:     const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(_chatNotifierProvider(widget.batchId).notifier)
          .deleteMessage(messageId);
    }
  }
}

class _EmptyChatState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.chat_bubble_outline_rounded,
          size:  64,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
        ),
        const SizedBox(height: 16),
        Text(
          'No messages yet',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Be the first to say hello!',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ],
    ),
  );
}