import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_service_legacy.dart' as legacy;

export 'chat_service_legacy.dart' hide ChatService;

/// Capa segura de almacenamiento multimedia para InclusiChat.
///
/// Conserva toda la lógica estable del servicio original y sustituye únicamente
/// el manejo de fotos y notas de voz para usar el bucket privado `chat-media`.
class ChatService extends legacy.ChatService {
  ChatService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client,
        super(client: client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('No authenticated user');
    return id;
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
    final conversations = await super.loadConversations();

    return conversations.map((item) {
      var preview = item.lastMessage;
      if (preview != null && preview.startsWith('{')) {
        try {
          final decodedValue = jsonDecode(preview);
          if (decodedValue is Map) {
            final decoded = Map<String, dynamic>.from(decodedValue);
            if (decoded['audio_path'] != null) {
              final duration = decoded['duration'] as int? ?? 0;
              final minutes = duration ~/ 60;
              final seconds = (duration % 60).toString().padLeft(2, '0');
              preview = '🎤 Nota de voz ($minutes:$seconds)';
            } else if (decoded['image_path'] != null) {
              final caption = (decoded['caption'] as String?)?.trim() ?? '';
              preview = caption.isNotEmpty ? '📷 $caption' : '📷 Foto';
            }
          }
        } catch (_) {}
      }

      return legacy.ConversationSummary(
        id: item.id,
        title: item.title,
        type: item.type,
        lastActivityAt: item.lastActivityAt,
        unreadCount: item.unreadCount,
        avatarUrl: item.avatarUrl,
        lastMessage: preview,
        isLastMessageMine: item.isLastMessageMine,
        lastMessageReceiptStatus: item.lastMessageReceiptStatus,
        isStarred: item.isStarred,
      );
    }).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> loadMessages(String conversationId) async {
    final rows = await super.loadMessages(conversationId);
    return Future.wait(
      rows.map((row) => _resolvePrivateMedia(Map<String, dynamic>.from(row))),
    );
  }

  @override
  Stream<List<Map<String, dynamic>>> watchMessages(String conversationId) {
    return super.watchMessages(conversationId).asyncMap(
      (rows) => Future.wait(
        rows.map((row) => _resolvePrivateMedia(Map<String, dynamic>.from(row))),
      ),
    );
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
