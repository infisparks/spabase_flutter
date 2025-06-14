import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://cvcmjtyamlwgkcmsiemd.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN2Y21qdHlhbWx3Z2tjbXNpZW1kIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk4OTQyNTEsImV4cCI6MjA2NTQ3MDI1MX0.HyRKMdofXJjlbnsagmQscBBTSr0aJBkxaSzAkPoyA2k'; // use full key

class SupabaseConfig {
  static Future<void> init() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
