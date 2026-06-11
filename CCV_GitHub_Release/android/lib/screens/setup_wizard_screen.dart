import 'package:flutter/material.dart';
import '../services/permission_service.dart';

/// 首次启动权限向导
///
/// 三步引导用户开启必要权限：
///   1. 无障碍服务（检测微信复制事件）
///   2. 悬浮窗权限（复制后显示同步按钮）
///   3. 电池优化（保证后台连接稳定）
class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen>
    with WidgetsBindingObserver {
  int _step = 1; // 1, 2, 3, 4=完成
  Permissions? _perms;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从系统设置页返回时自动刷新状态
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final p = await PermissionService.checkAll();
    if (!mounted) return;
    setState(() {
      _perms = p;
      // 根据权限状态自动推进步骤
      if (_step == 1 && p.accessibility) _step = 2;
      if (_step == 2 && p.overlay) _step = 3;
      if (_step == 3 && p.batteryOptimization) _step = 4;
    });
  }

  // ── 各步骤的跳转 ──

  void _openAccessibility() async {
    await PermissionService.openAccessibilitySettings();
    // 返回后 WidgetsBindingObserver 自动触发 _refresh
  }

  void _openOverlay() async {
    await PermissionService.openOverlaySettings();
  }

  void _openBattery() async {
    await PermissionService.openBatteryOptimizationSettings();
  }

  void _finish() {
    Navigator.of(context).pushReplacementNamed('/home');
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text('Ccv 首次设置'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_step == 4) return _buildCompletePage();
    return _buildStepPage();
  }

  // ── 步骤页 ──

  Widget _buildStepPage() {
    final steps = [
      _StepInfo(
        icon: Icons.accessibility_new,
        title: '开启无障碍服务',
        desc: '用于检测微信中的"复制"事件，\n实现手机复制后自动发送到电脑。',
        buttonText: '去开启',
        onTap: _openAccessibility,
        isDone: _perms?.accessibility ?? false,
      ),
      _StepInfo(
        icon: Icons.fit_screen,
        title: '开启悬浮窗权限',
        desc: '在微信复制后屏幕顶部显示悬浮按钮，\n点击即可触发同步。',
        buttonText: '去开启',
        onTap: _openOverlay,
        isDone: _perms?.overlay ?? false,
      ),
      _StepInfo(
        icon: Icons.battery_saver,
        title: '关闭电池优化',
        desc: '防止系统在后台杀死 Ccv，\n保持与电脑的稳定连接。\n\n（vivo / OPPO 用户强烈建议）',
        buttonText: '去设置',
        onTap: _openBattery,
        isDone: _perms?.batteryOptimization ?? false,
      ),
    ];

    final info = steps[_step - 1];

    return Column(
      children: [
        // 步骤指示器
        _StepIndicator(current: _step, total: 3),
        const SizedBox(height: 48),

        // 图标
        Icon(info.icon, size: 72, color: Colors.blue.shade300),
        const SizedBox(height: 24),

        // 标题
        Text(info.title,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 16),

        // 描述
        Text(info.desc,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.grey,
                height: 1.6)),
        const SizedBox(height: 32),

        // 状态
        if (info.isDone)
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 20),
              SizedBox(width: 8),
              Text('已完成 ✓',
                  style: TextStyle(color: Colors.green, fontSize: 16)),
            ],
          )
        else ...[
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: info.onTap,
              icon: const Icon(Icons.open_in_new),
              label: Text(info.buttonText),
            ),
          ),
          const SizedBox(height: 12),
          Text('点击后会自动跳转系统设置，开启后返回即可',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],

        const Spacer(),

        // 底部跳过按钮
        if (!info.isDone)
          TextButton(
            onPressed: () {
              if (_step < 3) {
                setState(() => _step++);
              } else {
                _finish();
              }
            },
            child: Text(
              _step < 3 ? '跳过此步 >' : '跳过，直接使用 >',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
      ],
    );
  }

  // ── 完成页 ──

  Widget _buildCompletePage() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, size: 80, color: Colors.green),
        const SizedBox(height: 24),
        const Text('Ccv 已准备就绪',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 32),

        _doneRow(Icons.accessibility_new, '无障碍已开启'),
        _doneRow(Icons.fit_screen, '悬浮窗已开启'),
        _doneRow(Icons.battery_saver, '电池优化已关闭'),

        const SizedBox(height: 48),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _finish,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('开始使用'),
          ),
        ),
      ],
    );
  }

  Widget _doneRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.green, size: 20),
          const SizedBox(width: 12),
          Text(text,
              style: const TextStyle(fontSize: 15, color: Colors.green)),
        ],
      ),
    );
  }
}

// ── 步骤指示器 ──

class _StepIndicator extends StatelessWidget {
  final int current;
  final int total;

  const _StepIndicator({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final isActive = i + 1 == current;
        final isPast = i + 1 < current;
        return Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? Colors.blue
                    : isPast
                        ? Colors.green
                        : Colors.grey.shade800,
              ),
              child: Center(
                child: isPast
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                    : Text('${i + 1}',
                        style: TextStyle(
                            color: isActive ? Colors.white : Colors.grey,
                            fontWeight: FontWeight.bold)),
              ),
            ),
            if (i < total - 1)
              Container(
                width: 40,
                height: 2,
                color: isPast ? Colors.green : Colors.grey.shade800,
              ),
          ],
        );
      }),
    );
  }
}

// ── 步骤数据 ──

class _StepInfo {
  final IconData icon;
  final String title;
  final String desc;
  final String buttonText;
  final VoidCallback onTap;
  final bool isDone;

  _StepInfo({
    required this.icon,
    required this.title,
    required this.desc,
    required this.buttonText,
    required this.onTap,
    required this.isDone,
  });
}
