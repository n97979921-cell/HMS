import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
// lib/widgets/app_ui.dart
// App UI kit — poori app (admin, doctor, patient, receptionist,
// lab staff) ke liye ek hi design file: colors + reusable widgets.
// Is file mein koi Firestore / business logic nahi hai.
//
// Kisi bhi screen mein use karne ke liye import:
//   lib/screens/...            → import '../widgets/app_ui.dart';
//   lib/doctor_screens/...     → import '../widgets/app_ui.dart';
//   lib/patient_screens/...    → import '../widgets/app_ui.dart';
//   ya kahin se bhi            → import 'package:hospital_management_app/widgets/app_ui.dart';
// ─────────────────────────────────────────────────────────────

class AppColors {
  static const Color header = Color(0xFF0B2E33);
  static const Color mint = Color(0xFF7FE0C8);
  static const Color bg = Color(0xFFF2F5F5);
  static const Color teal = Color(0xFF0E6E68);
  static const Color tealSoft = Color(0xFFE6F3F0);
  static const Color text = Color(0xFF0E1E21);
  static const Color muted = Color(0xFF52666A);
  static const Color faint = Color(0xFF8A9A9C);
  static const Color headerMuted = Color(0xFFA9C7C4);
  static const Color headerLabel = Color(0xFF7FA6A2);
  static const Color border = Color(0xFFDCE5E5);
  static const Color divider = Color(0xFFE6ECEC);
  static const Color danger = Color(0xFFB23A1E);
  static const Color dangerSoft = Color(0xFFFBEDE8);
  static const Color blue = Color(0xFF1D4F91);
  static const Color blueSoft = Color(0xFFE3EEFB);
  static const Color star = Color(0xFFFFD27A);
}

/// Status chip colors (text, background) — same palette for all admin screens.
class AppChipColors {
  final Color fg;
  final Color bg;
  const AppChipColors(this.fg, this.bg);

  static const green = AppChipColors(Color(0xFF0B5E57), Color(0xFFDDF3EE));
  static const red = AppChipColors(Color(0xFF9A2E16), Color(0xFFFBE6E0));
  static const blue = AppChipColors(Color(0xFF1D4F91), Color(0xFFE3EEFB));
  static const yellow = AppChipColors(Color(0xFF5B4B00), Color(0xFFF6F2E2));
  static const purple = AppChipColors(Color(0xFF5B3FA8), Color(0xFFEEE8FB));
  static const grey = AppChipColors(Color(0xFF52666A), Color(0xFFECEFEF));
}

/// Dark rounded header used on every admin screen.
class AppHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? bottom;
  final IconData leadingIcon;
  final Widget? trailing;

  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.bottom,
    this.leadingIcon = Icons.arrow_back_ios_new_rounded,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.header,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AppHeaderIconButton(
                    icon: leadingIcon,
                    tooltip: 'Back',
                    onTap: onBack ?? () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.headerMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  trailing ?? const SizedBox(width: 44),
                ],
              ),
              if (bottom != null) ...[
                const SizedBox(height: 16),
                bottom!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AppHeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const AppHeaderIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.white.withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withOpacity(0.18)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }
}

/// White rounded card.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Rounded square icon tile (e.g. department icon).
class AppIconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color? background;
  final double size;

  const AppIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.background,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Small pill-shaped status label.
class AppStatusChip extends StatelessWidget {
  final String label;
  final AppChipColors colors;
  final double fontSize;

  const AppStatusChip({
    super.key,
    required this.label,
    required this.colors,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.fg,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Soft "Edit" button used inside cards.
class AppSoftButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color background;

  const AppSoftButton({
    super.key,
    required this.label,
    required this.onTap,
    this.color = AppColors.teal,
    this.background = AppColors.tealSoft,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// Square trash button (soft red).
class AppDeleteButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  final String tooltip;

  const AppDeleteButton({
    super.key,
    required this.onTap,
    this.size = 36,
    this.tooltip = 'Delete',
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(Icons.delete_outline_rounded,
                color: AppColors.danger, size: size * 0.46),
          ),
        ),
      ),
    );
  }
}

/// "Delete all" pill button shown above lists.
class AppDeleteAllButton extends StatelessWidget {
  final VoidCallback onTap;

