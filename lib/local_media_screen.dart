import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core_bridge.dart';
import 'local_store.dart';
import 'media_library.dart';
import 'models.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import 'merge_queue_screen.dart';

class LocalMediaScreen extends StatefulWidget {
  const LocalMediaScreen({
    super.key,
    required this.repository,
    required this.store,
  });
  final AppRepository repository;
  final LocalStore store;
  @override
  State<LocalMediaScreen> createState() => _LocalMediaScreenState();
}

class _LocalMediaScreenState extends State<LocalMediaScreen> {
  late final MediaLibrary library =
      MediaLibrary.current ?? MediaLibrary(widget.repository, widget.store);
  List<DownloadJob> _jobs = [];
  bool _loading = true, _merged = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    if (library != MediaLibrary.current && !library.busy) library.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final jobs = await widget.repository.downloads();
      await library.reload();
      if (mounted) {
        setState(() {
          _jobs = jobs.where((job) => job.completed).toList();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create(bool merge) async {
    if (merge) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => MergeQueueScreen(
            library: library,
            repository: widget.repository,
            store: widget.store,
            addOnOpen: true,
          ),
        ),
      );
      if (mounted) await _refresh();
      return;
    }
    final groups = <String, List<DownloadJob>>{};
    for (final job in _jobs) {
      (groups[job.drama.id] ??= []).add(job);
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Drama mana yang ingin diekspor ke Emby?'),
        children: [
          if (_jobs.isNotEmpty)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, '*'),
              child: Text('SemuaSudah diunduh · ${_jobs.length} 集'),
            ),
          for (final entry in groups.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(
                '${entry.value.first.drama.title} · Sudah diunduh ${entry.value.length} 集',
              ),
            ),
          if (groups.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text('Unduh episode terlebih dahulu')),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final jobs = selected == '*' ? _jobs : groups[selected]!;
    setState(() {
      _error = null;
      _merged = false;
    });
    try {
      await library.exportJobs(jobs);
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _play(LocalMediaItem item) async {
    final watch = widget.store.mediaWatched(item.id);
    final episode = Episode({
      'id': item.id,
      'title': item.merged ? 'Video gabungan' : '第 ${item.episodes.first} 集',
      'currentEpisode': item.episodes.first,
    }, 1);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          detail: DramaDetail(item.drama, [episode]),
          initialIndex: 0,
          initialPosition: watch == null || watch.finished ? 0 : watch.position,
          repository: _LocalFileRepository(
            widget.repository,
            widget.store,
            item,
            library.fileFor(item),
          ),
          store: widget.store,
          localOnly: true,
          allowOnlineFallback: false,
          mediaId: item.id,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _remove(LocalMediaItem item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus file media ini?'),
        content: Text(
          '将删除此成品文件。已单独Simpan的原分集不受影响。${item.merged || item.special ? '' : '此分集不再自动导出，需要时可手动重新导出。'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Simpan'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await library.remove(item);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _exportMerged(LocalMediaItem item) async {
    try {
      await library.exportMerged(item);
      if (mounted) {
        setState(() {
          _merged = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: library,
    builder: (_, _) {
      final items = library.items
          .where((item) => item.merged == _merged)
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: const Text('Media lokal'),
          actions: [
            IconButton(
              tooltip: 'Segarkan',
              onPressed: library.busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Hasil gabungan'),
                    selected: _merged,
                    onSelected: (_) => setState(() => _merged = true),
                  ),
                  ChoiceChip(
                    label: const Text('Ekspor Emby'),
                    selected: !_merged,
                    onSelected: (_) => setState(() => _merged = false),
                  ),
                  FilledButton.icon(
                    onPressed: library.busy && !_merged
                        ? null
                        : () => _create(_merged),
                    icon: Icon(_merged ? Icons.merge : Icons.output),
                    label: Text(_merged ? '合并Sudah diunduh分集' : '导出Sudah diunduh分集'),
                  ),
                ],
              ),
            ),
            if (library.busy)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: library.progress > 0 ? library.progress : null,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: Text(library.status)),
                        TextButton(
                          onPressed: () => unawaited(library.cancel()),
                          child: const Text('取消'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (_error != null || library.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error ?? library.error),
              ),
            if (!_merged)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tambahkan folder exports ke pustaka acara TV Emby untuk membaca nama episode dan metadata poster. Ekspor otomatis dapat diaktifkan di Pengaturan.',
                    ),
                    if (library.root != null)
                      TextButton.icon(
                        onPressed: () => Clipboard.setData(
                          ClipboardData(
                            text:
                                '${library.root}${Platform.pathSeparator}exports',
                          ),
                        ),
                        icon: const Icon(Icons.copy),
                        label: const Text('Salin folder media Emby'),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                  ? Center(
                      child: Text(_merged ? 'Hasil gabungan会显示在这里，可直接播放和续播。' : 'Belum ada media yang diekspor'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.drama.title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${item.merged
                                      ? '已合并 ${item.episodes.length} 集'
                                      : item.special
                                      ? '特别篇 ${item.specialNumber} · 第 ${item.episodes.first}–${item.episodes.last} 集'
                                      : '第 ${item.episodes.first} 集'} · ${storageSize(item.bytes)}',
                                ),
                                if (item.merged)
                                  Text(
                                    '视频转码 ${item.videoTranscodes} 集 · 音轨处理 ${item.audioTranscodes} 集',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                if (item.merged)
                                  TextButton.icon(
                                    onPressed: library.busy
                                        ? null
                                        : () => _exportMerged(item),
                                    icon: const Icon(Icons.output_rounded),
                                    label: const Text('导出到 Emby 特别篇'),
                                  ),
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _play(item),
                                      icon: const Icon(Icons.play_arrow),
                                      label: Text(
                                        item.merged &&
                                                item.episodes.length ==
                                                    item.drama.episodes
                                            ? 'Putar semua episode'
                                            : 'Putar lokal',
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      tooltip: 'Salin lokasi file',
                                      onPressed: () => Clipboard.setData(
                                        ClipboardData(
                                          text: library.fileFor(item),
                                        ),
                                      ),
                                      icon: const Icon(Icons.copy),
                                    ),
                                    IconButton(
                                      tooltip: 'Hapus hasil gabungan',
                                      onPressed: library.busy
                                          ? null
                                          : () => _remove(item),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class _LocalFileRepository extends AppRepository {
  _LocalFileRepository(this.parent, this.store, this.item, this.file);
  final AppRepository parent;
  final LocalStore store;
  final LocalMediaItem item;
  final String file;
  Future<PlaybackPlan> _plan() async {
    if (!store.canDownload || !store.allowsSource(item.drama.source)) {
      throw AppFailure('Pengguna saat ini tidak memiliki izin membaca video ini');
    }
    if (!await File(file).exists() || await File(file).length() == 0) {
      throw AppFailure('File hasil lokal tidak ditemukan. Buat ulang.', code: 'local_media');
    }
    return PlaybackPlan(url: file, local: true);
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) => parent.catalog(
    source,
    page: page,
    query: query,
    category: category,
    force: force,
  );
  @override
  Future<CatalogPage> cached(String source, {String category = ''}) =>
      parent.cached(source, category: category);
  @override
  Future<List<CatalogCategory>> categories(
    String source, {
    bool force = false,
  }) => parent.categories(source, force: force);
  @override
  Future<String> cover(Drama drama, {bool force = false}) =>
      parent.cover(drama, force: force);
  @override
  Future<DramaDetail> detail(Drama drama) => parent.detail(drama);
  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) => _plan();
  @override
  Future<PlaybackPlan?> localPlayback(Drama drama, Episode episode) => _plan();
  @override
  Future<PlaybackPlan> resolveOnline(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) => throw AppFailure('此成品仅支持Putar lokal');
  @override
  Future<PlaybackPlan> fallback(PlaybackPlan current) => _plan();
  @override
  Future<void> cancelPlayback() async {}
  @override
  Future<void> release(String session) async {}
}
