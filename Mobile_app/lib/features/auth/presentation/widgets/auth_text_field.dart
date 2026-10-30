/// features/auth/presentation/widgets/auth_text_field.dart
/// Reusable text field widget for authentication forms.
///
/// Used in: LoginPage, RegisterPage
/// Provides consistent styling matching AppTheme.inputDecorationTheme.
///
/// Supports:
///  - Custom prefix icon
///  - Optional suffix widget (e.g., password visibility toggle)
///  - Obscured text for passwords
///  - Keyboard type and input action configuration
///  - Built-in validator slot for Form validation

import 'package:flutter/material.dart';

class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.focusNode,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText      = false,
    this.keyboardType     = TextInputType.text,
    this.textInputAction  = TextInputAction.next,
    this.validator,
    this.onFieldSubmitted,
    this.enabled          = true,
    this.maxLines         = 1,
    this.autocorrect      = false,
    this.enableSuggestions = false,
  });

  final TextEditingController controller;
  final String                label;
  final String?               hint;
  final FocusNode?            focusNode;
  final IconData?             prefixIcon;
  final Widget?               suffixIcon;
  final bool                  obscureText;
  final TextInputType         keyboardType;
  final TextInputAction       textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)?     onFieldSubmitted;
  final bool                  enabled;
  final int                   maxLines;
  final bool                  autocorrect;
  final bool                  enableSuggestions;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller:         controller,
      focusNode:          focusNode,
      obscureText:        obscureText,
      keyboardType:       keyboardType,
      textInputAction:    textInputAction,
      validator:          validator,
      onFieldSubmitted:   onFieldSubmitted,
      enabled:            enabled,
      maxLines:           obscureText ? 1 : maxLines,
      autocorrect:        autocorrect,
      enableSuggestions:  enableSuggestions,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize:   15,
        fontWeight: FontWeight.w400,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText:  hint,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 20)
            : null,
        suffixIcon:  suffixIcon,
        // Use theme's input decoration (defined in app_theme.dart)
        // These overrides only apply when needed
        errorMaxLines: 2,
      ),
    );
  }
}