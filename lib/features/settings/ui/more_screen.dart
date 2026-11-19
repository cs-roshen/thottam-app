import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../l10n/app_localizations.dart';
import 'pages.dart';

/// Screen 6: a tile for every page switched on that the role can open,
/// then Settings.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final hidden = ref.watch(settingsProvider.select((s) => s.hiddenPages));
    final access = ref.watch(accessProvider).value;
    final pages = [
      for (final p in appPages)
        if (!hidden.contains(p.code) && (access?.canRead(p.needs) ?? false)) p,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navMore)),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          LayoutBuilder(
            builder: (context, box) {
              const gap = 10.0;
              final width = (box.maxWidth - 2 * gap) / 3;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final p in pages)
                    SizedBox(
                      width: width,
                      child: _PageTile(page: p),
                    ),
                ],
              );
            },
          ),
          SizedBox(height: t.cardGap),
          ThottamCard(
            key: const Key('more.settings'),
            onTap: () => context.go('/more/settings'),
            child: Row(
              children: [
                TintIconTile(
                  icon: Icons.tune,
                  background: t.lineSoft,
                  foreground: t.ink,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.settingsTitle, style: text.titleMedium),
                      Text(l10n.moreSettingsHint, style: text.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: t.muted),
              ],
            ),
          ),
          if (kDebugMode)
            ListTile(
              key: const Key('more.gallery'),
              leading: const Icon(Icons.widgets_outlined),
              title: Text(l10n.debugWidgetGallery),
              onTap: () => context.go('/more/gallery'),
            ),
        ],
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({required this.page});

  final AppPage page;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final (bg, fg) = page.colours(t);
    final radius = BorderRadius.circular(t.tileRadius);
    return Material(
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: t.line),
      ),
      child: InkWell(
        key: Key('more.page.${page.code}'),
        borderRadius: radius,
        onTap: () => context.push(page.path),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 104),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TintIconTile(icon: page.icon, background: bg, foreground: fg),
                const SizedBox(height: 8),
                Text(
                  page.label(l10n),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
