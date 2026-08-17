import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../shared/format/timestamp_format.dart';
import 'detail_item.dart';

class ItemDetailScreen extends StatefulWidget {
  final DetailItem item;

  const ItemDetailScreen({super.key, required this.item});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  YoutubePlayerController? _controller;
  bool _playing = false;

  bool get _isValidYoutubeId {
    final id = widget.item.contentId;
    return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id);
  }

  bool get _canPlay => widget.item.platform == 'youtube' && _isValidYoutubeId;

  void _startPlayback() {
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.item.contentId,
      autoPlay: true,
      startSeconds: widget.item.timestamp,
    );
    setState(() => _playing = true);
  }

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(title: const Text('상세보기')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(item.headline, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          if (item.detail.isNotEmpty) Text(item.detail),
          const SizedBox(height: 16),
          Text(
            '${item.platform} · ${item.contentTitle} · ${formatTimestamp(item.timestamp)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          if (_playing && _controller != null)
            YoutubePlayer(controller: _controller!)
          else if (_canPlay)
            ElevatedButton(
              onPressed: _startPlayback,
              child: const Text('재생하기'),
            )
          else if (item.platform == 'youtube')
            const Text('재생할 수 없는 항목입니다'),
        ],
      ),
    );
  }
}
