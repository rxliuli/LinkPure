import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/theme_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final themeService = ThemeService.instance;
    
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Theme'),
            subtitle: Text(themeService.getThemeModeLabel(themeService.themeMode)),
            onTap: () => _showThemeDialog(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Notifications'),
            subtitle: const Text('Show notification after cleaning'),
            trailing: Switch(value: true, onChanged: (value) {}),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('About'),
            subtitle: const Text('LinkPure v1.0.0'),
            onTap: () async {
              final uri = Uri.parse('https://rxliuli.com/project/linkpure');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
    );
  }
  
  void _showThemeDialog(BuildContext context) {
    final themeService = ThemeService.instance;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ThemeMode.values.map((mode) {
            return RadioListTile<ThemeMode>(
              title: Text(themeService.getThemeModeLabel(mode)),
              value: mode,
              groupValue: themeService.themeMode,
              onChanged: (value) {
                if (value != null) {
                  themeService.setThemeMode(value);
                  setState(() {});
                  Navigator.of(context).pop();
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
