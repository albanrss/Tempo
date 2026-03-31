import 'package:flutter/material.dart';

import 'package:tempo/screens/active_limits_screen.dart';
import 'package:tempo/services/app_cache.dart';

class SpinningLogoScreen extends StatefulWidget {
  const SpinningLogoScreen({super.key});

  @override
  State<SpinningLogoScreen> createState() => _SpinningLogoScreenState();
}

class _SpinningLogoScreenState extends State<SpinningLogoScreen>
    with TickerProviderStateMixin {
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

  void _goToLimits() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (context) => const ActiveLimitsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _goToLimits,
                icon: RotationTransition(
                  turns: _animation,
                  child: Image.asset("assets/flower.png", width: 150),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
