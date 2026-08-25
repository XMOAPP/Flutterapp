import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../security/password_policy.dart';
import '../../theme.dart';
import '../../utils/xmo_username.dart';

// ═══════════════════════════════════════════════════════════════════════════
// REUSABLE FORM FIELD WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class UsernameField extends StatelessWidget {
  final TextEditingController controller;
  final String? externalError;
  final VoidCallback? onChanged;

  const UsernameField({
    super.key,
    required this.controller,
    this.externalError,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _FieldLabel(text: 'Username'),
        const SizedBox(height: 6),
        _CustomTextField(
          controller: controller,
          hint: 'e.g. alice',
          collapseErrorText: externalError != null,
          autocorrect: false,
          textCapitalization: TextCapitalization.none,
          inputFormatters: xmoUsernameInputFormatters(),
          onChanged: (_) => onChanged?.call(),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            if (!isValidXmoUsername(v.trim())) {
              return 'Use lowercase letters and numbers only';
            }
            return externalError == null ? null : ' ';
          },
        ),
        if (externalError != null) ...[
          const SizedBox(height: 7),
          _InlineFieldError(text: externalError!),
        ],
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

class PhoneField extends StatefulWidget {
  final TextEditingController controller;

  const PhoneField({super.key, required this.controller});

  @override
  State<PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<PhoneField> {
  final _localCtrl = TextEditingController();
  _PhoneCountry _country = _phoneCountries.firstWhere((c) => c.isoCode == 'IN');

  @override
  void initState() {
    super.initState();
    _hydrateFromParent();
    _localCtrl.addListener(_syncParentController);
  }

  @override
  void dispose() {
    _localCtrl.removeListener(_syncParentController);
    _localCtrl.dispose();
    super.dispose();
  }

  void _hydrateFromParent() {
    final value = widget.controller.text.trim();
    if (value.isEmpty) return;
    final matched =
        _phoneCountries
            .where((country) => value.startsWith(country.dialCode))
            .toList()
          ..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
    if (matched.isEmpty) return;
    _country = matched.first;
    _localCtrl.text = value.substring(_country.dialCode.length);
  }

  void _syncParentController() {
    widget.controller.text = '${_country.dialCode}${_localCtrl.text.trim()}';
  }

  Future<void> _pickCountry() async {
    final selected = await showModalBottomSheet<_PhoneCountry>(
      context: context,
      backgroundColor: kDarkerGrey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: ListView.builder(
              itemCount: _phoneCountries.length,
              itemBuilder: (context, index) {
                final country = _phoneCountries[index];
                final selected = country.isoCode == _country.isoCode;
                return ListTile(
                  dense: true,
                  title: Text(
                    country.name,
                    style: GoogleFonts.inter(
                      color: kWhite,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  trailing: Text(
                    country.dialCode,
                    style: GoogleFonts.inter(
                      color: selected ? kLimeGreen : kLightGrey,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, country),
                );
              },
            ),
          ),
        );
      },
    );
    if (selected == null || selected == _country) return;
    setState(() {
      _country = selected;
      if (_localCtrl.text.length > _country.maxLength) {
        _localCtrl.text = _localCtrl.text.substring(0, _country.maxLength);
        _localCtrl.selection = TextSelection.collapsed(
          offset: _localCtrl.text.length,
        );
      }
    });
    _syncParentController();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _FieldLabel(text: 'Phone Number'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _localCtrl,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_country.maxLength),
          ],
          cursorColor: kWhite,
          style: _inputTextStyle,
          decoration: _inputDecoration(
            '9876543210',
            prefixIcon: _CountryCodePrefix(
              country: _country,
              onTap: _pickCountry,
            ),
          ),
          validator: (v) {
            final digits = v?.trim() ?? '';
            if (digits.length < _country.minLength ||
                digits.length > _country.maxLength) {
              if (_country.minLength == _country.maxLength) {
                return 'Enter ${_country.maxLength} digits for ${_country.name}';
              }
              return 'Enter ${_country.minLength}-${_country.maxLength} digits';
            }
            return null;
          },
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
          validator:
              widget.validator ??
              (v) => PasswordPolicy.validationError(v ?? ''),
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
    return Center(child: Text(text.toUpperCase(), style: _labelTextStyle));
  }
}

class _CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final ValueChanged<String>? onChanged;
  final bool collapseErrorText;
  final String? Function(String?)? validator;

  const _CustomTextField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.suffixIcon,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.sentences,
    this.autocorrect = true,
    this.onChanged,
    this.collapseErrorText = false,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      autocorrect: autocorrect,
      cursorColor: kWhite,
      style: _inputTextStyle,
      onChanged: onChanged,
      validator: validator,
      decoration: _inputDecoration(
        hint,
        suffixIcon: suffixIcon,
        collapseErrorText: collapseErrorText,
      ),
    );
  }
}

