import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/legal/legal_content.dart';

enum LegalDocument { privacy, terms }

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({required this.document, super.key});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final isPrivacy = document == LegalDocument.privacy;
    final publicUrl =
        isPrivacy ? LegalContent.privacyPolicyUrl : LegalContent.termsUrl;
    return Scaffold(
      appBar: AppBar(
          title: Text(isPrivacy ? 'Privacy Policy' : 'Terms and Conditions')),
      body: SafeArea(
        child: SelectionArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Text(
                    isPrivacy ? LegalContent.privacyPolicy : LegalContent.terms,
                    style: const TextStyle(fontSize: 15, height: 1.55),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(publicUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open public web version'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
