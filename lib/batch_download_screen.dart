import 'dart:async';

import 'package:flutter/material.dart';

import 'batch_downloads.dart';
import 'core_bridge.dart';
import 'downloads_screen.dart';
import 'local_store.dart';
import 'models.dart';
import 'widgets.dart';

class BatchDownloadScreen extends StatefulWidget {
  const BatchDownloadScreen({
    super.key,
    required this.repository,
    required this.store,
    required this.dramas,
  });
  final AppRepository repository;
  final LocalStore store;
  final List<Drama> dramas;

  @override
  State<BatchDownloadScreen> createState() => _BatchDownloadScreenState();
}

class _BatchDownloadScreenState extends State<BatchDownloadScreen> {
  late final BatchDownloads _batch;

  @override
  void initState() {
    super.initState();
    _batch = BatchDownloads(widget.repository, widget.store, widget.dramas);
    unawaited(_batch.prepare());
  }

  @override
  void dispose() {
    _batch.dispose();
    super.dispose();
  }

  String _subtitle(BatchDownloadItem item) {
    if (item.loading) return 'Membaca episode';
    if (item.error != null) return item.error!;
    if (item.detail == null) return 'Menunggu pembacaan episode';
    final count = item.episodes(_batch.includeVip).length;
    final vip = item.detail!.episodes.where((episode) => episode.vip).length;
    if (count == 0) return 'Tidak ada episode non-VIP. Anda dapat memilih episode VIP secara manual.';
    final pieces = <String>[
      'Dipilih $count 集',
      if (!_batch.includeVip && vip > 0) 'Dikecualikan $vip 集 VIP',
      if (item.added > 0) 'Baru ditambahkan ${item.added} 集',
      if (item.existing > 0) 'Sudah ada ${item.existing} 集',
      if (_batch.settingsLocked && item.pending(_batch.includeVip).isEmpty)
        'Ditambahkan ke antrean',
      if (item.detail!.warning.isNotEmpty) item.detail!.warning,
    ];
    return pieces.join(' · ');
  }

  void _openDownloads() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) =>
          DownloadsScreen(repository: widget.repository, store: widget.store),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_batch, widget.store]),
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Unduhan massal')),
      body: SafeArea(
        top: false,
        child: !_batch.hasAccess
            ? const StatusPanel(title: 'Izin unduhan berubah', message: 'Kembali lalu pilih drama lagi.')
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    children: [
                      if (_batch.busy)
                        const LinearProgressIndicator(minHeight: 2),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          children: [
                            Text(
                              '${_batch.items.length} drama',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            const Text('先读取分集，再Tambahkan ke unduhan。默认选择非 VIP 集，Sudah ada任务自动跳过。'),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              key: const ValueKey('batch-download-quality'),
                              initialValue: _batch.quality,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Kualitas unduhan',
                              ),
                              onChanged: _batch.busy || _batch.settingsLocked
                                  ? null
                                  : (value) => _batch.setQuality(value ?? 0),
                              items: [
                                const DropdownMenuItem(
                                  value: 0,
                                  child: Text('自动 · Prioritaskan kualitas tinggi'),
                                ),
                                for (final quality in [1080, 720, 480])
                                  DropdownMenuItem(
                                    value: quality,
                                    child: Text('${quality}P'),
                                  ),
                              ],
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Sertakan episode VIP'),
                              subtitle: const Text('Episode VIP mungkin hanya dapat diunduh sebagai cuplikan'),
                              value: _batch.includeVip,
                              onChanged: _batch.busy || _batch.settingsLocked
                                  ? null
                                  : (value) =>
                                        _batch.setIncludeVip(value ?? false),
                            ),
                            if (_batch.warning.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  _batch.warning,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            if (_batch.current != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  '${_batch.submitting ? 'Sedang menambahkan' : 'Sedang membaca'}：${_batch.current!.drama.title}',
                                ),
                              ),
                            for (final item in _batch.items)
                              Card(
                                child: CheckboxListTile(
                                  key: ValueKey('batch-drama-${item.drama.id}'),
                                  value: item.selected,
                                  onChanged:
                                      _batch.busy || _batch.settingsLocked
                                      ? null
                                      : (value) =>
                                            _batch.select(item, value ?? false),
                                  title: Text(
                                    item.detail?.drama.title ??
                                        item.drama.title,
                                  ),
                                  subtitle: Text(
                                    _subtitle(item),
                                    style: item.error == null
                                        ? null
                                        : TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                          ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              [
                                'Baru ditambahkan ${_batch.added} 集',
                                'Sudah ada ${_batch.existing} 集',
                                if (_batch.failures > 0)
                                  '${_batch.failures} 部perlu dicoba lagi',
                                if (_batch.stopped) 'Dihentikan后续添加，已加入任务继续下载',
                              ].join(' · '),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.end,
                              children: [
                                if (_batch.busy)
                                  OutlinedButton(
                                    onPressed: _batch.stopping
                                        ? null
                                        : _batch.stop,
                                    child: Text(
                                      _batch.stopping
                                          ? 'Sedang menghentikan'
                                          : _batch.submitting
                                          ? 'Hentikan penambahan'
                                          : 'Hentikan pembacaan',
                                    ),
                                  )
                                else ...[
                                  if (_batch.unread > 0)
                                    OutlinedButton(
                                      onPressed: _batch.prepare,
                                      child: const Text('Baca sisanya / coba lagi'),
                                    ),
                                  if (_batch.added + _batch.existing > 0 &&
                                      widget.store.canDownload)
                                    TextButton(
                                      onPressed: _openDownloads,
                                      child: const Text('Lihat unduhan'),
                                    ),
                                  FilledButton.icon(
                                    key: const ValueKey(
                                      'submit-batch-downloads',
                                    ),
                                    onPressed:
                                        !widget.store.canDownload ||
                                            _batch.pendingEpisodes == 0
                                        ? null
                                        : _batch.submit,
                                    icon: const Icon(Icons.download_rounded),
                                    label: Text(
                                      '${_batch.settingsLocked ? 'Lanjutkan penambahan' : 'Tambahkan ke unduhan'} · ${_batch.pendingEpisodes} 集',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    ),
  );
}
