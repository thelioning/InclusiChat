import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    '../supabase/migrations/20260820_001_security_baseline.sql',
  );

  test('security migration removes universal chat policies', () {
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, isNot(contains('create policy "messages_access_policy"')));
    expect(sql, isNot(contains('using (true)')));
    expect(sql, contains('messages_insert_member_sender'));
    expect(sql, contains('sender_id = auth.uid()'));
    expect(sql, contains('is_conversation_participant'));
  });

  test('security migration hardens privileged functions and concurrency', () {
    final sql = migration.readAsStringSync();

    expect(sql, contains("security definer set search_path = ''"));
    expect(sql, contains('conversations_direct_pair_key_uidx'));
    expect(sql, contains('delete_message_for_me'));
    expect(sql, contains('begin;'));
    expect(sql, contains('commit;'));
  });

  test('chat media migration creates a private member-scoped bucket', () {
    final sql = File(
      '../supabase/migrations/20260820_002_private_chat_media.sql',
    ).readAsStringSync();

    expect(sql, contains("'chat-media'"));
    expect(sql, contains('false'));
    expect(sql, contains('chat_media_select_members'));
    expect(sql, contains('is_conversation_participant'));
    expect(sql, contains('file_size_limit'));
  });

  test('chat service does not upload media to the former public host', () {
    final source = File(
      'lib/src/features/chat/data/chat_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('catbox.moe')));
    expect(source, contains("_mediaBucket = 'chat-media'"));
    expect(source, contains('createSignedUrl'));
  });
}
