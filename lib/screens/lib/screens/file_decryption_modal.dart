// secret_app/lib/screens/file_decryption_modal.dart
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:secret_app/services/file_encryption_service.dart';
import 'package:secret_app/services/supabase_service.dart';

class FileDecryptionModal extends StatefulWidget {
  final String fileName;
  final Uint8List encryptedData;
  final String defaultKey;

  const FileDecryptionModal({
    super.key,
    required this.fileName,
    required this.encryptedData,
    required this.defaultKey,
  });

  @override
  State<FileDecryptionModal> createState() => _FileDecryptionModalState();
}

class _FileDecryptionModalState extends State<FileDecryptionModal> {
  final _keyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isDecrypting = false;
  String _decryptionStatus = '';
  bool _decryptionSuccess = false;
  Uint8List? _decryptedData;

  @override
  void initState() {
    super.initState();
    _keyController.text = widget.defaultKey;
  }

  Future<void> _decryptFile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isDecrypting = true;
      _decryptionStatus = 'Sedang mendekripsi file...';
      _decryptionSuccess = false;
    });

    try {
      final fileEncryption = FileEncryptionService();
      
      if (kDebugMode) {
        debugPrint('🔓 Starting file decryption...');
        debugPrint('   File: ${widget.fileName}');
        debugPrint('   Key: ${_keyController.text}');
        debugPrint('   Data size: ${widget.encryptedData.length} bytes');
      }

      // Untuk demo, kita buat file temporary
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_encrypted_${widget.fileName}');
      await tempFile.writeAsBytes(widget.encryptedData);

      final decryptionResult = await fileEncryption.decryptFile(
        file: tempFile,
        encryptionKey: _keyController.text,
        chatId: 'decryption_modal', // ID sementara
      );

      setState(() {
        _decryptedData = decryptionResult.decryptedData;
        _decryptionSuccess = true;
        _decryptionStatus = '✅ Dekripsi berhasil!';
      });

      // Hapus file temporary
      await tempFile.delete();

      if (kDebugMode) {
        debugPrint('✅ File decrypted successfully');
        debugPrint('   Decrypted size: ${_decryptedData!.length} bytes');
      }

    } catch (e) {
      setState(() {
        _decryptionSuccess = false;
        _decryptionStatus = '❌ Gagal mendekripsi: $e';
      });
      
      if (kDebugMode) {
        debugPrint('❌ Decryption error: $e');
      }
    } finally {
      setState(() {
        _isDecrypting = false;
      });
    }
  }

  void _saveDecryptedFile() async {
    if (_decryptedData == null) return;

    try {
      final supabaseService = SupabaseService();
      final savedFile = await supabaseService.saveFileToLocation(
        data: _decryptedData!,
        fileName: 'decrypted_${widget.fileName}',
        locationType: 'downloads',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File berhasil disimpan di: ${savedFile.path}'),
            backgroundColor: Colors.green,
          ),
        );
      }

      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _viewDecryptedContent() {
    if (_decryptedData == null) return;

    // Cek jika file adalah text file
    final fileName = widget.fileName.toLowerCase();
    final isTextFile = fileName.endsWith('.txt') || 
                       fileName.endsWith('.log') ||
                       fileName.endsWith('.json') ||
                       fileName.endsWith('.xml');

    if (isTextFile) {
      final textContent = String.fromCharCodes(_decryptedData!);
      _showTextContent(textContent);
    } else {
      _showFileInfo();
    }
  }

  void _showTextContent(String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kontens File Terdekripsi'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              content.length > 1000 
                ? '${content.substring(0, 1000)}...\n\n[Content dipotong, total ${content.length} karakter]'
                : content,
              style: const TextStyle(fontFamily: 'Monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _saveDecryptedFile();
            },
            child: const Text('Simpan File'),
          ),
        ],
      ),
    );
  }

  void _showFileInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File Terdekripsi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nama: ${widget.fileName}'),
            Text('Ukuran: ${_formatFileSize(_decryptedData!.length)}'),
            Text('Tipe: Binary File'),
            const SizedBox(height: 16),
            const Text(
              'File berhasil didekripsi. Silakan simpan untuk melihat konten.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _saveDecryptedFile();
            },
            child: const Text('Simpan File'),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_open, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Dekripsi File',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              widget.fileName,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ukuran: ${_formatFileSize(widget.encryptedData.length)}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _keyController,
                decoration: const InputDecoration(
                  labelText: 'Kunci Dekripsi',
                  hintText: 'Masukkan kunci dekripsi...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Harap masukkan kunci dekripsi';
                  }
                  if (value.length < 6) {
                    return 'Kunci terlalu pendek (min. 6 karakter)';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 16),
            if (_decryptionStatus.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _decryptionSuccess ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _decryptionSuccess ? Colors.green : Colors.red,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _decryptionSuccess ? Icons.check_circle : Icons.error,
                      color: _decryptionSuccess ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _decryptionStatus,
                        style: TextStyle(
                          color: _decryptionSuccess ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            if (!_decryptionSuccess)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isDecrypting ? null : _decryptFile,
                      child: _isDecrypting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Dekripsi'),
                    ),
                  ),
                ],
              ),
            if (_decryptionSuccess)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _viewDecryptedContent,
                      child: const Text('Lihat Konten'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saveDecryptedFile,
                      child: const Text('Simpan File'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }
}