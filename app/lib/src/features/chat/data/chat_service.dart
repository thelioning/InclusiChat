import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_service_legacy.dart' as legacy;

export 'chat_service_legacy.dart' hide ChatService;

/// Capa segura de almacenamiento multimedia y estado de chat para InclusiChat.
///
/// Conserva la lógica estable del servicio original y sustituye el manejo de
/// fotos y notas de voz para usar el bucket privado `chat-media`. También
/// mantiene las señales de llamada fuera de Chats y separa el estado privado
/// "ya lo leí" del receipt que puede ver el remitente.
class ChatService extends legacy.ChatService {
  ChatService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client,
        super(client: client);

  final SupabaseClient _client;

  static ValueNotifier<legacy.UserProfileData?> get currentUserProfileNotifier =>
      legacy.ChatService.currentUserProfileNotifier;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('No authenticated user');
    return id;
  }

  bool _isCallSignal(Map<String, dynamic> row) {
    final metadata = row['metadata'];
    return metadata is Map && metadata['call_signal'] == true;
  }

  bool _isVisibleChatMessage(Map<String, dynamic> row) {
    if (row['is_deleted'] == true || _isCallSignal(row)) return false;

    final metadata = row['metadata'];
    if (metadata is Map && metadata['deleted_for'] is List) {
      final deletedFor = metadata['deleted_for'] as List;
      if (deletedFor.contains(_userId)) return false;
    }
    return true;
  }

  DateTime _messageDate(dynamic value, DateTime fallback) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ?? fallback;
  }

  int _receiptRank(String status) {
    switch (status) {
      case 'read':
        return 3;
      case 'delivered':
        return 2;
      case 'sent':
        return 1;
      default:
        return 0;
    }
  }

  Future<bool> getReadReceiptsEnabled() async {
    try {
      final row = await _client
          .from('privacy_settings')
          .select('read_receipts_enabled')
          .eq('user_id', _userId)
          .maybeSingle();
      return row?['read_receipts_enabled'] as bool? ?? true;
    } catch (e) {
      debugPrint('Read receipt preference load error: $e');
      return true;
    }
  }

  Future<void> setReadReceiptsEnabled(bool enabled) async {
    await _client.from('privacy_settings').upsert({
      'user_id': _userId,
      'read_receipts_enabled': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }

  Future<Set<String>> _loadPrivateReadIds(List<String> incomingIds) async {
    final readIds = <String>{};
    if (incomingIds.isEmpty) return readIds;

    try {
      final rows = await _client
          .from('message_read_states')
          .select('message_id')
          .eq('user_id', _userId)
          .inFilter('message_id', incomingIds);
      for (final row in rows as List) {
        readIds.add(row['message_id'].toString());
      }
      return readIds;
    } catch (e) {
      // Compatibilidad temporal con entornos que todavía no tengan la
      // migración de message_read_states.
      debugPrint('Private read state fallback: $e');
      final receiptRows = await _client
          .from('message_receipts')
          .select('message_id,status')
          .eq('user_id', _userId)
          .inFilter('message_id', incomingIds);
      for (final receipt in receiptRows as List) {
        if (receipt['status']?.toString() == 'read') {
          readIds.add(receipt['message_id'].toString());
        }
      }
      return readIds;
    }
  }

  @override
  Future<void> markMessageRead(String messageId) async {
    var privateStateStored = false;
    try {
      await _client.from('message_read_states').upsert({
        'message_id': messageId,
        'user_id': _userId,
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'message_id,user_id');
      privateStateStored = true;
    } catch (e) {
      debugPrint('Private read state write fallback: $e');
    }

    // En un entorno anterior a la migración se conserva el comportamiento
    // histórico para no romper la lectura ni los badges.
    if (!privateStateStored) {
      await super.markMessageRead(messageId);
      return;
    }

    if (await getReadReceiptsEnabled()) {
      await super.markMessageRead(messageId);
      return;
    }

    // La lectura queda guardada de forma privada, pero el remitente solo debe
    // conocer que el mensaje fue entregado. Nunca degradamos un receipt que ya
    // había sido publicado como read antes de desactivar la preferencia.
    try {
      final existing = await _client
          .from('message_receipts')
          .select('status')
          .eq('message_id', messageId)
          .eq('user_id', _userId)
          .maybeSingle();
      if (existing?['status']?.toString() != 'read') {
        await _client.from('message_receipts').upsert({
          'message_id': messageId,
          'user_id': _userId,
          'status': 'delivered',
          'status_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'message_id,user_id');
      }
    } catch (e) {
      debugPrint('Delivered receipt preservation error: $e');
    }
  }

  String? _previewFromContent(String? content) {
    if (content == null) return null;

    if (content.startsWith('{')) {
      try {
        final decodedValue = jsonDecode(content);
        if (decodedValue is Map) {
          final decoded = Map<String, dynamic>.from(decodedValue);
          if (decoded['audio_path'] != null || decoded['audio_url'] != null) {
            final duration = decoded['duration'] as int? ?? 0;
            final minutes = duration ~/ 60;
            final seconds = (duration % 60).toString().padLeft(2, '0');
            return '🎤 Nota de voz ($minutes:$seconds)';
          }
          if (decoded['image_path'] != null ||
              decoded['image_url'] != null ||
              decoded['image_base64'] != null) {
            final caption = (decoded['caption'] as String?)?.trim() ?? '';
            return caption.isNotEmpty ? '📷 $caption' : '📷 Foto';
          }
        }
      } catch (_) {}
    }

    if (content.contains('[IMAGE_URL]')) {
      final parts = content.split('|||');
      if (parts.length > 1 && parts[1].trim().isNotEmpty) {
        return '📷 ${parts[1].trim()}';
      }
      return '📷 Foto';
    }

    return content;
  }

  String _extensionFromPath(String filePath, String fallback) {
    final normalized = filePath.replaceAll('\\', '/');
    final fileName = normalized.split('/').last;
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return fallback;

    final extension = fileName.substring(dot + 1).toLowerCase();
    if (!RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension)) return fallback;
    return extension;
  }

  String _contentTypeFor(String extension, {required bool audio}) {
    if (audio) {
      switch (extension) {
        case 'm4a':
        case 'mp4':
          return 'audio/mp4';
        case 'aac':
          return 'audio/aac';
        case 'mp3':
          return 'audio/mpeg';
        case 'wav':
          return 'audio/wav';
        default:
          return 'application/octet-stream';
      }
    }

    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  Future<String> _storePrivateMedia({
    required String conversationId,
    required String filePath,
    required String kind,
    required String fallbackExtension,
    required bool audio,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception(
        'El archivo multimedia ya no está disponible en el dispositivo.',
      );
    }

    final extension = _extensionFromPath(filePath, fallbackExtension);
    final objectPath =
        '$conversationId/$_userId/${kind}_${DateTime.now().microsecondsSinceEpoch}.$extension';

    await _client.storage.from('chat-media').upload(
      objectPath,
      file,
      fileOptions: FileOptions(
        upsert: false,
        contentType: _contentTypeFor(extension, audio: audio),
      ),
    );

    return objectPath;
  }

  Future<Map<String, dynamic>> _resolvePrivateMedia(
    Map<String, dynamic> row,
  ) async {
    final content = row['content'];
    if (content is! String || !content.startsWith('{')) return row;

    try {
      final decodedValue = jsonDecode(content);
      if (decodedValue is! Map) return row;

      final decoded = Map<String, dynamic>.from(decodedValue);
      var changed = false;

      final imagePath = decoded['image_path'] as String?;
      if (imagePath != null &&
          imagePath.isNotEmpty &&
          decoded['image_url'] == null) {
        decoded['image_url'] = await _client.storage
            .from('chat-media')
            .createSignedUrl(imagePath, 21600);
        changed = true;
      }

      final audioPath = decoded['audio_path'] as String?;
      if (audioPath != null &&
          audioPath.isNotEmpty &&
          decoded['audio_url'] == null) {
        decoded['audio_url'] = await _client.storage
            .from('chat-media')
            .createSignedUrl(audioPath, 21600);
        changed = true;
      }

      if (!changed) return row;
      return <String, dynamic>{...row, 'content': jsonEncode(decoded)};
    } catch (e) {
      debugPrint('Private media URL error: $e');
      return row;
    }
  }

  @override
  Future<List<legacy.ConversationSummary>> loadConversations() async {
    final baseConversations = await super.loadConversations();
    if (baseConversations.isEmpty) return baseConversations;

    final conversationIds = baseConversations.map((item) => item.id).toList();

    try {
      final rawRows = await _client
          .from('messages')
          .select(
            'id,conversation_id,sender_id,content,created_at,metadata,is_deleted',
          )
          .inFilter('conversation_id', conversationIds)
          .order('created_at', ascending: false);

      final chatRows = (rawRows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .where(_isVisibleChatMessage)
          .toList();

      final latestByConversation = <String, Map<String, dynamic>>{};
      for (final row in chatRows) {
        latestByConversation.putIfAbsent(
          row['conversation_id'].toString(),
          () => row,
        );
      }

      final incomingIds = chatRows
          .where((row) => row['sender_id']?.toString() != _userId)
          .map((row) => row['id'].toString())
          .toList();

      final readIds = await _loadPrivateReadIds(incomingIds);

      final unreadByConversation = <String, int>{};
      for (final row in chatRows) {
        if (row['sender_id']?.toString() == _userId) continue;
        if (readIds.contains(row['id'].toString())) continue;
        final conversationId = row['conversation_id'].toString();
        unreadByConversation.update(
          conversationId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }

      final latestOutgoingIds = latestByConversation.values
          .where((row) => row['sender_id']?.toString() == _userId)
          .map((row) => row['id'].toString())
          .toList();

      final outgoingReceiptStatus = <String, String>{};
      if (latestOutgoingIds.isNotEmpty) {
        final receiptRows = await _client
            .from('message_receipts')
            .select('message_id,status')
            .neq('user_id', _userId)
            .inFilter('message_id', latestOutgoingIds);
        for (final receipt in receiptRows as List) {
          final messageId = receipt['message_id'].toString();
          final status = receipt['status']?.toString() ?? 'sent';
          final current = outgoingReceiptStatus[messageId];
          if (current == null || _receiptRank(status) > _receiptRank(current)) {
            outgoingReceiptStatus[messageId] = status;
          }
        }
      }

      final createdRows = await _client
          .from('conversations')
          .select('id,created_at')
          .inFilter('id', conversationIds);
      final createdAtByConversation = <String, DateTime>{};
      for (final row in createdRows as List) {
        final id = row['id'].toString();
        final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
        if (createdAt != null) createdAtByConversation[id] = createdAt;
      }

      final rebuilt = baseConversations.map((item) {
        final latest = latestByConversation[item.id];
        final isMine = latest?['sender_id']?.toString() == _userId;
        final messageId = latest?['id']?.toString();
        final fallbackDate = createdAtByConversation[item.id] ?? item.lastActivityAt;
        final activityDate = latest == null
            ? fallbackDate
            : _messageDate(latest['created_at'], fallbackDate);

        return legacy.ConversationSummary(
          id: item.id,
          title: item.title,
          type: item.type,
          lastActivityAt: activityDate,
          unreadCount: unreadByConversation[item.id] ?? 0,
          avatarUrl: item.avatarUrl,
          lastMessage: _previewFromContent(latest?['content'] as String?),
          isLastMessageMine: isMine,
          lastMessageReceiptStatus: isMine && messageId != null
              ? (outgoingReceiptStatus[messageId] ?? 'sent')
              : null,
          isStarred: item.isStarred,
        );
      }).toList();

      rebuilt.sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
      return rebuilt;
    } catch (e) {
      debugPrint('Error separating call signals from chat list: $e');
      return baseConversations;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> loadMessages(String conversationId) async {
    final rows = await super.loadMessages(conversationId);
    final visibleRows = rows
        .map((row) => Map<String, dynamic>.from(row))
        .where(_isVisibleChatMessage)
        .toList();
    return Future.wait(visibleRows.map(_resolvePrivateMedia));
  }

  @override
  Stream<List<Map<String, dynamic>>> watchMessages(String conversationId) {
    return super.watchMessages(conversationId).asyncMap((rows) {
      final visibleRows = rows
          .map((row) => Map<String, dynamic>.from(row))
          .where(_isVisibleChatMessage)
          .toList();
      return Future.wait(visibleRows.map(_resolvePrivateMedia));
    });
  }

  /// Mantiene la firma usada por la UI. La subida real se hace cuando ya
  /// conocemos la conversación, dentro de [sendImageMessage].
  @override
  Future<String> uploadImageFile(String filePath) async => filePath;

  @override
  Future<void> sendImageMessage({
    required String conversationId,
    required String imageUrl,
    String? caption,
  }) async {
    final cleanCaption = caption?.trim() ?? '';
    final isLegacyRemote =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');

    final payload = <String, dynamic>{'caption': cleanCaption};
    if (isLegacyRemote) {
      payload['image_url'] = imageUrl;
    } else {
      payload['image_path'] = await _storePrivateMedia(
        conversationId: conversationId,
        filePath: imageUrl,
        kind: 'image',
        fallbackExtension: 'jpg',
        audio: false,
      );
    }

    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': _userId,
      'type': 'image',
      'content': jsonEncode(payload),
    });

    try {
      await _client.from('conversations').update({
        'last_activity_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', conversationId);
    } catch (_) {}
  }

  /// Igual que con imágenes: la subida se difiere hasta conocer la
  /// conversación, dentro de [sendAudioMessage].
  @override
  Future<String> uploadAudioFile(String filePath) async => filePath;

  @override
  Future<void> sendAudioMessage({
    required String conversationId,
    required String audioUrl,
    required int durationSeconds,
  }) async {
    final isLegacyRemote =
        audioUrl.startsWith('http://') || audioUrl.startsWith('https://');

    final payload = <String, dynamic>{'duration': durationSeconds};
    if (isLegacyRemote) {
      payload['audio_url'] = audioUrl;
    } else {
      payload['audio_path'] = await _storePrivateMedia(
        conversationId: conversationId,
        filePath: audioUrl,
        kind: 'audio',
        fallbackExtension: 'm4a',
        audio: true,
      );
    }

    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': _userId,
      'type': 'audio',
      'content': jsonEncode(payload),
    });

    try {
      await _client.from('conversations').update({
        'last_activity_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', conversationId);
    } catch (_) {}
  }
}
