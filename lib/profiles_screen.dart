import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'local_profiles.dart';
import 'local_store.dart';
import 'models.dart';
import 'app_build.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key, required this.store, this.locked = false});
  final LocalStore store;
  final bool locked;
  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _recover({bool export = false, bool reload = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (reload) {
        await widget.store.reload();
      } else if (export) {
        await FilePicker.saveFile(
          fileName: '$appSlug-recovery.json',
          bytes: Uint8List.fromList(
            utf8.encode(widget.store.exportRecoveryData()),
          ),
          mimeType: 'application/json',
        );
      } else {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (file == null || !mounted) return;
        final size = await file.length();
        if (size == null || size > 8 * 1024 * 1024) {
          throw const FormatException('File cadangan terlalu besar atau tidak dapat dibaca');
        }
        final content = utf8.decode(await file.readAsBytes());
        widget.store.validateBackup(content);
        if (!mounted) return;
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('从备份Pulihkan用户与记录？'),
            content: const Text(
              '将使用这份备份替换损坏的用户配置、Daftar tontonan、观看记录和偏好。建议先Ekspor konfigurasi asli；已Unduhan视频保留。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('继续Pulihkan'),
              ),
            ],
          ),
        );
        if (accepted != true || !mounted) return;
        final pin = await showDialog<String>(
          context: context,
          builder: (_) => const _PasswordDialog(name: '管理员（原配置或备份中的Kata sandi）'),
        );
        if (pin == null || !mounted) return;
        await widget.store.recoverBackup(content, pin: pin);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switch(LocalProfile profile) async {
    String pin = '';
    if (profile.protected) {
      final value = await showDialog<String>(
        context: context,
        builder: (_) => _PasswordDialog(name: profile.name),
      );
      if (value == null || !mounted) return;
      pin = value;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.switchProfile(profile.id, pin: pin);
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([LocalProfile? profile]) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProfileEditor(store: widget.store, profile: profile),
      ),
    );
    if (mounted) setState(() {});
  }

  String _permissionsLabel(LocalProfile profile) {
    if (profile.admin) return 'Administrator · semua izin';
    final sources = profile.sources
        .where(SourceSite.isAvailable)
        .map((id) => SourceSite.byId(id).name)
        .join(' / ');
    return '${sources.isEmpty ? 'Sumber belum dibuka' : sources} · ${profile.download ? '可Unduhan' : 'Hanya menonton online'}';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (_, _) => Scaffold(
      appBar: AppBar(title: Text(widget.locked ? '解锁$appName' : 'Kelola pengguna')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.store.configurationError != null) ...[
                Text('需要Pulihkan本地配置', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(widget.store.configurationError!),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _recover(),
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('从备份Pulihkan'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _recover(export: true),
                  child: const Text('Ekspor konfigurasi asli'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _recover(reload: true),
                  child: const Text('Muat ulang konfigurasi'),
                ),
              ] else ...[
                Text(
                  widget.locked
                      ? 'Pilih pengguna dan masukkan kata sandi'
                      : '当前用户：${widget.store.profile.name}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text('各用户的Daftar tontonan和观看记录独立Simpan，Unduhan文件由本机共享。'),
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
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
              const SizedBox(height: 16),
              for (final profile
                  in widget.store.configurationError == null
                      ? widget.store.profiles
                      : <LocalProfile>[])
                Card(
                  child: ListTile(
                    leading: Icon(
                      profile.admin
                          ? Icons.admin_panel_settings_outlined
                          : Icons.person_outline,
                    ),
                    title: Text(profile.name),
                    subtitle: Text(_permissionsLabel(profile)),
                    onTap: _busy ? null : () => _switch(profile),
                    trailing: !widget.store.locked && widget.store.profile.admin
                        ? IconButton(
                            tooltip: 'Edit pengguna',
                            onPressed: _busy ? null : () => _edit(profile),
                            icon: const Icon(Icons.edit_outlined),
                          )
                        : Icon(
                            profile.protected
                                ? Icons.lock_outline
                                : Icons.chevron_right,
                          ),
                  ),
                ),
              if (!widget.store.locked && widget.store.profile.admin) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _edit(),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Tambah pengguna'),
                ),
              ],
              if (!widget.store.locked && widget.store.profile.protected)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    widget.store.lock();
                  },
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Kunci pengguna saat ini'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.name});
  final String name;
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _pin = TextEditingController();
  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Masuk ${widget.name}'),
    content: TextField(
      controller: _pin,
      autofocus: true,
      obscureText: true,
      decoration: const InputDecoration(labelText: 'Kata sandi'),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _pin.text),
        child: const Text('Masuk'),
      ),
    ],
  );
}

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key, required this.store, this.profile});
  final LocalStore store;
  final LocalProfile? profile;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final _name = TextEditingController(text: widget.profile?.name ?? '');
  final _pin = TextEditingController(), _confirm = TextEditingController();
  late final _sources =
      (widget.profile?.sources ?? SourceSite.values.map((s) => s.id).toList())
          .toSet();
  late bool _download = widget.profile?.download ?? true;
  bool _clearPin = false, _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      if (_pin.text != _confirm.text) throw StateError('两次输入的Kata sandi不一致');
      await widget.store.saveProfile(
        id: widget.profile?.id,
        name: _name.text,
        sources: _sources.toList(),
        download: _download,
        pin: _clearPin
            ? ''
            : _pin.text.isEmpty
            ? null
            : _pin.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus pengguna ini?'),
        content: const Text('会同时Hapus该用户的Daftar tontonan和观看记录。Unduhan文件会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await widget.store.deleteProfile(widget.profile!.id);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.profile == null ? 'Tambah pengguna' : 'Edit pengguna')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _name,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Nama pengguna'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pin,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '设置Kata sandi（至少 6 位）',
                helperText: '留空保留原Kata sandi',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: '再次输入Kata sandi'),
            ),
            if (widget.profile?.protected == true &&
                widget.profile?.admin != true)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Batal此用户Kata sandi'),
                value: _clearPin,
                onChanged: (v) => setState(() => _clearPin = v!),
              ),
            const SizedBox(height: 20),
            if (widget.profile?.admin != true) ...[
              Text('Izinkan akses ke sumber', style: Theme.of(context).textTheme.titleMedium),
              for (final source in SourceSite.values)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(source.name),
                  value: _sources.contains(source.id),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _sources.add(source.id);
                      } else {
                        _sources.remove(source.id);
                      }
                    });
                  },
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('允许Unduhan和本地媒体'),
                subtitle: Text(_download ? '可Unduhan、合并和导出' : 'Hanya menonton online，隐藏Unduhan入口'),
                value: _download,
                onChanged: (v) => setState(() => _download = v),
              ),
            ] else
              const Text('管理员可以访问Semua sumber和功能。创建其他用户前需要先设置管理员Kata sandi。'),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? '正在Simpan…' : 'Simpan'),
            ),
            if (widget.profile != null && !widget.profile!.admin)
              TextButton(
                onPressed: _busy ? null : _delete,
                child: const Text('Hapus用户'),
              ),
          ],
        ),
      ),
    ),
  );
}
