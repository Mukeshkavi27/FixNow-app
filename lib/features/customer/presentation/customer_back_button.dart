import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CustomerBackButton extends StatelessWidget {
  const CustomerBackButton({this.fallbackLocation = '/customer', super.key});

  final String fallbackLocation;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(fallbackLocation);
        }
      },
    );
  }
}
