import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:math' as math;

import 'package:dart_vulkan/dart_vulkan.dart';
import 'package:flutter_vulkan/flutter_vulkan.dart';

/// Benchmark scene that renders up to 100k instanced cubes.
class BenchmarkGame extends FlutterVulkanGame {
  BenchmarkGame({int objectCount = 100, int gpuIndex = -1})
    : _objectCount = objectCount.clamp(1, _kMaxObjects),
      _gpuIndex = gpuIndex;

  static const int _kMaxObjects = 100000;

  final int _gpuIndex;

  @override
  int get gpuIndex => _gpuIndex;

  Renderer3D? _renderer;
  final List<Mesh> _cubes = [];
  final List<InstanceBuffer> _instanceBuffers = [];
  final List<int> _instanceCounts = List.filled(_palette.length, 0);

  double _time = 0;
  int _objectCount;
  int _lastDrawCalls = 0;
  bool _instancesDirty = true;

  int _frameCount = 0;
  double _fpsTimer = 0;
  double _fps = 0;

  final StreamController<double> _tickController =
      StreamController<double>.broadcast(sync: true);

  Stream<double> get tickStream => _tickController.stream;
  double get fps => _fps;
  double get frameMs => _fps > 0 ? 1000.0 / _fps : 0.0;
  int get drawCalls => _lastDrawCalls;
  int get objectCount => _objectCount;

  void setObjectCount(int count) {
    final next = count.clamp(1, _kMaxObjects);
    if (next == _objectCount) return;
    _objectCount = next;
    _instancesDirty = true;
  }

  int get verticesPerFrame => _objectCount * 24;

  static const _palette = [
    Color(0.90, 0.30, 0.30),
    Color(0.30, 0.88, 0.40),
    Color(0.30, 0.55, 0.95),
    Color(0.95, 0.80, 0.15),
    Color(0.15, 0.85, 0.85),
    Color(0.85, 0.30, 0.85),
    Color(0.95, 0.55, 0.15),
    Color(0.55, 0.90, 0.45),
  ];

  @override
  Future<void> onLoad(FlutterVulkanContext ctx) async {
    _renderer = ctx.createRenderer();
    final capacityPerColour = (_kMaxObjects / _palette.length).ceil();
    for (final colour in _palette) {
      _cubes.add(Mesh.box(color: colour));
      _instanceBuffers.add(InstanceBuffer(capacityPerColour));
    }
  }

  void _rebuildInstances() {
    _instanceCounts.fillRange(0, _instanceCounts.length, 0);
    final side = math.sqrt(_objectCount).ceil();
    const spacing = 2.5;
    final gridHalf = (side - 1) * spacing * 0.5;

    for (var i = 0; i < _objectCount; i++) {
      final group = i % _palette.length;
      final slot = _instanceCounts[group]++;
      final row = i ~/ side;
      final col = i % side;
      final phase = (i * 2.399) % (2 * math.pi);
      _instanceBuffers[group].setTranslation(
        slot,
        col * spacing - gridHalf,
        math.sin(phase) * 0.4,
        row * spacing - gridHalf,
      );
    }
    _instancesDirty = false;
  }

  @override
  void onUpdate(double dt) {
    _time += dt;
    _frameCount++;
    _fpsTimer += dt;
    if (_fpsTimer >= 0.5) {
      _fps = _frameCount / _fpsTimer;
      _frameCount = 0;
      _fpsTimer = 0;
    }
    _tickController.add(dt);
  }

  @override
  void onRenderFrame(ffi.DynamicLibrary lib, int width, int height) {
    final renderer = _renderer;
    if (renderer == null || _cubes.isEmpty) return;
    if (_instancesDirty) _rebuildInstances();
    if (!renderer.beginFrame()) return;

    final side = math.sqrt(_objectCount).ceil();
    const spacing = 2.5;
    final distance = math.max(20.0, side * spacing * 0.65);
    final cameraX = math.cos(_time * 0.15) * distance;
    final cameraZ = math.sin(_time * 0.15) * distance;
    final cameraY = distance * 0.55;

    final projection = Mat4.perspective(
      fovRadians: 60 * math.pi / 180,
      aspect: width / height.toDouble(),
      near: 0.5,
      far: math.max(2000.0, distance * 4),
    );
    final view = Mat4.lookAt(
      Vec3(cameraX, cameraY, cameraZ),
      const Vec3(0, 0, 0),
      const Vec3(0, 1, 0),
    );
    final viewProjection = projection * view;

    var calls = 0;

    calls++;

    for (var i = 0; i < _cubes.length; i++) {
      final count = _instanceCounts[i];
      if (count == 0) continue;

      renderer.drawMeshInstanced(
        _cubes[i],
        instances: _instanceBuffers[i],
        instanceCount: count,
        mvp: viewProjection,
      );
      calls++;
    }

    _lastDrawCalls = calls;
    renderer.endFrame();
  }

  @override
  void onResize(int width, int height) => _renderer?.onResize(width, height);

  @override
  void dispose() {
    super.dispose();
    _tickController.close();
    _renderer?.dispose();
    _renderer = null;
    for (final buffer in _instanceBuffers) {
      buffer.dispose();
    }
    _instanceBuffers.clear();
    _cubes.clear();
  }
}
