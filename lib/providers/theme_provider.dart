import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  bool _isBlindUserInterface = true; // Default to blind user interface
  
  ThemeData _currentTheme = ThemeData.light().copyWith(
    primaryColor: Colors.blue,
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
  );

  ThemeProvider() {
    _loadTheme();
  }

  bool get isDarkMode => _isDarkMode;
  bool get isBlindUserInterface => _isBlindUserInterface;
  ThemeData get currentTheme => _currentTheme;

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    _isBlindUserInterface = prefs.getBool('isBlindUserInterface') ?? true;
    _setTheme(_isDarkMode, _isBlindUserInterface);
    notifyListeners();
  }

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    _setTheme(_isDarkMode, _isBlindUserInterface);
    _saveTheme();
    notifyListeners();
  }
  
  void setUserInterfaceType(bool isBlindUser) {
    if (_isBlindUserInterface != isBlindUser) {
      _isBlindUserInterface = isBlindUser;
      _setTheme(_isDarkMode, _isBlindUserInterface);
      _saveUserInterfaceType();
      notifyListeners();
    }
  }

  void _setTheme(bool darkMode, bool isBlindUser) {
    // Choose primary color based on user type
    final MaterialColor primaryMaterialColor = isBlindUser ? Colors.blue : Colors.deepOrange;
    final Color primaryColor = primaryMaterialColor;
    final Color secondaryColor = isBlindUser ? Colors.lightBlue : Colors.orange;
    final Color backgroundColor = isBlindUser ? Colors.blue.shade50 : Colors.orange.shade50;
    
    if (darkMode) {
      _currentTheme = ThemeData.dark().copyWith(
        primaryColor: primaryColor,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E1E),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: primaryColor.withOpacity(0.3), width: 1),
          ),
        ),
        colorScheme: ColorScheme.dark(
          primary: primaryColor,
          secondary: secondaryColor,
          background: const Color(0xFF121212),
          surface: const Color(0xFF1E1E1E),
        ),
      );
    } else {
      _currentTheme = ThemeData.light().copyWith(
        primaryColor: primaryColor,
        scaffoldBackgroundColor: backgroundColor,
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: primaryColor.withOpacity(0.3), width: 1),
          ),
        ),
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          secondary: secondaryColor,
          background: backgroundColor,
          surface: Colors.white,
        ),
      );
    }
  }

  Future<void> _saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode);
  }
  
  Future<void> _saveUserInterfaceType() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isBlindUserInterface', _isBlindUserInterface);
  }
} 