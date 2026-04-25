import 'package:flutter/material.dart';

/// Text field that owns its [TextEditingController] across rebuilds.
///
/// Re-creating a controller on every parent rebuild — which is what
/// `controller: TextEditingController(text: ...)` does — scrambles the
/// cursor and drops focus on each keystroke when the parent watches a
/// state that changes per-keystroke. We avoid that by holding the
/// controller in a State, and only mirror external value changes when
/// the field is idle (not focused).
class PersistentTextField extends StatefulWidget {
  const PersistentTextField({
    required this.value,
    required this.onChanged,
    required this.labelText,
    this.enabled = true,
    this.keyboardType,
    this.helperText,
    this.prefixText,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String labelText;
  final bool enabled;
  final TextInputType? keyboardType;
  final String? helperText;
  final String? prefixText;

  @override
  State<PersistentTextField> createState() => _PersistentTextFieldState();
}

class _PersistentTextFieldState extends State<PersistentTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant PersistentTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      enabled: widget.enabled,
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      decoration: InputDecoration(
        labelText: widget.labelText,
        helperText: widget.helperText,
        prefixText: widget.prefixText,
      ),
      onChanged: widget.onChanged,
    );
  }
}
