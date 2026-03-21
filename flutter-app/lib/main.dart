import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const MoodifyApp());

const _gatewayUrl = 'http://localhost:8080';

// ── Modelos ───────────────────────────────────────────────────────────────────

class Track {
  final String id;
  final String name;
  final String artist;
  final String? previewUrl;
  final double valence;
  final double energy;

  Track({
    required this.id,
    required this.name,
    required this.artist,
    this.previewUrl,
    required this.valence,
    required this.energy,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'],
        name: json['name'],
        artist: json['artist'],
        previewUrl: json['preview_url'],
        valence: (json['valence'] as num).toDouble(),
        energy: (json['energy'] as num).toDouble(),
      );
}

class PlaylistResult {
  final String sentiment;
  final double compound;
  final List<Track> tracks;
  final String? playlistUrl;

  PlaylistResult({
    required this.sentiment,
    required this.compound,
    required this.tracks,
    this.playlistUrl,
  });

  factory PlaylistResult.fromJson(Map<String, dynamic> json) => PlaylistResult(
        sentiment: json['sentiment'],
        compound: (json['compound'] as num).toDouble(),
        tracks: (json['tracks'] as List).map((t) => Track.fromJson(t)).toList(),
        playlistUrl: json['playlistUrl'],
      );
}

// ── Sesión de usuario ─────────────────────────────────────────────────────────

class UserSession {
  final String accessToken;
  final String userId;
  UserSession({required this.accessToken, required this.userId});
}

// ── Servicio API ──────────────────────────────────────────────────────────────

Future<PlaylistResult> fetchPlaylist(String mood) async {
  final response = await http.post(
    Uri.parse('$_gatewayUrl/mood'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'mood': mood, 'limit': 10}),
  );
  if (response.statusCode != 200) {
    final body = jsonDecode(response.body);
    throw Exception(body['error'] ?? 'Error desconocido');
  }
  return PlaylistResult.fromJson(jsonDecode(response.body));
}

Future<void> sendFeedback(String trackId, bool liked, String mood) async {
  await http.post(
    Uri.parse('$_gatewayUrl/feedback?track_id=$trackId&liked=$liked&mood=${Uri.encodeComponent(mood)}'),
  );
}

Future<String> getLoginUrl() async {
  final response = await http.get(Uri.parse('$_gatewayUrl/auth/login'));
  final body = jsonDecode(response.body);
  return body['loginUrl'];
}

// ── App ───────────────────────────────────────────────────────────────────────

class MoodifyApp extends StatelessWidget {
  const MoodifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moodify Me',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const MoodifyScreen(),
    );
  }
}

// ── UI ────────────────────────────────────────────────────────────────────────

class MoodifyScreen extends StatefulWidget {
  const MoodifyScreen({super.key});

  @override
  State<MoodifyScreen> createState() => _MoodifyScreenState();
}

class _MoodifyScreenState extends State<MoodifyScreen> {
  final _controller = TextEditingController();
  PlaylistResult? _result;
  bool _loading = false;
  String? _error;
  UserSession? _session;

  // Feedback: trackId → true(like) / false(dislike)
  final Map<String, bool> _feedback = {};

  Future<void> _generate() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _feedback.clear();
    });

    try {
      final result = await fetchPlaylist(text);
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loginWithSpotify() async {
    try {
      final url = await getLoginUrl();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      setState(() => _error = 'No se pudo iniciar el login: $e');
    }
  }

  void _logout() {
    setState(() => _session = null);
    http.post(Uri.parse('$_gatewayUrl/auth/logout'));
  }

  Future<void> _sendFeedback(String trackId, bool liked) async {
    setState(() => _feedback[trackId] = liked);
    await sendFeedback(trackId, liked, _controller.text.trim());
  }

  Color _sentimentColor(String sentiment) => switch (sentiment) {
        'positive' => Colors.greenAccent,
        'negative' => Colors.redAccent,
        _ => Colors.amberAccent,
      };

  String _sentimentEmoji(String sentiment) => switch (sentiment) {
        'positive' => '😊',
        'negative' => '😔',
        _ => '😐',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // Header + botón de sesión
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Spacer(),
                  Text(
                    '🎵 Moodify Me',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurpleAccent,
                        ),
                  ),
                  const Spacer(),
                  // Botón login / logout
                  _session == null
                      ? IconButton(
                          tooltip: 'Conectar con Spotify',
                          icon: const Icon(Icons.login, color: Colors.greenAccent),
                          onPressed: _loginWithSpotify,
                        )
                      : IconButton(
                          tooltip: 'Cerrar sesión',
                          icon: const Icon(Icons.logout, color: Colors.redAccent),
                          onPressed: _logout,
                        ),
                ],
              ),

              const SizedBox(height: 4),
              Text(
                _session == null
                    ? 'Escribe cómo te sentís y te armo una playlist'
                    : '✅ Conectado a Spotify — tu playlist se guardará automáticamente',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _session == null
                          ? null
                          : Colors.greenAccent.withOpacity(0.8),
                    ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),

              // Mood input
              TextField(
                controller: _controller,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'ej: "estoy relajado 😊" o "me siento 🔥 hoy"',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                onSubmitted: (_) => _generate(),
              ),
              const SizedBox(height: 12),

              // Botón generar
              FilledButton.icon(
                onPressed: _loading ? null : _generate,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.headphones),
                label: Text(_loading ? 'Generando...' : 'Generar Playlist'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Error
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),

              // Resultados
              if (_result != null) ...[
                // Sentimiento detectado
                Row(
                  children: [
                    Text(
                      _sentimentEmoji(_result!.sentiment),
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sentimiento: ${_result!.sentiment}  (${_result!.compound.toStringAsFixed(2)})',
                      style: TextStyle(
                        color: _sentimentColor(_result!.sentiment),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

                // Link a playlist guardada en Spotify
                if (_result!.playlistUrl != null) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse(_result!.playlistUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1DB954).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF1DB954).withOpacity(0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_new, size: 16, color: Color(0xFF1DB954)),
                          SizedBox(width: 6),
                          Text(
                            'Ver playlist guardada en Spotify',
                            style: TextStyle(color: Color(0xFF1DB954), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Lista de canciones con feedback
                Expanded(
                  child: ListView.separated(
                    itemCount: _result!.tracks.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final track = _result!.tracks[i];
                      final feedbackGiven = _feedback[track.id];

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepPurple.withOpacity(0.3),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(track.name),
                        subtitle: Text(track.artist),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Métricas
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'V ${(track.valence * 100).round()}%',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.greenAccent.withOpacity(0.8),
                                  ),
                                ),
                                Text(
                                  'E ${(track.energy * 100).round()}%',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orangeAccent.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            // Botones de feedback
                            IconButton(
                              icon: Icon(
                                Icons.thumb_up,
                                size: 18,
                                color: feedbackGiven == true
                                    ? Colors.greenAccent
                                    : Colors.white24,
                              ),
                              onPressed: () => _sendFeedback(track.id, true),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(
                                Icons.thumb_down,
                                size: 18,
                                color: feedbackGiven == false
                                    ? Colors.redAccent
                                    : Colors.white24,
                              ),
                              onPressed: () => _sendFeedback(track.id, false),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
