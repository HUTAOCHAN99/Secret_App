import 'package:flutter/material.dart';

class FileLocationModal extends StatefulWidget {
  final String fileName;
  final bool isUpload;

  const FileLocationModal({
    super.key,
    required this.fileName,
    this.isUpload = true,
  });

  @override
  State<FileLocationModal> createState() => _FileLocationModalState();
}

class _FileLocationModalState extends State<FileLocationModal> {
  String _selectedLocation = 'app_documents';
  final Map<String, String> _locationNames = {
    'app_documents': 'Penyimpanan Internal',
    'external_storage': 'Penyimpanan Eksternal',
    'downloads': 'Folder Downloads',
    'temp': 'Penyimpanan Sementara',
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.isUpload 
            ? 'Upload File: ${widget.fileName}'
            : 'Simpan File: ${widget.fileName}',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isUpload
                ? 'Pilih file dari:'
                : 'Simpan file ke:',
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          ..._locationNames.entries.map((entry) {
            return RadioListTile<String>(
              title: Text(entry.value),
              value: entry.key,
              groupValue: _selectedLocation,
              onChanged: (value) {
                setState(() {
                  _selectedLocation = value!;
                });
              },
            );
          }).toList(),
          const SizedBox(height: 8),
          Text(
            _getLocationDescription(_selectedLocation),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selectedLocation),
          child: Text(widget.isUpload ? 'Pilih File' : 'Simpan'),
        ),
      ],
    );
  }

  String _getLocationDescription(String location) {
    switch (location) {
      case 'app_documents':
        return 'File disimpan di folder aplikasi (aman, tidak terlihat user lain)';
      case 'external_storage':
        return 'File disimpan di penyimpanan perangkat (bisa diakses file manager)';
      case 'downloads':
        return 'File disimpan di folder Downloads (mudah ditemukan)';
      case 'temp':
        return 'File disimpan sementara (bisa terhapus oleh sistem)';
      default:
        return '';
    }
  }
}