import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/matrix_provider.dart';
import '../../widgets/common/error_display.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LOGIN ERROR DISPLAY WRAPPER
// ═══════════════════════════════════════════════════════════════════════════

class LoginErrorDisplay extends StatelessWidget {
  final bool isRegisterMode;

  const LoginErrorDisplay({super.key, required this.isRegisterMode});

  @override
  Widget build(BuildContext context) {
    return Selector<MatrixProvider, String?>(
      selector: (_, provider) => provider.error,
      builder: (context, error, _) {
        final isLoading = context.select<MatrixProvider, bool>(
          (p) => p.state == MatrixAuthState.loggingIn,
        );

        if (error != null && !isLoading && !isRegisterMode) {
          return ErrorDisplay(error: error);
        }
        return const SizedBox.shrink();
      },
    );
  }
}