class _InlineFieldError extends StatelessWidget {
  final String text;

  const _InlineFieldError({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.info_outline, color: _fieldErrorColor, size: 13),
        const SizedBox(width: 5),
        Text(
          text,
          style: GoogleFonts.inter(
            color: _fieldErrorColor,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CountryCodePrefix extends StatelessWidget {
  final _PhoneCountry country;
  final VoidCallback onTap;

  const _CountryCodePrefix({required this.country, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${country.isoCode} ${country.dialCode}',
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, color: kLightGrey, size: 18),
            const SizedBox(width: 6),
            Container(
              width: 1,
              height: 22,
              color: kLightGrey.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneCountry {
  final String isoCode;
  final String name;
  final String dialCode;
  final int minLength;
  final int maxLength;

  const _PhoneCountry(
    this.isoCode,
    this.name,
    this.dialCode,
    this.minLength,
    this.maxLength,
  );
}

const List<_PhoneCountry> _phoneCountries = [
  _PhoneCountry('IN', 'India', '+91', 10, 10),
  _PhoneCountry('US', 'United States', '+1', 10, 10),
  _PhoneCountry('CA', 'Canada', '+1', 10, 10),
  _PhoneCountry('GB', 'United Kingdom', '+44', 10, 10),
  _PhoneCountry('AE', 'United Arab Emirates', '+971', 9, 9),
  _PhoneCountry('SA', 'Saudi Arabia', '+966', 9, 9),
  _PhoneCountry('QA', 'Qatar', '+974', 8, 8),
  _PhoneCountry('KW', 'Kuwait', '+965', 8, 8),
  _PhoneCountry('OM', 'Oman', '+968', 8, 8),
  _PhoneCountry('BH', 'Bahrain', '+973', 8, 8),
  _PhoneCountry('SG', 'Singapore', '+65', 8, 8),
  _PhoneCountry('MY', 'Malaysia', '+60', 9, 10),
  _PhoneCountry('LK', 'Sri Lanka', '+94', 9, 9),
  _PhoneCountry('PK', 'Pakistan', '+92', 10, 10),
  _PhoneCountry('BD', 'Bangladesh', '+880', 10, 10),
  _PhoneCountry('NP', 'Nepal', '+977', 10, 10),
  _PhoneCountry('AF', 'Afghanistan', '+93', 9, 9),
  _PhoneCountry('AL', 'Albania', '+355', 8, 9),
  _PhoneCountry('DZ', 'Algeria', '+213', 9, 9),
  _PhoneCountry('AD', 'Andorra', '+376', 6, 6),
  _PhoneCountry('AO', 'Angola', '+244', 9, 9),
  _PhoneCountry('AR', 'Argentina', '+54', 10, 10),
  _PhoneCountry('AM', 'Armenia', '+374', 8, 8),
  _PhoneCountry('AU', 'Australia', '+61', 9, 9),
  _PhoneCountry('AT', 'Austria', '+43', 10, 13),
  _PhoneCountry('AZ', 'Azerbaijan', '+994', 9, 9),
  _PhoneCountry('BS', 'Bahamas', '+1', 10, 10),
  _PhoneCountry('BY', 'Belarus', '+375', 9, 9),
  _PhoneCountry('BE', 'Belgium', '+32', 8, 9),
  _PhoneCountry('BZ', 'Belize', '+501', 7, 7),
  _PhoneCountry('BJ', 'Benin', '+229', 8, 8),
  _PhoneCountry('BT', 'Bhutan', '+975', 8, 8),
  _PhoneCountry('BO', 'Bolivia', '+591', 8, 8),
  _PhoneCountry('BA', 'Bosnia and Herzegovina', '+387', 8, 8),
  _PhoneCountry('BW', 'Botswana', '+267', 7, 8),
  _PhoneCountry('BR', 'Brazil', '+55', 10, 11),
  _PhoneCountry('BN', 'Brunei', '+673', 7, 7),
  _PhoneCountry('BG', 'Bulgaria', '+359', 8, 9),
  _PhoneCountry('BF', 'Burkina Faso', '+226', 8, 8),
  _PhoneCountry('BI', 'Burundi', '+257', 8, 8),
  _PhoneCountry('KH', 'Cambodia', '+855', 8, 9),
  _PhoneCountry('CM', 'Cameroon', '+237', 9, 9),
  _PhoneCountry('CL', 'Chile', '+56', 9, 9),
  _PhoneCountry('CN', 'China', '+86', 11, 11),
  _PhoneCountry('CO', 'Colombia', '+57', 10, 10),
  _PhoneCountry('CR', 'Costa Rica', '+506', 8, 8),
  _PhoneCountry('HR', 'Croatia', '+385', 8, 9),
  _PhoneCountry('CU', 'Cuba', '+53', 8, 8),
  _PhoneCountry('CY', 'Cyprus', '+357', 8, 8),
  _PhoneCountry('CZ', 'Czechia', '+420', 9, 9),
  _PhoneCountry('DK', 'Denmark', '+45', 8, 8),
  _PhoneCountry('DO', 'Dominican Republic', '+1', 10, 10),
  _PhoneCountry('EC', 'Ecuador', '+593', 9, 9),
  _PhoneCountry('EG', 'Egypt', '+20', 10, 10),
  _PhoneCountry('EE', 'Estonia', '+372', 7, 8),
  _PhoneCountry('ET', 'Ethiopia', '+251', 9, 9),
  _PhoneCountry('FI', 'Finland', '+358', 9, 12),
  _PhoneCountry('FR', 'France', '+33', 9, 9),
  _PhoneCountry('GE', 'Georgia', '+995', 9, 9),
  _PhoneCountry('DE', 'Germany', '+49', 10, 11),
  _PhoneCountry('GH', 'Ghana', '+233', 9, 9),
  _PhoneCountry('GR', 'Greece', '+30', 10, 10),
  _PhoneCountry('GT', 'Guatemala', '+502', 8, 8),
  _PhoneCountry('HK', 'Hong Kong', '+852', 8, 8),
  _PhoneCountry('HU', 'Hungary', '+36', 9, 9),
  _PhoneCountry('IS', 'Iceland', '+354', 7, 7),
  _PhoneCountry('ID', 'Indonesia', '+62', 9, 12),
  _PhoneCountry('IR', 'Iran', '+98', 10, 10),
  _PhoneCountry('IQ', 'Iraq', '+964', 10, 10),
  _PhoneCountry('IE', 'Ireland', '+353', 9, 9),
  _PhoneCountry('IL', 'Israel', '+972', 9, 9),
  _PhoneCountry('IT', 'Italy', '+39', 9, 10),
  _PhoneCountry('JM', 'Jamaica', '+1', 10, 10),
  _PhoneCountry('JP', 'Japan', '+81', 10, 10),
  _PhoneCountry('JO', 'Jordan', '+962', 9, 9),
  _PhoneCountry('KZ', 'Kazakhstan', '+7', 10, 10),
  _PhoneCountry('KE', 'Kenya', '+254', 9, 9),
  _PhoneCountry('KR', 'South Korea', '+82', 9, 10),
  _PhoneCountry('LA', 'Laos', '+856', 8, 10),
  _PhoneCountry('LV', 'Latvia', '+371', 8, 8),
  _PhoneCountry('LB', 'Lebanon', '+961', 7, 8),
  _PhoneCountry('LT', 'Lithuania', '+370', 8, 8),
  _PhoneCountry('LU', 'Luxembourg', '+352', 6, 9),
  _PhoneCountry('MO', 'Macao', '+853', 8, 8),
  _PhoneCountry('MG', 'Madagascar', '+261', 9, 9),
  _PhoneCountry('MW', 'Malawi', '+265', 9, 9),
  _PhoneCountry('MV', 'Maldives', '+960', 7, 7),
  _PhoneCountry('ML', 'Mali', '+223', 8, 8),
  _PhoneCountry('MT', 'Malta', '+356', 8, 8),
  _PhoneCountry('MX', 'Mexico', '+52', 10, 10),
  _PhoneCountry('MD', 'Moldova', '+373', 8, 8),
  _PhoneCountry('MC', 'Monaco', '+377', 8, 9),
  _PhoneCountry('MN', 'Mongolia', '+976', 8, 8),
  _PhoneCountry('ME', 'Montenegro', '+382', 8, 8),
  _PhoneCountry('MA', 'Morocco', '+212', 9, 9),
  _PhoneCountry('MZ', 'Mozambique', '+258', 9, 9),
  _PhoneCountry('MM', 'Myanmar', '+95', 8, 10),
  _PhoneCountry('NA', 'Namibia', '+264', 8, 9),
  _PhoneCountry('NL', 'Netherlands', '+31', 9, 9),
  _PhoneCountry('NZ', 'New Zealand', '+64', 8, 10),
  _PhoneCountry('NG', 'Nigeria', '+234', 10, 10),
  _PhoneCountry('NO', 'Norway', '+47', 8, 8),
  _PhoneCountry('PA', 'Panama', '+507', 8, 8),
  _PhoneCountry('PY', 'Paraguay', '+595', 9, 9),
  _PhoneCountry('PE', 'Peru', '+51', 9, 9),
  _PhoneCountry('PH', 'Philippines', '+63', 10, 10),
  _PhoneCountry('PL', 'Poland', '+48', 9, 9),
  _PhoneCountry('PT', 'Portugal', '+351', 9, 9),
  _PhoneCountry('RO', 'Romania', '+40', 9, 9),
  _PhoneCountry('RU', 'Russia', '+7', 10, 10),
  _PhoneCountry('RW', 'Rwanda', '+250', 9, 9),
  _PhoneCountry('RS', 'Serbia', '+381', 8, 9),
  _PhoneCountry('SK', 'Slovakia', '+421', 9, 9),
  _PhoneCountry('SI', 'Slovenia', '+386', 8, 8),
  _PhoneCountry('ZA', 'South Africa', '+27', 9, 9),
  _PhoneCountry('ES', 'Spain', '+34', 9, 9),
  _PhoneCountry('SE', 'Sweden', '+46', 7, 10),
  _PhoneCountry('CH', 'Switzerland', '+41', 9, 9),
  _PhoneCountry('TW', 'Taiwan', '+886', 9, 9),
  _PhoneCountry('TZ', 'Tanzania', '+255', 9, 9),
  _PhoneCountry('TH', 'Thailand', '+66', 9, 9),
  _PhoneCountry('TN', 'Tunisia', '+216', 8, 8),
  _PhoneCountry('TR', 'Turkey', '+90', 10, 10),
  _PhoneCountry('UG', 'Uganda', '+256', 9, 9),
  _PhoneCountry('UA', 'Ukraine', '+380', 9, 9),
  _PhoneCountry('UY', 'Uruguay', '+598', 8, 8),
  _PhoneCountry('UZ', 'Uzbekistan', '+998', 9, 9),
  _PhoneCountry('VE', 'Venezuela', '+58', 10, 10),
  _PhoneCountry('VN', 'Vietnam', '+84', 9, 10),
  _PhoneCountry('YE', 'Yemen', '+967', 7, 9),
  _PhoneCountry('ZM', 'Zambia', '+260', 9, 9),
  _PhoneCountry('ZW', 'Zimbabwe', '+263', 9, 9),
];

// ═══════════════════════════════════════════════════════════════════════════
// CACHED STYLES
// ═══════════════════════════════════════════════════════════════════════════

final _labelTextStyle = GoogleFonts.inter(
  color: kLightGrey,
  fontSize: 9,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.8,
);

final _inputTextStyle = GoogleFonts.inter(color: kWhite, fontSize: 14);

final _hintTextStyle = GoogleFonts.inter(color: kLightGrey, fontSize: 14);

InputDecoration _inputDecoration(
  String hint, {
  Widget? prefixIcon,
  Widget? suffixIcon,
  bool collapseErrorText = false,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: _hintTextStyle,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: const Color(0xFF2C2C2E),
    border: _borderStyle,
    enabledBorder: _borderStyle,
    focusedBorder: _focusedBorderStyle,
    errorBorder: _errorBorderStyle,
    focusedErrorBorder: _focusedErrorBorderStyle,
    errorStyle: collapseErrorText
        ? const TextStyle(fontSize: 0, height: 0)
        : _errorTextStyle,
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

const _fieldErrorColor = Colors.redAccent;

final _errorTextStyle = GoogleFonts.inter(
  color: _fieldErrorColor,
  fontSize: 11.5,
  fontWeight: FontWeight.w600,
);

final _errorBorderStyle = OutlineInputBorder(
  borderRadius: BorderRadius.circular(25),
  borderSide: const BorderSide(color: _fieldErrorColor),
);

final _focusedErrorBorderStyle = OutlineInputBorder(
  borderRadius: BorderRadius.circular(25),
  borderSide: const BorderSide(color: _fieldErrorColor, width: 2),
);
