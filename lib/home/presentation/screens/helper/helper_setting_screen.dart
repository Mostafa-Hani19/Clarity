// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../routes/app_router.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../services/language_service.dart';

class HelperSettingScreen extends StatefulWidget {
  const HelperSettingScreen({super.key});
  @override
  State<HelperSettingScreen> createState() => _HelperSettingScreenState();
}

class _HelperSettingScreenState extends State<HelperSettingScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _errorMessage;

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = false); // لو عندك تحميل بيانات فعلي عدل هنا
  }

  Future<void> _editField({
    required BuildContext context,
    required String title,
    required String currentValue,
    required Future<bool> Function(String) onSave,
    bool isPassword = false,
    String? subtitle,
    bool requiresCurrentPassword = false,
  }) async {
    final TextEditingController controller = TextEditingController(text: currentValue);
    final TextEditingController currentPasswordController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${'edit'.tr()} $title'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(subtitle),
              ),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: title,
                hintText: '${'enter_your'.tr()} $title',
              ),
              obscureText: isPassword,
              autofocus: true,
            ),
            if (requiresCurrentPassword) ...[
              const SizedBox(height: 16),
              TextField(
                controller: currentPasswordController,
                decoration: InputDecoration(
                  labelText: 'current_password'.tr(),
                  hintText: 'enter_current_password'.tr(),
                ),
                obscureText: true,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('cancel').tr(),
          ),
          ElevatedButton(
            onPressed: () {
              if (requiresCurrentPassword) {
                Navigator.pop(ctx, {
                  'value': controller.text,
                  'currentPassword': currentPasswordController.text,
                });
              } else {
                Navigator.pop(ctx, {'value': controller.text});
              }
            },
            child: const Text('save').tr(),
          ),
        ],
      ),
    );

    if (result != null) {
      final newValue = result['value']?.trim();
      if (newValue != null && newValue.isNotEmpty && newValue != currentValue.trim()) {
        if (requiresCurrentPassword) {
          final currentPassword = result['currentPassword'];
          if (currentPassword == null || currentPassword.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('current_password_required'.tr())),
            );
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$title ${'updated_successfully'.tr()}')),
          );
        } else {
          final success = await onSave(newValue);
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$title ${'updated_successfully'.tr()}')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${'failed_to_update'.tr()} $title')),
            );
          }
        }
      }
    }
  }
