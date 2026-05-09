import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// REUSABLE FORM FIELD WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class UsernameField extends StatelessWidget {
  final TextEditingController controller;

  const UsernameField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _FieldLabel(text: 'Username'),
        const SizedBox(height: 6),
        _CustomTextField(
          controller: controller,
          hint: 'e.g. alice',
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
      ],
    );
  }
}

class EmailField extends StatelessWidget {
  final TextEditingController controller;

  const EmailField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _FieldLabel(text: 'Email Address'),
        const SizedBox(height: 6),
        _CustomTextField(
          controller: controller,
          hint: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Email is required';
            if (!RegExp(r'^[\w\.\-]+@[\w\-]+\.\w{2,}$').hasMatch(v.trim())) {
              return 'Enter a valid email';
            }
            return null;
          },
        ),
      ],
    );
  }
}

class PhoneField extends StatelessWidget {
  final TextEditingController controller;

  const PhoneField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _FieldLabel(text: 'Phone Number'),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          cursorColor: kWhite,
          style: _inputTextStyle,
          decoration: _inputDecoration('+91 9876543210'),
          validator: (v) =>
              (v == null || v.trim().length < 6) ? 'Valid phone required' : null,
        ),
      ],
    );
  }
}

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;

  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.validator,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FieldLabel(text: widget.label),
        const SizedBox(height: 6),
        _CustomTextField(
          controller: widget.controller,
          hint: '••••••••',
          obscure: _obscure,
          suffixIcon: IconButton(
            icon: Icon(
              _obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: kLightGrey,
              size: 20,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
          validator: widget.validator ??
              (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
        ),
      ],
    );
  }
}

class ConfirmPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final TextEditingController passwordController;

  const ConfirmPasswordField({
    super.key,
    required this.controller,
    required this.passwordController,
  });

  @override
  State<ConfirmPasswordField> createState() => _ConfirmPasswordFieldState();
}

class _ConfirmPasswordFieldState extends State<ConfirmPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _FieldLabel(text: 'Confirm Password'),
        const SizedBox(height: 6),
        _CustomTextField(
          controller: widget.controller,
          hint: '••••••••',
          obscure: _obscure,
          suffixIcon: IconButton(
            icon: Icon(
              _obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: kLightGrey,
              size: 20,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Required';
            if (v != widget.passwordController.text) {
              return 'Passwords do not match';
            }
            return null;
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INTERNAL WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text.toUpperCase(),
        style: _labelTextStyle,
      ),
    );
  }
}

class _CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _CustomTextField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      cursorColor: kWhite,
      style: _inputTextStyle,
      validator: validator,
      decoration: _inputDecoration(hint, suffixIcon: suffixIcon),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CACHED STYLES
// ═══════════════════════════════════════════════════════════════════════════

final _labelTextStyle = GoogleFonts.inter(
  color: kLightGrey,
  fontSize: 9,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.8,
);

final _inputTextStyle = GoogleFonts.inter(
  color: kWhite,
  fontSize: 14,
);

final _hintTextStyle = GoogleFonts.inter(
  color: kLightGrey,
  fontSize: 14,
);

InputDecoration _inputDecoration(String hint, {Widget? suffixIcon}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: _hintTextStyle,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: kDarkGrey,
    border: _borderStyle,
    enabledBorder: _borderStyle,
    focusedBorder: _focusedBorderStyle,
    errorBorder: _errorBorderStyle,
    focusedErrorBorder: _focusedErrorBorderStyle,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
  );
}

final _borderStyle = OutlineInputBorder(
  borderRadius: BorderRadius.circular(25),
  borderSide: BorderSide.none,
);

final _focusedBorderStyle = OutlineInputBorder(
  borderRadius: BorderRadius.circular(25),
  borderSide: const BorderSide(color: kWhite, width: 1),
);

final _errorBorderStyle = OutlineInputBorder(
  borderRadius: BorderRadius.circular(25),
  borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.6)),
);

final _focusedErrorBorderStyle = OutlineInputBorder(
  borderRadius: BorderRadius.circular(25),
  borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.6), width: 2),
);
