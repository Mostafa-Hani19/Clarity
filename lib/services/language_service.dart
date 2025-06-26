import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A service to manage language settings throughout the app.
/// This class centralizes language operations and can be extended with additional features.
class LanguageService {
  static final LanguageService _instance = LanguageService._internal();
  
  factory LanguageService() => _instance;
  
  LanguageService._internal();
  
  // Available languages with their display info
  final Map<String, LanguageInfo> supportedLanguages = {
    'en': LanguageInfo(
      code: 'en',
      name: 'English',
      localName: 'English',
      flag: '🇺🇸',
    ),
    'ar': LanguageInfo(
      code: 'ar',
      name: 'Arabic',
      localName: 'العربية',
      flag: '🇪🇬',
    ),
    'de': LanguageInfo(
      code: 'de',
      name: 'German',
      localName: 'Deutsch',
      flag: '🇩🇪',
    ),
  };
  
  /// Get the current language code
  Future<String> getCurrentLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('language_code') ?? 'en';
  }
  
  /// Get the current language info
  Future<LanguageInfo> getCurrentLanguage() async {
    final langCode = await getCurrentLanguageCode();
    return supportedLanguages[langCode] ?? supportedLanguages['en']!;
  }
  
  /// Set the application language
  Future<void> setLanguage(BuildContext context, String languageCode) async {
    if (!supportedLanguages.containsKey(languageCode)) {
      debugPrint('Unsupported language code: $languageCode');
      return;
    }
    
    // Save to shared preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', languageCode);
    
    // Update the app locale
    if (context.mounted) {
      await context.setLocale(Locale(languageCode));
    }
  }
  
  /// Returns a list of all supported languages
  List<LanguageInfo> getAvailableLanguages() {
    return supportedLanguages.values.toList();
  }
  
  /// Build a language selector widget that can be reused across the app
  Widget buildLanguageSelectorWidget(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.language, color: Colors.blue),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (String languageCode) {
        setLanguage(context, languageCode);
      },
      itemBuilder: (BuildContext context) => supportedLanguages.values.map((language) {
        return PopupMenuItem<String>(
          value: language.code,
          child: Row(
            children: [
              Text(language.flag),
              const SizedBox(width: 8),
              Text(language.localName),
              const SizedBox(width: 8),
              if (context.locale.languageCode == language.code)
                const Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        );
      }).toList(),
    );
  }
  
  /// Build a simplified language selector as a dropdown
  Widget buildLanguageDropdown(BuildContext context, {Color? iconColor}) {
    return DropdownButton<String>(
      value: context.locale.languageCode,
      icon: Icon(
        Icons.arrow_drop_down,
        color: iconColor,
      ),
      underline: Container(height: 0),
      onChanged: (String? langCode) async {
        if (langCode != null) {
          await setLanguage(context, langCode);
        }
      },
      items: supportedLanguages.values.map((language) {
        return DropdownMenuItem(
          value: language.code,
          child: Text(language.localName),
        );
      }).toList(),
    );
  }
}

/// Represents information about a language
class LanguageInfo {
  final String code;      // Language code (e.g., 'en', 'ar')
  final String name;      // English name of the language
  final String localName; // Name of the language in its own alphabet
  final String flag;      // Emoji flag representation
  
  const LanguageInfo({
    required this.code,
    required this.name,
    required this.localName,
    required this.flag,
  });
} 