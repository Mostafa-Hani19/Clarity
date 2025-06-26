import 'dart:ui';
import 'package:clarity/home/presentation/screens/blind/blind_ai_chat_screen.dart';
import 'package:flutter/material.dart';
// ignore: unnecessary_import
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_nav_bar/google_nav_bar.dart';

class CustomGNavBar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onTabChange;

  const CustomGNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTabChange,
  });

  @override
  State<CustomGNavBar> createState() => _CustomGNavBarState();
}

class _CustomGNavBarState extends State<CustomGNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
      ),
    );

    // Auto-play animation
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // Main navigation bar with glass effect
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? Colors.black.withOpacity(0.5)
                      : Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: isDarkMode
                        ? Colors.white.withOpacity(0.1)
                        : Colors.white.withOpacity(0.8),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.2),
                      spreadRadius: 1,
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      spreadRadius: 0,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: GNav(
                  gap: 8,
                  backgroundColor: Colors.transparent,
                  color: isDarkMode ? Colors.white70 : Colors.grey.shade600,
                  activeColor: isDarkMode ? Colors.white : Colors.blue,
                  tabBackgroundColor: isDarkMode
                      ? Colors.white.withOpacity(0.1)
                      : Colors.blue.withOpacity(0.1),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  duration: const Duration(milliseconds: 400),
                  tabBorderRadius: 40,
                  curve: Curves.easeOutExpo,
                  onTabChange: widget.onTabChange,
                  tabs: [
                    // Home tab
                    GButton(
                      icon: Icons.home_rounded,
                      text: 'home'.tr(),
                      iconSize: 24,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    // Settings tab (combined with profile)
                    GButton(
                      icon: Icons.settings_rounded,
                      text: 'settings'.tr(),
                      iconSize: 24,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  selectedIndex: widget.selectedIndex,
                  haptic: true, // Enable haptic feedback
                ),
              ),
            ),
          ),
        ),

        //  assistant button 
        Positioned(
          top: -0,
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value * _scaleAnimation.value,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue
                            .withOpacity(0.3 + 0.2 * _pulseAnimation.value),
                        blurRadius: 15,
                        spreadRadius: 2 * _pulseAnimation.value,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: GestureDetector(
                    onTap: () {
                      if (mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const BlindAIChatScreen(),
                          ),
                        );
                      }
                    },
                    child: Container(
                      width: 65,
                      height: 65,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.lightBlue
                                .withOpacity(0.3 + 0.2 * _pulseAnimation.value),
                            blurRadius: 15,
                            spreadRadius: 2 * _pulseAnimation.value,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Image.asset(
                          'assets/images/whiteLogo.png',
                          width: 60,
                          height: 60,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
