// lib/language.dart
//
// Multi-language support for noteliha.
//
// Design: translations live in assets/translations/<code>.json.
// Only the active language is loaded into memory at any time.
// Adding a new language = drop a JSON file in assets/ + register it below.
// No recompile needed for the translation content itself.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Supported languages registry
// This is the ONLY place you touch when adding a new language.
// ─────────────────────────────────────────────────────────────────────────────

class _LangMeta {
  final String nameEnglish;
  final String nameNative;
  final String flag;
  final String fileName; // asset filename without extension, e.g. 'english'
  const _LangMeta(this.nameEnglish, this.nameNative, this.flag, this.fileName);
}

const Map<String, _LangMeta> _kSupportedLanguages = {
  'am': _LangMeta('Amharic', 'አማርኛ', '🇪🇹', 'amharic'),
  'ar': _LangMeta('Arabic', 'العربية', '🇸🇦', 'arabic'),
  'as': _LangMeta('Assamese', 'অসমীয়া', '🇮🇳', 'assamese'),
  'awa': _LangMeta('Awadhi', 'अवधी', '🇮🇳', 'awadhi'),
  'az': _LangMeta('Azerbaijani', 'Azərbaycanca', '🇦🇿', 'azerbaijani'),
  'bg': _LangMeta('Bulgarian', 'Български', '🇧🇬', 'bulgarian'),
  'bho': _LangMeta('Bhojpuri', 'भोजपुरी', '🇮🇳', 'bhojpuri'),
  'bn': _LangMeta('Bengali', 'বাংলা', '🇮🇳', 'bengali'),
  'ceb': _LangMeta('Cebuano', 'Sinugbuanong Binisaya', '🇵🇭', 'cebuano'),
  'cs': _LangMeta('Czech', 'Čeština', '🇨🇿', 'czech'),
  'de': _LangMeta('German', 'Deutsch', '🇩🇪', 'german'),
  'da': _LangMeta('Danish', 'Dansk', '🇩🇰', 'danish'),
  'el': _LangMeta('Greek', 'Ελληνικά', '🇬🇷', 'greek'),
  'en': _LangMeta('English', 'English', '🇬🇧', 'english'),
  'es': _LangMeta('Spanish', 'Español', '🇪🇸', 'spanish'),
  'fa': _LangMeta('Farsi', 'فارسی', '🇮🇷', 'farsi'),
  'ff': _LangMeta('Fula', 'Fulfulde', '🇸🇳', 'fula'),
  'fi': _LangMeta('Finnish', 'Suomi', '🇫🇮', 'finnish'),
  'fr': _LangMeta('French', 'Français', '🇫🇷', 'french'),
  'gn': _LangMeta('Guarani', 'Avañe\'ẽ', '🇵🇾', 'guarani'),
  'gu': _LangMeta('Gujarati', 'ગુજરાતી', '🇮🇳', 'gujarati'),
  'ha': _LangMeta('Hausa', 'Hausa', '🇳🇬', 'hausa'),
  'hi': _LangMeta('Hindi', 'हिन्दी', '🇮🇳', 'hindi'),
  'hr': _LangMeta('Croatian', 'Hrvatski', '🇭🇷', 'croatian'),
  'hu': _LangMeta('Hungarian', 'Magyar', '🇭🇺', 'hungarian'),
  'id': _LangMeta('Indonesian', 'Bahasa Indonesia', '🇮🇩', 'indonesian'),
  'ig': _LangMeta('Igbo', 'Igbo', '🇳🇬', 'igbo'),
  'it': _LangMeta('Italian', 'Italiano', '🇮🇹', 'italian'),
  'ja': _LangMeta('Japanese', '日本語', '🇯🇵', 'japanese'),
  'jv': _LangMeta('Javanese', 'Basa Jawa', '🇮🇩', 'javanese'),
  'kk': _LangMeta('Kazakh', 'Қазақша', '🇰🇿', 'kazakh'),
  'km': _LangMeta('Khmer', 'ភាសាខ្មែរ', '🇰🇭', 'khmer'),
  'kn': _LangMeta('Kannada', 'ಕನ್ನಡ', '🇮🇳', 'kannada'),
  'ko': _LangMeta('Korean', '한국어', '🇰🇷', 'korean'),
  'ku': _LangMeta('Kurdish', 'Kurdî', '🇮🇶', 'kurdish'),
  'mad': _LangMeta('Madurese', 'Madhura', '🇮🇩', 'madurese'),
  'mai': _LangMeta('Maithili', 'मैथिली', '🇮🇳', 'maithili'),
  'mg': _LangMeta('Malagasy', 'Malagasy', '🇲🇬', 'malagasy'),
  'ml': _LangMeta('Malayalam', 'മലയാളം', '🇮🇳', 'malayalam'),
  'mni': _LangMeta('Manipuri', 'মৈতৈলোন্', '🇮🇳', 'manipuri'),
  'mr': _LangMeta('Marathi', 'मराठी', '🇮🇳', 'marathi'),
  'ms': _LangMeta('Malay', 'Bahasa Melayu', '🇲🇾', 'malay'),
  'my': _LangMeta('Burmese', 'မြန်မာစာ', '🇲🇲', 'burmese'),
  'ne': _LangMeta('Nepali', 'नेपाली', '🇳🇵', 'nepali'),
  'nl': _LangMeta('Dutch', 'Nederlands', '🇳🇱', 'dutch'),
  'no': _LangMeta('Norwegian', 'Norsk', '🇳🇴', 'norwegian'),
  'om': _LangMeta('Oromo', 'Oromoo', '🇪🇹', 'oromo'),
  'or': _LangMeta('Odia', 'ଓଡ଼ିଆ', '🇮🇳', 'odia'),
  'pa': _LangMeta('Punjabi', 'ਪੰਜਾਬੀ', '🇮🇳', 'punjabi'),
  'pl': _LangMeta('Polish', 'Polski', '🇵🇱', 'polish'),
  'ps': _LangMeta('Pashto', 'پښتو', '🇦🇫', 'pashto'),
  'pt': _LangMeta('Portuguese', 'Português', '🇵🇹', 'portuguese'),
  'qu': _LangMeta('Quechua', 'Runa Simi', '🇵🇪', 'quechua'),
  'raj': _LangMeta('Rajasthani', 'राजस्थानी', '🇮🇳', 'rajasthani'),
  'ro': _LangMeta('Romanian', 'Română', '🇷🇴', 'romanian'),
  'ru': _LangMeta('Russian', 'Русский', '🇷🇺', 'russian'),
  'si': _LangMeta('Sinhala', 'සිංහල', '🇱🇰', 'sinhala'),
  'sk': _LangMeta('Slovak', 'Slovenčina', '🇸🇰', 'slovak'),
  'skr': _LangMeta('Saraiki', 'سرائیکی', '🇵🇰', 'saraiki'),
  'sn': _LangMeta('Shona', 'ChiShona', '🇿🇼', 'shona'),
  'so': _LangMeta('Somali', 'Soomaali', '🇸🇴', 'somali'),
  'sr': _LangMeta('Serbian', 'Српски / Srpski', '🇷🇸', 'serbian'),
  'su': _LangMeta('Sundanese', 'Basa Sunda', '🇮🇩', 'sundanese'),
  'sv': _LangMeta('Swedish', 'Svenska', '🇸🇪', 'swedish'),
  'sw': _LangMeta('Swahili', 'Kiswahili', '🇹🇿', 'swahili'),
  'ta': _LangMeta('Tamil', 'தமிழ்', '🇮🇳', 'tamil'),
  'te': _LangMeta('Telugu', 'తెలుగు', '🇮🇳', 'telugu'),
  'th': _LangMeta('Thai', 'ไทย', '🇹🇭', 'thai'),
  'tl': _LangMeta('Tagalog', 'Tagalog', '🇵🇭', 'tagalog'),
  'tr': _LangMeta('Turkish', 'Türkçe', '🇹🇷', 'turkish'),
  'uk': _LangMeta('Ukrainian', 'Українська', '🇺🇦', 'ukrainian'),
  'ur': _LangMeta('Urdu', 'اردو', '🇮🇳', 'urdu'),
  'uz': _LangMeta('Uzbek', 'Oʻzbekcha', '🇺🇿', 'uzbek'),
  'vi': _LangMeta('Vietnamese', 'Tiếng Việt', '🇻🇳', 'vietnamese'),
  'xh': _LangMeta('Xhosa', 'isiXhosa', '🇿🇦', 'xhosa'),
  'yo': _LangMeta('Yoruba', 'Yorùbá', '🇳🇬', 'yoruba'),
  'yue': _LangMeta('Cantonese', '廣東話', '🇭🇰', 'cantonese'),
  'za': _LangMeta('Zhuang', 'Saɯ cueŋƅ', '🇨🇳', 'zhuang'),
  'zh': _LangMeta('Mandarin', '中文', '🇨🇳', 'mandarin'),
  'zu': _LangMeta('Zulu', 'isiZulu', '🇿🇦', 'zulu'),
};

