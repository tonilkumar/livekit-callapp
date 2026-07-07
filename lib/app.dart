import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/call/domain/entities/connection_params.dart';
import 'features/call/presentation/pages/call_page.dart';
import 'features/call/presentation/pages/join_page.dart';

class VideoCallApp extends StatelessWidget {
  const VideoCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Call',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      initialRoute: JoinPage.route,
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case JoinPage.route:
        return MaterialPageRoute(
          builder: (_) => const JoinPage(),
          settings: settings,
        );
      case CallPage.route:
        final params = settings.arguments;
        if (params is! ConnectionParams) {
          // Deep link or bad arguments — fall back to the join screen.
          return MaterialPageRoute(
            builder: (_) => const JoinPage(),
            settings: settings,
          );
        }
        return MaterialPageRoute(
          builder: (_) => CallPage(params: params),
          settings: settings,
        );
    }
    return null;
  }
}
