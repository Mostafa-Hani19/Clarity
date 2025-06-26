// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../providers/auth_provider.dart';
import '../../../models/images.dart';
import '../../../routes/app_router.dart';
import '../../../services/language_service.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final languageService = LanguageService();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: ClipPath(
                clipper: BottomCurveClipper(),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.62,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue,
                        Colors.lightBlue,
                        Colors.blueAccent,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),
            // المحتوى فوق الجريدينت
            Column(
              children: [
                // Language switcher at the top
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8.0, right: 16.0),
                    child: languageService.buildLanguageSelectorWidget(context),
                  ),
                ),
                const SizedBox(height: 20),
                // لوجو دائري
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blueAccent.withOpacity(0.08),
                          blurRadius: 20,
                          offset: Offset(0, 10),
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Image.asset(
                      Appimages.logo1,
                      width: 150,
                      height: 150,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // اسم التطبيق
                Text(
                  "app_name".tr(),
                  style: const TextStyle(
                    fontSize: 31,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 10),
                // وصف التطبيق
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22.0),
                  child: Text(
                    "welcome.app_description".tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15.5,
                      color: Colors.black87,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const Spacer(),

                // Continue as:
                Text(
                  "welcome.continue_as".tr(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 18),
                // زر Blind User
                _buildModernButton(
                  context: context,
                  text: "welcome.blind_user".tr(),
                  icon: Icons.accessibility_new_rounded,
                  color: Colors.blue.shade700,
                  onTap: () => _continueAsBlindUser(context),
                ),
                const SizedBox(height: 16),
                // زر Sighted User
                _buildModernButton(
                  context: context,
                  text: "welcome.sighted_user".tr(),
                  icon: Icons.visibility,
                  color: Colors.green.shade700,
                  onTap: () => _continueAsSightedUser(context),
                ),
                const SizedBox(height: 46),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildModernButton({
    required BuildContext context,
    required String text,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26.0),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, color: color, size: 26),
          label: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            shadowColor: Colors.black12,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            side: BorderSide(color: color.withOpacity(0.12)),
          ),
        ),
      ),
    );
  }

  Future<void> _continueAsBlindUser(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.setUserType(true);
    context.go(AppRouter.signin, extra: {'isBlindUser': true});
  }

  void _continueAsSightedUser(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.setUserType(false);
    context.go(AppRouter.sightedSignin);
  }
}

class BottomCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.moveTo(0, size.height * 0.20);
    path.quadraticBezierTo(
      size.width / 3,
      0,
      size.width,
      size.height * 0.50,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
