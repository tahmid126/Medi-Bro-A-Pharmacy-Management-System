import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class SearchableDropdownField<T> extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final String? hint;
  final bool isSelected;
  final bool isSearching;
  final List<T> items;
  final String Function(T) itemLabel;
  final Function(String) onChanged;
  final Function(T) onSelect;
  final Function(String)? onSelectCustom;
  final VoidCallback onClear;
  final String newItemLabel;
  final VoidCallback? onTap;

  const SearchableDropdownField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.icon,
    this.hint,
    required this.isSelected,
    required this.isSearching,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    required this.onSelect,
    this.onSelectCustom,
    required this.onClear,
    required this.newItemLabel,
    this.onTap,
  });

  @override
  State<SearchableDropdownField<T>> createState() => _SearchableDropdownFieldState<T>();
}

class _SearchableDropdownFieldState<T> extends State<SearchableDropdownField<T>> {
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _portalController = OverlayPortalController();
  final GlobalKey _targetKey = GlobalKey();

  void _showDropdown() {
    if (!_portalController.isShowing) {
      _portalController.show();
    }
  }

  void _hideDropdown() {
    if (_portalController.isShowing) {
      _portalController.hide();
    }
  }

  @override
  void didUpdateWidget(SearchableDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Never call _hideDropdown() directly in persistentCallbacks!
    // Safely schedule after the frame if needed
    if (widget.items.isEmpty && widget.controller.text.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _hideDropdown();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textVal = widget.controller.text.trim();
    final hasText = textVal.isNotEmpty;
    final bool hasExactMatch = widget.items.any((item) =>
        widget.itemLabel(item).toLowerCase().trim() == textVal.toLowerCase());

    return TapRegion(
      groupId: this,
      onTapOutside: (_) => _hideDropdown(),
      child: CompositedTransformTarget(
        link: _layerLink,
        child: OverlayPortal(
          controller: _portalController,
          overlayChildBuilder: (BuildContext overlayContext) {
            // Safety guard: if empty, show nothing
            if (widget.items.isEmpty && !hasText) {
              return const SizedBox.shrink();
            }

            final renderBox = _targetKey.currentContext?.findRenderObject() as RenderBox?;
            final width = renderBox?.size.width ?? 200.0;

            return CompositedTransformFollower(
              link: _layerLink,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              showWhenUnlinked: false,
              child: Align(
                alignment: Alignment.topLeft,
                child: TapRegion(
                  groupId: this,
                  child: SizedBox(
                    width: width,
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Material(
                        color: Colors.white,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ...widget.items.map((item) {
                                  final label = widget.itemLabel(item);
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      widget.onSelect(item);
                                      _hideDropdown();
                                      widget.focusNode.unfocus();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              color: AppColors.primary.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Icon(widget.icon, size: 14, color: AppColors.primary),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              label,
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                          Icon(Icons.north_west_rounded, size: 13, color: Colors.grey.shade400),
                                        ],
                                      ),
                                    ),
                                  );
                                }),

                                // Option to add new if user typed something not matching exactly
                                if (hasText && !hasExactMatch)
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      if (widget.onSelectCustom != null) {
                                        widget.onSelectCustom!(textVal);
                                      }
                                      _hideDropdown();
                                      widget.focusNode.unfocus();
                                    },
                                    child: Container(
                                      color: Colors.orange.shade50.withValues(alpha: 0.8),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Icon(Icons.add_rounded, size: 15, color: Colors.deepOrange),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: RichText(
                                              text: TextSpan(
                                                style: const TextStyle(fontSize: 12, color: Colors.black87),
                                                children: [
                                                  const TextSpan(text: "Use \""),
                                                  TextSpan(
                                                    text: textVal,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
                                                  ),
                                                  TextSpan(
                                                    text: " (${widget.newItemLabel})",
                                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const Icon(Icons.check_rounded, size: 14, color: Colors.deepOrange),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          child: Container(
            key: _targetKey,
            margin: const EdgeInsets.only(bottom: 15),
            child: TextFormField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              onChanged: (val) {
                widget.onChanged(val);
                if (val.trim().isEmpty && widget.items.isEmpty) {
                  _hideDropdown();
                } else {
                  _showDropdown();
                }
              },
              onTap: () {
                widget.onTap?.call();
                if (widget.items.isNotEmpty || widget.controller.text.trim().isNotEmpty) {
                  _showDropdown();
                }
              },
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint ?? "Type to search or add new...",
                prefixIcon: Icon(widget.icon, color: AppColors.primary),
                suffixIcon: widget.isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : widget.isSelected
                        ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                        : (hasText
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
                                onPressed: () {
                                  widget.onClear();
                                  _hideDropdown();
                                },
                              )
                            : null),
                filled: true,
                fillColor: widget.isSelected
                    ? Colors.green.shade50
                    : (hasText ? Colors.orange.shade50 : Colors.grey.shade100),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: widget.isSelected
                      ? BorderSide(color: Colors.green.shade300, width: 1.5)
                      : (hasText
                          ? BorderSide(color: Colors.orange.shade300, width: 1.5)
                          : BorderSide.none),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(
                    color: widget.isSelected
                        ? Colors.green.shade400
                        : (hasText ? Colors.orange.shade400 : AppColors.primary),
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
