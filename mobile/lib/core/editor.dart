import 'package:flutter/material.dart';
import 'models.dart';
import 'widgets.dart';

class EditField {
  final String key, label;
  final String type;
  final bool optional;
  final List<String>? choices;
  const EditField(this.key, this.label,
      {this.type = 'text', this.optional = false, this.choices});
}

Future<void> editRecord(BuildContext context,
        {required String title,
        required List<EditField> fields,
        Json initial = const {},
        required Future<void> Function(Json) save}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _RecordEditor(
            title: title, fields: fields, initial: initial, save: save)));

class _RecordEditor extends StatefulWidget {
  final String title;
  final List<EditField> fields;
  final Json initial;
  final Future<void> Function(Json) save;
  const _RecordEditor(
      {required this.title,
      required this.fields,
      required this.initial,
      required this.save});
  @override
  State<_RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<_RecordEditor> {
  final form = GlobalKey<FormState>();
  final controllers = <String, TextEditingController>{};
  final values = <String, dynamic>{};
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      if (f.type == 'bool') {
        values[f.key] = widget.initial[f.key] ?? false;
      } else if (f.choices != null) {
        values[f.key] = widget.initial[f.key] ?? f.choices!.first;
      } else {
        controllers[f.key] = TextEditingController(
            text: widget.initial[f.key]?.toString() ?? '');
      }
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
          child: Form(
              key: form,
              child: ListView(padding: const EdgeInsets.all(20), children: [
                for (final f in widget.fields)
                  if (f.type == 'bool')
                    SwitchListTile(
                        title: Text(f.label),
                        value: values[f.key],
                        onChanged: (v) => setState(() => values[f.key] = v))
                  else if (f.choices != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: DropdownButtonFormField<String>(
                            value: values[f.key],
                            isExpanded: true,
                            decoration: InputDecoration(labelText: f.label),
                            items: f.choices!
                                .map((v) => DropdownMenuItem(
                                    value: v, child: Text(human(v))))
                                .toList(),
                            onChanged: (v) => values[f.key] = v))
                  else
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: TextFormField(
                            controller: controllers[f.key],
                            decoration: InputDecoration(labelText: f.label),
                            maxLines: f.type == 'multiline' ? 3 : 1,
                            keyboardType: ['int', 'decimal'].contains(f.type)
                                ? const TextInputType.numberWithOptions(
                                    decimal: true, signed: true)
                                : null,
                            validator: (v) {
                              if ((v ?? '').trim().isEmpty) {
                                return f.optional ? null : 'Required';
                              }
                              if (f.type == 'int' &&
                                  (int.tryParse(v!) == null ||
                                      int.parse(v) < 0)) {
                                return 'Enter a nonnegative whole number';
                              }
                              if (f.type == 'decimal' &&
                                  (double.tryParse(v!) == null ||
                                      !double.parse(v).isFinite)) {
                                return 'Enter a valid number';
                              }
                              return null;
                            })),
                const SizedBox(height: 16),
                ActionButton('Save changes', () async {
                  if (!form.currentState!.validate()) return;
                  final data = <String, dynamic>{...values};
                  for (final f in widget.fields) {
                    if (!controllers.containsKey(f.key)) continue;
                    final text = controllers[f.key]!.text.trim();
                    data[f.key] = text.isEmpty && f.optional
                        ? null
                        : f.type == 'int'
                            ? int.parse(text)
                            : f.type == 'decimal'
                                ? double.parse(text)
                                : text;
                  }
                  await widget.save(data);
                  if (context.mounted) Navigator.pop(context);
                }),
              ]))));
}
