import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PrescriptionPage extends StatefulWidget {
  const PrescriptionPage({super.key});

  @override
  State<PrescriptionPage> createState() => _PrescriptionPageState();
}

class _PrescriptionPageState extends State<PrescriptionPage> {
  final TransformationController _transformationController = TransformationController();
  final Map<int, List<DrawnLine>> _pageLines = {}; // Store lines for each page
  final GlobalKey _interactiveViewerKey = GlobalKey();

  DrawnLine? _line;
  Color _selectedColor = const Color(0xFF1E40AF);
  double _selectedWidth = 3.0;
  bool _isErasing = false;
  bool _isPanMode = false;
  int _currentPage = 1;

  // Available prescription templates
  final List<PrescriptionTemplate> _templates = [
    PrescriptionTemplate(id: 1, name: "General Prescription", asset: "assets/prescription1.png"),
    PrescriptionTemplate(id: 2, name: "Pediatric Form", asset: "assets/prescription2.png"),
    PrescriptionTemplate(id: 3, name: "Specialist Consultation", asset: "assets/prescription3.png"),
    PrescriptionTemplate(id: 4, name: "Emergency Prescription", asset: "assets/prescription4.png"),
    PrescriptionTemplate(id: 5, name: "Follow-up Form", asset: "assets/prescription5.png"),
    PrescriptionTemplate(id: 6, name: "Discharge Summary", asset: "assets/prescription6.png"),
  ];

  List<DrawnLine> get _currentLines => _pageLines[_currentPage] ?? [];

