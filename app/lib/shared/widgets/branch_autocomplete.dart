import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../core/config/api_config.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';

class BranchAutocomplete extends StatefulWidget {
  final String? initialValue;
  final String? initialBranchName;
  final Function(int? branchId, String branchName) onChanged;
  final bool enabled;
  final String? Function(String?)? validator;

  const BranchAutocomplete({
    super.key,
    this.initialValue,
    this.initialBranchName,
    required this.onChanged,
    this.enabled = true,
    this.validator,
  });

  @override
  State<BranchAutocomplete> createState() => _BranchAutocompleteState();
}

class _BranchAutocompleteState extends State<BranchAutocomplete> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _branches = [];
  bool _isLoading = true;
  int? _selectedBranchId;

  @override
  void initState() {
    super.initState();
    _loadBranches();
    
    // Set initial value
    if (widget.initialBranchName != null) {
      _controller.text = widget.initialBranchName!;
    }
    if (widget.initialValue != null) {
      _selectedBranchId = int.tryParse(widget.initialValue!);
    }
  }

  Future<void> _loadBranches() async {
    setState(() => _isLoading = true);
    
    try {
      final token = await AuthService.getToken();
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token'},
      ));

      final response = await dio.get('/api/branches');
      
      setState(() {
        _branches = List<Map<String, dynamic>>.from(
          response.data['branches'].map((b) => {
            'id': b['id'],
            'name': b['name'],
          })
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Failed to load branches: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Branch',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppTheme.foreground,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Autocomplete<Map<String, dynamic>>(
          initialValue: widget.initialBranchName != null 
              ? TextEditingValue(text: widget.initialBranchName!)
              : null,
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return _branches;
            }
            return _branches.where((branch) {
              return branch['name']
                  .toString()
                  .toLowerCase()
                  .contains(textEditingValue.text.toLowerCase());
            });
          },
          displayStringForOption: (Map<String, dynamic> option) => option['name'],
          onSelected: (Map<String, dynamic> selection) {
            _selectedBranchId = selection['id'];
            _controller.text = selection['name'];
            widget.onChanged(selection['id'], selection['name']);
          },
          fieldViewBuilder: (
            BuildContext context,
            TextEditingController textEditingController,
            FocusNode focusNode,
            VoidCallback onFieldSubmitted,
          ) {
            // Sync with our controller
            if (_controller.text.isNotEmpty && textEditingController.text.isEmpty) {
              textEditingController.text = _controller.text;
            }

            return TextFormField(
              controller: textEditingController,
              focusNode: focusNode,
              enabled: widget.enabled,
              decoration: InputDecoration(
                hintText: 'Type to search or add new branch',
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
                prefixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.gold,
                          ),
                        ),
                      )
                    : const Icon(Icons.store, color: AppTheme.mutedForeground),
                suffixIcon: textEditingController.text.isNotEmpty && widget.enabled
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppTheme.mutedForeground),
                        onPressed: () {
                          textEditingController.clear();
                          _controller.clear();
                          _selectedBranchId = null;
                          widget.onChanged(null, '');
                        },
                      )
                    : null,
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.foreground,
              ),
              validator: widget.validator,
              onChanged: (value) {
                _controller.text = value;
                // Check if it matches an existing branch
                final matchingBranch = _branches.firstWhere(
                  (b) => b['name'].toString().toLowerCase() == value.toLowerCase(),
                  orElse: () => {},
                );
                
                if (matchingBranch.isNotEmpty) {
                  _selectedBranchId = matchingBranch['id'];
                  widget.onChanged(matchingBranch['id'], matchingBranch['name']);
                } else {
                  // New branch name
                  _selectedBranchId = null;
                  widget.onChanged(null, value);
                }
              },
            );
          },
          optionsViewBuilder: (
            BuildContext context,
            AutocompleteOnSelected<Map<String, dynamic>> onSelected,
            Iterable<Map<String, dynamic>> options,
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
                    maxWidth: MediaQuery.of(context).size.width - 48, // Constrain width
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
                              const Icon(Icons.store, size: 20, color: AppTheme.mutedForeground),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  option['name'],
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.foreground,
                                  ),
                                ),
                              ),
                              if (option['id'] == 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.gold.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Global',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.gold,
                                      fontWeight: FontWeight.bold,
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
        if (_controller.text.isNotEmpty && _selectedBranchId == null && widget.enabled)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: AppTheme.gold),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'New branch "${_controller.text}" will be created',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.gold,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
