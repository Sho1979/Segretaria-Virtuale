// lib/utils/web_utils.dart

import 'package:flutter/foundation.dart';

/// Classe per gestire operazioni web in modo multipiattaforma
class WebUtils {
  /// Ottiene l'URL corrente (solo su web)
  static String getCurrentUrl() {
    // Implementazione stub per piattaforme non-web
    return '';
  }

  /// Ottiene un valore da localStorage (solo su web)
  static String? getLocalStorageItem(String key) {
    // Implementazione stub per piattaforme non-web
    return null;
  }

  /// Imposta un valore in localStorage (solo su web)
  static void setLocalStorageItem(String key, String value) {
    // Implementazione stub per piattaforme non-web
  }

  /// Rimuove un valore da localStorage (solo su web)
  static void removeLocalStorageItem(String key) {
    // Implementazione stub per piattaforme non-web
  }

  /// Sostituisce lo stato della history (solo su web)
  static void replaceHistoryState(String url) {
    // Implementazione stub per piattaforme non-web
  }

  /// Naviga a un URL (solo su web)
  static void navigateTo(String url) {
    // Implementazione stub per piattaforme non-web
  }
}