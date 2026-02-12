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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty) ...[
          Text(
            widget.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Autocomplete<DropdownItem<T>>(
          initialValue: widget.value != null
              ? TextEditingValue(
                  text: widget.items
                      .firstWhere(
                        (item) => item.value == widget.value,
                        orElse: () => DropdownItem(value: widget.value as T, label: ''),
                      )
                      .label,
                )
              : null,
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return widget.items;
            }
            return widget.items.where((item) {
              return item.label
                  .toLowerCase()
                  .contains(textEditingValue.text.toLowerCase());
            });
          },
          displayStringForOption: (DropdownItem<T> option) => option.label,
          onSelected: (DropdownItem<T> selection) {
            widget.onChanged(selection.value);
          },
          fieldViewBuilder: (
            BuildContext context,
            TextEditingController textEditingController,
            FocusNode focusNode,
            VoidCallback onFieldSubmitted,
          ) {
            return TextFormField(
              controller: textEditingController,
              focusNode: focusNode,
              enabled: widget.enabled,
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(color: AppTheme.mutedForeground.withOpacity(0.6)),
                filled: true,
                fillColor: widget.enabled ? AppTheme.surface : AppTheme.muted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                prefixIcon: widget.prefixIcon != null
                    ? Icon(widget.prefixIcon, color: AppTheme.mutedForeground)
                    : null,
                suffixIcon: textEditingController.text.isNotEmpty && widget.enabled
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppTheme.mutedForeground),
                        onPressed: () {
                          textEditingController.clear();
                          widget.onChanged(null);
                        },
                      )
                    : null,
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.foreground,
              ),
              validator: widget.validator != null
                  ? (String? value) {
                      // Find the matching item by label
                      final matchingItem = widget.items.firstWhere(
                        (item) => item.label == value,
                        orElse: () => DropdownItem(value: widget.value as T, label: ''),
                      );
                      return widget.validator!(matchingItem.value);
                    }
                  : null,
            );
          },
          optionsViewBuilder: (
            BuildContext context,
            AutocompleteOnSelected<DropdownItem<T>> onSelected,
            Iterable<DropdownItem<T>> options,
          ) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: AppTheme.surface,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 200,
                    maxWidth: MediaQuery.of(context).size.width - 48,
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (BuildContext context, int index) {
                      final option = options.elementAt(index);
                      return InkWell(
                        onTap: () => onSelected(option),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              if (option.icon != null) ...[
                                Icon(option.icon, size: 20, color: AppTheme.mutedForeground),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Text(
                                  option.label,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.foreground,
                                  ),
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
