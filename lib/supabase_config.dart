import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://newmedford.infispark.in';
const supabaseAnonKey = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc1NDMyMDc0MCwiZXhwIjo0OTA5OTk0MzQwLCJyb2xlIjoiYW5vbiJ9.cL44o9NQ7iv-aSXmlvae9xKuRtZlpoPfaDF3wuDHkZE'; // use full key

class SupabaseConfig {
  static Future<void> init() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
