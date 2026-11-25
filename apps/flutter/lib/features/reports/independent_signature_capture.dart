import 'package:flutter/material.dart';

class IndependentSignatureCapture extends StatefulWidget {
  const IndependentSignatureCapture({
    super.key,
    required this.strokes,
    required this.enabled,
    required this.onChanged,
  });

  final List<String> strokes;
  final bool enabled;
  final ValueChanged<List<String>> onChanged;

  @override
  State<IndependentSignatureCapture> createState() =>
      _IndependentSignatureCaptureState();
}

class _IndependentSignatureCaptureState
    extends State<IndependentSignatureCapture> {
  late List<String> _paths;
  List<Offset> _active = [];

  @override
  void initState() {
    super.initState();
    _paths = [...widget.strokes];
  }

  @override
  void didUpdateWidget(covariant IndependentSignatureCapture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.strokes != widget.strokes) _paths = [...widget.strokes];
  }

  String _encode(List<Offset> points) {
    if (points.isEmpty) return '';
    return 'M ${points.first.dx.toStringAsFixed(1)} ${points.first.dy.toStringAsFixed(1)}' +
        points
            .skip(1)
            .map(
              (point) =>
                  ' L ${point.dx.toStringAsFixed(1)} ${point.dy.toStringAsFixed(1)}',
            )
            .join();
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 180,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFB8C8D0)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: widget.enabled
          ? (details) => setState(() => _active = [details.localPosition])
          : null,
      onPanUpdate: widget.enabled
          ? (details) =>
                setState(() => _active = [..._active, details.localPosition])
          : null,
      onPanEnd: widget.enabled
          ? (_) {
              final path = _encode(_active);
              if (path.isNotEmpty &&
                  _paths.length < 200 &&
                  path.length <= 15000) {
                final next = [..._paths, path];
                setState(() {
                  _paths = next;
                  _active = [];
                });
                widget.onChanged(next);
              } else {
                setState(() => _active = []);
              }
            }
          : null,
      onPanCancel: widget.enabled
          ? () => setState(() => _active = [])
          : null,
      child: CustomPaint(
        painter: _IndependentSignaturePainter([
          ..._paths,
          if (_active.isNotEmpty) _encode(_active),
        ]),
        size: Size.infinite,
        child: _paths.isEmpty && _active.isEmpty
            ? const Center(
                child: Text(
                  'ارسم التوقيع بإصبعك هنا',
                  style: TextStyle(color: Colors.black38),
                ),
              )
            : null,
      ),
    ),
  );
}

class _IndependentSignaturePainter extends CustomPainter {
  const _IndependentSignaturePainter(this.paths);
  final List<String> paths;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = const Color(0xFF17324D)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final numberPattern = RegExp(r'-?\d+(?:\.\d+)?');
    for (final raw in paths) {
      final values = numberPattern
          .allMatches(raw)
          .map((match) => double.parse(match.group(0)!))
          .toList();
      if (values.length < 2) continue;
      final path = Path()..moveTo(values[0], values[1]);
      for (var index = 2; index + 1 < values.length; index += 2) {
        path.lineTo(values[index], values[index + 1]);
      }
      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(covariant _IndependentSignaturePainter oldDelegate) =>
      oldDelegate.paths != paths;
}