// ========= Logout Confirmation =========//
  void _showLogoutConfirmation(AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('logout').tr(),
        content: const Text('logout_confirmation').tr(),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('cancel').tr(),
          ),
          ElevatedButton(
            onPressed: () {
              context.pop();
              context.go(AppRouter.welcome);
              authProvider.logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('logout').tr(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final user = authProvider.user;
    final theme = themeProvider.currentTheme;
    final isDarkMode = themeProvider.isDarkMode;
    // final isBlindUI = themeProvider.isBlindUserInterface;

    // ========= Check if user is logged in =========//
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('settings').tr()),
        body: Center(
          child: ElevatedButton(
            child: const Text('sign_in').tr(),
            onPressed: () => context.go(AppRouter.signin),
          ),
        ),
      );
    }

    // =========  settings screen =========//
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        title: Text(
          'settings'.tr(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 24,
            color: theme.appBarTheme.foregroundColor ?? (isDarkMode ? Colors.white : Colors.black),
          ),
        ),
        centerTitle: true,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade400, size: 64),
                        const SizedBox(height: 16),
                        Text('error'.tr(), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red)),
                        const SizedBox(height: 8),
                        Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('go_back').tr(),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 28),
                        _buildAnimatedItem(
                          0,
                          _buildProfileHeader(user, theme),
                        ),
                        const SizedBox(height: 20),
                        _buildAnimatedItem(
                          1,
                          _buildProfileItem(
                            context: context,
                            theme: theme,
                            title: 'name'.tr(),
                            value: user.displayName ?? 'user'.tr(),
                            icon: Icons.person,
                            onTap: () => _editField(
                              context: context,
                              title: 'name'.tr(),
                              currentValue: user.displayName ?? 'user'.tr(),
                              onSave: authProvider.updateDisplayName,
                            ),
                          ),
                        ),
                        _buildAnimatedItem(
                          2,
                          _buildProfileItem(
                            context: context,
                            theme: theme,
                            title: 'email'.tr(),
                            value: user.email ?? 'no_email'.tr(),
                            icon: Icons.email,
                            onTap: () => _editField(
                              context: context,
                              title: 'email'.tr(),
                              currentValue: user.email ?? '',
                              onSave: (_) async => false,
                              requiresCurrentPassword: true,
                              subtitle: 'change_email_requires_password'.tr(),
                            ),
                          ),
                        ),
                        _buildAnimatedItem(
                          3,
                          _buildProfileItem(
                            context: context,
                            theme: theme,
                            title: 'password'.tr(),
                            value: '••••••••',
                            icon: Icons.lock,
                            onTap: () => _editField(
                              context: context,
                              title: 'new_password'.tr(),
                              currentValue: '',
                              onSave: (newPassword) async => false,
                              isPassword: true,
                              requiresCurrentPassword: true,
                              subtitle: 'enter_current_and_new_password'.tr(),
                            ),
                          ),
                        ),
                        _buildAnimatedItem(
                          4,
                          _buildListTile(
                            context: context,
                            theme: theme,
                            title: 'connection_code'.tr(),
                            subtitle: 'show_qr_to_connect'.tr(),
                            icon: Icons.qr_code,
                            onTap: () {
                              _showConnectionCodeDialog(user.uid, theme);
                            },
                          ),
                        ),
                        _buildAnimatedItem(
                          5,
                          _buildSwitchTile(
                            theme: theme,
                            title: 'dark_mode'.tr(),
                            subtitle: 'dark_mode_description'.tr(),
                            icon: isDarkMode ? Icons.dark_mode : Icons.light_mode,
                            value: isDarkMode,
                            onChanged: (val) {
                              themeProvider.toggleTheme();
                            },
                          ),
                        ),
                        _buildAnimatedItem(
                          6,
                          _buildLanguageSelector(theme),
                        ),
                        const SizedBox(height: 18),
                        _buildAnimatedItem(
                          7,
                          _buildListTile(
                            context: context,
                            theme: theme,
                            title: 'logout'.tr(),
                            subtitle: 'sign_out_account'.tr(),
                            icon: Icons.logout,
                            isDestructive: true,
                            onTap: () {
                              _showLogoutConfirmation(authProvider);
                            },
                          ),
                        ),
                        const SizedBox(height: 36),
                      ],
                    ),
                  ),
                ),
    );
  }

  // ========= UI Helper Widgets (كلها بتستخدم theme) ===========
  Widget _buildProfileHeader(user, ThemeData theme) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withOpacity(0.18),
                spreadRadius: 6,
                blurRadius: 18,
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 48,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              _getInitials(user.displayName ?? user.email ?? "?"),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          user.displayName ?? 'User',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          user.email ?? '',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary),
        ),
      ],
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return "?";
    if (name.contains('@')) return name[0].toUpperCase();
    final parts = name.trim().split(' ');
    if (parts.length > 1) {
      return parts.first[0].toUpperCase() + parts.last[0].toUpperCase();
    }
    return parts.first[0].toUpperCase();
  }

  Widget _buildProfileItem({
    required BuildContext context,
    required ThemeData theme,
    required String title,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 9,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.11),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isDarkMode ? Colors.white70 : Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        value,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ========= Build the switch tile =========//
  Widget _buildSwitchTile({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDarkMode = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      color: theme.cardColor,
      child: SwitchListTile(
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700,
          ),
        ),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.11),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: theme.colorScheme.primary),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: theme.colorScheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  // ========= Build the list tile =========//
  Widget _buildListTile({
    required BuildContext context,
    required ThemeData theme,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final isDarkMode = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      color: theme.cardColor,
      child: ListTile(
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: isDestructive
                ? Colors.red
                : (isDarkMode ? Colors.white : Colors.black87),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700,
          ),
        ),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDestructive
                ? Colors.red.withOpacity(0.13)
                : theme.colorScheme.primary.withOpacity(0.11),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: isDestructive
                ? Colors.red
                : theme.colorScheme.primary,
          ),
        ),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700,
        ),
      ),
    );
  }

  // ========= Build the animated item =========//
  Widget _buildAnimatedItem(int index, Widget child) {
    final animation = CurvedAnimation(
      parent: _animationController,
      curve: Interval(0.07 * index, 1.0, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Transform.translate(
          offset: Offset(0, 24 * (1 - animation.value)),
          child: Opacity(opacity: animation.value, child: child),
        );
      },
    );
  }


  // ========= Show the connection code dialog =========//  
  void _showConnectionCodeDialog(String uid, ThemeData theme) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: theme.cardColor,
        title: const Text('connection_code').tr(),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'share_code_or_qr'.tr(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.11),
                    spreadRadius: 1,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: QrImageView(
                data: uid,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SelectableText(
                uid,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: uid));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('connection_code_copied'.tr()),
                ),
              );
            },
            child: const Text('copy_code').tr(),
          ),
          TextButton(
            onPressed: () {
              Share.share(
                '${'connect_with_me'.tr()} $uid',
                subject: 'clarity_connection_code'.tr(),
              );
            },
            child: const Text('share').tr(),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('close').tr(),
          ),
        ],
      ),
    );
  }

  // Add this method to create the language selector
  Widget _buildLanguageSelector(ThemeData theme) {
    final isDarkMode = theme.brightness == Brightness.dark;
    final languageService = LanguageService();
    
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      color: isDarkMode ? Colors.grey.shade900 : Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.language,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'language'.tr(),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    'select_preferred_language'.tr(),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDarkMode
                          ? Colors.grey.shade400
                          : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            languageService.buildLanguageDropdown(
              context,
              iconColor: isDarkMode ? Colors.white : Colors.black87,
            ),
          ],
        ),
      ),
    );
  }
}
