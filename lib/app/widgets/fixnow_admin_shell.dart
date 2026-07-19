import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'resilient_asset_image.dart';

class FixNowAdminDestination {
  const FixNowAdminDestination({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

class FixNowAdminShell extends StatelessWidget {
  const FixNowAdminShell({
    super.key,
    required this.destinations,
    required this.selectedId,
    required this.onDestinationSelected,
    required this.userName,
    required this.roleLabel,
    required this.consoleLabel,
    required this.body,
    this.contextLabel,
    this.navigationFooter,
    this.onSignOut,
    this.isLoading = false,
    this.errorMessage,
  });

  final List<FixNowAdminDestination> destinations;
  final String selectedId;
  final ValueChanged<String> onDestinationSelected;
  final String userName;
  final String roleLabel;
  final String consoleLabel;
  final String? contextLabel;
  final Widget body;
  final Widget? navigationFooter;
  final VoidCallback? onSignOut;
  final bool isLoading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final selected = destinations.firstWhere(
      (item) => item.id == selectedId,
      orElse: () => destinations.first,
    );
    final tableTheme = DataTableThemeData(
      headingRowColor: WidgetStateProperty.all(AppTheme.surface),
      headingTextStyle: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
      dataTextStyle: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 13,
      ),
      dividerThickness: 0.8,
      horizontalMargin: 18,
      columnSpacing: 26,
    );
    return Theme(
      data: Theme.of(context).copyWith(dataTableTheme: tableTheme),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 960;
          Widget navigation({required bool closeDrawer}) {
            return _AdminNavigationPanel(
              destinations: destinations,
              selectedId: selectedId,
              consoleLabel: consoleLabel,
              userName: userName,
              roleLabel: roleLabel,
              footer: navigationFooter,
              onSignOut: onSignOut,
              onSelected: (id) {
                onDestinationSelected(id);
                if (closeDrawer) Navigator.pop(context);
              },
            );
          }

          return Scaffold(
            backgroundColor: AppTheme.background,
            appBar: desktop
                ? null
                : AppBar(
                    toolbarHeight: 66,
                    titleSpacing: 8,
                    title: Row(
                      children: [
                        const ResilientAssetImage(
                          assetName: 'assets/images/fixnow_logo.png',
                          width: 36,
                          height: 36,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selected.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                contextLabel ?? consoleLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      if (onSignOut != null)
                        IconButton(
                          tooltip: 'Sign out',
                          onPressed: onSignOut,
                          icon: const Icon(Icons.logout_outlined),
                        ),
                    ],
                  ),
            drawer: desktop
                ? null
                : Drawer(
                    width: 280,
                    child: navigation(closeDrawer: true),
                  ),
            body: SafeArea(
              top: desktop,
              child: Row(
                children: [
                  if (desktop)
                    SizedBox(
                      width: 264,
                      child: navigation(closeDrawer: false),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        if (desktop)
                          _AdminTopBar(
                            title: selected.label,
                            contextLabel: contextLabel ?? consoleLabel,
                            userName: userName,
                            roleLabel: roleLabel,
                            onSignOut: onSignOut,
                          ),
                        if (isLoading)
                          const LinearProgressIndicator(minHeight: 2),
                        if (errorMessage != null)
                          MaterialBanner(
                            content: Text(errorMessage!),
                            leading: const Icon(Icons.error_outline),
                            actions: const [SizedBox.shrink()],
                          ),
                        if (!desktop)
                          _AdminMobileSectionBar(
                            destinations: destinations,
                            selectedId: selectedId,
                            onSelected: onDestinationSelected,
                          ),
                        Expanded(child: RepaintBoundary(child: body)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AdminNavigationPanel extends StatelessWidget {
  const _AdminNavigationPanel({
    required this.destinations,
    required this.selectedId,
    required this.consoleLabel,
    required this.userName,
    required this.roleLabel,
    required this.onSelected,
    this.footer,
    this.onSignOut,
  });

  final List<FixNowAdminDestination> destinations;
  final String selectedId;
  final String consoleLabel;
  final String userName;
  final String roleLabel;
  final ValueChanged<String> onSelected;
  final Widget? footer;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0D2344),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 18, 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const ResilientAssetImage(
                      assetName: 'assets/images/fixnow_logo.png',
                      width: 36,
                      height: 36,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'FixNow',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          consoleLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF9CB5D9),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                'WORKSPACE',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: destinations.length,
                itemExtent: 54,
                itemBuilder: (context, index) {
                  final destination = destinations[index];
                  return _AdminNavigationTile(
                    destination: destination,
                    selected: destination.id == selectedId,
                    onTap: () => onSelected(destination.id),
                  );
                },
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: footer,
              ),
            const Divider(color: Color(0xFF284260)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    child: Icon(Icons.shield_outlined, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName.isEmpty ? roleLabel : userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          roleLabel,
                          style: const TextStyle(
                            color: Color(0xFF9CB5D9),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onSignOut != null)
                    IconButton(
                      tooltip: 'Sign out',
                      onPressed: onSignOut,
                      icon: const Icon(
                        Icons.logout_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminMobileSectionBar extends StatelessWidget {
  const _AdminMobileSectionBar({
    required this.destinations,
    required this.selectedId,
    required this.onSelected,
  });

  final List<FixNowAdminDestination> destinations;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: SizedBox(
        height: 50,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          itemCount: destinations.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final destination = destinations[index];
            final selected = destination.id == selectedId;
            return Material(
              color: selected ? AppTheme.primary : AppTheme.surface,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => onSelected(destination.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  child: Row(
                    children: [
                      Icon(
                        destination.icon,
                        size: 17,
                        color: selected ? Colors.white : AppTheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        destination.label,
                        style: TextStyle(
                          color: selected ? Colors.white : AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AdminNavigationTile extends StatefulWidget {
  const _AdminNavigationTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final FixNowAdminDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_AdminNavigationTile> createState() => _AdminNavigationTileState();
}

class _AdminNavigationTileState extends State<_AdminNavigationTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          transform: Matrix4.translationValues(_hovered ? 3 : 0, 0, 0),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppTheme.primary
                : _hovered
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            dense: true,
            minLeadingWidth: 24,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            leading: Icon(widget.destination.icon, size: 21),
            iconColor: widget.selected ? Colors.white : const Color(0xFFB9CAE3),
            textColor: widget.selected ? Colors.white : const Color(0xFFD7E2F2),
            title: Text(
              widget.destination.label,
              style: TextStyle(
                fontWeight: widget.selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            onTap: widget.onTap,
          ),
        ),
      ),
    );
  }
}

class _AdminTopBar extends StatelessWidget {
  const _AdminTopBar({
    required this.title,
    required this.contextLabel,
    required this.userName,
    required this.roleLabel,
    this.onSignOut,
  });

  final String title;
  final String contextLabel;
  final String userName;
  final String roleLabel;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  contextLabel,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  color: AppTheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 7),
                Text(
                  userName.isEmpty ? roleLabel : userName,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (onSignOut != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Sign out',
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_outlined),
            ),
          ],
        ],
      ),
    );
  }
}

class FixNowAdminSkeleton extends StatefulWidget {
  const FixNowAdminSkeleton({super.key, this.label = 'Loading dashboard'});

  final String label;

  @override
  State<FixNowAdminSkeleton> createState() => _FixNowAdminSkeletonState();
}

class _FixNowAdminSkeletonState extends State<FixNowAdminSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final color = Color.lerp(
            AppTheme.surface,
            const Color(0xFFE7EEF9),
            _controller.value,
          )!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SkeletonBlock(width: 250, height: 28, color: color),
                const SizedBox(height: 10),
                _SkeletonBlock(width: 390, height: 14, color: color),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: List.generate(
                    4,
                    (_) => _SkeletonBlock(
                      width: 230,
                      height: 104,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _SkeletonBlock(height: 280, color: color),
                const SizedBox(height: 18),
                _SkeletonBlock(height: 180, color: color),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    this.width = double.infinity,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider.withValues(alpha: 0.7)),
      ),
    );
  }
}

class FixNowHoverCard extends StatefulWidget {
  const FixNowHoverCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  State<FixNowHoverCard> createState() => _FixNowHoverCardState();
}

class _FixNowHoverCardState extends State<FixNowHoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor:
          widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hovered
                ? AppTheme.primary.withValues(alpha: 0.28)
                : AppTheme.divider,
          ),
          boxShadow: _hovered
              ? const [
                  BoxShadow(
                    color: Color(0x140B5EEA),
                    blurRadius: 18,
                    offset: Offset(0, 7),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}
