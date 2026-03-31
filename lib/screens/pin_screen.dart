import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tempo/constants/app_constants.dart';
import 'package:tempo/services/password_service.dart';

class PinScreen {
  PinScreen._();

  static Future<bool> promptPin(BuildContext context) async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const _PinVerifyScreen()));
    return result ?? false;
  }

  static Future<bool> setupPin(BuildContext context) async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const _PinSetupScreen()));
    return result ?? false;
  }

  static Future<bool> changePin(BuildContext context) async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const _PinChangeScreen()));
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
                border: Border.all(color: Colors.black, width: 2),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _SharedPinLayout extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? error;
  final VoidCallback onShowKeyboard;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmit;
  final VoidCallback onCancel;
  final String actionText;
  final Widget? extraAction;

  const _SharedPinLayout({
    required this.title,
    required this.controller,
    required this.focusNode,
    required this.error,
    required this.onShowKeyboard,
    required this.onChanged,
    required this.onSubmit,
    required this.onCancel,
    required this.actionText,
    this.extraAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(flex: 2),

        Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),

        const SizedBox(height: 48),

        _PinDots(filled: controller.text.length, onTap: onShowKeyboard),

        SizedBox(
          width: 0,
          height: 0,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            enableSuggestions: false,
            autocorrect: false,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(counterText: '', border: InputBorder.none),
            onChanged: onChanged,
          ),
        ),

        SizedBox(
          height: 44,
          child: Center(
            child: AnimatedOpacity(
              opacity: error != null ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                error ?? '',
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
            ),
          ),
        ),

        const Spacer(flex: 3),

        if (extraAction != null) ...[
          Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 0), child: extraAction!),
        ],

        Padding(
          padding: EdgeInsets.fromLTRB(24, extraAction != null ? 8 : 0, 24, 48),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Colors.black),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(Strings.pinCancel, style: TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: onSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.black.withValues(alpha: 0.15),
                    disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(actionText, style: const TextStyle(fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ],
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
          child: _SharedPinLayout(
            title: Strings.pinDialogTitle,
            controller: _controller,
            focusNode: _focusNode,
            error: _error,
            onShowKeyboard: _showKeyboard,
            onChanged: (_) {
              if (_error != null) {
                setState(() => _error = null);
              } else {
                setState(() {});
              }
            },
            onSubmit: _controller.text.length == 4 ? _submit : null,
            onCancel: () => Navigator.of(context).pop(false),
            actionText: Strings.pinValidateAction,
            extraAction: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      await PinScreen.changePin(context);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black.withValues(alpha: 0.6),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      Strings.pinChangeAction,
                      style: TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
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
          child: _SharedPinLayout(
            title: _isConfirmStep
                ? Strings.pinConfirmDialogTitle
                : Strings.pinSetupDialogTitle,
            controller: _controller,
            focusNode: _focusNode,
            error: _error,
            onShowKeyboard: _showKeyboard,
            onChanged: (_) {
              if (_error != null) {
                setState(() => _error = null);
              } else {
                setState(() {});
              }
            },
            onSubmit: _controller.text.length == 4 ? _submit : null,
            onCancel: () => Navigator.of(context).pop(false),
            actionText: _isConfirmStep ? Strings.pinValidateAction : Strings.pinNextAction,
          ),
        ),
      ),
    );
  }
}

class _PinChangeScreen extends StatefulWidget {
  const _PinChangeScreen();

  @override
  State<_PinChangeScreen> createState() => _PinChangeScreenState();
}

class _PinChangeScreenState extends State<_PinChangeScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _oldPinValidated = false;
  String? _firstPin;
  String? _error;
  bool _success = false;

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

    if (!_oldPinValidated) {
      final correct = await PasswordService.verifyPin(pin);
      if (correct) {
        setState(() {
          _oldPinValidated = true;
          _error = null;
          _controller.clear();
        });
      } else {
        setState(() {
          _error = Strings.pinWrongError;
          _controller.clear();
        });
      }
    } else if (!_isConfirmStep) {
      setState(() {
        _firstPin = pin;
        _error = null;
        _controller.clear();
      });
    } else {
      if (pin == _firstPin) {
        await PasswordService.setPin(pin);
        if (mounted) {
          setState(() {
            _success = true;
          });
          await Future.delayed(const Duration(milliseconds: 1500));
          if (mounted) Navigator.of(context).pop(true);
        }
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
    String title = Strings.pinChangeOldTitle;
    if (_oldPinValidated) {
      title = _isConfirmStep ? Strings.pinConfirmDialogTitle : Strings.pinSetupDialogTitle;
    }

    String actionText = Strings.pinValidateAction;
    if (_oldPinValidated && !_isConfirmStep) {
      actionText = Strings.pinNextAction;
    }

    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            );
          },
          child: _success ? _buildSuccess() : _buildForm(context, title, actionText),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Center(
      key: const ValueKey('success'),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 72),
      ),
    );
  }

  Widget _buildForm(BuildContext context, String title, String actionText) {
    return GestureDetector(
      key: const ValueKey('form'),
      onTap: _showKeyboard,
      behavior: HitTestBehavior.opaque,
      child: _SharedPinLayout(
        title: title,
        controller: _controller,
        focusNode: _focusNode,
        error: _error,
        onShowKeyboard: _showKeyboard,
        onChanged: (_) {
          if (_error != null) {
            setState(() => _error = null);
          } else {
            setState(() {});
          }
        },
        onSubmit: _controller.text.length == 4 ? _submit : null,
        onCancel: () => Navigator.of(context).pop(false),
        actionText: actionText,
      ),
    );
  }
}