  const AppDeleteAllButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.dangerSoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline_rounded,
                  size: 15, color: AppColors.danger),
              SizedBox(width: 6),
              Text(
                'Delete all',
                style: TextStyle(
                  color: AppColors.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dark extended floating button ("+ Add …").
class AppFab extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const AppFab({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onPressed,
      backgroundColor: AppColors.header,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: const Icon(Icons.add_rounded, color: AppColors.mint, size: 24),
      label: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Header dropdown (dark style) — e.g. STATUS / TYPE filters.
/// Tap karne par menu khulta hai; bahar tap karne se band ho jata hai.
class AppHeaderDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String Function(String option)? displayOf;
  final Color Function(String option)? dotColorOf;

  const AppHeaderDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.displayOf,
    this.dotColorOf,
  });

  String _display(String o) => displayOf?.call(o) ?? o;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onChanged,
      offset: const Offset(0, 60),
      color: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (_) => options.map((o) {
        final selected = o == value;
        return PopupMenuItem<String>(
          value: o,
          height: 42,
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColorOf?.call(o) ?? AppColors.faint,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _display(o),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.text,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded,
                    size: 18, color: AppColors.teal),
            ],
          ),
        );
      }).toList(),
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.headerLabel,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _display(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.mint, size: 22),
          ],
        ),
      ),
    );
  }
}

/// Empty-state card.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: const Color(0xFF9DB3B1)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.muted,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.faint),
            ),
          ],
        ],
      ),
    );
  }
}

/// Label/value row used inside cards (Patient, Doctor, Date…).
class AppInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final double labelWidth;

  const AppInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = 64,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.text,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Text field style for admin sheets/dialogs.
InputDecoration appInputDecoration({
  String? hint,
  String? prefixText,
  bool filled = false,
}) {
  OutlineInputBorder b(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.faint),
    prefixText: prefixText,
    prefixStyle: const TextStyle(
      color: AppColors.muted,
      fontWeight: FontWeight.w800,
    ),
    filled: true,
    fillColor: filled ? AppColors.bg : Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    border: b(AppColors.border),
    enabledBorder: b(AppColors.border),
    disabledBorder: b(AppColors.bg),
    focusedBorder: b(AppColors.teal),
  );
}

/// Field label above inputs.
class AppFieldLabel extends StatelessWidget {
  final String text;
  const AppFieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
    );
  }
}

/// Popup window shell (title + close button + content).
class AppSheet extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const AppSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.teal,
                        ),
                      ),
                  ],
                ),
              ),
              Material(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(context),
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(Icons.close_rounded,
                        color: AppColors.muted, size: 20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

/// Opens [AppSheet] content as a rounded popup window.
/// Window ke bahar tap karne se band ho jati hai (barrierDismissible).
/// Dialog isliye rakha hai taake purane SnackBar messages (jaise
/// "Test name is required") pehle ki tarah neeche nazar aayein.
Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showDialog<T>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: builder(ctx),
    ),
  );
}

/// Dark primary button (Save etc.)
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? child;

  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.header,
          disabledBackgroundColor: AppColors.header.withOpacity(0.6),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: child ??
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
      ),
    );
  }
}

/// Light info note (ⓘ + text).
class AppInfoNote extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const AppInfoNote({super.key, required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F0F0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 17, color: AppColors.teal),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF3B4F53),
                height: 1.4,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// Small text pill for header actions (e.g. "Select", "Deleted").
class AppHeaderPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool danger;

  const AppHeaderPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = danger ? const Color(0xFFFFB4A3) : Colors.white;
    return Material(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 16, color: onTap == null ? fg.withOpacity(0.4) : fg),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: onTap == null ? fg.withOpacity(0.4) : fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search field styled for the dark header.
class AppHeaderSearch extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback? onClear;

  const AppHeaderSearch({
    super.key,
    required this.controller,
    this.hint = 'Search…',
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        cursorColor: AppColors.mint,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              const TextStyle(color: AppColors.headerMuted, fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.mint),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.headerMuted, size: 20),
                  onPressed: onClear ?? () => controller.clear(),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}
