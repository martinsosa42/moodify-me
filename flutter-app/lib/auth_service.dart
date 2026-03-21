import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const _gatewayUrl = 'http://localhost:8080';

// ── Modelo de sesión ──────────────────────────────────────────────────────────

class SpotifySession {
  final String accessToken;
  final String userId;

  SpotifySession({required this.accessToken, required this.userId});
}

// ── Servicio de autenticación ─────────────────────────────────────────────────

class AuthService extends ChangeNotifier {
  SpotifySession? _session;
  SpotifySession? get session => _session;
  bool get isLoggedIn => _session != null;

  /// Paso 1: Pide la URL de login a Kotlin y abre el navegador
  Future<void> startLogin() async {
    final response = await http.get(Uri.parse('$_gatewayUrl/auth/login'));
    if (response.statusCode != 200) {
      throw Exception('No se pudo obtener la URL de login');
    }

    final body = jsonDecode(response.body);
    final loginUrl = Uri.parse(body['loginUrl']);

    // Abre el navegador con la pantalla de autorización de Spotify
    if (await canLaunchUrl(loginUrl)) {
      await launchUrl(loginUrl, mode: LaunchMode.externalApplication);
    }
  }

  /// Paso 2: Llamado cuando Spotify redirige de vuelta a la app
  /// con el token en la URL (deep link o redirect web)
  void handleCallback({required String token, required String userId}) {
    _session = SpotifySession(accessToken: token, userId: userId);
    notifyListeners();
  }

  void logout() {
    _session = null;
    notifyListeners();
    http.post(Uri.parse('$_gatewayUrl/auth/logout'));
  }
}
