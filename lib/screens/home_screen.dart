import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yanji/widgets/sidebar.dart';
import 'package:yanji/screens/meeting_list_screen.dart';
import 'package:yanji/screens/audio_test_screen.dart';
import 'package:yanji/screens/settings_screen.dart';
import 'package:yanji/screens/statistics_screen.dart';
import 'package:yanji/screens/log_viewer_screen.dart';
import 'package:yanji/providers/meeting_session_provider.dart';
import 'package:yanji/utils/config_loader.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isSidebarOpen = false;
  late AnimationController _sidebarAnimController;
  late Animation<double> _sidebarSlideAnimation;
  late Animation<double> _backdropAnimation;

  static const List<Widget> _screens = <Widget>[
    MeetingListScreen(),
    StatisticsScreen(),
    AudioTestScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _sidebarAnimController = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );
    _sidebarSlideAnimation = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(parent: _sidebarAnimController, curve: Curves.easeOutCubic),
    );
    _backdropAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _sidebarAnimController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _sidebarAnimController.dispose();
    super.dispose();
  }

  void _openSidebar() {
    if (!_isSidebarOpen) {
      setState(() => _isSidebarOpen = true);
      _sidebarAnimController.forward();
    }
  }

  void _closeSidebar() {
    if (_isSidebarOpen) {
      _sidebarAnimController.reverse().then((_) {
        if (mounted) setState(() => _isSidebarOpen = false);
      });
    }
  }

  void _toggleSidebar() {
    if (_isSidebarOpen) {
      _closeSidebar();
    } else {
      _openSidebar();
    }
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    _closeSidebar();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    if (!isMobile) {
      return _buildDesktopLayout();
    }
    return _buildMobileLayout(screenWidth);
  }

  // ==================== 桌面端布局 ====================

  Widget _buildDesktopLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('言记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LogViewerScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // 桌面端侧边栏
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            width: _isSidebarOpen ? 250 : 60,
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Column(
                children: [
                  Container(
                    height: 60,
                    alignment: Alignment.center,
                    child: IconButton(
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          _isSidebarOpen ? Icons.menu_open : Icons.menu,
                          key: ValueKey(_isSidebarOpen),
                        ),
                      ),
                      onPressed: _toggleSidebar,
                    ),
                  ),
                  Expanded(
                    child: _isSidebarOpen
                        ? Sidebar(
                            currentIndex: _selectedIndex,
                            onItemTapped: _onItemTapped,
                          )
                        : const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
          // 主内容区域
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              child: _screens[_selectedIndex],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  // ==================== 移动端布局 ====================

  Widget _buildMobileLayout(double screenWidth) {
    final sidebarWidth = screenWidth * 0.75;
    final sidebarAnim = _sidebarSlideAnimation;
    final backdropAnim = _backdropAnimation;

    return Scaffold(
      appBar: AppBar(
        title: const Text('言记'),
        leading: IconButton(
          icon: AnimatedIcon(
            icon: AnimatedIcons.menu_close,
            progress: _sidebarAnimController,
          ),
          onPressed: _toggleSidebar,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LogViewerScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 主内容（带左边缘滑动手势）
          GestureDetector(
            onHorizontalDragEnd: _isSidebarOpen
                ? null
                : (details) {
                    if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
                      _openSidebar();
                    }
                  },
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              child: _screens[_selectedIndex],
            ),
          ),

          // 半透明遮罩
          if (_isSidebarOpen)
            AnimatedBuilder(
              animation: backdropAnim,
              builder: (context, _) {
                return GestureDetector(
                  onTap: _closeSidebar,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.4 * backdropAnim.value),
                  ),
                );
              },
            ),

          // 侧边栏滑入
          AnimatedBuilder(
            animation: sidebarAnim,
            builder: (context, child) {
              final slideOffset = sidebarAnim.value * sidebarWidth;
              return Transform.translate(
                offset: Offset(slideOffset, 0),
                child: child,
              );
            },
            child: SizedBox(
              width: sidebarWidth,
              height: double.infinity,
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  // 向右滑关闭
                  if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
                    _closeSidebar();
                  }
                },
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  elevation: 4,
                  child: SafeArea(
                    child: Sidebar(
                      currentIndex: _selectedIndex,
                      onItemTapped: _onItemTapped,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  Widget? _buildFab() {
    if (_selectedIndex == 0) {
      return FloatingActionButton(
        onPressed: _startNewMeeting,
        child: const Icon(Icons.add),
        tooltip: '开始新会议',
      );
    }
    if (_selectedIndex == 1) {
      return FloatingActionButton(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AudioTestScreen()));
        },
        child: const Icon(Icons.build),
        tooltip: '系统检测',
      );
    }
    return null;
  }

  Future<void> _startNewMeeting() async {
    final provider = Provider.of<MeetingSessionProvider>(context, listen: false);
    final config = await ConfigLoader.loadConfig();

    // 自动标题：会议 MM-dd HH:mm
    final now = DateTime.now();
    final title = '会议 ${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // 取第一个可用的 ASR 和摘要模型
    final asrModel = config.asrModels.isNotEmpty ? config.asrModels.first.name : '';
    final summaryModel = config.llmModels.isNotEmpty ? config.llmModels.first.name : '';

    await provider.createSession(
      title: title,
      asrModelName: asrModel,
      summaryModelName: summaryModel,
    );

    if (mounted) {
      Navigator.of(context).pushNamed('/meeting-recording');
    }
  }
}