  @override
  void initState() {
    super.initState();
    // Initialize first page
    _pageLines[_currentPage] = [];
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Offset _getCanvasPosition(Offset globalPosition) {
    final RenderBox? renderBox = _interactiveViewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return Offset.zero;

    final Offset localPosition = renderBox.globalToLocal(globalPosition);
    final Matrix4 transform = _transformationController.value;
    final double scale = transform.getMaxScaleOnAxis();
    final Offset translation = Offset(transform.getTranslation().x, transform.getTranslation().y);

    final Offset canvasPosition = Offset(
      (localPosition.dx - translation.dx) / scale,
      (localPosition.dy - translation.dy) / scale,
    );

    return canvasPosition;
  }

  void _increaseThickness() {
    setState(() {
      if (_selectedWidth < 8.0) {
        _selectedWidth = (_selectedWidth + 0.5).clamp(1.0, 8.0);
      }
    });
    HapticFeedback.selectionClick();
  }

  void _decreaseThickness() {
    setState(() {
      if (_selectedWidth > 1.0) {
        _selectedWidth = (_selectedWidth - 0.5).clamp(1.0, 8.0);
      }
    });
    HapticFeedback.selectionClick();
  }

  void _showPageSelector() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Select Prescription Template",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.7,
                    ),
                    itemCount: _templates.length,
                    itemBuilder: (context, index) {
                      final template = _templates[index];
                      final isSelected = template.id == _currentPage;
                      final hasContent = _pageLines[template.id]?.isNotEmpty ?? false;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentPage = template.id;
                            if (_pageLines[_currentPage] == null) {
                              _pageLines[_currentPage] = [];
                            }
                          });
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF3B82F6) : Colors.grey[300]!,
                              width: isSelected ? 3 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.white,
                                  ),
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.asset(
                                          template.asset,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              color: Colors.grey[100],
                                              child: const Center(
                                                child: Icon(Icons.description, size: 40, color: Colors.grey),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      if (hasContent)
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.green,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.edit, color: Colors.white, size: 16),
                                          ),
                                        ),
                                      if (isSelected)
                                        Positioned(
                                          top: 8,
                                          left: 8,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF3B82F6),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.check, color: Colors.white, size: 16),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  children: [
                                    Text(
                                      template.name,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF64748B),
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Page ${template.id}",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              "Prescription",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "Page $_currentPage",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3B82F6),
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        shadowColor: Colors.black12,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.library_books, size: 20),
            onPressed: _showPageSelector,
            tooltip: 'Change Page',
          ),
          IconButton(
            icon: Icon(_isPanMode ? Icons.edit : Icons.pan_tool, size: 20),
            onPressed: () {
              setState(() {
                _isPanMode = !_isPanMode;
              });
            },
            tooltip: _isPanMode ? 'Draw Mode' : 'Pan Mode',
          ),
          IconButton(
            icon: const Icon(Icons.undo, size: 20),
            onPressed: _undo,
            tooltip: 'Undo',
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined, size: 20),
            onPressed: _savePrescription,
            tooltip: 'Save',
          ),
        ],
      ),
      body: Column(
        children: [
          // 🔧 FIXED: Responsive Toolbar with proper overflow handling
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              children: [
                // First Row: Mode and Basic Controls
                Row(
                  children: [
                    // Mode indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: _isPanMode ? Colors.orange[100] : Colors.blue[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _isPanMode ? '🤏 Pan' : '✏️ Draw',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: _isPanMode ? Colors.orange[800] : Colors.blue[800],
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Pen/Eraser toggle
                    if (!_isPanMode) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ToggleButtons(
                          isSelected: [!_isErasing, _isErasing],
                          onPressed: (index) {
                            setState(() {
                              _isErasing = index == 1;
                            });
                          },
                          borderRadius: BorderRadius.circular(4),
                          selectedColor: Colors.white,
                          fillColor: const Color(0xFF3B82F6),
                          color: const Color(0xFF64748B),
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 24),
                          children: const [
                            Icon(Icons.edit, size: 12),
                            Icon(Icons.cleaning_services, size: 12),
                          ],
                        ),
                      ),
                    ],

                    const Spacer(),

                    // Quick action buttons
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.undo, size: 16),
                          onPressed: _undo,
                          tooltip: 'Undo',
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        ),
                        IconButton(
                          icon: const Icon(Icons.clear_all, size: 16),
                          onPressed: _clearCanvas,
                          tooltip: 'Clear',
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        ),
                      ],
                    ),
                  ],
                ),

                // Second Row: Drawing Controls (only when not in pan mode)
                if (!_isPanMode) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // Color picker
                      if (!_isErasing) ...[
                        Expanded(
                          flex: 2,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _colorButton(const Color(0xFF1E40AF)),
                              _colorButton(const Color(0xFF1F2937)),
                              _colorButton(const Color(0xFFDC2626)),
                              _colorButton(const Color(0xFF059669)),
                              _colorButton(const Color(0xFF7C3AED)),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Thickness controls
                        Expanded(
                          flex: 3,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Decrease thickness
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 14),
                                  onPressed: _selectedWidth > 1.0 ? _decreaseThickness : null,
                                  tooltip: 'Thinner',
                                  padding: const EdgeInsets.all(2),
                                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                  color: _selectedWidth > 1.0 ? const Color(0xFF64748B) : Colors.grey[400],
                                ),

                                // Current thickness display
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3B82F6).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: (_selectedWidth * 1.5).clamp(3.0, 12.0),
                                          height: (_selectedWidth * 1.5).clamp(3.0, 12.0),
                                          decoration: BoxDecoration(
                                            color: _selectedColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${_selectedWidth.toStringAsFixed(1)}',
                                          style: const TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF3B82F6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Increase thickness
                                IconButton(
                                  icon: const Icon(Icons.add, size: 14),
                                  onPressed: _selectedWidth < 8.0 ? _increaseThickness : null,
                                  tooltip: 'Thicker',
                                  padding: const EdgeInsets.all(2),
                                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                  color: _selectedWidth < 8.0 ? const Color(0xFF64748B) : Colors.grey[400],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const Spacer(),

                      // Zoom controls
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.zoom_out, size: 16),
                            onPressed: _zoomOut,
                            tooltip: 'Zoom Out',
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          ),
                          IconButton(
                            icon: const Icon(Icons.zoom_in, size: 16),
                            onPressed: _zoomIn,
                            tooltip: 'Zoom In',
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          ),
                          IconButton(
                            icon: const Icon(Icons.center_focus_strong, size: 16),
                            onPressed: _resetZoom,
                            tooltip: 'Reset',
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Expanded Drawing area
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.all(8),
              child: _buildDrawingArea(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawingArea() {
    return InteractiveViewer(
      key: _interactiveViewerKey,
      transformationController: _transformationController,
      boundaryMargin: const EdgeInsets.all(20),
      minScale: 0.5,
      maxScale: 4.0,
      panEnabled: _isPanMode,
      scaleEnabled: _isPanMode,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: _isPanMode ? null : (details) {
          final canvasPosition = _getCanvasPosition(details.globalPosition);

          if (_isErasing) {
            _eraseAtPoint(canvasPosition);
          } else {
            // 🔥 INSTANT RESPONSE: Create line with tiny second point for immediate visibility
            final instantSecondPoint = Offset(
                canvasPosition.dx + 0.01,
                canvasPosition.dy + 0.01
            );

            setState(() {
              _line = DrawnLine([canvasPosition, instantSecondPoint], _selectedColor, _selectedWidth);
            });
          }
        },
        onPanUpdate: _isPanMode ? null : (details) {
          final canvasPosition = _getCanvasPosition(details.globalPosition);

          if (_isErasing) {
            _eraseAtPoint(canvasPosition);
          } else if (_line != null) {
            setState(() {
              // Replace the tiny second point with actual movement
              if (_line!.path.length == 2 &&
                  (_line!.path[1] - _line!.path[0]).distance < 0.1) {
                // Replace tiny point with real movement
                _line = DrawnLine([_line!.path[0], canvasPosition], _selectedColor, _selectedWidth);
              } else {
                // Continue adding points normally
                _line = DrawnLine([..._line!.path, canvasPosition], _selectedColor, _selectedWidth);
              }
            });
          }
        },
        onPanEnd: _isPanMode ? null : (details) {
          if (!_isErasing && _line != null) {
            setState(() {
              // If it was just a tap (tiny movement), make it a proper dot
              if (_line!.path.length == 2 &&
                  (_line!.path[1] - _line!.path[0]).distance < 0.1) {
                _line = DrawnLine([_line!.path[0]], _selectedColor, _selectedWidth);
              }

              _pageLines[_currentPage]!.add(_line!);
              _line = null;
            });
          }
        },
        child: _buildPrescriptionContainer(),
      ),
    );
  }

  Widget _buildPrescriptionContainer() {
    final currentTemplate = _templates.firstWhere((t) => t.id == _currentPage);

    return Container(
      width: MediaQuery.of(context).size.width * 1.1,
      height: MediaQuery.of(context).size.height * 1.3,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Prescription background
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                currentTemplate.asset,
                fit: BoxFit.fill,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: CustomPaint(
                      painter: PrescriptionBackgroundPainter(),
                      size: Size.infinite,
                    ),
                  );
                },
              ),
            ),
          ),

          // Drawing layer
          Positioned.fill(
            child: CustomPaint(
              painter: DrawingPainter(_currentLines, _line),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorButton(Color color) {
    final isSelected = _selectedColor == color;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedColor = color;
        });
      },
      child: Container(
        width: 16,
        height: 16,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
          ],
        ),
      ),
    );
  }

  void _zoomIn() {
    final Matrix4 matrix = _transformationController.value.clone();
    matrix.scale(1.2);
    _transformationController.value = matrix;
  }

  void _zoomOut() {
    final Matrix4 matrix = _transformationController.value.clone();
    matrix.scale(0.8);
    _transformationController.value = matrix;
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  void _eraseAtPoint(Offset point) {
    setState(() {
      _pageLines[_currentPage]!.removeWhere((line) {
        return line.path.any((linePoint) {
          return (linePoint - point).distance < 30.0;
        });
      });
    });
  }

  void _undo() {
    if (_currentLines.isNotEmpty) {
      setState(() {
        _pageLines[_currentPage]!.removeLast();
      });
    }
  }

  void _clearCanvas() {
    setState(() {
      _pageLines[_currentPage]!.clear();
      _line = null;
    });
  }

  void _savePrescription() {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text('Page $_currentPage saved successfully!'),
          ],
        ),
        backgroundColor: Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class PrescriptionTemplate {
  final int id;
  final String name;
  final String asset;

  PrescriptionTemplate({
    required this.id,
    required this.name,
    required this.asset,
  });
}

