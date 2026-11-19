import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_parse.dart';
import '../../l10n/app_localizations.dart';
import '../theme/tokens.dart';

/// White card with the standard radius and padding.
class ThottamCard extends StatelessWidget {
  const ThottamCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(t.cardRadius);
    return Material(
      color: t.surface,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(padding: EdgeInsets.all(t.cardPadding), child: child),
      ),
    );
  }
}

/// Square tinted tile with a matching dark icon. When tappable it needs a
/// [label] and keeps a 48 dp hit area even when drawn smaller.
class TintIconTile extends StatelessWidget {
  const TintIconTile({
    super.key,
    required this.icon,
    required this.background,
    required this.foreground,
    this.size = 48,
    this.label,
    this.onTap,
  }) : assert(
         onTap == null || label != null,
         // gate: not user-facing
         'tap needs label',
       );

  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(t.tileRadius);
    final tile = Material(
      color: background,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, color: foreground, size: t.iconSize),
        ),
      ),
    );
    final hit = onTap == null ? size : (size < t.minTouch ? t.minTouch : size);
    return Semantics(
      label: label,
      button: onTap != null,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: hit,
        child: Center(child: tile),
      ),
    );
  }
}

/// Large rupee input that opens with the number keypad up.
class AmountInput extends StatelessWidget {
  const AmountInput({
    super.key,
    required this.label,
    required this.hint,
    required this.onChanged,
    this.controller,
    this.autofocus = true,
  });

  final String label;
  final String hint;
  final ValueChanged<int?> onChanged;
  final TextEditingController? controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      hint: hint,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        style: text.displayLarge,
        decoration: InputDecoration(
          labelText: label,
          prefixText: '₹ ',
          prefixStyle: text.displayLarge,
        ),
        onChanged: (v) => onChanged(parseRupeesToPaise(v)),
      ),
    );
  }
}

/// Says what a screen is for and offers the first action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TintIconTile(
          icon: icon,
          background: t.primaryTint,
          foreground: t.primaryDark,
          size: t.tintTileLarge,
        ),
        SizedBox(height: t.cardGap),
        Text(title, style: text.titleMedium, textAlign: TextAlign.center),
        Text(message, style: text.bodySmall, textAlign: TextAlign.center),
        if (actionLabel != null) ...[
          SizedBox(height: t.cardGap),
          FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    );
  }
}

/// Yellow "last time" or "due" banner; also for a notice such as "needs a
/// connection", with its own [icon].
class LastTimeBanner extends StatelessWidget {
  const LastTimeBanner({
    super.key,
    required this.text,
    this.icon = Icons.history,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(t.cardGap),
      decoration: BoxDecoration(
        color: t.noticeBg,
        border: Border.all(color: t.noticeLine),
        borderRadius: BorderRadius.circular(t.tileRadius),
      ),
      child: Row(
        children: [
          Icon(icon, color: t.onAccentTint, size: t.iconSize),
          SizedBox(width: t.cardGap),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Marks data older than a day; text and icon, never colour alone.
class StaleDataTag extends StatelessWidget {
  const StaleDataTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: t.onNegativeTint);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: t.negativeTint,
        borderRadius: BorderRadius.circular(t.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 16, color: t.onNegativeTint),
          const SizedBox(width: 4),
          Flexible(child: Text(label, style: style)),
        ],
      ),
    );
  }
}

/// Toast without an action; disappears after about 1.9 s.
void showToast(BuildContext context, String message) {
  final t = context.tokens;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: t.toastStay,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// Toast with an undo action; disappears after about 1.9 s.
void showUndoToast(BuildContext context, String message, VoidCallback onUndo) {
  final t = context.tokens;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: t.toastStay,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: AppLocalizations.of(context).actionUndo,
          textColor: t.accent,
          onPressed: onUndo,
        ),
      ),
    );
}

/// Bottom sheet with 28 dp top corners.
Future<T?> showThottamSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final t = context.tokens;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: t.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(t.sheetRadius)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          t.screenPadding,
          0,
          t.screenPadding,
          t.screenPadding,
        ),
        child: builder(context),
      ),
    ),
  );
}
