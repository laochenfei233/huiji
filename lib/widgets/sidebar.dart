import 'package:flutter/material.dart';
import 'package:yanji/screens/settings_screen.dart';
import 'package:yanji/screens/profile_screen.dart';

class Sidebar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onItemTapped;
  
  const Sidebar({
    super.key, 
    required this.currentIndex, 
    required this.onItemTapped
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          // 顶部区域 - 设置和账户
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: const Text('账户'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('设置'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          const Divider(),
          // 中间区域 - 功能菜单
          ListTile(
            leading: const Icon(Icons.meeting_room),
            title: const Text('会议列表'),
            selected: currentIndex == 0,
            onTap: () => onItemTapped(0),
          ),
          ListTile(
            leading: const Icon(Icons.analytics),
            title: const Text('数据统计'),
            selected: currentIndex == 1,
            onTap: () => onItemTapped(1),
          ),
          // 系统检测工具
          ListTile(
            leading: const Icon(Icons.build),
            title: const Text('系统检测'),
            selected: currentIndex == 2,
            onTap: () => onItemTapped(2),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}