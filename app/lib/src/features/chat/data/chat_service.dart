import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    required this.type,
    required this.lastActivityAt,
    this.unreadCount = 0,
    this.avatarUrl,
    this.lastMessage,
    this.isLastMessageMine = false,
    this.lastMessageReceiptStatus,
    this.isStarred = false,
  });

  final String id;
  final String title;
  final String type; // 'direct', 'circle', 'collective'
  final String? avatarUrl;
  final String? lastMessage;
  final bool isLastMessageMine;
  final String? lastMessageReceiptStatus;
  final DateTime lastActivityAt;
  final int unreadCount;
  final bool isStarred;
}

class ContactProfile {
  const ContactProfile({
    required this.id,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.bio,
    this.pronouns,
    this.isVerified = false,
    this.circleCategory = 'general',
  });

  final String id;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final String? bio;
  final String? pronouns;
  final bool isVerified;
  final String circleCategory;
}

class ContactRequestItem {
  const ContactRequestItem({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
    required this.profile,
    required this.isIncoming,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final String status;
  final DateTime createdAt;
  final ContactProfile profile;
  final bool isIncoming;
}

class UserProfileData {
  const UserProfileData({
    required this.id,
    required this.displayName,
    required this.username,
    this.avatarUrl,
    this.bio,
    this.pronouns,
    this.isVerified = false,
  });

  final String id;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final String? bio;
  final String? pronouns;
  final bool isVerified;
}

class ChatService {
  ChatService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const maxTextCharacters = 4000;
  static const maxCaptionCharacters = 1000;
  static const maxVoiceNoteSeconds = 600;
  static const maxMediaBytes = 15 * 1024 * 1024;
  static final currentUserProfileNotifier =
      ValueNotifier<UserProfileData?>(null);

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('No authenticated user');
    return id;
  }

  String get currentUserId => _userId;

  Future<UserProfileData> loadUserProfile() async {
    final row =
        await _client.from('profiles').select().eq('id', _userId).maybeSingle();

    if (row == null) {
      final user = _client.auth.currentUser;
      final rawName =
          user?.userMetadata?['display_name'] as String? ?? 'Usuario';
      final rawUsername = user?.userMetadata?['username'] as String? ??
          'user_${_userId.substring(0, 6)}';
      final fallbackProfile = UserProfileData(
        id: _userId,
        displayName: rawName,
        username: rawUsername,
      );
      currentUserProfileNotifier.value = fallbackProfile;
      return fallbackProfile;
    }

    final profile = UserProfileData(
      id: row['id'] as String,
      displayName: row['display_name'] as String? ?? 'Usuario',
      username: row['username'] as String? ?? '',
      avatarUrl: row['avatar_url'] as String?,
      bio: row['bio'] as String?,
      pronouns: row['pronouns'] as String?,
      isVerified: row['is_verified'] as bool? ?? false,
    );
    currentUserProfileNotifier.value = profile;
    return profile;
  }

  Future<void> updateUserProfile({
    required String displayName,
    required String username,
    String? bio,
    String? pronouns,
    String? avatarUrl,
  }) async {
    final sanitizedUsername = username.trim().toLowerCase().replaceAll('@', '');
    await _client.from('profiles').upsert({
      'id': _userId,
      'display_name': displayName.trim(),
      'username': sanitizedUsername,
      'bio': bio?.trim(),
      'pronouns': pronouns?.trim(),
      'avatar_url': avatarUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });

    currentUserProfileNotifier.value = UserProfileData(
      id: _userId,
      displayName: displayName.trim(),
      username: sanitizedUsername,
      avatarUrl: avatarUrl,
      bio: bio?.trim(),
      pronouns: pronouns?.trim(),
      isVerified: currentUserProfileNotifier.value?.isVerified ?? false,
    );
  }

  DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString()) ?? DateTime.now();
  }

  Future<List<ConversationSummary>> loadConversations() async {
    try {
      final membershipRows = await _client
          .from('conversation_participants')
          .select('conversation_id,left_at,cleared_at')
          .eq('user_id', _userId);

      final activeMemberships = (membershipRows as List)
          .where((row) => row['left_at'] == null)
          .toList();
      final ids = activeMemberships
          .map<String>((row) => row['conversation_id'].toString())
          .toSet()
          .toList();
      final clearedAtByConversation = <String, DateTime?>{
        for (final row in activeMemberships)
          row['conversation_id'].toString(): row['cleared_at'] == null
              ? null
              : DateTime.tryParse(row['cleared_at'].toString()),
      };

      if (ids.isEmpty) return const [];

      final conversationRows =
          await _client.from('conversations').select().inFilter('id', ids);

      final participantRows = await _client
          .from('conversation_participants')
          .select('conversation_id,user_id,left_at')
          .inFilter('conversation_id', ids);

      final otherParticipants = (participantRows as List)
          .where((row) => row['user_id'] != _userId && row['left_at'] == null)
          .toList();

      final otherUserIds = otherParticipants
          .map<String>((row) => row['user_id'].toString())
          .toSet()
          .toList();

      final profileRows = otherUserIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await _client
              .from('profiles')
              .select('id,display_name,username,avatar_url')
              .inFilter('id', otherUserIds);

      final profiles = {
        for (final row in (profileRows as List)) row['id'].toString(): row
      };

      final partnerByConversation = <String, Map<String, dynamic>>{};
      for (final row in otherParticipants) {
        final cId = row['conversation_id'].toString();
        final uId = row['user_id'].toString();
        if (profiles.containsKey(uId)) {
          partnerByConversation[cId] = profiles[uId]!;
        }
      }

      final messageRows = (await _client
          .rpc('get_conversation_message_summaries')) as List<dynamic>;

      final visibleMessageRows = messageRows.where((row) {
        if (row['is_deleted'] == true) return false;
        final meta = row['metadata'];
        if (meta is Map && meta['deleted_for'] is List) {
          final deletedList = meta['deleted_for'] as List;
          if (deletedList.contains(_userId)) return false;
        }
        return true;
      }).toList();

      final latestMessage = <String, String?>{};
      final latestMessageSender = <String, String?>{};
      final latestMessageId = <String, String?>{};
      final latestReceiptStatus = <String, String?>{};
      final unreadByConversation = <String, int>{};

      for (final row in visibleMessageRows) {
        final cId = row['conversation_id'].toString();
        if (!latestMessage.containsKey(cId)) {
          final rawContent = row['content'] as String?;
          String? displayContent = rawContent;
          if (rawContent != null && rawContent.startsWith('{')) {
            try {
              final decoded = jsonDecode(rawContent) as Map;
              if (decoded.containsKey('audio_url')) {
                final dur = decoded['duration'] as int? ?? 0;
                final minutes = dur ~/ 60;
                final seconds = (dur % 60).toString().padLeft(2, '0');
                displayContent = '🎤 Nota de voz ($minutes:$seconds)';
              } else if (decoded.containsKey('image_url') ||
                  decoded.containsKey('image_base64')) {
                final cap = (decoded['caption'] as String?)?.trim() ?? '';
                displayContent = cap.isNotEmpty ? '📷 $cap' : '📷 Foto';
              } else if (decoded.containsKey('file_url')) {
                displayContent = '📄 ${decoded['file_name'] ?? 'Documento'}';
              }
            } catch (_) {
              displayContent = rawContent;
            }
          } else if (rawContent != null && rawContent.contains('[IMAGE_URL]')) {
            final parts = rawContent.split('|||');
            if (parts.length > 1 && parts[1].trim().isNotEmpty) {
              displayContent = '📷 ${parts[1].trim()}';
            } else {
              displayContent = '📷 Foto';
            }
          }
          latestMessage[cId] = displayContent;
          latestMessageSender[cId] = row['sender_id']?.toString();
          latestMessageId[cId] = row['id']?.toString();
          latestReceiptStatus[cId] = row['receipt_status']?.toString();
        }
        unreadByConversation[cId] = (row['unread_count'] as num?)?.toInt() ?? 0;
      }

      final results = (conversationRows as List).map((row) {
        final id = row['id'].toString();
        final partner = partnerByConversation[id];
        final customTitle = (row['title'] as String?)?.trim();
        final partnerName = (partner?['display_name'] as String?)?.trim();
        final partnerUsername = (partner?['username'] as String?)?.trim();

        final title = (customTitle != null && customTitle.isNotEmpty)
            ? customTitle
            : (partnerName != null && partnerName.isNotEmpty)
                ? partnerName
                : (partnerUsername != null && partnerUsername.isNotEmpty)
                    ? '@$partnerUsername'
                    : 'Conversación';

        final rawActivity = row['last_activity_at'] ?? row['created_at'];
        final activityDate = _parseDate(rawActivity);

        final isMine = latestMessageSender[id] == _userId;
        final lMsgId = latestMessageId[id];
        final receiptStatus =
            isMine && lMsgId != null ? latestReceiptStatus[id] ?? 'sent' : null;

        return ConversationSummary(
          id: id,
          type: row['type']?.toString() ?? 'direct',
          title: title,
          avatarUrl: (row['avatar_url'] ?? partner?['avatar_url']) as String?,
          lastMessage: latestMessage[id],
          isLastMessageMine: isMine,
          lastMessageReceiptStatus: receiptStatus,
          unreadCount: unreadByConversation[id] ?? 0,
          lastActivityAt: activityDate,
        );
      }).where((summary) {
        return clearedAtByConversation[summary.id] == null ||
            summary.lastMessage != null;
      }).toList();

      results.sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
      return results;
    } catch (e) {
      debugPrint('Error loading conversations: $e');
      return const [];
    }
  }

  Future<List<ContactProfile>> loadContacts() async {
    final allIds = <String>{};
    final categoryById = <String, String>{};

    // 1. Contactos guardados en la tabla contacts
    try {
      final contactRows = await _client
          .from('contacts')
          .select('contact_user_id,circle_category')
          .eq('user_id', _userId);
      for (final r in (contactRows as List)) {
        final cid = r['contact_user_id'] as String?;
        if (cid != null && cid != _userId) {
          allIds.add(cid);
          categoryById[cid] = r['circle_category'] as String? ?? 'general';
        }
      }
    } catch (_) {}

    // 2. Solicitudes de contacto mutuas aceptadas
    try {
      final acceptedReqs = await _client
          .from('contact_requests')
          .select('sender_id,receiver_id')
          .eq('status', 'accepted')
          .or('sender_id.eq.$_userId,receiver_id.eq.$_userId');
      for (final r in (acceptedReqs as List)) {
        final sid = r['sender_id'] as String;
        final rid = r['receiver_id'] as String;
        final otherId = sid == _userId ? rid : sid;
        if (otherId != _userId) {
          allIds.add(otherId);
        }
      }
    } catch (_) {}

    // 3. Participantes de todas tus conversaciones activas (autodescubrimiento)
    try {
      final myPartRows = await _client
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', _userId)
          .isFilter('left_at', null);

      final myConvIds = (myPartRows as List)
          .map<String>((r) => r['conversation_id'] as String)
          .toList();

      if (myConvIds.isNotEmpty) {
        final otherPartRows = await _client
            .from('conversation_participants')
            .select('user_id')
            .inFilter('conversation_id', myConvIds)
            .neq('user_id', _userId)
            .isFilter('left_at', null);
        for (final r in (otherPartRows as List)) {
          final uid = r['user_id'] as String?;
          if (uid != null && uid != _userId) {
            allIds.add(uid);
          }
        }
      }
    } catch (_) {}

    if (allIds.isEmpty) return const [];

    try {
      final profiles = await _client
          .from('profiles')
          .select(
              'id,display_name,username,avatar_url,bio,pronouns,is_verified')
          .inFilter('id', allIds.toList())
          .order('display_name');

      return (profiles as List).map((row) {
        final id = row['id'] as String;
        return ContactProfile(
          id: id,
          displayName:
              (row['display_name'] as String?)?.trim().isNotEmpty == true
                  ? row['display_name'] as String
                  : 'Usuario de InclusiChat',
          username: row['username'] as String?,
          avatarUrl: row['avatar_url'] as String?,
          bio: row['bio'] as String?,
          pronouns: row['pronouns'] as String?,
          isVerified: row['is_verified'] as bool? ?? false,
          circleCategory: categoryById[id] ?? 'general',
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<ContactProfile>> searchProfiles(String query) async {
    final cleanQuery = query.trim().replaceAll('@', '');
    if (cleanQuery.isEmpty) return const [];

    try {
      final rpcResults = await _client.rpc(
        'search_profiles',
        params: {'query_text': cleanQuery},
      );
      if (rpcResults is List) {
        return rpcResults
            .map((r) => ContactProfile(
                  id: r['id'] as String,
                  displayName: r['display_name'] as String? ?? 'Usuario',
                  username: r['username'] as String?,
                  avatarUrl: r['avatar_url'] as String?,
                  isVerified: r['is_verified'] as bool? ?? false,
                ))
            .toList();
      }
    } catch (_) {
      // Fallback a consulta directa si la RPC aún no está creada
      final rows = await _client
          .from('profiles')
          .select('id,display_name,username,avatar_url,is_verified')
          .neq('id', _userId)
          .or('username.ilike.%$cleanQuery%,display_name.ilike.%$cleanQuery%')
          .limit(15);
      return (rows as List)
          .map((r) => ContactProfile(
                id: r['id'] as String,
                displayName: r['display_name'] as String? ?? 'Usuario',
                username: r['username'] as String?,
                avatarUrl: r['avatar_url'] as String?,
                isVerified: r['is_verified'] as bool? ?? false,
              ))
          .toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> sendContactRequest(String targetUsername) async {
    final cleanUsername =
        targetUsername.trim().toLowerCase().replaceAll('@', '');
    if (cleanUsername.isEmpty) {
      return {'success': false, 'message': 'Escribe un alias válido.'};
    }

    try {
      final res = await _client.rpc(
        'send_contact_request',
        params: {'target_username': cleanUsername},
      );
      if (res is Map) {
        final success = res['success'] as bool? ?? false;
        final msg = res['message'] as String? ?? 'Solicitud procesada';
        if (success || msg.contains('contactos') || msg.contains('mismo')) {
          return Map<String, dynamic>.from(res);
        }
      }
    } catch (_) {
      // Fallback a lógica directa si la RPC falla
    }

    try {
      final targetRows = await _client
          .from('profiles')
          .select('id,username,display_name')
          .or('username.ilike.$cleanUsername,username.ilike.@$cleanUsername')
          .limit(1);

      if ((targetRows as List).isEmpty) {
        return {
          'success': false,
          'message': 'Usuario @$cleanUsername no encontrado.'
        };
      }

      final target = targetRows.first;
      final targetId = target['id'] as String;
      final targetUName =
          (target['username'] as String? ?? cleanUsername).replaceAll('@', '');

      if (targetId == _userId) {
        return {'success': false, 'message': 'No puedes agregarte a ti mismo.'};
      }

      // 1. Verificar si ya son contactos directos
      final existingContact = await _client
          .from('contacts')
          .select('contact_user_id')
          .eq('user_id', _userId)
          .eq('contact_user_id', targetId)
          .maybeSingle();

      if (existingContact != null) {
        return {
          'success': false,
          'message': 'Este usuario ya está en tus contactos.'
        };
      }

      // 2. Verificar si ya existe una solicitud registrada entre ambos
      final existingReq = await _client
          .from('contact_requests')
          .select('id,sender_id,receiver_id,status')
          .or('and(sender_id.eq.$_userId,receiver_id.eq.$targetId),and(sender_id.eq.$targetId,receiver_id.eq.$_userId)')
          .maybeSingle();

      if (existingReq != null) {
        final status = existingReq['status'] as String? ?? 'pending';
        final senderId = existingReq['sender_id'] as String;
        if (status == 'accepted') {
          return {
            'success': false,
            'message': '@$targetUName ya forma parte de tus contactos.'
          };
        } else if (senderId == _userId) {
          return {
            'success': false,
            'message':
                'Ya enviaste una solicitud a @$targetUName. Está pendiente de aprobación.'
          };
        } else {
          return {
            'success': false,
            'message':
                '@$targetUName ya te envió una solicitud. Revisa la sección de solicitudes para aceptarla.'
          };
        }
      }

      // 3. Insertar nueva solicitud
      await _client.from('contact_requests').insert({
        'sender_id': _userId,
        'receiver_id': targetId,
        'status': 'pending',
      });

      return {
        'success': true,
        'message': 'Solicitud enviada a @$targetUName',
      };
    } catch (e) {
      final cleanErr = e
          .toString()
          .replaceAll('Exception:', '')
          .replaceAll('PostgrestException', '')
          .trim();
      return {
        'success': false,
        'message':
            cleanErr.isNotEmpty ? cleanErr : 'No se pudo enviar la solicitud.'
      };
    }
  }

  Future<List<ContactRequestItem>> loadContactRequests() async {
    final rows = await _client
        .from('contact_requests')
        .select()
        .or('sender_id.eq.$_userId,receiver_id.eq.$_userId')
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    if ((rows as List).isEmpty) return const [];

    final otherIds = rows
        .map<String>((r) => (r['sender_id'] == _userId
            ? r['receiver_id']
            : r['sender_id']) as String)
        .toSet()
        .toList();

    final profileRows = await _client
        .from('profiles')
        .select('id,display_name,username,avatar_url,is_verified')
        .inFilter('id', otherIds);

    final profileMap = {
      for (final p in profileRows)
        p['id'] as String: ContactProfile(
          id: p['id'] as String,
          displayName: p['display_name'] as String? ?? 'Usuario',
          username: p['username'] as String?,
          avatarUrl: p['avatar_url'] as String?,
          isVerified: p['is_verified'] as bool? ?? false,
        )
    };

    return rows.map((r) {
      final isIncoming = r['receiver_id'] == _userId;
      final otherId =
          isIncoming ? r['sender_id'] as String : r['receiver_id'] as String;
      final profile = profileMap[otherId] ??
          ContactProfile(
            id: otherId,
            displayName: 'Usuario de InclusiChat',
          );

      return ContactRequestItem(
        id: r['id'] as String,
        senderId: r['sender_id'] as String,
        receiverId: r['receiver_id'] as String,
        status: r['status'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
        profile: profile,
        isIncoming: isIncoming,
      );
    }).toList();
  }

  Future<bool> acceptContactRequest(String requestId) async {
    try {
      final res = await _client.rpc(
        'accept_contact_request',
        params: {'request_id': requestId},
      );
      if (res == true) return true;
    } catch (_) {}

    try {
      final req = await _client
          .from('contact_requests')
          .select('sender_id,receiver_id')
          .eq('id', requestId)
          .maybeSingle();

      if (req != null) {
        await _client.from('contact_requests').update({
          'status': 'accepted',
        }).eq('id', requestId);

        final senderId = req['sender_id'] as String;
        final receiverId = req['receiver_id'] as String;
        final targetContactId = _userId == receiverId ? senderId : receiverId;

        try {
          await _client.from('contacts').upsert({
            'user_id': _userId,
            'contact_user_id': targetContactId,
            'circle_category': 'general',
          });
        } catch (_) {}

        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> rejectContactRequest(String requestId) async {
    try {
      final res = await _client.rpc(
        'reject_contact_request',
        params: {'request_id': requestId},
      );
      if (res == true) return true;
    } catch (_) {}

    try {
      await _client.from('contact_requests').update({
        'status': 'rejected',
      }).eq('id', requestId);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> removeContact(String contactUserId) async {
    await _client
        .from('contacts')
        .delete()
        .eq('user_id', _userId)
        .eq('contact_user_id', contactUserId);
  }

  Future<String> createDirectConversation(String otherUserId) async {
    try {
      final result = await _client.rpc(
        'create_direct_conversation',
        params: {'other_user_id': otherUserId},
      );
      if (result != null && result.toString().isNotEmpty) {
        return result.toString();
      }
      throw const PostgrestException(
        message: 'La base de datos no devolvio la conversacion.',
      );
    } catch (e) {
      final clean = e
          .toString()
          .replaceAll('Exception:', '')
          .replaceAll('PostgrestException', '')
          .trim();
      throw Exception(
          clean.isNotEmpty ? clean : 'Error al conectar con el usuario');
    }
  }

  Future<List<Map<String, dynamic>>> loadMessages(String conversationId) async {
    try {
      final rows = await _client
          .from('messages')
          .select(
              'id,conversation_id,sender_id,type,content,created_at,metadata,is_deleted')
          .eq('conversation_id', conversationId)
          .eq('is_deleted', false)
          .order('created_at', ascending: false)
          .limit(200);
      return List<Map<String, dynamic>>.from(rows as List)
          .reversed
          .where((row) {
        if (row['is_deleted'] == true) return false;
        final meta = row['metadata'];
        if (meta is Map && meta['deleted_for'] is List) {
          final deletedList = meta['deleted_for'] as List;
          if (deletedList.contains(_userId)) return false;
        }
        return true;
      }).toList();
    } catch (_) {
      try {
        final rows = await _client
            .from('messages')
            .select('id,conversation_id,sender_id,type,content,created_at')
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: false)
            .limit(200);
        return List<Map<String, dynamic>>.from(rows as List).reversed.toList();
      } catch (_) {
        return const [];
      }
    }
  }

  Stream<List<Map<String, dynamic>>> watchMessages(String conversationId) {
    return Stream.fromFuture(_conversationClearedAt(conversationId))
        .asyncExpand((clearedAt) {
      return _client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(200)
          .map((rows) {
            final visibleRows = rows.where((row) {
              if (row['is_deleted'] == true) return false;
              if (clearedAt != null) {
                final createdAt =
                    DateTime.tryParse(row['created_at'].toString());
                if (createdAt == null || !createdAt.isAfter(clearedAt)) {
                  return false;
                }
              }
              final meta = row['metadata'];
              if (meta is Map && meta['deleted_for'] is List) {
                final deletedList = meta['deleted_for'] as List;
                if (deletedList.contains(_userId)) return false;
              }
              return true;
            }).toList();
            return visibleRows.reversed.toList();
          });
    });
  }

  Future<DateTime?> _conversationClearedAt(String conversationId) async {
    final row = await _client
        .from('conversation_participants')
        .select('cleared_at')
        .eq('conversation_id', conversationId)
        .eq('user_id', _userId)
        .maybeSingle();
    final value = row?['cleared_at'];
    return value == null ? null : DateTime.tryParse(value.toString());
  }

  Future<void> clearConversationForMe(String conversationId) async {
    await _client.rpc(
      'clear_conversation_for_me',
      params: {'target_conversation_id': conversationId},
    );
  }

  Stream<List<Map<String, dynamic>>> watchReceipts(
    Iterable<String> messageIds,
  ) {
    final ids = messageIds.toSet().take(200).toList(growable: false);
    if (ids.isEmpty) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _client
        .from('message_receipts')
        .stream(primaryKey: ['message_id', 'user_id'])
        .inFilter('message_id', ids)
        .limit(ids.length * 8);
  }

  Future<void> markMessageDelivered(String messageId) async {
    try {
      final existing = await _client
          .from('message_receipts')
          .select('status')
          .eq('message_id', messageId)
          .eq('user_id', _userId)
          .maybeSingle();
      if (existing == null) {
        await _client.from('message_receipts').upsert({
          'message_id': messageId,
          'user_id': _userId,
          'status': 'delivered',
          'status_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'message_id,user_id');
      }
    } catch (_) {}
  }

  Future<void> markMessageRead(String messageId) async {
    await _client.from('message_receipts').upsert({
      'message_id': messageId,
      'user_id': _userId,
      'status': 'read',
      'status_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'message_id,user_id');
  }

  Future<void> sendTextMessage({
    required String conversationId,
    required String content,
  }) async {
    final text = content.trim();
    if (text.isEmpty) return;
    if (text.length > maxTextCharacters) {
      throw ArgumentError(
          'El mensaje supera los $maxTextCharacters caracteres.');
    }

    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': _userId,
      'type': 'text',
      'content': text,
    });

    try {
      await _client.from('conversations').update({
        'last_activity_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', conversationId);
    } catch (_) {}
  }

  Future<void> deleteMessageForEveryone(String messageId) async {
    await _client.from('messages').update({
      'is_deleted': true,
      'content': '🚫 Este mensaje fue eliminado',
    }).eq('id', messageId);
  }

  Future<void> deleteMessageForMe(String messageId) async {
    final deleted = await _client.rpc(
      'delete_message_for_me',
      params: {'target_message_id': messageId},
    );
    if (deleted != true) {
      throw const PostgrestException(
        message: 'No se pudo ocultar el mensaje para este usuario.',
      );
    }
  }

  static const _mediaBucket = 'chat-media';

  Future<String> uploadImageFile(
    String filePath, {
    required String conversationId,
  }) async {
    try {
      final file = File(filePath);
      if (await file.length() > maxMediaBytes) {
        throw ArgumentError('La imagen supera el límite de 15 MB.');
      }
      final extension = _safeExtension(filePath, fallback: 'jpg');
      final objectPath =
          '$conversationId/$_userId/${DateTime.now().microsecondsSinceEpoch}.$extension';
      await _client.storage.from(_mediaBucket).upload(
            objectPath,
            file,
            fileOptions: const FileOptions(upsert: false),
          );
      return objectPath;
    } catch (e) {
      debugPrint('Upload error: $e');
      rethrow;
    }
  }

  Future<void> sendImageMessage({
    required String conversationId,
    required String imageUrl,
    String? caption,
  }) async {
    final cleanCaption = caption?.trim() ?? '';
    if (cleanCaption.length > maxCaptionCharacters) {
      throw ArgumentError(
        'El texto de la foto supera los $maxCaptionCharacters caracteres.',
      );
    }
    final payload = jsonEncode({
      'image_url': imageUrl,
      'caption': cleanCaption,
    });

    try {
      await _client.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': _userId,
        'type': 'image',
        'content': payload,
      });
    } catch (_) {
      await _client.storage.from(_mediaBucket).remove([imageUrl]);
      rethrow;
    }

    try {
      await _client.from('conversations').update({
        'last_activity_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', conversationId);
    } catch (_) {}
  }

  Future<void> sendImageToMultipleDestinations({
    required List<String> contactUserIds,
    required List<String> conversationIds,
    required String imagePath,
    String? caption,
  }) async {
    final targetConvIds = <String>{...conversationIds};
    for (final uId in contactUserIds) {
      final convId = await createDirectConversation(uId);
      targetConvIds.add(convId);
    }
    for (final convId in targetConvIds) {
      final imageUrl = await uploadImageFile(
        imagePath,
        conversationId: convId,
      );
      await sendImageMessage(
        conversationId: convId,
        imageUrl: imageUrl,
        caption: caption,
      );
    }
  }

  Future<String> uploadAudioFile(
    String filePath, {
    required String conversationId,
  }) async {
    try {
      final file = File(filePath);
      if (await file.length() > maxMediaBytes) {
        throw ArgumentError('La nota de voz supera el límite de 15 MB.');
      }
      final extension = _safeExtension(filePath, fallback: 'm4a');
      final objectPath =
          '$conversationId/$_userId/${DateTime.now().microsecondsSinceEpoch}.$extension';
      await _client.storage.from(_mediaBucket).upload(
            objectPath,
            file,
            fileOptions: const FileOptions(upsert: false),
          );
      return objectPath;
    } catch (e) {
      debugPrint('Audio upload error: $e');
      rethrow;
    }
  }

  Future<String> uploadDocumentFile(
    String filePath, {
    required String conversationId,
  }) async {
    final file = File(filePath);
    if (await file.length() > maxMediaBytes) {
      throw ArgumentError('El documento supera el límite de 15 MB.');
    }
    final extension = _safeExtension(filePath, fallback: 'bin');
    const allowedExtensions = {
      'pdf',
      'txt',
      'csv',
      'zip',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
    };
    if (!allowedExtensions.contains(extension)) {
      throw ArgumentError('Este tipo de documento no está permitido.');
    }
    final objectPath =
        '$conversationId/$_userId/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await _client.storage.from(_mediaBucket).upload(
          objectPath,
          file,
          fileOptions: FileOptions(
            upsert: false,
            contentType: _documentMimeType(extension),
          ),
        );
    return objectPath;
  }

  Future<void> sendDocumentMessage({
    required String conversationId,
    required String fileUrl,
    required String fileName,
    required int fileSize,
  }) async {
    final safeName = fileName.trim();
    if (safeName.isEmpty || safeName.length > 255) {
      await _client.storage.from(_mediaBucket).remove([fileUrl]);
      throw ArgumentError('El nombre del documento no es válido.');
    }
    final payload = jsonEncode({
      'file_url': fileUrl,
      'file_name': safeName,
      'file_size': fileSize,
    });
    try {
      await _client.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': _userId,
        'type': 'file',
        'content': payload,
      });
    } catch (_) {
      await _client.storage.from(_mediaBucket).remove([fileUrl]);
      rethrow;
    }
  }

  String _documentMimeType(String extension) => switch (extension) {
        'pdf' => 'application/pdf',
        'txt' => 'text/plain',
        'csv' => 'text/csv',
        'zip' => 'application/zip',
        'doc' => 'application/msword',
        'docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls' => 'application/vnd.ms-excel',
        'xlsx' =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt' => 'application/vnd.ms-powerpoint',
        'pptx' =>
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        _ => 'application/octet-stream',
      };

  String _safeExtension(String filePath, {required String fallback}) {
    if (!filePath.contains('.')) return fallback;
    final extension = filePath
        .split('.')
        .last
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    return extension.isEmpty ? fallback : extension;
  }

  Future<String> createSignedMediaUrl(String reference) async {
    final uri = Uri.tryParse(reference);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      throw const FormatException(
        'Referencia multimedia externa no permitida.',
      );
    }
    final segments = reference.split('/');
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (segments.length != 3 ||
        !uuid.hasMatch(segments[0]) ||
        !uuid.hasMatch(segments[1]) ||
        segments[2].isEmpty ||
        segments[2].contains('..')) {
      throw const FormatException('Referencia multimedia inválida.');
    }
    return _client.storage.from(_mediaBucket).createSignedUrl(reference, 600);
  }

  Future<void> sendAudioMessage({
    required String conversationId,
    required String audioUrl,
    required int durationSeconds,
  }) async {
    if (durationSeconds < 1 || durationSeconds > maxVoiceNoteSeconds) {
      throw ArgumentError(
        'La nota de voz debe durar entre 1 y $maxVoiceNoteSeconds segundos.',
      );
    }
    final payload = jsonEncode({
      'audio_url': audioUrl,
      'duration': durationSeconds,
    });

    try {
      await _client.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': _userId,
        'type': 'audio',
        'content': payload,
      });
    } catch (_) {
      await _client.storage.from(_mediaBucket).remove([audioUrl]);
      rethrow;
    }

    try {
      await _client.from('conversations').update({
        'last_activity_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', conversationId);
    } catch (_) {}
  }

  Future<String?> getOtherParticipantId(String conversationId) async {
    try {
      final rows = await _client
          .from('conversation_participants')
          .select('user_id')
          .eq('conversation_id', conversationId)
          .neq('user_id', _userId)
          .limit(1);
      if ((rows as List).isNotEmpty) {
        return rows.first['user_id']?.toString();
      }
    } catch (_) {}
    return null;
  }

  bool isOwnMessage(Map<String, dynamic> message) =>
      message['sender_id'] == _userId;
}