// ─────────────────────────────────────────────────────────────────────────────
// Translation Service
// ─────────────────────────────────────────────────────────────────────────────

class AppTranslations {
  static const String _kLocaleKey = 'app_locale';
  static const String _kAssetPath = 'lib/translations';

  static Locale _currentLocale = const Locale('en');
  static Map<String, String> _currentStrings = {};

  // ── Public getters ──────────────────────────────────────────────────────────

  static Locale get currentLocale => _currentLocale;

  static List<Locale> get supportedLocales =>
      _kSupportedLanguages.keys.map((c) => Locale(c)).toList();

  static bool isSupported(String languageCode) =>
      _kSupportedLanguages.containsKey(languageCode);

  // ── Core translate ──────────────────────────────────────────────────────────

  static String translate(String key) => _currentStrings[key] ?? key;

  // ── Load ────────────────────────────────────────────────────────────────────

  /// Loads [locale] from assets and makes it active.
  /// Falls back to English if the asset is missing.
  static Future<void> setLocale(Locale locale) async {
    final code = isSupported(locale.languageCode) ? locale.languageCode : 'en';
    _currentStrings = await _load(code);
    _currentLocale = Locale(code);
  }

  static Future<Map<String, String>> _load(String code) async {
    final fileName = _kSupportedLanguages[code]?.fileName ?? code;
    try {
      final raw = await rootBundle.loadString('$_kAssetPath/$fileName.json');
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      // Asset missing — try English, then return empty map
      if (code != 'en') return _load('en');
      return {};
    }
  }

