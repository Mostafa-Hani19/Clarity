import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  bool _largeText = false;
  bool _screenReader = false;
  Locale _locale = const Locale('en', 'US');

  bool get largeText => _largeText;
  bool get screenReader => _screenReader;
  double get textScaleFactor => _largeText ? 1.2 : 1.0;
  Locale get locale => _locale;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _largeText = prefs.getBool('large_text') ?? false;
    _screenReader = prefs.getBool('screen_reader') ?? false;
    
    // Load saved locale
    final languageCode = prefs.getString('language_code') ?? 'en';
    final countryCode = prefs.getString('country_code') ?? 'US';
    _locale = Locale(languageCode, countryCode);
    
    notifyListeners();
  }

  Future<void> toggleLargeText() async {
    _largeText = !_largeText;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('large_text', _largeText);
    notifyListeners();
  }

  Future<void> toggleScreenReader() async {
    _screenReader = !_screenReader;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('screen_reader', _screenReader);
    notifyListeners();
  }
  
  Future<void> updateLocale(Locale newLocale) async {
    _locale = newLocale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', newLocale.languageCode);
    await prefs.setString('country_code', newLocale.countryCode ?? '');
    notifyListeners();
  }
}
