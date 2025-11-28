import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://apimmedford.infispark.in';
const supabaseAnonKey = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc1OTgzMjY0MCwiZXhwIjo0OTE1NTA2MjQwLCJyb2xlIjoiYW5vbiJ9.WCvYapuptIMkVDYae1qTMy6AqT4brJa6GWNc-au-Cx8'; // use full key


class SupabaseConfig {
  static Future<void> init() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        // autoRefreshToken: true,   // ✅ WORKS IN v2.10.1
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}