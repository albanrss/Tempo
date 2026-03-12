import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:tempo/services/time_limit_manager.dart';
import 'package:tempo/constants/app_constants.dart';

class AppLimitScreen extends StatefulWidget {
  final AppInfo app;

  const AppLimitScreen({super.key, required this.app});

  @override
  State<AppLimitScreen> createState() => _AppLimitScreenState();
}

class _AppLimitScreenState extends State<AppLimitScreen> {
  static const int _maxMinutes = 60;
  late final FixedExtentScrollController _scrollController;
  int _selectedMinutes = 15;

  @override
  void initState() {
    super.initState();
    _scrollController = FixedExtentScrollController(
      initialItem: _kLoopCenter + _selectedMinutes,
    );
    _loadCurrentLimit();
  }

  static const int _kLoopCenter = 10000 * (_maxMinutes + 1);

  Future<void> _loadCurrentLimit() async {
    final limit = await TimeLimitManager.getTimeLimit(widget.app.packageName);
    if (limit != null && mounted) {
      setState(() {
        _selectedMinutes = limit.clamp(0, _maxMinutes);
      });
      _scrollController.jumpToItem(_kLoopCenter + _selectedMinutes);
    }
  }

  Future<void> _setLimit() async {
    final navigator = Navigator.of(context);

    await TimeLimitManager.setTimeLimit(
      widget.app.packageName,
      _selectedMinutes,
    );

    if (mounted) navigator.pop();
  }

  Future<void> _removeLimit() async {
    final navigator = Navigator.of(context);

    await TimeLimitManager.removeTimeLimit(widget.app.packageName);

    if (mounted) navigator.pop();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Strings.setLimitTitle(widget.app.name)),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SizedBox(
                height: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 56,
                      margin: const EdgeInsets.symmetric(horizontal: 64),
                      decoration: BoxDecoration(
                        border: Border.symmetric(
                          horizontal: BorderSide(
                            color: Colors.black.withValues(alpha: 0.15),
                          ),
                        ),
                      ),
                    ),

                    ListWheelScrollView.useDelegate(
                      controller: _scrollController,
                      itemExtent: 56,
                      perspective: 0.003,
                      diameterRatio: 1.6,
                      physics: const FixedExtentScrollPhysics(),
                      onSelectedItemChanged: (index) {
                        setState(() {
                          _selectedMinutes = index % (_maxMinutes + 1);
                        });
                      },
                      childDelegate: ListWheelChildBuilderDelegate(
                        builder: (context, index) {
                          final minute = index % (_maxMinutes + 1);
                          final isSelected = minute == _selectedMinutes;
                          return Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 150),
                              style: TextStyle(
                                fontSize: isSelected ? 40 : 24,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w300,
                                color: isSelected
                                    ? Colors.black
                                    : Colors.black.withValues(alpha: 0.30),
                              ),
                              child: isSelected
                                ? Text('$minute min')
                                : Text('$minute'),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Text(
              Strings.limitDescription,
              style: TextStyle(
                fontSize: 13,
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _removeLimit,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.black),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      Strings.removeLimitAction,
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                Expanded(
                  child: ElevatedButton(
                    onPressed: _setLimit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      Strings.setLimitAction,
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
