import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/ui/ui.dart';
import '../../styles/tokens.dart';
import '../../services/system/logger_service.dart';
import '../../l10n/app_localizations.dart';
import '../../services/api/api_service.dart';

enum AuthMode { login, signup }

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key, this.initialMode = AuthMode.login});
  final AuthMode initialMode;

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final emailCtrl = TextEditingController();
  final pwdCtrl = TextEditingController();
  final pwd2Ctrl = TextEditingController();
  String? errorText;
  String? infoText;
  bool busy = false;
  late bool isSignup;
  bool _showPwd = false;
  bool _showPwd2 = false;
  bool _rememberAccount = false;
  void _switchMode(bool toSignup) {
    setState(() {
      isSignup = toSignup;
      errorText = null;
      infoText = null;
    });
  }

  @override
  void initState() {
    super.initState();
    isSignup = widget.initialMode == AuthMode.signup;
    // 延迟加载凭证，确保 provider 已初始化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedCredentials();
    });
  }

  Future<void> _loadSavedCredentials() async {
    // 暂时不加载保存的凭证，后续可以添加本地存储逻辑
  }

  Future<void> _saveCredentials(String email, String password) async {
    // 暂时不保存凭证，后续可以添加本地存储逻辑
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    pwdCtrl.dispose();
    pwd2Ctrl.dispose();
    super.dispose();
  }

  bool isValidEmail(String s) {
    final t = s.trim();
    final emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRe.hasMatch(t);
  }

  bool isValidPassword(String s) {
    if (s.length < 6) return false;
    final hasAlpha = RegExp(r'[A-Za-z]').hasMatch(s);
    final hasDigit = RegExp(r'\d').hasMatch(s);
    return hasAlpha && hasDigit;
  }

  String friendlyAuthError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('邮箱或密码错误')) {
      return AppLocalizations.of(context).authErrorInvalidCredentials;
    }
    if (msg.contains('邮箱已被注册')) {
      return AppLocalizations.of(context).authErrorEmailExists;
    }
    if (msg.contains('网络') || msg.contains('timeout')) {
      return AppLocalizations.of(context).authErrorNetworkIssue;
    }
    return AppLocalizations.of(context).authErrorLoginFailed;
  }

  String friendlySignupError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('邮箱已被注册')) {
      return AppLocalizations.of(context).authErrorEmailExists;
    }
    if (msg.contains('网络') || msg.contains('timeout')) {
      return AppLocalizations.of(context).authErrorNetworkIssue;
    }
    return AppLocalizations.of(context).authErrorSignupFailed;
  }

  // 恢复流程改为登录后回到“我的”页由其触发，不再在登录页内执行

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(12);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(title: isSignup ? AppLocalizations.of(context).authSignup : AppLocalizations.of(context).authLogin, showBack: true),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: SingleChildScrollView(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    decoration: BoxDecoration(
                      color: BeeTokens.surface(context),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: BeeTokens.isDark(context) ? null : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ChoiceChip(
                              selected: !isSignup,
                              label: Text(AppLocalizations.of(context).authLogin),
                              selectedColor: theme.colorScheme.primary,
                              backgroundColor: BeeTokens.surface(context),
                              side: BorderSide(
                                color: theme.colorScheme.primary,
                                width: (!isSignup) ? 0 : 1,
                              ),
                              labelStyle: TextStyle(
                                color: (!isSignup)
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.primary,
                                fontWeight: (!isSignup)
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              onSelected: (v) => _switchMode(false),
                              checkmarkColor: theme.colorScheme.onPrimary,
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              selected: isSignup,
                              label: Text(AppLocalizations.of(context).authSignup),
                              selectedColor: theme.colorScheme.primary,
                              backgroundColor: BeeTokens.surface(context),
                              side: BorderSide(
                                color: theme.colorScheme.primary,
                                width: (isSignup) ? 0 : 1,
                              ),
                              labelStyle: TextStyle(
                                color: (isSignup)
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.primary,
                                fontWeight: (isSignup)
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              onSelected: (v) => _switchMode(true),
                              checkmarkColor: theme.colorScheme.onPrimary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(labelText: AppLocalizations.of(context).authEmail),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: pwdCtrl,
                          obscureText: !_showPwd,
                          decoration: InputDecoration(
                            labelText: isSignup ? AppLocalizations.of(context).authPasswordRequirement : AppLocalizations.of(context).authPassword,
                            suffixIcon: IconButton(
                              icon: Icon(_showPwd
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined),
                              onPressed: () =>
                                  setState(() => _showPwd = !_showPwd),
                            ),
                          ),
                        ),
                        if (isSignup) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: pwd2Ctrl,
                            obscureText: !_showPwd2,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(context).authConfirmPassword,
                              suffixIcon: IconButton(
                                icon: Icon(_showPwd2
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
                                onPressed: () =>
                                    setState(() => _showPwd2 = !_showPwd2),
                              ),
                            ),
                          ),
                        ],
                        if (!isSignup) ...[
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () {
                              setState(() {
                                _rememberAccount = !_rememberAccount;
                              });
                            },
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _rememberAccount,
                                  onChanged: (value) {
                                    setState(() {
                                      _rememberAccount = value ?? false;
                                    });
                                  },
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        AppLocalizations.of(context).authRememberAccount,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: BeeTokens.textPrimary(context),
                                        ),
                                      ),
                                      Text(
                                        AppLocalizations.of(context).authRememberAccountHint,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: BeeTokens.textSecondary(context),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (errorText != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(
                              errorText!,
                              style: TextStyle(color: BeeTokens.error(context)),
                            ),
                          ),
                        if (infoText != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(
                              infoText!,
                              style: TextStyle(color: BeeTokens.success(context)),
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: isSignup
                              ? OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                        borderRadius: radius),
                                    foregroundColor:
                                        Theme.of(context).colorScheme.primary,
                                    side: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary),
                                  ),
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          final email = emailCtrl.text.trim();
                                          final pwd = pwdCtrl.text;
                                          final pwd2 = pwd2Ctrl.text;
                                          logger.info('auth', '开始注册：邮箱=$email');
                                          if (!isValidEmail(email)) {
                                            setState(
                                                () => errorText = 'AppLocalizations.of(context).authInvalidEmail');
                                            return;
                                          }
                                          if (!isValidPassword(pwd)) {
                                            setState(() => errorText =
                                                'AppLocalizations.of(context).authPasswordRequirementShort');
                                            return;
                                          }
                                          if (pwd != pwd2) {
                                            setState(
                                                () => errorText = AppLocalizations.of(context).authPasswordMismatch);
                                            return;
                                          }
                                          setState(() {
                                            busy = true;
                                            errorText = null;
                                            infoText = null;
                                          });
                                          try {
                                            await ApiService.register(email, pwd, email.split('@')[0]);
                                            if (!context.mounted) return;
                                            logger.info('auth',
                                                '注册成功：邮箱=$email');
                                            Navigator.of(context)
                                                .pushReplacement(
                                              MaterialPageRoute(
                                                  builder: (_) =>
                                                      const SignupSuccessPage()),
                                            );
                                          } catch (e, stSignup) {
                                            final friendlyMsg = friendlySignupError(e);
                                            final detailedMsg = 'Type: ${e.runtimeType}, Message: $e';
                                            logger.error(
                                                'auth',
                                                '注册失败：邮箱=$email，用户友好信息=$friendlyMsg，详细错误=$detailedMsg',
                                                e,
                                                stSignup);
                                            setState(() => errorText =
                                                friendlyMsg);
                                          } finally {
                                            if (mounted) {
                                              setState(() => busy = false);
                                            }
                                          }
                                        },
                                  child: busy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : Text(AppLocalizations.of(context).authSignup),
                                )
                              : FilledButton(
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                        borderRadius: radius),
                                  ),
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          final email = emailCtrl.text.trim();
                                          final pwd = pwdCtrl.text;
                                          logger.info('auth', '开始登录：邮箱=$email');
                                          if (!isValidEmail(email)) {
                                            setState(
                                                () => errorText = 'AppLocalizations.of(context).authInvalidEmail');
                                            return;
                                          }
                                          if (!isValidPassword(pwd)) {
                                            setState(() => errorText =
                                                'AppLocalizations.of(context).authPasswordRequirementShort');
                                            return;
                                          }
                                          setState(() {
                                            busy = true;
                                            errorText = null;
                                            infoText = null;
                                          });
                                          try {
                                            await ApiService.login(email, pwd);
                                            if (!context.mounted) return;
                                            logger.info('auth', '登录成功：邮箱=$email');

                                            // Save credentials if "remember account" is checked
                                            await _saveCredentials(email, pwd);

                                            // 直接返回上一页，让欢迎页面处理后续逻辑
                                            Navigator.of(context).pop();
                                          } catch (e, st) {
                                            final friendlyMsg = friendlyAuthError(e);
                                            final detailedMsg = 'Type: ${e.runtimeType}, Message: $e';
                                            logger.error(
                                                'auth',
                                                '登录失败：邮箱=$email，用户友好信息=$friendlyMsg，详细错误=$detailedMsg',
                                                e,
                                                st);
                                            setState(() => errorText = friendlyMsg);
                                          } finally {
                                            if (mounted) {
                                              setState(() => busy = false);
                                            }
                                          }
                                        },
                                  child: busy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white),
                                        )
                                      : Text(AppLocalizations.of(context).authLogin),
                                ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const AuthPage(initialMode: AuthMode.login);
}

class SignupPage extends StatelessWidget {
  const SignupPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const AuthPage(initialMode: AuthMode.signup);
}

class SignupSuccessPage extends StatelessWidget {
  const SignupSuccessPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(title: AppLocalizations.of(context).authSignupSuccess, showBack: false),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mark_email_read_outlined,
                        size: 72, color: BeeTokens.success(context)),
                    const SizedBox(height: 12),
                    Text(
                      AppLocalizations.of(context).authVerificationEmailSent,
                      style: TextStyle(color: BeeTokens.textPrimary(context)),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(context).popUntil((r) => r.isFirst),
                      child: Text(AppLocalizations.of(context).authBackToMinePage),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 旧的对话框已废弃，改为独立页面展示
