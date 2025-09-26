import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://reihuolixhizaychbttl.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJlaWh1b2xpeGhpemF5Y2hidHRsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg3MzA2OTQsImV4cCI6MjA3NDMwNjY5NH0.1HEWQEWBA3JxNCZPeTBpMmu8q1oeYxUH4hkRWUj-ftI'; // use full key

class SupabaseConfig {
  static Future<void> init() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
