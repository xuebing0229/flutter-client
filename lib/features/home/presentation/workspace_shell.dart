import 'package:flutter/material.dart';

import '../../../core/theme/guild_visual_theme.dart';
import 'app_drawer.dart';

class GuildWorkspaceTab {
  const GuildWorkspaceTab({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

/// Shared application chrome used by Android, Windows and Web.
///
/// Platform-specific code owns storage, sync and account capabilities. The
/// visible navigation shell stays here so a UI/menu change is made once.
class GuildWorkspaceShell extends StatelessWidget {
  const GuildWorkspaceShell({
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.title,
    required this.ready,
    required this.contentAvailable,
    required this.mobileBody,
    required this.desktopBody,
    required this.drawer,
    required this.desktopToolMenu,
    required this.desktopNavigationOpen,
    required this.onDesktopNavigationChanged,
    required this.toolSelected,
    this.unavailableBody,
    this.floatingActionButton,
    this.showAppBar = true,
    super.key,
  });

  final List<GuildWorkspaceTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final String title;
  final bool ready;
  final bool contentAvailable;
  final Widget mobileBody;
  final Widget desktopBody;
  final Widget drawer;
  final Widget desktopToolMenu;
  final bool desktopNavigationOpen;
  final ValueChanged<bool> onDesktopNavigationChanged;
  final bool toolSelected;
  final Widget? unavailableBody;
  final Widget? floatingActionButton;
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useDesktopLayout = width >= 900;
    final uiStyle = GuildStyleTheme.of(context);

    return Scaffold(
      extendBody: uiStyle.isGlass && !useDesktopLayout,
      drawer: ready && contentAvailable ? drawer : null,
      appBar: showAppBar
          ? AppBar(
              leading: useDesktopLayout
                  ? IconButton(
                      tooltip:
                          desktopNavigationOpen ? '收起主导航' : '展开主导航',
                      icon: Icon(
                        desktopNavigationOpen
                            ? Icons.menu_open_rounded
                            : Icons.menu_rounded,
                      ),
                      onPressed: () => onDesktopNavigationChanged(
                        !desktopNavigationOpen,
                      ),
                    )
                  : null,
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
      body: GuildStyleBackdrop(
        child: !ready
            ? const Center(child: CircularProgressIndicator())
            : !contentAvailable
                ? (unavailableBody ?? const SizedBox.shrink())
                : useDesktopLayout
                    ? Row(
                        children: [
                          ClipRect(
                            child: AnimatedSize(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeInOut,
                              alignment: Alignment.centerLeft,
                              child: desktopNavigationOpen
                                  ? GuildStyledSurface(
                                      role: GuildSurfaceRole.chrome,
                                      backdropAvailable: false,
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .surface,
                                      child: SizedBox(
                                        width: 320,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            ListView(
                                              shrinkWrap: true,
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                12,
                                                12,
                                                12,
                                                8,
                                              ),
                                              children: [
                                                for (
                                                  var index = 0;
                                                  index < tabs.length;
                                                  index++
                                                )
                                                  AppMenuTile(
                                                    icon: tabs[index].icon,
                                                    selectedIcon:
                                                        tabs[index]
                                                            .selectedIcon,
                                                    title:
                                                        tabs[index].label,
                                                    selected: !toolSelected &&
                                                        selectedIndex == index,
                                                    onTap: () =>
                                                        onTabSelected(index),
                                                  ),
                                              ],
                                            ),
                                            const Divider(height: 1),
                                            Expanded(
                                              child: desktopToolMenu,
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeInOut,
                            width: desktopNavigationOpen ? 1 : 0,
                            child: const VerticalDivider(width: 1),
                          ),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: desktopBody,
                            ),
                          ),
                        ],
                      )
                    : mobileBody,
      ),
      floatingActionButton:
          ready && contentAvailable && !toolSelected
              ? floatingActionButton
              : null,
      bottomNavigationBar:
          !ready || !contentAvailable || tabs.length <= 1 || useDesktopLayout
              ? null
              : GuildStyledSurface(
                  role: GuildSurfaceRole.chrome,
                  backdropAvailable: uiStyle.isGlass,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainer,
                  child: NavigationBar(
                    backgroundColor:
                        uiStyle.isClassic ? null : Colors.transparent,
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onTabSelected,
                    destinations: [
                      for (final tab in tabs)
                        NavigationDestination(
                          icon: Icon(tab.icon),
                          selectedIcon: Icon(tab.selectedIcon),
                          label: tab.label,
                        ),
                    ],
                  ),
                ),
    );
  }
}
