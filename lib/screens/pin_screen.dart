import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tempo/constants/app_constants.dart';
import 'package:tempo/services/password_service.dart';
import 'package:tempo/screens/active_limits_screen.dart';

class PinScreen {
  PinScreen._();

  static Future<bool> promptPin(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _PinVerifyScreen()),
    );
    return result ?? false;
  }

  static Future<bool> setupPin(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _PinSetupScreen()),
    );
    return result ?? false;
  }
}

class _PinDots extends StatelessWidget {
  final int filled;
  final VoidCallback? onTap;
  const _PinDots({required this.filled, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (i) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 12),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? Colors.black : Colors.transparent,
                border: Border.all(
                  color: Colors.black,
                  width: 2,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _PinVerifyScreen extends StatefulWidget {
  const _PinVerifyScreen();

  @override
  State<_PinVerifyScreen> createState() => _PinVerifyScreenState();
}

class _PinVerifyScreenState extends State<_PinVerifyScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _error;

  void _showKeyboard() {
    if (_focusNode.hasFocus) {
      SystemChannels.textInput.invokeMethod('TextInput.show');
    } else {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _controller.text;
    if (pin.length != 4) return;

    final correct = await PasswordService.verifyPin(pin);
    if (correct) {
      if (mounted) Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = Strings.pinWrongError;
        _controller.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: _showKeyboard,
          behavior: HitTestBehavior.opaque,
          child: Column(
            children: [
              const Spacer(flex: 2),

              Text(
                Strings.pinDialogTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 48),

              _PinDots(filled: _controller.text.length, onTap: _showKeyboard),

              SizedBox(
                width: 0,
                height: 0,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  enableSuggestions: false,
                  autocorrect: false,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                  ),
                  onChanged: (_) {
                    if (_error != null) _error = null;
                    setState(() {});
                  },
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 24),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
              ],

              const Spacer(flex: 3),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ActiveLimitsScreen(),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black.withValues(alpha: 0.6),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      Strings.viewActiveLimits,
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black,
                          side: const BorderSide(color: Colors.black),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          Strings.pinCancel,
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _controller.text.length == 4 ? _submit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.black.withValues(alpha: 0.15),
                          disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          Strings.pinValidateAction,
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinSetupScreen extends StatefulWidget {
  const _PinSetupScreen();

  @override
  State<_PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<_PinSetupScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _firstPin;
  String? _error;

  void _showKeyboard() {
    if (_focusNode.hasFocus) {
      SystemChannels.textInput.invokeMethod('TextInput.show');
    } else {
      _focusNode.requestFocus();
    }
  }

  bool get _isConfirmStep => _firstPin != null;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _controller.text;
    if (pin.length != 4) return;

    if (!_isConfirmStep) {
      setState(() {
        _firstPin = pin;
        _error = null;
        _controller.clear();
      });
    } else {
      if (pin == _firstPin) {
        await PasswordService.setPin(pin);
        if (mounted) Navigator.of(context).pop(true);
      } else {
        setState(() {
          _firstPin = null;
          _error = Strings.pinMismatchError;
          _controller.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: _showKeyboard,
          behavior: HitTestBehavior.opaque,
          child: Column(
            children: [
              const Spacer(flex: 2),

              Text(
                _isConfirmStep
                    ? Strings.pinConfirmDialogTitle
                    : Strings.pinSetupDialogTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 48),

              _PinDots(filled: _controller.text.length, onTap: _showKeyboard),

              SizedBox(
                width: 0,
                height: 0,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  enableSuggestions: false,
                  autocorrect: false,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                  ),
                  onChanged: (_) {
                    if (_error != null) _error = null;
                    setState(() {});
                  },
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 24),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
              ],

              const Spacer(flex: 3),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black,
                          side: const BorderSide(color: Colors.black),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          Strings.pinCancel,
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _controller.text.length == 4 ? _submit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.black.withValues(alpha: 0.15),
                          disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _isConfirmStep
                              ? Strings.pinValidateAction
                              : Strings.pinNextAction,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
