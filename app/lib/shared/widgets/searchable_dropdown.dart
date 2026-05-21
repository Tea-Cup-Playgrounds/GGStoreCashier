import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class SearchableDropdown<T> extends StatefulWidget {
  final String label;
  final String hintText;
  final T? value;
  final List<DropdownItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? Function(T?)? validator;
  final bool enabled;
  final IconData? prefixIcon;

  const SearchableDropdown({
    super.key,
    required this.label,
    required this.hintText,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    this.enabled = true,
    this.prefixIcon,
  });

  @override
  State<SearchableDropdown<T>> createState() => _SearchableDropdownState<T>();
}

class _SearchableDropdownState<T> extends State<SearchableDropdown<T>> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty) ...[
          Text(
            widget.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 4),
        ],
        Autocomplete<DropdownItem<T>>(
          initialValue: widget.value != null
              ? TextEditingValue(
                  text: widget.items
                          .cast<DropdownItem<T>?>()
                          .firstWhere(
                            (item) => item?.value == widget.value,
                            orElse: () => null,
                          )
                          ?.label ??
                      '',
                )
              : null,
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) return widget.items;
            return widget.items.where((item) => item.label.toLowerCase().contains(textEditingValue.text.toLowerCase()));
          },
          displayStringForOption: (option) => option.label,
          onSelected: (selection) => widget.onChanged(selection.value),
          fieldViewBuilder: (context, textController, focusNode, onSubmitted) {
            return TextFormField(
              controller: textController,
              focusNode: focusNode,
              enabled: widget.enabled,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: widget.hintText,
                filled: true,
                fillColor: widget.enabled ? cs.surface : cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.gold, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.destructive),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.destructive, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                prefixIcon:
                    widget.prefixIcon != null ? Icon(widget.prefixIcon, color: cs.onSurfaceVariant, size: 20) : null,
                suffixIcon: textController.text.isNotEmpty && widget.enabled
                    ? IconButton(
                        icon: Icon(Icons.clear, color: cs.onSurfaceVariant, size: 18),
                        onPressed: () {
                          textController.clear();
                          widget.onChanged(null);
                        },
                      )
                    : null,
              ),
              validator: widget.validator != null
                  ? (String? value) {
                      // If field is empty/no match, pass null to the validator
                      final matchingItem = widget.items.cast<DropdownItem<T>?>().firstWhere(
                            (item) => item?.label == value,
                            orElse: () => null,
                          );
                      return widget.validator!(matchingItem?.value);
                    }
                  : null,
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final cs = Theme.of(context).colorScheme;
            final isDark = cs.brightness == Brightness.dark;

            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: isDark ? 2 : 6,
                borderRadius: BorderRadius.circular(12),
                color: cs.surface,
                shadowColor: Colors.black.withValues(alpha: 0.15),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant, width: 0.8),
                  ),
                  constraints: BoxConstraints(
                    maxHeight: 200,
                    maxWidth: MediaQuery.of(context).size.width - 48,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return InkWell(
                          onTap: () => onSelected(option),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                if (option.icon != null) ...[
                                  Icon(option.icon, size: 18, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: Text(
                                    option.label,
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class DropdownItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  DropdownItem({
    required this.value,
    required this.label,
    this.icon,
  });
}