  // ── Persistence ─────────────────────────────────────────────────────────────

  static Future<void> loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kLocaleKey);
    final code = (saved != null && isSupported(saved)) ? saved : 'en';
    await setLocale(Locale(code));
  }

  static Future<void> persistLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleKey, locale.languageCode);
    await setLocale(locale);
  }

  // ── Language metadata ───────────────────────────────────────────────────────

  static String getLanguageName(String code) =>
      _kSupportedLanguages[code]?.nameEnglish ?? code;

  static String getNativeLanguageName(String code) =>
      _kSupportedLanguages[code]?.nameNative ?? code;

  static String getLanguageFlag(String code) =>
      _kSupportedLanguages[code]?.flag ?? '🌐';
}

// ─────────────────────────────────────────────────────────────────────────────
// Language Provider — notifies the widget tree when language changes
// ─────────────────────────────────────────────────────────────────────────────

class LanguageProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');
  bool _loading = true;

  Locale get locale => _locale;
  String get languageCode => _locale.languageCode;
  bool get isLoading => _loading;

  LanguageProvider() {
    _init();
  }

  Future<void> _init() async {
    await AppTranslations.loadSavedLocale();
    _locale = AppTranslations.currentLocale;
    _loading = false;
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    await AppTranslations.persistLocale(locale);
    _locale = locale;
    notifyListeners();
  }

  String tr(String key) => AppTranslations.translate(key);
}

// ─────────────────────────────────────────────────────────────────────────────
// BuildContext extension — call sites are unchanged: context.tr('key')
// ─────────────────────────────────────────────────────────────────────────────

extension AppTranslation on BuildContext {
  String tr(String key) => AppTranslations.translate(key);
}
