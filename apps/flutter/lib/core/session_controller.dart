import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final sessionProvider = StreamProvider<Session?>((ref) {
  final client = Supabase.instance.client;
  return client.auth.onAuthStateChange.map((event) => event.session);
});

final currentUserProvider =
    Provider<User?>((ref) => Supabase.instance.client.auth.currentUser);
