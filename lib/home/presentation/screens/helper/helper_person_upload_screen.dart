import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';

class HelperPersonUploadScreen extends StatefulWidget {
  const HelperPersonUploadScreen({super.key});

  @override
  State<HelperPersonUploadScreen> createState() => _HelperPersonUploadScreenState();
}

class _HelperPersonUploadScreenState extends State<HelperPersonUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final List<File?> _images = List.filled(5, null);
  bool _isUploading = false;
  String? _uploadError;

  Future<void> _pickImage(int index) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      setState(() {
        _images[index] = File(image.path);
      });
    }
  }

  Future<void> _uploadPersonData() async {
    if (!_formKey.currentState!.validate()) return;
    if (_images.where((image) => image == null).length > 0) {
      setState(() {
        _uploadError = 'Please upload all 5 images';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    try {
      final storage = FirebaseStorage.instance;
      final firestore = FirebaseFirestore.instance;
      final personName = _nameController.text.trim();
      
      // Create a new document in the persons collection
      final personDoc = await firestore.collection('persons').add({
        'name': personName,
        'uploadedBy': FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid),
        'uploadedAt': FieldValue.serverTimestamp(),
      });

      // Upload each image
      final List<String> imageUrls = [];
      for (int i = 0; i < _images.length; i++) {
        final imageFile = _images[i]!;
        final imageName = '${personDoc.id}_$i.jpg';
        final storageRef = storage.ref().child('person_images/$imageName');
        
        await storageRef.putFile(imageFile);
        final imageUrl = await storageRef.getDownloadURL();
        imageUrls.add(imageUrl);
      }

      // Update the document with image URLs
      await personDoc.update({
        'imageUrls': imageUrls,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Person data uploaded successfully'.tr())),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _uploadError = 'Failed to upload: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Upload Person Data'.tr()),
      ),
      body: _isUploading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Person Name'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a name'.tr();
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Upload 5 Images'.tr(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: 5,
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () => _pickImage(index),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: _images[index] != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      _images[index]!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_a_photo,
                                          color: Colors.grey[400]),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Image ${index + 1}'.tr(),
                                        style: TextStyle(color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                          ),
                        );
                      },
                    ),
                    if (_uploadError != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _uploadError!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _uploadPersonData,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text('Upload Person Data'.tr()),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
} 