class DrawnLine {
  final List<Offset> path;
  final Color color;
  final double width;

  DrawnLine(this.path, this.color, this.width);
}

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> lines;
  final DrawnLine? currentLine;

  DrawingPainter(this.lines, this.currentLine);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw completed lines
    for (final line in lines) {
      final paint = Paint()
        ..color = line.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = line.width
        ..style = PaintingStyle.stroke;

      if (line.path.length == 1) {
        // 🎯 INSTANT DOT: Draw single points as circles immediately
        canvas.drawCircle(line.path.first, line.width / 2, paint..style = PaintingStyle.fill);
      } else if (line.path.length >= 2) {
        // Draw multi-point lines
        final path = Path();
        path.moveTo(line.path.first.dx, line.path.first.dy);

        for (int i = 1; i < line.path.length; i++) {
          path.lineTo(line.path[i].dx, line.path[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    // Draw current line being drawn
    if (currentLine != null) {
      final paint = Paint()
        ..color = currentLine!.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = currentLine!.width
        ..style = PaintingStyle.stroke;

      if (currentLine!.path.length == 1) {
        // 🎯 INSTANT DOT: Single point as circle
        canvas.drawCircle(currentLine!.path.first, currentLine!.width / 2, paint..style = PaintingStyle.fill);
      } else if (currentLine!.path.length >= 2) {
        // Multi-point line
        final path = Path();
        path.moveTo(currentLine!.path.first.dx, currentLine!.path.first.dy);

        for (int i = 1; i < currentLine!.path.length; i++) {
          path.lineTo(currentLine!.path[i].dx, currentLine!.path[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class PrescriptionBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final headerPaint = Paint()
      ..color = const Color(0xFF3B82F6).withOpacity(0.1);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 120),
      headerPaint,
    );

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    textPainter.text = const TextSpan(
      text: 'MEDFORD HOSPITAL',
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1E40AF),
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(40, 20));

    textPainter.text = const TextSpan(
      text: 'Address: 123 Medical Center Drive, City, State 12345\nPhone: (555) 123-4567 | Email: info@medfordhospital.com',
      style: TextStyle(
        fontSize: 12,
        color: Color(0xFF64748B),
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(40, 55));

    textPainter.text = const TextSpan(
      text: 'PRESCRIPTION',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1E40AF),
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(40, 140));

    final linePaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..strokeWidth = 1;

    canvas.drawLine(const Offset(40, 180), Offset(size.width - 40, 180), linePaint);
    textPainter.text = const TextSpan(
      text: 'Patient Name: ________________________________',
      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(40, 165));

    canvas.drawLine(const Offset(40, 220), const Offset(200, 220), linePaint);
    canvas.drawLine(Offset(size.width - 200, 220), Offset(size.width - 40, 220), linePaint);

    textPainter.text = const TextSpan(
      text: 'Age: _______',
      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(40, 205));

    textPainter.text = const TextSpan(
      text: 'Date: _______',
      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - 150, 205));

    for (double i = 260; i < size.height - 100; i += 30) {
      canvas.drawLine(
        Offset(40, i),
        Offset(size.width - 40, i),
        Paint()..color = Colors.blue.withOpacity(0.1)..strokeWidth = 0.5,
      );
    }

    final signaturePaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(size.width - 250, size.height - 60),
      Offset(size.width - 40, size.height - 60),
      signaturePaint,
    );

    textPainter.text = const TextSpan(
      text: 'Doctor Signature',
      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - 200, size.height - 45));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}