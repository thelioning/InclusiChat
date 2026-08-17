import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'brand_logo.dart';

class BrandAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BrandAppBar({
    super.key,
    this.title = 'InclusiChat',
    this.actions = const [],
    this.showBackButton = false,
  });

  final String title;
  final List<Widget> actions;
  final bool showBackButton;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: showBackButton,
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      titleSpacing: showBackButton ? 0 : 16,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BrandLogo(size: 38),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      actions: actions,
    );
  }
}
