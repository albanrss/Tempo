import 'package:flutter/material.dart';

import 'package:tempo/screens/app_lister_screen.dart';
import 'package:tempo/services/app_cache.dart';
import 'package:tempo/services/password_service.dart';
import 'package:tempo/screens/pin_screen.dart';

class SpinningLogoScreen extends StatefulWidget {
  const SpinningLogoScreen({super.key});

  @override
  State<SpinningLogoScreen> createState() => _SpinningLogoScreenState();
}

class _SpinningLogoScreenState extends State<SpinningLogoScreen> with TickerProviderStateMixin{
  late final AnimationController _controller = AnimationController(
    duration: const Duration(seconds: 5),
    vsync: this,
  )..repeat();

  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.slowMiddle,
  );

  @override
  void initState() {
    super.initState();
    AppCache.loadAppsInBackground();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToAppLister() async {
    final hasPin = await PasswordService.hasPin();
    if (hasPin) {
      if (!mounted) return;
      final ok = await PinScreen.promptPin(context);
      if (!ok) return;
    }
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => AppListerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: .center,
        children: [
          Row(
            mainAxisAlignment: .center,
            children: [
              IconButton(
                onPressed: _goToAppLister,
                icon: RotationTransition(
                  turns: _animation,
                  child: Image.asset("assets/flower.png", width: 150),
                  )
                ),
            ],
          )
        ],
      )
    );
  }
}
