import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; // Import the new package
import 'supabase_config.dart';
import 'login_page.dart';
import 'dashboard_page.dart'; // Assuming this is 'dashboard_page.dart' based on your previous code

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.init();

  // Grab the existing session (if any)
  final session = SupabaseConfig.client.auth.currentSession;

  runApp(MyApp(isLoggedIn: session != null));
}

// MyApp can now be a StatelessWidget, as it just builds the MaterialApp.
class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medford App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      // The home is now an AppUpdateWrapper, which is INSIDE MaterialApp
      home: AppUpdateWrapper(isLoggedIn: isLoggedIn),
    );
  }
}

// This new widget will live inside the MaterialApp and handle the update check.
class AppUpdateWrapper extends StatefulWidget {
  final bool isLoggedIn;
  const AppUpdateWrapper({super.key, required this.isLoggedIn});

  @override
  State<AppUpdateWrapper> createState() => _AppUpdateWrapperState();
}

class _AppUpdateWrapperState extends State<AppUpdateWrapper> {
  // Define the current version of *this* app.
  // If this version doesn't match the one in Supabase, the popup will show.
  static const String _currentVersion = "V14"; // <-- This line was changed

  @override
  void initState() {
    super.initState();
    // Run the check after the first frame is built
    // This context is now valid because it's a child of MaterialApp.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  Future<void> _checkForUpdates() async {
    try {
      // This matches the string '1' from your INSERT statement.
      final response = await SupabaseConfig.client
          .from('update')
          .select()
          .eq('id', '1')
          .single();

      final latestVersion = response['version'] as String?;
      final downloadUrl = response['url'] as String?;

      if (latestVersion == null || downloadUrl == null) {
        // No update info found, so just continue
        return;
      }

      // Compare versions and show dialog if they don't match
      if (latestVersion != _currentVersion && mounted) {
        // Use the scaffold messenger from the widget's context, which is safe.
        _showUpdateDialog(latestVersion, downloadUrl);
      }
    } catch (e) {
      // Log the error, but don't block the user from using the app
      debugPrint("Error checking for updates: $e");
    }
  }

  void _showUpdateDialog(String newVersion, String url) {
    // This context is valid and will find MaterialLocalizations
    showDialog(
      context: context,
      barrierDismissible: false, // User must interact with the dialog
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Update Available"),
          content: Text(
              "A new version ($newVersion) of the app is available. Please update to continue."),
          actions: <Widget>[
            TextButton(
              child: const Text("Download"),
              onPressed: () {
                _launchURL(url); // Launch the download URL
                Navigator.of(dialogContext).pop(); // Dismiss the dialog
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        // Launch the URL in an external browser
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Show an error if the URL can't be launched
        _showErrorSnackbar("Could not launch update URL.");
      }
    } catch (e) {
      _showErrorSnackbar("Error launching URL: $e");
    }
  }

  void _showErrorSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // This widget just builds the page that *should* be shown,
    // after running its update check in initState.
    return widget.isLoggedIn
        ? const IpdManagementPage()
        : const LoginPage();
  }
}

