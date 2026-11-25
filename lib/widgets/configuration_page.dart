import 'package:material_ui/material_ui.dart';

import 'ducky_script_text.dart';

Future<T?> showConfigurationPage<T>(
  BuildContext context,
  WidgetBuilder builder,
) {
  FocusManager.instance.primaryFocus?.unfocus();
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push<T>(MaterialPageRoute<T>(builder: builder, fullscreenDialog: true));
}

/// A modal editor with a scrollable form and an action above the keyboard.
class ConfigurationPage extends StatelessWidget {
  const ConfigurationPage({
    super.key,
    required this.title,
    required this.child,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final Widget child;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: TextButton(onPressed: onAction, child: Text(actionLabel)),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SizedBox(width: double.infinity, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Owns the controller for short, single-value configuration forms.
class TextConfigurationPage extends StatefulWidget {
  const TextConfigurationPage({
    super.key,
    required this.title,
    required this.fieldLabel,
    required this.actionLabel,
    this.initialValue = '',
    this.hint,
    this.multiline = true,
    this.highlightScript = false,
  });

  final String title;
  final String fieldLabel;
  final String actionLabel;
  final String initialValue;
  final String? hint;
  final bool multiline;
  final bool highlightScript;

  @override
  State<TextConfigurationPage> createState() => _TextConfigurationPageState();
}

class _TextConfigurationPageState extends State<TextConfigurationPage> {
  late final _controller = widget.highlightScript
      ? DuckyScriptEditingController(text: widget.initialValue)
      : TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConfigurationPage(
      title: widget.title,
      actionLabel: widget.actionLabel,
      onAction: () => Navigator.pop(context, _controller.text),
      child: TextField(
        controller: _controller,
        minLines: widget.multiline ? 4 : 1,
        maxLines: widget.multiline ? 10 : 1,
        keyboardType: widget.multiline
            ? TextInputType.multiline
            : TextInputType.text,
        textInputAction: widget.multiline
            ? TextInputAction.newline
            : TextInputAction.done,
        onSubmitted: widget.multiline
            ? null
            : (value) => Navigator.pop(context, value),
        autocorrect: false,
        style: widget.multiline
            ? const TextStyle(fontFamily: 'monospace')
            : null,
        decoration: InputDecoration(
          labelText: widget.fieldLabel,
          hintText: widget.hint,
          hintMaxLines: 3,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
