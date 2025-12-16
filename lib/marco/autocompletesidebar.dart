import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'drawing_macro_model.dart';
import '/supabase_config.dart'; // Ensure this points to your config

class AutoCompleteSidebar extends StatefulWidget {
  final Function(MedicalMacro, Offset) onMacroDropped; // Callback when dropped

  const AutoCompleteSidebar({super.key, required this.onMacroDropped});

  @override
  State<AutoCompleteSidebar> createState() => _AutoCompleteSidebarState();
}

class _AutoCompleteSidebarState extends State<AutoCompleteSidebar> {
  final SupabaseClient supabase = SupabaseConfig.client;
  List<MedicalMacro> _macros = [];
  List<MedicalMacro> _filteredMacros = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  final String _currentUserId = SupabaseConfig.client.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _fetchMacros();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredMacros = _macros.where((m) {
        return m.name.toLowerCase().contains(query);
      }).toList();
    });
  }

  Future<void> _fetchMacros() async {
    try {
      // --- OPTIMIZATION: Don't select 'content' column ---
      final response = await supabase
          .from('medical_macros')
          .select('id, name, user_id, created_at') // <--- ONLY METADATA
          .order('created_at', ascending: false);

      final List<MedicalMacro> loaded = (response as List)
          .map((e) => MedicalMacro.fromJson(e))
          .toList();

      setState(() {
        _macros = loaded;
        _filteredMacros = loaded;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching macros: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteMacro(String id) async {
    try {
      await supabase.from('medical_macros').delete().eq('id', id);
      setState(() {
        _macros.removeWhere((m) => m.id == id);
        _filteredMacros.removeWhere((m) => m.id == id);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 10),
            color: const Color(0xFF3B82F6), // Primary Blue
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Smart Macros",
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Search macros...",
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredMacros.isEmpty
                ? const Center(child: Text("No macros found."))
                : ListView.builder(
              itemCount: _filteredMacros.length,
              itemBuilder: (context, index) {
                final macro = _filteredMacros[index];
                final isOwner = macro.userId == _currentUserId;

                // --- CHANGED TO Draggable (was LongPressDraggable) ---
                return Draggable<MedicalMacro>(
                  data: macro,
                  feedback: Material(
                    elevation: 4,
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.draw, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(macro.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.5,
                    child: _buildListTile(macro, isOwner),
                  ),
                  child: _buildListTile(macro, isOwner),
                );
                // ----------------------------------------------------
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListTile(MedicalMacro macro, bool isOwner) {
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFEFF6FF),
        child: Icon(Icons.gesture, color: Color(0xFF3B82F6)),
      ),
      title: Text(macro.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(isOwner ? "My Macro" : "System Template", style: const TextStyle(fontSize: 10)),
      trailing: isOwner
          ? IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.grey),
        onPressed: () => _deleteMacro(macro.id),
      )
          : null,
    );
  }
}