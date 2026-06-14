import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyUpEvent, LogicalKeyboardKey;
import 'package:flutter_vulkan/flutter_vulkan.dart';

import 'benchmark_game.dart';

void main() => runApp(const VulkanExampleApp());

class VulkanExampleApp extends StatelessWidget {
  const VulkanExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vulkan Example',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: const VulkanScreen(),
    );
  }
}

enum _Mode { demo, benchmark }

class VulkanScreen extends StatefulWidget {
  const VulkanScreen({super.key});

  @override
  State<VulkanScreen> createState() => _VulkanScreenState();
}

class _VulkanScreenState extends State<VulkanScreen>
    with WidgetsBindingObserver {
  List<GpuInfo> _gpus = [];
  int _selectedGpuIndex = -1;

  int _benchCount = 100;

  late BenchmarkGame _game = BenchmarkGame(
    objectCount: _benchCount,
    gpuIndex: _selectedGpuIndex,
  );
  UniqueKey _gameKey = UniqueKey();

  // ---- lifecycle -----------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGpus());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      for (final key
          in HardwareKeyboard.instance.physicalKeysPressed.toList()) {
        HardwareKeyboard.instance.handleKeyEvent(
          KeyUpEvent(
            physicalKey: key,
            logicalKey: LogicalKeyboardKey(key.usbHidUsage),
            timeStamp: Duration.zero,
            synthesized: true,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _game.dispose();
    super.dispose();
  }

  // ---- helpers -------------------------------------------------------------

  void _loadGpus() {
    try {
      final gpus = FlutterVulkanGame.enumerateGpus();
      if (mounted) setState(() => _gpus = gpus);
    } catch (_) {}
  }

  void _selectGpu(int index) {
    if (index == _selectedGpuIndex) return;
    final old = _game;
    setState(() {
      _selectedGpuIndex = index;
      _game = BenchmarkGame(
        objectCount: _benchCount,
        gpuIndex: _selectedGpuIndex,
      );

      _gameKey = UniqueKey();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _updateBenchCount(int count) {
    _benchCount = count;
    _game.setObjectCount(count);
  }

  // ---- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Vulkan surface ──────────────────────────────────────────────
          VulkanGameView(key: _gameKey, game: _game),

          // ── HUD overlay ─────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title + mode toggle
                  Row(
                    children: [
                      const Text(
                        'Vulkan + Flutter',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                  const SizedBox(height: 8),

                  _BenchStats(game: _game),

                  const SizedBox(height: 10),

                  // GPU picker (both modes)
                  if (_gpus.isNotEmpty)
                    _GpuDropdown(
                      gpus: _gpus,
                      selected: _selectedGpuIndex,
                      onChanged: _selectGpu,
                    ),

                  // Benchmark controls
                  const SizedBox(height: 10),
                  _ObjectSlider(
                    key: _gameKey,
                    count: _benchCount,
                    onChanged: (v) => setState(() => _updateBenchCount(v)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BenchStats extends StatelessWidget {
  final BenchmarkGame game;

  const _BenchStats({required this.game});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: game.tickStream,
      builder: (BuildContext context, AsyncSnapshot<double> snapshot) {
        final fps = game.fps.toStringAsFixed(1);
        final ms = game.frameMs.toStringAsFixed(2);
        final objs = game.objectCount;
        final calls = game.drawCalls;

        return Text(
          '$fps FPS  ·  ${ms}ms  ·  $objs objects  ·  $calls draw calls',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        );
      },
    );
  }
}

/// Logarithmic slider: covers 1 – 100 000 with equal visual resolution across
/// all decades (tweaking 10→50 is as easy as tweaking 10 000→50 000).
class _ObjectSlider extends StatelessWidget {
  static const int _maxObjects = 100000;

  final int count;
  final ValueChanged<int> onChanged;

  const _ObjectSlider({
    super.key,
    required this.count,
    required this.onChanged,
  });

  // Map linear slider [0,1] → log count [1, _maxObjects]
  static double _toSlider(int count) {
    return math.log(count.clamp(1, _maxObjects)) / math.log(_maxObjects);
  }

  static int _fromSlider(double v) {
    return math.pow(_maxObjects, v).round().clamp(1, _maxObjects);
  }

  static String _label(int v) {
    if (v >= 1000) {
      final k = v / 1000;
      return k == k.truncateToDouble()
          ? '${k.toInt()}k'
          : '${k.toStringAsFixed(1)}k';
    }
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Objects: ${_label(count)}',
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.deepPurpleAccent,
            thumbColor: Colors.deepPurpleAccent,
            inactiveTrackColor: Colors.white24,
            overlayColor: Colors.deepPurpleAccent.withValues(alpha: 0.2),
            trackHeight: 3,
          ),
          child: Slider(
            value: _toSlider(count),
            min: 0,
            max: 1,
            onChanged: (v) => onChanged(_fromSlider(v)),
          ),
        ),
        // Quick-access preset buttons
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [10, 50, 100, 500, 1000, 5000, 10000, 50000, 100000]
              .map(
                (n) => ActionChip(
                  label: Text(_label(n), style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: count == n
                      ? Colors.deepPurpleAccent
                      : Colors.white10,
                  onPressed: () => onChanged(n),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _GpuDropdown extends StatelessWidget {
  final List<GpuInfo> gpus;
  final int selected;
  final ValueChanged<int> onChanged;

  const _GpuDropdown({
    required this.gpus,
    required this.selected,
    required this.onChanged,
  });

  String _label(GpuInfo g) {
    final type = switch (g.deviceType) {
      VulkanDeviceType.discreteGpu => 'Discrete',
      VulkanDeviceType.integratedGpu => 'Integrated',
      VulkanDeviceType.virtualGpu => 'Virtual',
      VulkanDeviceType.cpu => 'CPU',
      _ => 'Other',
    };
    return '${g.name} ($type)';
  }

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuEntry<int>>[
      const DropdownMenuEntry(value: -1, label: 'Auto (recommended)'),
      ...gpus.map((g) => DropdownMenuEntry(value: g.index, label: _label(g))),
    ];
    return DropdownMenu<int>(
      initialSelection: selected,
      dropdownMenuEntries: items,
      label: const Text('GPU'),
      width: 320,
      textStyle: const TextStyle(color: Colors.white, fontSize: 13),
      menuStyle: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Color(0xDD1E1E2E)),
      ),
      onSelected: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
