import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('message streams and reads have explicit bounds', () {
    final source =
        File('lib/src/features/chat/data/chat_service.dart').readAsStringSync();
    expect(
        source,
        contains(
            ".order('created_at', ascending: false)\n          .limit(200)"));
    final watchMessages = source
        .split('Stream<List<Map<String, dynamic>>> watchMessages')[1]
        .split('Stream<List<Map<String, dynamic>>> watchReceipts')[0];
    expect(watchMessages, contains(".order('created_at', ascending: false)"));
    expect(watchMessages, contains('.limit(200)'));
    expect(watchMessages, contains('visibleRows.reversed.toList()'));
  });

  test('Android manifest avoids obsolete broad storage permissions', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, isNot(contains('READ_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('WRITE_EXTERNAL_STORAGE')));
  });

  test('direct conversations require the atomic database RPC', () {
    final source =
        File('lib/src/features/chat/data/chat_service.dart').readAsStringSync();
    final method = source
        .split('Future<String> createDirectConversation')[1]
        .split('Future<List<Map<String, dynamic>>> loadMessages')[0];
    expect(method, contains("'create_direct_conversation'"));
    expect(method, isNot(contains("from('conversations').insert")));
  });

  test('receipt stream is limited to the messages visible in the chat', () {
    final service =
        File('lib/src/features/chat/data/chat_service.dart').readAsStringSync();
    final page = File(
      'lib/src/features/chat/presentation/conversation_page.dart',
    ).readAsStringSync();

    final method = service
        .split('Stream<List<Map<String, dynamic>>> watchReceipts')[1]
        .split('Future<void> markMessageDelivered')[0];
    expect(method, contains('Iterable<String> messageIds'));
    expect(method, contains(".inFilter('message_id', ids)"));
    expect(page, contains('stream: _service.watchReceipts('));
    expect(
      page,
      contains("messages.map((message) => message['id'] as String)"),
    );
  });

  test('conversation summaries are aggregated by the database', () {
    final source =
        File('lib/src/features/chat/data/chat_service.dart').readAsStringSync();
    final method = source
        .split('Future<List<ConversationSummary>> loadConversations')[1]
        .split('Future<List<ContactProfile>> loadContacts')[0];
    expect(method, contains("rpc('get_conversation_message_summaries')"));
    expect(
      File(
        '../supabase/migrations/20260821_006_conversation_message_summaries.sql',
      ).existsSync(),
      isTrue,
    );
  });

  test('outgoing message payloads are bounded and uploads are compensable', () {
    final source =
        File('lib/src/features/chat/data/chat_service.dart').readAsStringSync();
    expect(source, contains('maxTextCharacters = 4000'));
    expect(source, contains('maxCaptionCharacters = 1000'));
    expect(source, contains('maxVoiceNoteSeconds = 600'));
    expect(source, contains('maxMediaBytes = 15 * 1024 * 1024'));
    expect(source, contains('remove([imageUrl])'));
    expect(source, contains('remove([audioUrl])'));
  });

  test('signed media URLs reject untrusted external references', () {
    final source =
        File('lib/src/features/chat/data/chat_service.dart').readAsStringSync();
    final method = source
        .split('Future<String> createSignedMediaUrl')[1]
        .split('Future<void> sendAudioMessage')[0];
    expect(method, isNot(contains('return reference;')));
    expect(method, contains('Referencia multimedia externa no permitida'));
  });

  test('document attachment sends a real private file and no fake location',
      () {
    final service =
        File('lib/src/features/chat/data/chat_service.dart').readAsStringSync();
    final page = File(
      'lib/src/features/chat/presentation/conversation_page.dart',
    ).readAsStringSync();
    expect(service, contains('Future<String> uploadDocumentFile'));
    expect(service, contains('Future<void> sendDocumentMessage'));
    expect(page, contains('FilePicker.pickFiles'));
    expect(page, isNot(contains('Ubicación segura compartida')));
    expect(page, isNot(contains('Documento seguro adjunto')));
  });

  test('clearing a chat is private, timestamp-based, and non-destructive', () {
    final service =
        File('lib/src/features/chat/data/chat_service.dart').readAsStringSync();
    final migration = File(
      '../supabase/migrations/20260821_008_clear_conversation_for_me.sql',
    ).readAsStringSync();

    expect(service, contains("rpc(\n      'clear_conversation_for_me'"));
    expect(migration, contains('add column if not exists cleared_at'));
    expect(migration, contains('message.created_at > mine.cleared_at'));
    expect(migration, isNot(contains('delete from public.messages')));
    expect(migration, isNot(contains('update public.messages')));
  });
}
