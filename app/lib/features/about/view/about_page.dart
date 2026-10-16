import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/app/app_info.dart';
import 'package:lanka_radar/core/links.dart';

/// The app's version, where its data comes from, its code and licenses.
class AboutPage extends StatelessWidget {
  const AboutPage({this.open = openExternally, super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (context) => const AboutPage());

  static const repository = 'https://github.com/ThivaaVipul/lanka-radar';

  final OpenLink open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final version = context.read<AppInfo>().version;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text('Lanka Radar', style: theme.textTheme.headlineSmall),
          Text('Version $version', style: quiet),
          const SizedBox(height: 16),
          Text(
            'What Sri Lankan official sources publish: gazettes, prices, '
            'rates, holidays and exams.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Not affiliated with any of them. Every item links to its '
            'official source.',
            style: quiet,
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('Source code'),
                  onTap: () => open(Uri.parse(repository)),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Licenses'),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Lanka Radar',
                    applicationVersion: version,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
