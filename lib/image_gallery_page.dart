// file: image_gallery_page.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// The import path below needs to match your project's structure
import 'package:medford_app/supabase_config.dart'; // Ensure this path is correct
import 'package:medford_app/ManageIpdPatientPage.dart' show DrawingPage;

class ImageGalleryPage extends StatefulWidget {
  final List<DrawingPage> images;
  final int initialIndex;
  final String title;

  const ImageGalleryPage({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.title,
  });

  @override
  State<ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends State<ImageGalleryPage> {
  late PageController _pageController;
  late int _currentPageIndex;

  @override
  void initState() {
    super.initState();
    _currentPageIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // A helper function to get the full public URL from the relative path
  String _getPublicUrl(String relativePath) {
    // Correcting the path to prevent duplication of the bucket name
    final correctedPath = relativePath.startsWith('reportdata/')
        ? relativePath.substring('reportdata/'.length)
        : relativePath;

    return SupabaseConfig.client.storage
        .from('reportdata')
        .getPublicUrl(correctedPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          '${widget.title} (${_currentPageIndex + 1}/${widget.images.length})',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (index) {
                setState(() {
                  _currentPageIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final page = widget.images[index];
                final imageUrl = _getPublicUrl(page.templateImageUrl);

                return InteractiveViewer(
                  panEnabled: true,
                  scaleEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                : null,
                            color: Colors.white,
                          ),
                        );
                      },
                      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                        debugPrint('Failed to load image. URL: $imageUrl');
                        return const Center(child: Text('Failed to load image.', style: TextStyle(color: Colors.red)));
                      },
                    ),
                  ),
                );
              },
            ),
            // Navigation arrows
            if (widget.images.length > 1)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 40),
                  onPressed: _currentPageIndex > 0 ? () {
                    _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                  } : null,
                ),
              ),
            if (widget.images.length > 1)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 40),
                  onPressed: _currentPageIndex < widget.images.length - 1 ? () {
                    _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                  } : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}