import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../screens/dashboard/dashboard_overview_screen.dart';
import '../app_drawer.dart';

/// Standardized AppBar used across ALL screens in MediBro.
///
/// Layout:
///   [Back Button (if canPop)] | [MediBro Logo (clickable to Dashboard) + Title] | [optional actions] | [Burger Menu]
class MediAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBack;
  final VoidCallback? onBack;
  final Color backgroundColor;

  const MediAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBack = true,
    this.onBack,
    this.backgroundColor = AppColors.primary,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  void _navigateToDashboard(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const DashboardOverviewScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    final showBackBtn = showBack && canPop;

    return AppBar(
      backgroundColor: backgroundColor,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      leading: showBackBtn
          ? IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: onBack ?? () => Navigator.pop(context),
              tooltip: 'Back',
            )
          : null,
      title: Padding(
        padding: EdgeInsets.only(left: showBackBtn ? 0 : 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => _navigateToDashboard(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Image.asset(
                  'assets/images/mb_logo.png',
                  height: 32,
                  width: 78,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.local_pharmacy_rounded,
                      color: Colors.white,
                      size: 22,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              height: 18,
              width: 1.5,
              color: Colors.white.withValues(alpha: 0.35),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (actions != null) ...actions!,
        Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 26),
            onPressed: () {
              final scaffold = Scaffold.maybeOf(ctx);
              if (scaffold != null && scaffold.hasEndDrawer) {
                scaffold.openEndDrawer();
              } else if (scaffold != null && scaffold.hasDrawer) {
                scaffold.openDrawer();
              } else {
                showGeneralDialog(
                  context: ctx,
                  barrierDismissible: true,
                  barrierLabel: 'Drawer',
                  pageBuilder: (context, anim1, anim2) => const Align(
                    alignment: Alignment.centerRight,
                    child: AppDrawer(),
                  ),
                );
              }
            },
            tooltip: 'Menu',
          ),
        ),
      ],
    );
  }
}
