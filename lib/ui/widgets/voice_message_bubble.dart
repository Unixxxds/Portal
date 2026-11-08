import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../models/message.dart';
import '../theme.dart';

/// Single audio player coordinator so playing one voice message stops any other
class VoicePlayerCoordinator {
  static AudioPlayer? activePlayer;
  static VoidCallback? stopCallback;

  static void register(AudioPlayer player, VoidCallback onStop) {
    if (activePlayer != null && activePlayer != player) {
      try {
        activePlayer?.stop();
      } catch (_) {}
      stopCallback?.call();
    }
    activePlayer = player;
    stopCallback = onStop;
  }

  static void unregister(AudioPlayer player) {
    if (activePlayer == player) {
      activePlayer = null;
      stopCallback = null;
    }
  }
}

class VoiceMessageBubble extends StatefulWidget {
  final Message message;
  final bool isMe;
  final VoidCallback? onLongPress;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onLongPress,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  String _audioUrl = '';
  int _declaredDurationSec = 0;

  // 30 waveform bar heights (normalized 0.15 - 1.0)
  late final List<double> _waveformHeights;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _parsePayload();

    // Generate deterministic waveform based on message id for consistent look
    final seed = widget.message.id.abs();
    _waveformHeights = List.generate(28, (i) {
      final v = ((seed * (i + 3) * 17) % 85 + 15) / 100.0;
      return v.clamp(0.2, 1.0);
    });

    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state == PlayerState.playing;
        if (state == PlayerState.completed) {
          _position = Duration.zero;
          _isPlaying = false;
        }
      });
    });

    _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() {
        _position = pos;
      });
    });

    _player.onDurationChanged.listen((dur) {
      if (!mounted) return;
      if (dur.inMilliseconds > 0) {
        setState(() {
          _duration = dur;
        });
      }
    });
  }

  void _parsePayload() {
    final text = widget.message.text.trim();
    try {
      final startIdx = text.indexOf('{');
      final endIdx = text.lastIndexOf('}');
      if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
        final jsonStr = text.substring(startIdx, endIdx + 1);
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        var url = map['url']?.toString() ?? '';
        if (url.isNotEmpty && !url.startsWith('http')) {
          url = AppConstants.formatMediaUrl(url);
        }
        _audioUrl = url;
        _declaredDurationSec = (map['duration'] is int)
            ? map['duration'] as int
            : (int.tryParse(map['duration']?.toString() ?? '') ?? 0);
        if (_declaredDurationSec > 0) {
          _duration = Duration(seconds: _declaredDurationSec);
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    VoicePlayerCoordinator.unregister(_player);
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_audioUrl.isEmpty) return;

    if (_isPlaying) {
      await _player.pause();
    } else {
      VoicePlayerCoordinator.register(_player, () {
        if (mounted) {
          setState(() {
            _isPlaying = false;
          });
        }
      });

      setState(() => _isLoading = true);
      try {
        if (_position > Duration.zero && _position < _duration) {
          await _player.resume();
        } else {
          await _player.play(UrlSource(_audioUrl));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка воспроизведения: $e'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.destructive,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  void _seekToProgress(double progress) {
    if (_duration.inMilliseconds <= 0) return;
    final targetMs = (_duration.inMilliseconds * progress).round();
    final target = Duration(milliseconds: targetMs);
    _player.seek(target);
    setState(() {
      _position = target;
    });
  }

  String _formatTimer() {
    final cur = _position.inMilliseconds > 0
        ? _position
        : (_duration.inMilliseconds > 0 ? _duration : Duration(seconds: _declaredDurationSec));
    final m = cur.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = cur.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatMessageTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '00:00';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.isMe;
    final totalMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1;
    final progress = (_position.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(10, 10, 14, 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
            minWidth: 200,
          ),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFF2A2A2A) : const Color(0xFF191919),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
            border: isMe ? null : Border.all(color: const Color(0x14FFFFFF), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Play / Pause Circle Button
                  GestureDetector(
                    onTap: _togglePlay,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : Icon(
                                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.black,
                                size: 26,
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Waveform & Time
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Interactive Waveform Bars
                        LayoutBuilder(
                          builder: (context, constraints) {
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragUpdate: (details) {
                                final p = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                                _seekToProgress(p);
                              },
                              onTapDown: (details) {
                                final p = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                                _seekToProgress(p);
                              },
                              child: SizedBox(
                                height: 26,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: List.generate(_waveformHeights.length, (i) {
                                    final barProgress = i / _waveformHeights.length;
                                    final isPlayed = barProgress <= progress;
                                    final h = 24.0 * _waveformHeights[i];

                                    return Container(
                                      width: 2.4,
                                      height: h.clamp(5.0, 24.0),
                                      decoration: BoxDecoration(
                                        color: isPlayed ? Colors.white : const Color(0x4DFFFFFF),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 4),

                        // Voice duration
                        Text(
                          _formatTimer(),
                          style: const TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF9E9E9E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 2),

              // Message Time & Read Status
              Align(
                alignment: Alignment.bottomRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatMessageTime(widget.message.createdAt),
                      style: const TextStyle(
                        fontFamily: AppTheme.fontText,
                        fontSize: 10.5,
                        color: Color(0xFF929292),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 3.5),
                      Icon(
                        widget.message.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                        size: 13,
                        color: widget.message.isRead ? const Color(0xFF3B98FF) : const Color(0xFF929292),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

