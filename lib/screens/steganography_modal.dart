// secret_app/lib/screens/steganography_modal.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/steganography_service.dart';

class SteganographyModal extends StatefulWidget {
  final String chatId;
  final String encryptionKey;

  const SteganographyModal({
    super.key,
    required this.chatId,
    required this.encryptionKey,
  });

  @override
  State<SteganographyModal> createState() => _SteganographyModalState();
}

class _SteganographyModalState extends State<SteganographyModal> {
  final SteganographyService _steganographyService = SteganographyService();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  Uint8List? _selectedImage;
  Uint8List? _originalImage;
  String? _imageFileName;
  bool _isProcessing = false;
  bool _isEncoding = true;
  String? _resultMessage;
  bool _resultSuccess = false;
  int? _maxCapacity;

  @override
  void initState() {
    super.initState();
    _passwordController.text = widget.encryptionKey;
    _initializeService();
  }

  Future<void> _initializeService() async {
    try {
      await _steganographyService.initialize();
      _showSuccess('Real Steganography Ready - LSB Algorithm');
    } catch (e) {
      _showError('Service initialization failed: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _selectedImage = file.bytes;
          _originalImage = Uint8List.fromList(file.bytes!); // Simpan copy original
          _imageFileName = file.name;
        });

        // Calculate max capacity
        if (_selectedImage != null) {
          final capacity = _steganographyService.getMaxCapacity(_selectedImage!);
          setState(() {
            _maxCapacity = capacity;
          });
        }

        _showSuccess('Selected: ${file.name} (${_selectedImage!.length} bytes)');
      }
    } catch (e) {
      _showError('Error picking image: $e');
    }
  }

  Future<void> _encodeMessage() async {
    if (_selectedImage == null) {
      _showError('Please select an image first');
      return;
    }

    if (_messageController.text.isEmpty) {
      _showError('Please enter a message to hide');
      return;
    }

    if (_passwordController.text.isEmpty) {
      _showError('Please enter a password');
      return;
    }

    if (_maxCapacity != null && _messageController.text.length > _maxCapacity!) {
      _showError('Message too long. Max $_maxCapacity characters');
      return;
    }

    setState(() {
      _isProcessing = true;
      _resultMessage = null;
    });

    try {
      final stopwatch = Stopwatch()..start();
      
      final response = await _steganographyService.encodeMessage(
        imageData: _selectedImage!,
        message: _messageController.text,
        password: _passwordController.text,
      );

      stopwatch.stop();

      setState(() {
        _resultSuccess = response.success;
        if (response.success) {
          _selectedImage = response.data; // Update dengan gambar encoded
          _resultMessage = '✅ Message hidden successfully!\n\n'
              '• Algorithm: LSB Steganography\n'
              '• Processing: ${stopwatch.elapsedMilliseconds}ms\n'
              '• Security: XOR Encryption\n'
              '• Platform: ${Platform.operatingSystem}';
        } else {
          _resultMessage = '❌ Encode failed: ${response.errorMessage}';
        }
      });

      if (response.success) {
        _showEncodeSuccess();
      }
    } catch (e) {
      setState(() {
        _resultSuccess = false;
        _resultMessage = '❌ Encoding error: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _decodeMessage() async {
    if (_selectedImage == null) {
      _showError('Please select an encoded image first');
      return;
    }

    if (_passwordController.text.isEmpty) {
      _showError('Please enter the decryption password');
      return;
    }

    setState(() {
      _isProcessing = true;
      _resultMessage = null;
    });

    try {
      final stopwatch = Stopwatch()..start();
      
      final response = await _steganographyService.decodeMessage(
        imageData: _selectedImage!,
        password: _passwordController.text,
      );

      stopwatch.stop();

      setState(() {
        _resultSuccess = response.success;
        if (response.success) {
          _resultMessage = '✅ Message extracted successfully!\n\n'
              '• Algorithm: LSB Steganography\n'
              '• Processing: ${stopwatch.elapsedMilliseconds}ms\n'
              '• Security: XOR Decryption\n'
              '• Hidden Message: "${response.decodedMessage}"';
        } else {
          _resultMessage = '❌ Decode failed: ${response.errorMessage}';
        }
      });
    } catch (e) {
      setState(() {
        _resultSuccess = false;
        _resultMessage = '❌ Decoding error: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _compareImages() {
    if (_originalImage == null || _selectedImage == null) return;
    
    int differences = 0;
    for (int i = 0; i < _originalImage!.length; i++) {
      if (_originalImage![i] != _selectedImage![i]) {
        differences++;
      }
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Image Comparison'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total pixels modified: $differences'),
            Text('Modification rate: ${(differences / _originalImage!.length * 100).toStringAsFixed(2)}%'),
            const SizedBox(height: 12),
            const Text(
              'This shows how many pixels were altered to hide your message '
              'using the LSB (Least Significant Bit) technique.',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showEncodeSuccess() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.green),
            SizedBox(width: 8),
            Text('Message Hidden Successfully'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your message has been securely hidden in the image using LSB steganography.'),
            SizedBox(height: 12),
            Text(
              '🔐 Encrypted with your password\n'
              '🎨 Hidden in pixel LSBs\n'
              '📷 Visually identical to original\n'
              '🔍 Only detectable with correct password',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _compareImages();
            },
            child: const Text('Show Changes'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _clearAll() {
    setState(() {
      _selectedImage = _originalImage; // Kembali ke gambar original
      _imageFileName = null;
      _messageController.clear();
      _resultMessage = null;
      _maxCapacity = null;
    });
    _showSuccess('All fields cleared');
  }

  void _showOriginalImage() {
    if (_originalImage != null) {
      setState(() {
        _selectedImage = _originalImage;
      });
      _showSuccess('Showing original image');
    }
  }

  void _showEncodedImage() {
    // Encoded image sudah di _selectedImage setelah encode
    _showSuccess('Showing encoded image');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Real Steganography - LSB Algorithm'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          if (_originalImage != null && _selectedImage != _originalImage)
            IconButton(
              icon: const Icon(Icons.compare),
              onPressed: _compareImages,
              tooltip: 'Compare Images',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _clearAll,
            tooltip: 'Clear All',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Info Banner
          _buildInfoBanner(),
          const SizedBox(height: 16),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Mode Selection
                  _buildModeSelection(),
                  const SizedBox(height: 16),

                  // Image Selection
                  _buildImageSelection(),
                  const SizedBox(height: 16),

                  // Message Input
                  if (_isEncoding) _buildMessageInput(),
                  if (_isEncoding) const SizedBox(height: 16),

                  // Password Input
                  _buildPasswordInput(),
                  const SizedBox(height: 16),

                  // Image Comparison Buttons
                  if (_originalImage != null && _selectedImage != _originalImage)
                    _buildImageComparison(),
                  if (_originalImage != null && _selectedImage != _originalImage)
                    const SizedBox(height: 16),

                  // Result
                  if (_resultMessage != null) _buildResultDisplay(),
                  if (_resultMessage != null) const SizedBox(height: 16),

                  // Action Button
                  _buildActionButton(),
                  const SizedBox(height: 16),

                  // Technical Info
                  _buildTechnicalInfo(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user, color: Colors.green, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REAL STEGANOGRAPHY - LSB ALGORITHM',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Platform: ${Platform.operatingSystem} • Pure Dart Implementation',
                  style: const TextStyle(
                    color: Colors.green,
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

  Widget _buildModeSelection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Operation Mode',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Encode Message'),
                    selected: _isEncoding,
                    onSelected: (selected) {
                      setState(() {
                        _isEncoding = selected;
                        _resultMessage = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Decode Message'),
                    selected: !_isEncoding,
                    onSelected: (selected) {
                      setState(() {
                        _isEncoding = !selected;
                        _resultMessage = null;
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSelection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Image',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (_selectedImage != null) ...[
              Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: MemoryImage(_selectedImage!),
                    fit: BoxFit.cover,
                  ),
                  border: Border.all(
                    color: _selectedImage != _originalImage 
                        ? Colors.green 
                        : Colors.grey,
                    width: 2,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _imageFileName ?? 'Unknown file',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  if (_selectedImage != _originalImage)
                    const Text(
                      'ENCODED',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              if (_maxCapacity != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Max capacity: $_maxCapacity characters',
                  style: const TextStyle(fontSize: 12, color: Colors.blue),
                ),
              ],
              const SizedBox(height: 12),
            ],
            ElevatedButton.icon(
              icon: const Icon(Icons.photo_library),
              label: const Text('Pick Image'),
              onPressed: _pickImage,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageComparison() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.image),
            label: const Text('Original'),
            onPressed: _showOriginalImage,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            icon: const Icon(Icons.security),
            label: const Text('Encoded'),
            onPressed: _showEncodedImage,
          ),
        ),
      ],
    );
  }

  Widget _buildMessageInput() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Secret Message',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter your secret message...',
                border: OutlineInputBorder(),
              ),
            ),
            if (_maxCapacity != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _messageController.text.length / _maxCapacity!,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  _messageController.text.length > _maxCapacity! 
                      ? Colors.red 
                      : Colors.green,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_messageController.text.length}/$_maxCapacity characters',
                style: TextStyle(
                  fontSize: 12,
                  color: _messageController.text.length > _maxCapacity! 
                      ? Colors.red 
                      : Colors.grey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordInput() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Encryption Password',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'Enter strong password...',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.security),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This password encrypts your message before hiding it in the image.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultDisplay() {
    return Card(
      color: _resultSuccess ? Colors.green[50] : Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              _resultSuccess ? Icons.check_circle : Icons.error,
              color: _resultSuccess ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _resultMessage!,
                style: TextStyle(
                  color: _resultSuccess ? Colors.green[800] : Colors.red[800],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isProcessing ? null : 
            (_isEncoding ? _encodeMessage : _decodeMessage),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isEncoding ? Colors.green : Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: _isProcessing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Text(
                _isEncoding ? 'Hide Message in Image' : 'Extract Hidden Message',
                style: const TextStyle(fontSize: 16),
              ),
      ),
    );
  }

  Widget _buildTechnicalInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.architecture, size: 16, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                'Technical Details - LSB Algorithm',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '• LSB (Least Significant Bit) technique\n'
            '• Modifies last bit of each color channel\n'
            '• XOR encryption before hiding\n'
            '• Visually identical to original\n'
            '• Header for data validation\n'
            '• Pure Dart - No external dependencies',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue[700],
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}