// secret_app/lib/screens/file_decryption_modal.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../services/file_encryption_service.dart';

class FileDecryptionModal extends StatefulWidget {
  final String fileName;
  final Uint8List encryptedData;
  final String defaultKey;
  final Uint8List nonce;
  final Uint8List authTag;
  final String? chatId;
  final bool requireManualKey;
  final bool isOwner;

  const FileDecryptionModal({
    super.key,
    required this.fileName,
    required this.encryptedData,
    required this.defaultKey,
    required this.nonce,
    required this.authTag,
    this.chatId,
    this.requireManualKey = false,
    this.isOwner = false,
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
  String? _debugInfo;
  bool _showKey = false;
  bool _keyVisibleForOwner = false;

  @override
  void initState() {
    super.initState();
    
    if (widget.isOwner && widget.defaultKey.isNotEmpty) {
      _keyController.text = widget.defaultKey;
    } else if (!widget.requireManualKey && widget.defaultKey.isNotEmpty) {
      _keyController.text = widget.defaultKey;
    }
  }

  Future<void> _decryptFile() async {
    if (!_formKey.currentState!.validate()) return;

    if (!mounted) return;

    setState(() {
      _isDecrypting = true;
      _decryptionStatus = 'Sedang mendekripsi file...';
      _decryptionSuccess = false;
      _debugInfo = null;
    });

    try {
      final fileEncryption = FileEncryptionService();
      
      if (kDebugMode) {
        debugPrint('🔓 Starting file decryption...');
        debugPrint('   File: ${widget.fileName}');
        debugPrint('   Key length: ${_keyController.text.length}');
        debugPrint('   Data size: ${widget.encryptedData.length} bytes');
        debugPrint('   Is Owner: ${widget.isOwner}');
      }

      final chatId = widget.chatId ?? 'manual_decryption';

      final decryptionResult = await fileEncryption.decryptFile(
        encryptedData: widget.encryptedData,
        nonce: widget.nonce,
        authTag: widget.authTag,
        encryptionKey: _keyController.text.trim(),
        chatId: chatId,
      );

      setState(() {
        _decryptedData = decryptionResult;
        _decryptionSuccess = true;
        _decryptionStatus = '✅ Dekripsi berhasil!';
        _debugInfo = 'File berhasil didekripsi. Ukuran: ${_formatFileSize(decryptionResult.length)}';
      });

      if (kDebugMode) {
        debugPrint('✅ File decrypted successfully');
        debugPrint('   Decrypted size: ${_decryptedData!.length} bytes');
      }

    } catch (e) {
      setState(() {
        _decryptionSuccess = false;
        _decryptionStatus = '❌ Gagal mendekripsi';
        _debugInfo = 'Kunci dekripsi salah atau file rusak. Pastikan kunci yang dimasukkan benar.';
      });
      
      if (kDebugMode) {
        debugPrint('❌ Decryption error: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDecrypting = false;
        });
      }
    }
  }

  Future<void> _saveDecryptedFile() async {
    if (_decryptedData == null) return;

    try {
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          downloadsDir = await getExternalStorageDirectory();
        }
      } else {
        downloadsDir = await getDownloadsDirectory();
      }

      if (downloadsDir == null) {
        throw Exception('Tidak dapat mengakses directory downloads');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'decrypted_${timestamp}_${widget.fileName}';
      final file = File('${downloadsDir.path}/$fileName');

      await file.writeAsBytes(_decryptedData!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('File berhasil disimpan: $fileName'),
                Text(
                  'Lokasi: ${file.path}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
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

    final fileName = widget.fileName.toLowerCase();
    final isTextFile = fileName.endsWith('.txt') || 
                       fileName.endsWith('.log') ||
                       fileName.endsWith('.json') ||
                       fileName.endsWith('.xml') ||
                       fileName.endsWith('.csv') ||
                       fileName.endsWith('.html');

    if (isTextFile) {
      try {
        final textContent = utf8.decode(_decryptedData!);
        _showTextContent(textContent);
      } catch (e) {
        _showBinaryContent();
      }
    } else {
      _showBinaryContent();
    }
  }

  void _showTextContent(String content) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Konten File Terdekripsi',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 0),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      content,
                      style: const TextStyle(fontFamily: 'Monospace', fontSize: 12),
                    ),
                  ),
                ),
              ),
              const Divider(height: 0),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total karakter: ${content.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Tutup'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _saveDecryptedFile();
                          },
                          child: const Text('Simpan File'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBinaryContent() {
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info, size: 16, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'File ini berisi data biner. Simpan untuk melihat kontennya.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
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

  Widget _buildKeyInputField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Untuk Owner - Tampilkan kunci dengan toggle visibility
        if (widget.isOwner && widget.defaultKey.isNotEmpty)
          Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified_user, size: 16, color: Colors.green),
                        const SizedBox(width: 8),
                        const Text(
                          'Anda adalah Pemilik File',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _keyVisibleForOwner 
                                ? widget.defaultKey
                                : '•' * widget.defaultKey.length,
                            style: TextStyle(
                              fontFamily: 'Monospace',
                              fontSize: 12,
                              color: Colors.green[800],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _keyVisibleForOwner ? Icons.visibility_off : Icons.visibility,
                            size: 18,
                            color: Colors.green,
                          ),
                          onPressed: () {
                            setState(() {
                              _keyVisibleForOwner = !_keyVisibleForOwner;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.content_copy, size: 14, color: Colors.green[700]),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: widget.defaultKey));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Kunci dekripsi disalin ke clipboard'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          },
                          child: Text(
                            'Salin kunci',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(Icons.share, size: 14, color: Colors.green[700]),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: _shareDecryptionKey,
                          child: Text(
                            'Bagikan kunci',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),

        // Field input kunci (untuk manual input atau fallback)
        TextFormField(
          controller: _keyController,
          decoration: InputDecoration(
            labelText: widget.isOwner ? 'Kunci Dekripsi (Opsional)' : 'Kunci Dekripsi',
            hintText: widget.isOwner 
                ? 'Kunci sudah tersedia di atas, atau masukkan kunci lain...'
                : 'Masukkan kunci rahasia untuk mendekripsi...',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.key),
            suffixIcon: widget.isOwner ? null : IconButton(
              icon: Icon(_showKey ? Icons.visibility : Icons.visibility_off),
              onPressed: () {
                setState(() {
                  _showKey = !_showKey;
                });
              },
            ),
          ),
          obscureText: widget.isOwner ? false : !_showKey,
          readOnly: widget.isOwner && widget.defaultKey.isNotEmpty,
          validator: (value) {
            if (value == null || value.isEmpty) {
              if (!widget.isOwner) {
                return 'Harap masukkan kunci dekripsi';
              }
            }
            if (value != null && value.length < 6) {
              return 'Kunci terlalu pendek (min. 6 karakter)';
            }
            return null;
          },
        ),

        const SizedBox(height: 8),
        
        // Info untuk manual key requirement
        if (widget.requireManualKey && !widget.isOwner)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info, size: 16, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Minta kunci dekripsi dari pengirim file untuk membuka file ini.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        // Info untuk owner
        if (widget.isOwner)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.security, size: 16, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sebagai pemilik file, Anda memiliki akses penuh ke kunci dekripsi.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _shareDecryptionKey() {
    final message = 
        '🔐 Kunci Dekripsi File\n'
        'File: ${widget.fileName}\n'
        'Kunci: ${widget.defaultKey}\n'
        '\n'
        'Gunakan kunci ini untuk mendekripsi file. Jangan bagikan kepada orang yang tidak dipercaya.';

    Clipboard.setData(ClipboardData(text: message));
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Kunci dekripsi disalin ke clipboard. Bagikan secara aman.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildOwnerBadge() {
    if (!widget.isOwner) return const SizedBox();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user, color: Colors.green[600], size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pemilik File',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.green[800],
                    fontSize: 14,
                  ),
                ),
                Text(
                  'Anda memiliki akses penuh ke kunci dekripsi',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugInfo() {
    if (_debugInfo == null) return const SizedBox();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
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
              _debugInfo!,
              style: TextStyle(
                color: _decryptionSuccess ? Colors.green[800] : Colors.red[800],
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
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
                Icon(
                  widget.isOwner ? Icons.verified_user : Icons.lock_open,
                  color: widget.isOwner ? Colors.green : Colors.blue,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isOwner ? 'Owner File Access' : 'File Decryption',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Owner badge
            _buildOwnerBadge(),
            
            // File info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ukuran: ${_formatFileSize(widget.encryptedData.length)}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  if (!widget.isOwner && widget.requireManualKey) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.security, size: 14, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Manual key required - Contact file sender for decryption key',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            Form(
              key: _formKey,
              child: _buildKeyInputField(),
            ),
            
            const SizedBox(height: 16),
            _buildDebugInfo(),
            
            const SizedBox(height: 20),
            if (!_decryptionSuccess)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
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
                          : Text(widget.isOwner ? 'Dekripsi' : 'Dekripsi File'),
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