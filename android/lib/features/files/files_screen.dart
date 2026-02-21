import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/language_switcher_button.dart';
import 'files_controller.dart';

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(filesControllerProvider.notifier).loadFiles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(filesControllerProvider);
    final controller = ref.read(filesControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.filesTitle),
        actions: const [LanguageSwitcherButton()],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.files.isEmpty
              ? _buildEmptyState(l10n)
              : RefreshIndicator(
                  onRefresh: () => controller.loadFiles(),
                  child: ListView.builder(
                    itemCount: state.files.length,
                    itemBuilder: (context, index) {
                      final file = state.files[index];
                      return Dismissible(
                        key: Key(file.path),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) =>
                            _confirmDelete(context, l10n, file.name),
                        onDismissed: (_) async {
                          await controller.deleteFile(file.path);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l10n.fileDeleted)),
                            );
                          }
                        },
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          child:
                              const Icon(Icons.delete, color: Colors.white),
                        ),
                        child: ListTile(
                          leading: Icon(_iconForExtension(file.name)),
                          title: Text(
                            file.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${_formatSize(file.sizeBytes)} \u2022 ${_formatDate(file.modified)}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'share') {
                                await controller.shareFile(file.path);
                              } else if (action == 'delete') {
                                final confirmed = await _confirmDelete(
                                    context, l10n, file.name);
                                if (confirmed == true) {
                                  await controller.deleteFile(file.path);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(l10n.fileDeleted)),
                                    );
                                  }
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'share',
                                child: Row(
                                  children: [
                                    const Icon(Icons.share, size: 20),
                                    const SizedBox(width: 8),
                                    Text(l10n.shareFile),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, size: 20,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error),
                                    const SizedBox(width: 8),
                                    Text(l10n.delete,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            l10n.noFilesYet,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete(
      BuildContext context, AppLocalizations l10n, String filename) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteFileTitle),
        content: Text(l10n.deleteFileConfirm(filename)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete,
                style:
                    TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  static IconData _iconForExtension(String filename) {
    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
        return Icons.image;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
        return Icons.videocam;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
        return Icons.audiotrack;
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
      case 'rar':
        return Icons.folder_zip;
      case 'txt':
      case 'md':
      case 'log':
        return Icons.text_snippet;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart;
      default:
        return Icons.insert_drive_file;
    }
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
