import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
  static final currentUserProfileNotifier = ValueNotifier<UserProfileData?>(null);

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('No authenticated user');
    return id;
  }

  String get currentUserId => _userId;

  Future<UserProfileData> loadUserProfile() async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', _userId)
        .maybeSingle();

    if (row == null) {
      final user = _client.auth.currentUser;
      final rawName = user?.userMetadata?['display_name'] as String? ?? 'Usuario';
      final rawUsername = user?.userMetadata?['username'] as String? ?? 'user_${_userId.substring(0, 6)}';
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
          .select('conversation_id,left_at')
          .eq('user_id', _userId);
      
      final ids = (membershipRows as List)
          .where((row) => row['left_at'] == null)
          .map<String>((row) => row['conversation_id'].toString())
          .toSet()
          .toList();

      if (ids.isEmpty) return const [];

      final conversationRows = await _client
          .from('conversations')
          .select()
          .inFilter('id', ids);

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

      List<dynamic> messageRows = [];
      try {
        final mRes = await _client
            .from('messages')
            .select('id,conversation_id,sender_id,content,created_at,metadata,is_deleted')
            .inFilter('conversation_id', ids)
            .order('created_at', ascending: false);
        messageRows = (mRes as List);
      } catch (_) {
        try {
          final mRes = await _client
              .from('messages')
              .select('id,conversation_id,sender_id,content,created_at')
              .inFilter('conversation_id', ids)
              .order('created_at', ascending: false);
          messageRows = (mRes as List);
        } catch (_) {}
      }

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
              } else if (decoded.containsKey('image_url') || decoded.containsKey('image_base64')) {
                final cap = (decoded['caption'] as String?)?.trim() ?? '';
                displayContent = cap.isNotEmpty ? '📷 $cap' : '📷 Foto';
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
        }
      }

      // Obtener recibos de mis últimos mensajes enviados para saber si fueron entregados o leídos
      final myLatestMessageIds = latestMessageSender.entries
          .where((e) => e.value == _userId && latestMessageId[e.key] != null)
          .map((e) => latestMessageId[e.key]!)
          .toList();

      final myLatestReceipts = <String, String>{};
      if (myLatestMessageIds.isNotEmpty) {
        try {
          final myReceiptRows = await _client
              .from('message_receipts')
              .select('message_id,status')
              .neq('user_id', _userId)
              .inFilter('message_id', myLatestMessageIds);
          for (final r in (myReceiptRows as List)) {
            final mId = r['message_id'].toString();
            final st = r['status'].toString();
            if (st == 'read' || myLatestReceipts[mId] == null) {
              myLatestReceipts[mId] = st;
            }
          }
        } catch (_) {}
      }

      final incomingMessageIds = visibleMessageRows
          .where((row) => row['sender_id'] != _userId)
          .map<String>((row) => row['id'].toString())
          .toList();

      final receiptRows = incomingMessageIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await _client
              .from('message_receipts')
              .select('message_id,status')
              .eq('user_id', _userId)
              .inFilter('message_id', incomingMessageIds);

      final knownReceiptIds = (receiptRows as List)
          .map<String>((row) => row['message_id'].toString())
          .toSet();

      // Registrar automáticamente como entregados los mensajes recibidos en este dispositivo
      final unreceivedIds = incomingMessageIds.where((id) => !knownReceiptIds.contains(id)).toList();
      if (unreceivedIds.isNotEmpty) {
        for (final mId in unreceivedIds) {
          markMessageDelivered(mId);
        }
      }

      final readMessageIds = (receiptRows as List)
          .where((row) => row['status'] == 'read')
          .map<String>((row) => row['message_id'].toString())
          .toSet();

      final unreadByConversation = <String, int>{};
      for (final row in visibleMessageRows) {
        final messageId = row['id'].toString();
        if (row['sender_id'] != _userId && !readMessageIds.contains(messageId)) {
          final conversationId = row['conversation_id'].toString();
          unreadByConversation.update(
            conversationId,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
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
        final receiptStatus = isMine && lMsgId != null
            ? (myLatestReceipts[lMsgId] ?? 'sent')
            : null;

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
          .select('id,display_name,username,avatar_url,bio,pronouns,is_verified')
          .inFilter('id', allIds.toList())
          .order('display_name');

      return (profiles as List).map((row) {
        final id = row['id'] as String;
        return ContactProfile(
          id: id,
          displayName: (row['display_name'] as String?)?.trim().isNotEmpty == true
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
        return rpcResults.map((r) => ContactProfile(
          id: r['id'] as String,
          displayName: r['display_name'] as String? ?? 'Usuario',
          username: r['username'] as String?,
          avatarUrl: r['avatar_url'] as String?,
          isVerified: r['is_verified'] as bool? ?? false,
        )).toList();
      }
    } catch (_) {
      // Fallback a consulta directa si la RPC aún no está creada
      final rows = await _client
          .from('profiles')
          .select('id,display_name,username,avatar_url,is_verified')
          .neq('id', _userId)
          .or('username.ilike.%$cleanQuery%,display_name.ilike.%$cleanQuery%')
          .limit(15);
      return (rows as List).map((r) => ContactProfile(
        id: r['id'] as String,
        displayName: r['display_name'] as String? ?? 'Usuario',
        username: r['username'] as String?,
        avatarUrl: r['avatar_url'] as String?,
        isVerified: r['is_verified'] as bool? ?? false,
      )).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> sendContactRequest(String targetUsername) async {
    final cleanUsername = targetUsername.trim().toLowerCase().replaceAll('@', '');
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
        return {'success': false, 'message': 'Usuario @$cleanUsername no encontrado.'};
      }

      final target = targetRows.first;
      final targetId = target['id'] as String;
      final targetUName = (target['username'] as String? ?? cleanUsername).replaceAll('@', '');

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
        return {'success': false, 'message': 'Este usuario ya está en tus contactos.'};
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
          return {'success': false, 'message': '@$targetUName ya forma parte de tus contactos.'};
        } else if (senderId == _userId) {
          return {'success': false, 'message': 'Ya enviaste una solicitud a @$targetUName. Está pendiente de aprobación.'};
        } else {
          return {'success': false, 'message': '@$targetUName ya te envió una solicitud. Revisa la sección de solicitudes para aceptarla.'};
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
      final cleanErr = e.toString().replaceAll('Exception:', '').replaceAll('PostgrestException', '').trim();
      return {'success': false, 'message': cleanErr.isNotEmpty ? cleanErr : 'No se pudo enviar la solicitud.'};
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
        .map<String>((r) => (r['sender_id'] == _userId ? r['receiver_id'] : r['sender_id']) as String)
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
      final otherId = isIncoming ? r['sender_id'] as String : r['receiver_id'] as String;
      final profile = profileMap[otherId] ?? ContactProfile(
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
    } catch (_) {}

    try {
      final myParts = await _client
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', _userId)
          .isFilter('left_at', null);

      final myConvIds = (myParts as List)
          .map<String>((r) => r['conversation_id'] as String)
          .toList();

      if (myConvIds.isNotEmpty) {
        final otherParts = await _client
            .from('conversation_participants')
            .select('conversation_id')
            .eq('user_id', otherUserId)
            .inFilter('conversation_id', myConvIds)
            .isFilter('left_at', null)
            .limit(1);

        if ((otherParts as List).isNotEmpty) {
          return otherParts.first['conversation_id'] as String;
        }
      }

      final sortedUsers = [_userId, otherUserId]..sort();
      final pairKey = '${sortedUsers[0]}:${sortedUsers[1]}';

      final conv = await _client.from('conversations').insert({
        'type': 'direct',
        'created_by': _userId,
        'direct_pair_key': pairKey,
      }).select('id').single();

      final convId = conv['id'] as String;
      await _client.from('conversation_participants').insert([
        {'conversation_id': convId, 'user_id': _userId, 'role': 'admin'},
        {'conversation_id': convId, 'user_id': otherUserId, 'role': 'member'},
      ]);

      try {
        await _client.from('contacts').upsert({
          'user_id': _userId,
          'contact_user_id': otherUserId,
          'circle_category': 'general',
        });
      } catch (_) {}

      return convId;
    } catch (e) {
      final clean = e.toString().replaceAll('Exception:', '').replaceAll('PostgrestException', '').trim();
      throw Exception(clean.isNotEmpty ? clean : 'Error al conectar con el usuario');
    }
  }

  Future<List<Map<String, dynamic>>> loadMessages(String conversationId) async {
    try {
      final rows = await _client
          .from('messages')
          .select('id,conversation_id,sender_id,type,content,created_at,metadata,is_deleted')
          .eq('conversation_id', conversationId)
          .eq('is_deleted', false)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(rows as List).where((row) {
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
            .order('created_at', ascending: true);
        return List<Map<String, dynamic>>.from(rows as List);
      } catch (_) {
        return const [];
      }
    }
  }

  Stream<List<Map<String, dynamic>>> watchMessages(String conversationId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .map((rows) => rows.where((row) {
          if (row['is_deleted'] == true) return false;
          final meta = row['metadata'];
          if (meta is Map && meta['deleted_for'] is List) {
            final deletedList = meta['deleted_for'] as List;
            if (deletedList.contains(_userId)) return false;
          }
          return true;
        }).toList());
  }

  Stream<List<Map<String, dynamic>>> watchReceipts() {
    return _client
        .from('message_receipts')
        .stream(primaryKey: ['message_id', 'user_id']);
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
    try {
      final row = await _client
          .from('messages')
          .select('metadata')
          .eq('id', messageId)
          .maybeSingle();
      final currentMeta = Map<String, dynamic>.from((row?['metadata'] as Map?) ?? {});
      final deletedFor = List<String>.from((currentMeta['deleted_for'] as List?) ?? []);
      if (!deletedFor.contains(_userId)) {
        deletedFor.add(_userId);
        currentMeta['deleted_for'] = deletedFor;
        await _client.from('messages').update({
          'metadata': currentMeta,
        }).eq('id', messageId);
      }
    } catch (_) {}
  }

  Future<String> uploadImageFile(String filePath) async {
    try {
      final uri = Uri.parse('https://catbox.moe/user/api.php');
      final request = http.MultipartRequest('POST', uri)
        ..fields['reqtype'] = 'fileupload'
        ..files.add(await http.MultipartFile.fromPath('fileToUpload', filePath));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        final body = response.body.trim();
        if (body.startsWith('http')) {
          return body;
        }
      }
      throw Exception('No se pudo subir la imagen al servidor');
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
    final payload = jsonEncode({
      'image_url': imageUrl,
      'caption': cleanCaption,
    });

    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': _userId,
      'type': 'image',
      'content': payload,
    });

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
    final imageUrl = await uploadImageFile(imagePath);

    final targetConvIds = <String>{...conversationIds};
    for (final uId in contactUserIds) {
      final convId = await createDirectConversation(uId);
      targetConvIds.add(convId);
    }
    for (final convId in targetConvIds) {
      await sendImageMessage(
        conversationId: convId,
        imageUrl: imageUrl,
        caption: caption,
      );
    }
  }

  Future<String> uploadAudioFile(String filePath) async {
    try {
      final uri = Uri.parse('https://catbox.moe/user/api.php');
      final request = http.MultipartRequest('POST', uri)
        ..fields['reqtype'] = 'fileupload'
        ..files.add(await http.MultipartFile.fromPath('fileToUpload', filePath));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        final body = response.body.trim();
        if (body.startsWith('http')) {
          return body;
        }
      }
      throw Exception('No se pudo subir la nota de voz');
    } catch (e) {
      debugPrint('Audio upload error: $e');
      rethrow;
    }
  }

  Future<void> sendAudioMessage({
    required String conversationId,
    required String audioUrl,
    required int durationSeconds,
  }) async {
    final payload = jsonEncode({
      'audio_url': audioUrl,
      'duration': durationSeconds,
    });

    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': _userId,
      'type': 'audio',
      'content': payload,
    });

    try {
      await _client.from('conversations').update({
        'last_activity_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', conversationId);
    } catch (_) {}
  }

  bool isOwnMessage(Map<String, dynamic> message) =>
      message['sender_id'] == _userId;
}
