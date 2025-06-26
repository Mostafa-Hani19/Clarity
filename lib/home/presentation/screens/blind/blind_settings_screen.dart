// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../common/widgets/custom_gnav_bar.dart';
import '../../../../routes/app_router.dart';
import '../../../../services/language_service.dart';
import '../../../../presentation/screens/esp32_cam_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool hideBottomNavBar;

  const SettingsScreen({super.key, this.hideBottomNavBar = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Generic method to edit text fields with a dialog
  Future<void> _editField({
    required BuildContext context,
    required String title,
    required String currentValue,
    required Future<bool> Function(String) onSave,
    bool isPassword = false,
    String? subtitle,
    bool requiresCurrentPassword = false,
  }) async {
    final TextEditingController controller =
        TextEditingController(text: currentValue);
    final TextEditingController currentPasswordController =
        TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $title'),
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
                hintText: 'Enter your $title',
              ),
              obscureText: isPassword,
              autofocus: true,
            ),
            if (requiresCurrentPassword) ...[
              const SizedBox(height: 16),
              TextField(
                controller: currentPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Current Password',
                  hintText: 'Enter your current password',
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
      // Only proceed if there's a value
      final newValue = result['value']?.trim();
      if (newValue != null &&
          newValue.isNotEmpty &&
          newValue != currentValue.trim()) {
        // For operations that require current password
        if (requiresCurrentPassword) {
          final currentPassword = result['currentPassword'];
          if (currentPassword == null || currentPassword.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Current password is required')),
            );
            return;
          }

          // Handle email and password updates differently
          if (isPassword) {
            final success = await onSave(result['currentPassword']!);
            if (success) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$title updated successfully')),
              );
            } else {
              final authProvider =
                  Provider.of<AuthProvider>(context, listen: false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(authProvider.errorMessage ??
                        'Failed to update $title')),
              );
            }
          } else {
            // For email update
            final authProvider =
                Provider.of<AuthProvider>(context, listen: false);
            final success =
                await authProvider.updateEmail(newValue, currentPassword);
            if (success) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$title updated successfully')),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(authProvider.errorMessage ??
                        'Failed to update $title')),
              );
            }
          }
        } else {
          // For simple updates like display name
          final success = await onSave(newValue);
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$title updated successfully')),
            );
          } else {
            final authProvider =
                Provider.of<AuthProvider>(context, listen: false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      authProvider.errorMessage ?? 'Failed to update $title')),
            );
          }
        }
      }
    }
  }

  void _showLogoutConfirmation(AuthProvider authProvider) {
    // ignore: unused_local_variable
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('confirm_logout').tr(),
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
    // Using Provider.of<AuthProvider>(context) with the default listen:true parameter
    // ensures that this widget rebuilds whenever AuthProvider notifies its listeners
    // (which happens after user data changes like name, email, or password updates)
    final authProvider = Provider.of<AuthProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final user = authProvider.user;
    final isDarkMode = themeProvider.isDarkMode;

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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'settings'.tr(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 24,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black,
          ),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              const SizedBox(height: 24),

              // Profile Section at the top
              _buildProfileHeader(user, context),

              const SizedBox(height: 24),

              // Profile Items
              _buildAnimatedItem(
                1,
                _buildProfileItem(
                  context: context,
                  title: 'Name',
                  value: user.displayName ?? 'User',
                  icon: Icons.person,
                  onTap: () => _editField(
                    context: context,
                    title: 'Name',
                    currentValue: user.displayName ?? 'User',
                    onSave: authProvider.updateDisplayName,
                  ),
                ),
              ),

              _buildAnimatedItem(
                2,
                _buildProfileItem(
                  context: context,
                  title: 'Email',
                  value: user.email ?? 'No email',
                  icon: Icons.email,
                  onTap: () => _editField(
                    context: context,
                    title: 'Email',
                    currentValue: user.email ?? '',
                    onSave: (_) async =>
                        false, // This will be handled separately in the dialog
                    requiresCurrentPassword: true,
                    subtitle:
                        'Changing your email requires your current password',
                  ),
                ),
              ),

              _buildAnimatedItem(
                3,
                _buildProfileItem(
                  context: context,
                  title: 'Password',
                  value: '••••••••',
                  icon: Icons.lock,
                  onTap: () => _editField(
                    context: context,
                    title: 'New Password',
                    currentValue: '',
                    onSave: (newPassword) async {
                      // This is just a placeholder - actual logic happens in the dialog
                      // when the current password is collected
                      return false;
                    },
                    isPassword: true,
                    requiresCurrentPassword: true,
                    subtitle: 'Enter your current password and a new password',
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // App Settings Section
              _buildAnimatedItem(
                5,
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.grey.shade800.withOpacity(0.3)
                        : Colors.blue.shade50.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.settings, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'App Settings',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Additional Settings
              _buildAnimatedItem(
                6,
                _buildSwitchTile(
                  title: 'dark_mode'.tr(),
                  subtitle: 'dark_mode_description'.tr(),
                  icon: isDarkMode ? Icons.dark_mode : Icons.light_mode,
                  value: isDarkMode,
                  onChanged: (val) {
                    HapticFeedback.lightImpact();
                    themeProvider.toggleTheme();
                  },
                ),
              ),

              _buildAnimatedItem(
                7,
                _buildSwitchTile(
                  title: 'larger_text'.tr(),
                  subtitle: 'larger_text_description'.tr(),
                  icon: Icons.text_fields,
                  value: settingsProvider.largeText,
                  onChanged: (val) {
                    HapticFeedback.lightImpact();
                    settingsProvider.toggleLargeText();
                  },
                ),
              ),

              _buildAnimatedItem(
                9,
                _buildLanguageSelector(
                    current: Localizations.localeOf(context).languageCode),
              ),

              // Add a new item for connection code sharing
              _buildAnimatedItem(
                9, // Use the same index as language selector, it won't affect the animation much
                _buildListTile(
                  title: 'Connection Code',
                  subtitle: 'Show your ID as QR code to connect with others',
                  icon: Icons.qr_code,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _showConnectionCodeDialog(user.uid);
                  },
                ),
              ),
              _buildAnimatedItem(
                10,
                _buildListTile(
                  title: 'ESP32-CAM Stream',
                  subtitle: 'Connect to ESP32-CAM to view live stream',
                  icon: Icons.camera_alt,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    AppRouter.navigateToESP32Cam(context);
                  },
                ),
              ),
              _buildAnimatedItem(
                11,
                _buildListTile(
                  title: 'logout'.tr(),
                  subtitle: 'Sign out of your account',
                  icon: Icons.logout,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _showLogoutConfirmation(authProvider);
                  },
                  isDestructive: true,
                ),
              ),

              const SizedBox(height: 80), // Extra space at bottom for GNavBar
            ],
          ),
        ),
      ),
      bottomNavigationBar: widget.hideBottomNavBar
          ? null
          : CustomGNavBar(
              selectedIndex: 1,
              onTabChange: (index) {
                if (index != 1) {
                  // Navigate to the appropriate screen based on tab index
                  context.go(
                      index == 0 ? AppRouter.home : AppRouter.settingsRoute);
                }
              },
            ),
    );
  }

  Widget _buildProfileHeader(user, BuildContext context) {
    return Column(
      children: [
        // Profile image with blue outline
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                spreadRadius: 5,
                blurRadius: 15,
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 50,
            backgroundColor: Colors.blue,
            backgroundImage:
                user.photoURL != null ? NetworkImage(user.photoURL) : null,
            child: user.photoURL == null
                ? Text(
                    _getInitials(user.displayName ?? user.email ?? "?"),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),

        // User name
        Text(
          user.displayName ?? 'User',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),

        // User email
        Text(
          user.email ?? '',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
      ],
    );
  }

  // Helper method to get user initials from name
  String _getInitials(String name) {
    if (name.isEmpty) return "?";

    if (name.contains('@')) {
      // This is an email, so return first letter
      return name[0].toUpperCase();
    }

    // Split the name and get initials
    final parts = name.trim().split(' ');
    if (parts.length > 1) {
      // If there are multiple parts, get first letter of first and last part
      return parts.first[0].toUpperCase() + parts.last[0].toUpperCase();
    }

    // Just return the first letter of the name
    return parts.first[0].toUpperCase();
  }

  Widget _buildProfileItem({
    required BuildContext context,
    required String title,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color:
            isDarkMode ? Colors.grey.shade800.withOpacity(0.3) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: Colors.blue),
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
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        value,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
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

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

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
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: Theme.of(context).colorScheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildListTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

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
                ? Colors.red.withOpacity(0.1)
                : Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: isDestructive
                ? Colors.red
                : Theme.of(context).colorScheme.primary,
          ),
        ),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildLanguageSelector({required String current}) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.language,
                color: Theme.of(context).colorScheme.primary,
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
                    'Select your preferred language',
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

  Widget _buildAnimatedItem(int index, Widget child) {
    final animation = CurvedAnimation(
      parent: _animationController,
      curve: Interval(0.05 * index, 1.0, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - animation.value)),
          child: Opacity(opacity: animation.value, child: child),
        );
      },
    );
  }

  void _showConnectionCodeDialog(String uid) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Connection Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Share this code or QR with a helper who wants to connect with you:',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // QR Code
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
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
            const SizedBox(height: 24),
            // Text Code
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
                const SnackBar(
                  content: Text('Connection code copied to clipboard'),
                ),
              );
            },
            child: const Text('Copy Code'),
          ),
          TextButton(
            onPressed: () {
              Share.share(
                'Connect with me on Clarity using this code: $uid',
                subject: 'Clarity Connection Code',
              );
            },
            child: const Text('Share'),
          ),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
