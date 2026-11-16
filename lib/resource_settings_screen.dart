import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'download_preferences.dart';
import 'local_store.dart';
import 'resource_settings.dart';
import 'widgets.dart';

class DownloadPreferencesScreen extends StatelessWidget {
  const DownloadPreferencesScreen({super.key, required this.store});
  final LocalStore store;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final preferences = store.downloadPreferences;
      return Scaffold(
        appBar: AppBar(title: const Text('Preferensi unduhan')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  title: const Text('Kualitas default'),
                  subtitle: const Text('Jika kualitas yang dipilih tidak tersedia, gunakan kualitas yang disediakan sumber.'),
                ),
                DropdownButtonFormField<int>(
                  initialValue: preferences.quality,
                  decoration: const InputDecoration(labelText: 'Kualitas unduhan'),
                  items: [
                    for (final value in DownloadPreferences.qualities)
                      DropdownMenuItem(
                        value: value,
                        child: Text(value == 0 ? '自动 · Prioritaskan kualitas tinggi' : '${value}P'),
                      ),
                  ],
                  onChanged: !store.canDownload
                      ? null
                      : (value) {
                          if (value != null) {
                            saveUserChange(
                              context,
                              () => store.setDownloadPreferences(
                                preferences.copyWith(quality: value),
                              ),
                            );
                          }
                        },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: preferences.includeVip,
                  title: const Text('Sertakan episode VIP secara default'),
                  subtitle: const Text('Episode VIP mungkin hanya tersedia sebagai cuplikan; pilihan masih dapat diubah sebelum mengunduh.'),
                  onChanged: !store.canDownload
                      ? null
                      : (value) => saveUserChange(
                          context,
                          () => store.setDownloadPreferences(
                            preferences.copyWith(includeVip: value),
                          ),
                        ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('偏好Simpan在当前用户中，Terapkan于下载选集、Unduhan massal和更新本剧。'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class ResourceSettingsScreen extends StatefulWidget {
  const ResourceSettingsScreen({
    super.key,
    required this.repository,
    required this.store,
  });
  final AppRepository repository;
  final LocalStore store;
  @override
  State<ResourceSettingsScreen> createState() => _ResourceSettingsScreenState();
}

class _ResourceSettingsScreenState extends State<ResourceSettingsScreen> {
  final _proxy = TextEditingController();
  late final int _epoch = widget.store.profileEpoch;
  ResourceSettings? _settings;
  String _mode = 'auto';
  int _catalog = 3, _interval = 250, _downloads = 2;
  bool _folders = false, _busy = false, _showProxy = false;
  String? _error;
  bool get _allowed =>
      widget.store.profileEpoch == _epoch &&
      !widget.store.locked &&
      widget.store.profile.admin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _proxy.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.repository.resourceSettings();
      if (!mounted || !_allowed) return;
      setState(() {
        _settings = settings;
        _mode = settings.proxyMode;
        _proxy.text = settings.proxyUrl;
        _catalog = settings.catalogConcurrency;
        _interval = settings.catalogIntervalMs;
        _downloads = settings.downloadConcurrency;
        _folders = settings.downloadBySource;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _save() async {
    if (_busy || !_allowed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings = await widget.repository.saveResourceSettings(
        ResourceSettings(
          proxyMode: _mode,
          proxyUrl: _proxy.text.trim(),
          catalogConcurrency: _catalog,
          catalogIntervalMs: _interval,
          downloadConcurrency: _downloads,
          downloadBySource: _folders,
        ),
      );
      if (!mounted || !_allowed) return;
      setState(() => _settings = settings);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pengaturan tersimpan dan akan digunakan untuk permintaan serta unduhan berikutnya')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _count(String title, int value, ValueChanged<int> change) =>
      DropdownButtonFormField<int>(
        initialValue: value,
        decoration: InputDecoration(labelText: title),
        items: [
          for (var i = 1; i <= 6; i++)
            DropdownMenuItem(value: i, child: Text('$i')),
        ],
        onChanged: _busy
            ? null
            : (value) {
                if (value != null) setState(() => change(value));
              },
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Jaringan dan sumber daya'),
      actions: [
        TextButton(
          onPressed: _busy || _settings == null || !_allowed ? null : _save,
          child: const Text('Simpan'),
        ),
      ],
    ),
    body: !_allowed
        ? const StatusPanel(title: 'Memerlukan izin administrator', message: 'Kembali lalu beralih ke administrator.')
        : _settings == null
        ? _error == null
              ? const Center(child: CircularProgressIndicator())
              : StatusPanel(title: 'Tidak dapat membaca pengaturan', message: _error!, onRetry: _load)
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (_settings!.warning.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(_settings!.warning),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: _mode,
                    decoration: const InputDecoration(labelText: 'Metode koneksi'),
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('自动')),
                      DropdownMenuItem(value: 'direct', child: Text('Koneksi langsung')),
                      DropdownMenuItem(value: 'manual', child: Text('Proxy manual')),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _mode = value ?? 'auto'),
                  ),
                  if (_mode == 'auto')
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _settings!.systemProxyStatus.isEmpty
                            ? '使用系统静态代理；未配置时使用环境变量或Koneksi langsung。'
                            : _settings!.systemProxyStatus,
                      ),
                    ),
                  if (_mode == 'manual')
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: TextField(
                        controller: _proxy,
                        obscureText: !_showProxy,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'Alamat proxy',
                          hintText: 'http://127.0.0.1:7890',
                          helperText: '支持 HTTP、HTTPS、SOCKS5；仅Simpan在本机，不进入配置备份。',
                          helperMaxLines: 3,
                          suffixIcon: IconButton(
                            tooltip: _showProxy ? '隐藏Alamat proxy' : '显示Alamat proxy',
                            onPressed: () =>
                                setState(() => _showProxy = !_showProxy),
                            icon: Icon(
                              _showProxy
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 28),
                  _count('Permintaan katalog bersamaan', _catalog, (value) => _catalog = value),
                  const SizedBox(height: 16),
                  Text('Jeda permintaan katalog · $_interval 毫秒'),
                  Slider(
                    value: _interval.toDouble(),
                    min: 0,
                    max: 5000,
                    divisions: 100,
                    label: '$_interval 毫秒',
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _interval = value.round()),
                  ),
                  const SizedBox(height: 16),
                  _count('Jumlah unduhan bersamaan', _downloads, (value) => _downloads = value),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _folders,
                    title: const Text('按站源分类Simpan'),
                    subtitle: const Text('新任务放入各站源的子目录，Sudah ada下载继续使用原位置。'),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _folders = value),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
  );
}
