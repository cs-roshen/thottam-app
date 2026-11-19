import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/session.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../data/onboarding_providers.dart';

/// The sign-in step, and the first sync after it: the one step that waits
/// for the network (screens.md 1). Offline, it says so once and goes on by
/// itself when a connection returns.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // reopened after sign-in but before the first sync finished
    if (ref.read(sessionProvider).account != null) {
      Future.microtask(() => ref.read(firstSyncProvider.notifier).run());
    }
  }

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      final account = await ref.read(authGatewayProvider).signIn();
      await ref.read(sessionProvider.notifier).signIn(account);
      await ref.read(firstSyncProvider.notifier).run();
    } on Exception {
      if (mounted) {
        showToast(context, AppLocalizations.of(context).signInFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final signedIn =
        ref.watch(sessionProvider.select((s) => s.account)) != null;
    final offline = ref.watch(firstSyncProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.signInTitle)),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(t.screenPadding),
          children: [
            Text(l10n.signInBody, style: text.bodyMedium),
            SizedBox(height: t.cardGap * 2),
            if (!signedIn) ...[
              PrimaryButton(
                key: const Key('signIn.test'),
                label: l10n.signInTestAccount,
                icon: Icons.login,
                onPressed: _busy ? null : _signIn,
              ),
              const SizedBox(height: 10),
              Text(l10n.signInTestAccountHint, style: text.bodySmall),
            ] else if (offline)
              Semantics(
                liveRegion: true,
                child: LastTimeBanner(
                  key: const Key('signIn.offline'),
                  text: l10n.signInNeedsConnection,
                  icon: Icons.wifi_off,
                ),
              )
            else ...[
              Text(l10n.signInRestoring, style: text.bodyLarge),
              SizedBox(height: t.cardGap),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}
