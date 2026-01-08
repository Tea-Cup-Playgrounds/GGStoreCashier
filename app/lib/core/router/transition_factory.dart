import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class TransitionFactory {
  TransitionFactory._();

  static CustomTransitionPage getSlideTTransition(
      {required BuildContext context,
      required GoRouterState state,
      required Widget child}) {
    return CustomTransitionPage(
        child: child,
        key: state.pageKey,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0);
          const end = Offset.zero;
          final tween = Tween<Offset>(begin: begin, end: end)
              .chain(CurveTween(curve: Curves.fastOutSlowIn));
          return SlideTransition(
              position: animation.drive(tween), child: child);
        });
  }

  static Page<dynamic> getSlideBuilder(
      {required BuildContext context,
      required GoRouterState state,
      required Widget child}) {
    return getSlideTTransition(context: context, state: state, child: child);
  }
}
