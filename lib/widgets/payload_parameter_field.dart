import 'package:material_ui/material_ui.dart';

import '../data/models/payload.dart';

class PayloadParameterField extends StatelessWidget {
  const PayloadParameterField({
    super.key,
    required this.parameter,
    required this.controller,
  });

  final PayloadParameter parameter;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final label = parameter.required
        ? '${parameter.label} (required)'
        : parameter.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: Text(label, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: label,
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: parameter.defaultValue.isEmpty
                  ? null
                  : parameter.defaultValue,
              hintMaxLines: 2,
              helperText: parameter.description.isEmpty
                  ? null
                  : parameter.description,
              helperMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}
