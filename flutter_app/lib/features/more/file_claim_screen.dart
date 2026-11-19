import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../requests/request_form_widgets.dart';
import 'more_models.dart';
import 'more_providers.dart';
import 'more_widgets.dart';

const _tint = Color(0xFFD97706);

/// Files a reimbursement for the signed-in employee. A receipt is required.
class FileClaimScreen extends ConsumerStatefulWidget {
  const FileClaimScreen({super.key});

  @override
  ConsumerState<FileClaimScreen> createState() => _FileClaimScreenState();
}

class _FileClaimScreenState extends ConsumerState<FileClaimScreen> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String? _fileName;
  String? _filePath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(_refresh);
    _amount.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _ready =>
      !_saving &&
      claimReady(
        title: _title.text,
        amountText: _amount.text,
        date: _date,
        fileName: _fileName,
      );

  Future<void> _pickDate() async {
    final picked = await showRequestCalendarPicker(context, initialDate: _date);
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _pickFile() async {
    final file = await ref.read(claimFilePickerProvider)();
    if (file == null || !mounted) return;
    setState(() {
      _fileName = file.name;
      _filePath = file.path;
    });
  }

  Future<void> _submit() async {
    if (!_ready || _fileName == null || _filePath == null) return;
    FocusScope.of(context).unfocus();
    final amount = double.parse(_amount.text.trim());
    setState(() => _saving = true);
    try {
      await ref.read(claimFilerProvider)(
        ClaimDraft(
          title: _title.text.trim(),
          date: _date,
          amount: amount,
          description: _note.text,
          fileName: _fileName!,
          filePath: _filePath!,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, cleanError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('d MMM yyyy').format(_date);

    return MorePage(
      title: 'File a claim',
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                const _Label('What was it for'),
                TextField(
                  key: const Key('claim-title'),
                  controller: _title,
                  maxLength: 50,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: 'Client dinner',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 18),
                const _Label('Amount'),
                TextField(
                  key: const Key('claim-amount'),
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: '0.00',
                  ),
                ),
                const SizedBox(height: 18),
                const _Label('Date of the expense'),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                      child: Text(
                        dateLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const _Label('Note'),
                TextField(
                  key: const Key('claim-note'),
                  controller: _note,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: 'Optional details for the approver',
                  ),
                ),
                const SizedBox(height: 18),
                const _Label('Receipt'),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickFile,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _tint,
                    side: const BorderSide(color: Color(0xFFE8C9A0)),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    alignment: Alignment.centerLeft,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(
                    _fileName ?? 'Attach receipt',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          RequestFormFooter(
            canSubmit: _ready,
            onCancel: () => Navigator.of(context).pop(),
            onSubmit: _submit,
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
