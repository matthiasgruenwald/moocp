import 'package:flutter/material.dart';

import 'freigabe.dart';
import 'profil.dart';

class ProfileDialog extends StatefulWidget {
  const ProfileDialog({this.profil, this.port = 0, super.key});

  final Profil? profil;
  final int port;

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  late final _name = TextEditingController(text: widget.profil?.name);
  late final _adresse = TextEditingController(text: widget.profil?.adresse);
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _adresse.dispose();
    super.dispose();
  }

  void _speichern() {
    if (!_form.currentState!.validate()) return;
    final alt = widget.profil;
    final kennung = alt?.kennung ?? Profil.neueKennung();
    Navigator.pop(
      context,
      alt == null
          ? Profil(
              kennung: kennung,
              name: _name.text.trim(),
              adresse: _adresse.text.trim(),
              port: widget.port,
              mcpName: Profil.mcpNameFuer(_name.text.trim(), kennung),
              bestaetigungen: Bestaetigungen.vorgabe,
            )
          : alt.copyWith(
              name: _name.text.trim(),
              adresse: _adresse.text.trim(),
            ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.profil == null
          ? 'Moodle-Profil hinzufügen'
          : 'Moodle-Profil bearbeiten',
    ),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('profile-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Profilname'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Profilname eingeben' : null,
            ),
            TextFormField(
              key: const Key('profile-address'),
              controller: _adresse,
              decoration: const InputDecoration(labelText: 'Moodle-Adresse'),
              validator: (v) {
                final uri = Uri.tryParse(v?.trim() ?? '');
                return uri == null ||
                        !{'http', 'https'}.contains(uri.scheme) ||
                        uri.host.isEmpty
                    ? 'Eine gültige http- oder https-Adresse eingeben'
                    : null;
              },
            ),
            if (widget.profil != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('MCP-Servername: ${widget.profil!.mcpName}'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: _speichern,
        child: Text(widget.profil == null ? 'Hinzufügen' : 'Übernehmen'),
      ),
    ],
  );
}
