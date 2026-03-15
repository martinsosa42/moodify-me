import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const MoodifyApp());

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

  PlaylistResult({
    required this.sentiment,
    required this.compound,
    required this.tracks,
  });

  factory PlaylistResult.fromJson(Map<String, dynamic> json) => PlaylistResult(
        sentiment: json['sentiment'],
        compound: (json['compound'] as num).toDouble(),
        tracks: (json['tracks'] as List).map((t) => Track.fromJson(t)).toList(),
      );
}

// ── Servicio API ──────────────────────────────────────────────────────────────

const _gatewayUrl = 'http://localhost:8080'; // Cambiar en producción

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

  Future<void> _generate() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
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
              // Header
              const SizedBox(height: 12),
              Text(
                '🎵 Moodify Me',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurpleAccent,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Escribe cómo te sentís y te armo una playlist',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // Mood input
              TextField(
                controller: _controller,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'ej: "estoy relajado pero con ganas de concentrarme"',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                onSubmitted: (_) => _generate(),
              ),
              const SizedBox(height: 12),

              // Botón
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

              const SizedBox(height: 20),

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
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: _result!.tracks.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final track = _result!.tracks[i];
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
                        trailing: Column(
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
