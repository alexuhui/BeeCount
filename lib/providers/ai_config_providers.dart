import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ai/ai_constants.dart';
import '../services/ai/ai_provider_config.dart';
import '../services/ai/ai_provider_manager.dart';

/// AI 服务商类型
enum AIServiceProvider {
  /// 智谱 GLM (默认)
  zhipuGLM,

  /// 自定义（支持任何 OpenAI 兼容服务）
  custom,
}

/// AI 执行策略
enum AIStrategy {
  /// 本地优先
  localFirst,

  /// 云端优先
  cloudFirst,

  /// 仅本地
  localOnly,

  /// 仅云端
  cloudOnly,
}

/// AI 配置数据类
class AIConfigData {
  /// 服务商类型
  final AIServiceProvider provider;

  /// 智谱 GLM API Key
  final String glmApiKey;

  /// 自定义服务商 API Key
  final String customApiKey;

  /// 自定义服务商 Base URL
  final String? customBaseUrl;

  /// 智谱 GLM 模型配置
  final String? glmTextModel;
  final String? glmVisionModel;
  final String? glmAudioModel;

  /// 自定义服务商模型配置
  final String? customTextModel;
  final String? customVisionModel;
  final String? customAudioModel;

  /// AI 增强是否启用
  final bool enabled;

  /// 是否使用视觉模型（上传图片）
  final bool useVision;

  /// 执行策略
  final AIStrategy strategy;

  const AIConfigData({
    this.provider = AIServiceProvider.zhipuGLM,
    this.glmApiKey = '',
    this.customApiKey = '',
    this.customBaseUrl,
    this.glmTextModel,
    this.glmVisionModel,
    this.glmAudioModel,
    this.customTextModel,
    this.customVisionModel,
    this.customAudioModel,
    this.enabled = false,
    this.useVision = true,
    this.strategy = AIStrategy.cloudFirst,
  });

  /// 获取当前服务商的 API Key
  String get apiKey {
    switch (provider) {
      case AIServiceProvider.zhipuGLM:
        return glmApiKey.isNotEmpty
            ? glmApiKey
            : AIConstants.builtinGlmApiKey;
      case AIServiceProvider.custom:
        return customApiKey;
    }
  }

  /// 获取当前服务商的 Base URL
  String getBaseUrl() {
    switch (provider) {
      case AIServiceProvider.zhipuGLM:
        return 'https://open.bigmodel.cn/api/paas/v4';
      case AIServiceProvider.custom:
        return customBaseUrl ?? '';
    }
  }

  /// 获取文本模型
  String getTextModel() {
    switch (provider) {
      case AIServiceProvider.zhipuGLM:
        return glmTextModel ?? AIConstants.defaultGlmModel;
      case AIServiceProvider.custom:
        return customTextModel ?? '';
    }
  }

  /// 获取视觉模型
  String getVisionModel() {
    switch (provider) {
      case AIServiceProvider.zhipuGLM:
        return glmVisionModel ?? AIConstants.defaultGlmVisionModel;
      case AIServiceProvider.custom:
        return customVisionModel ?? '';
    }
  }

  /// 获取语音模型
  String getAudioModel() {
    switch (provider) {
      case AIServiceProvider.zhipuGLM:
        return glmAudioModel ?? AIConstants.defaultGlmAudioModel;
      case AIServiceProvider.custom:
        return customAudioModel ?? '';
    }
  }

  /// 检查配置是否有效
  bool isValid() {
    if (apiKey.isEmpty) return false;

    if (provider == AIServiceProvider.custom) {
      if (customBaseUrl == null || customBaseUrl!.isEmpty) return false;
      // 自定义服务商需要配置文本、视觉、语音模型
      if (customTextModel == null || customTextModel!.isEmpty) return false;
      if (customVisionModel == null || customVisionModel!.isEmpty) return false;
      if (customAudioModel == null || customAudioModel!.isEmpty) return false;
    }

    return true;
  }

  /// 复制并修改
  AIConfigData copyWith({
    AIServiceProvider? provider,
    String? glmApiKey,
    String? customApiKey,
    String? customBaseUrl,
    String? glmTextModel,
    String? glmVisionModel,
    String? glmAudioModel,
    String? customTextModel,
    String? customVisionModel,
    String? customAudioModel,
    bool? enabled,
    bool? useVision,
    AIStrategy? strategy,
  }) {
    return AIConfigData(
      provider: provider ?? this.provider,
      glmApiKey: glmApiKey ?? this.glmApiKey,
      customApiKey: customApiKey ?? this.customApiKey,
      customBaseUrl: customBaseUrl ?? this.customBaseUrl,
      glmTextModel: glmTextModel ?? this.glmTextModel,
      glmVisionModel: glmVisionModel ?? this.glmVisionModel,
      glmAudioModel: glmAudioModel ?? this.glmAudioModel,
      customTextModel: customTextModel ?? this.customTextModel,
      customVisionModel: customVisionModel ?? this.customVisionModel,
      customAudioModel: customAudioModel ?? this.customAudioModel,
      enabled: enabled ?? this.enabled,
      useVision: useVision ?? this.useVision,
      strategy: strategy ?? this.strategy,
    );
  }
}

/// AI 配置 Notifier
class AIConfigNotifier extends StateNotifier<AIConfigData> {
  Completer<void>? _loadCompleter;

  AIConfigNotifier() : super(const AIConfigData()) {
    _loadFromPrefs();
  }

  /// 等待配置加载完成
  Future<void> get ready async {
    if (_loadCompleter != null) {
      await _loadCompleter!.future;
    }
  }

  /// 从 SharedPreferences 加载配置
  Future<void> _loadFromPrefs() async {
    _loadCompleter = Completer<void>();
    try {
      final prefs = await SharedPreferences.getInstance();

      final providerStr =
          prefs.getString(AIConstants.keyAiServiceProvider) ?? 'zhipuGLM';
      final provider = providerStr == 'custom'
          ? AIServiceProvider.custom
          : AIServiceProvider.zhipuGLM;

      final strategyStr =
          prefs.getString(AIConstants.keyAiStrategy) ?? 'cloud_first';
      final strategy = _parseStrategy(strategyStr);

      final enabledPref = prefs.getBool(AIConstants.keyAiBillExtractionEnabled);
      // 有内置 Key 时默认开启；用户曾关掉过则尊重 prefs。
      final enabled = enabledPref ?? AIConstants.hasBuiltinGlmKey;
      if (enabledPref == null && enabled) {
        await prefs.setBool(AIConstants.keyAiBillExtractionEnabled, true);
      }

      state = AIConfigData(
        provider: provider,
        glmApiKey: prefs.getString(AIConstants.keyGlmApiKey) ?? '',
        customApiKey: prefs.getString(AIConstants.keyCustomApiKey) ?? '',
        customBaseUrl: prefs.getString(AIConstants.keyCustomBaseUrl),
        // GLM 模型配置
        glmTextModel: prefs.getString(AIConstants.keyGlmModel),
        glmVisionModel: prefs.getString(AIConstants.keyGlmVisionModel),
        glmAudioModel: prefs.getString(AIConstants.keyGlmAudioModel),
        // 自定义服务商模型配置
        customTextModel: prefs.getString(AIConstants.keyCustomTextModel),
        customVisionModel: prefs.getString(AIConstants.keyCustomVisionModel),
        customAudioModel: prefs.getString(AIConstants.keyCustomAudioModel),
        enabled: enabled,
        useVision: prefs.getBool(AIConstants.keyAiUseVision) ?? true,
        strategy: strategy,
      );
      _loadCompleter!.complete();
    } catch (e) {
      _loadCompleter!.complete();
      rethrow;
    }
  }

  AIStrategy _parseStrategy(String str) {
    switch (str) {
      case 'local_first':
        return AIStrategy.localFirst;
      case 'cloud_first':
        return AIStrategy.cloudFirst;
      case 'local_only':
        return AIStrategy.localOnly;
      case 'cloud_only':
        return AIStrategy.cloudOnly;
      default:
        return AIStrategy.cloudFirst;
    }
  }

  String _strategyToString(AIStrategy strategy) {
    switch (strategy) {
      case AIStrategy.localFirst:
        return 'local_first';
      case AIStrategy.cloudFirst:
        return 'cloud_first';
      case AIStrategy.localOnly:
        return 'local_only';
      case AIStrategy.cloudOnly:
        return 'cloud_only';
    }
  }

  /// 保存配置到 SharedPreferences
  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      AIConstants.keyAiServiceProvider,
      state.provider == AIServiceProvider.custom ? 'custom' : 'zhipuGLM',
    );
    await prefs.setString(AIConstants.keyGlmApiKey, state.glmApiKey);
    await prefs.setString(AIConstants.keyCustomApiKey, state.customApiKey);
    await prefs.setString(
        AIConstants.keyAiStrategy, _strategyToString(state.strategy));

    // 自定义服务商配置
    if (state.customBaseUrl != null) {
      await prefs.setString(AIConstants.keyCustomBaseUrl, state.customBaseUrl!);
    }
    // GLM 模型配置
    if (state.glmTextModel != null) {
      await prefs.setString(AIConstants.keyGlmModel, state.glmTextModel!);
    }
    if (state.glmVisionModel != null) {
      await prefs.setString(AIConstants.keyGlmVisionModel, state.glmVisionModel!);
    }
    if (state.glmAudioModel != null) {
      await prefs.setString(AIConstants.keyGlmAudioModel, state.glmAudioModel!);
    }
    // 自定义服务商模型配置
    if (state.customTextModel != null) {
      await prefs.setString(AIConstants.keyCustomTextModel, state.customTextModel!);
    }
    if (state.customVisionModel != null) {
      await prefs.setString(AIConstants.keyCustomVisionModel, state.customVisionModel!);
    }
    if (state.customAudioModel != null) {
      await prefs.setString(AIConstants.keyCustomAudioModel, state.customAudioModel!);
    }
    await prefs.setBool(AIConstants.keyAiBillExtractionEnabled, state.enabled);
    await prefs.setBool(AIConstants.keyAiUseVision, state.useVision);
  }

  /// 设置服务商
  Future<void> setProvider(AIServiceProvider provider) async {
    state = state.copyWith(provider: provider);
    await _saveToPrefs();
  }

  /// 设置 API Key（根据当前服务商自动选择存储位置）
  Future<void> setApiKey(String apiKey) async {
    if (state.provider == AIServiceProvider.zhipuGLM) {
      state = state.copyWith(glmApiKey: apiKey);
    } else {
      state = state.copyWith(customApiKey: apiKey);
    }
    await _saveToPrefs();
  }

  /// 设置智谱 GLM API Key
  Future<void> setGlmApiKey(String apiKey) async {
    state = state.copyWith(glmApiKey: apiKey);
    await _saveToPrefs();
  }

  /// 设置自定义服务商 API Key
  Future<void> setCustomApiKey(String apiKey) async {
    state = state.copyWith(customApiKey: apiKey);
    await _saveToPrefs();
  }

  /// 设置自定义服务商 Base URL
  Future<void> setCustomBaseUrl(String baseUrl) async {
    state = state.copyWith(customBaseUrl: baseUrl);
    await _saveToPrefs();
  }

  /// 设置文本模型（根据当前服务商自动选择存储位置）
  Future<void> setTextModel(String model) async {
    if (state.provider == AIServiceProvider.zhipuGLM) {
      state = state.copyWith(glmTextModel: model);
    } else {
      state = state.copyWith(customTextModel: model);
    }
    await _saveToPrefs();
  }

  /// 设置视觉模型（根据当前服务商自动选择存储位置）
  Future<void> setVisionModel(String model) async {
    if (state.provider == AIServiceProvider.zhipuGLM) {
      state = state.copyWith(glmVisionModel: model);
    } else {
      state = state.copyWith(customVisionModel: model);
    }
    await _saveToPrefs();
  }

  /// 设置语音模型（根据当前服务商自动选择存储位置）
  Future<void> setAudioModel(String model) async {
    if (state.provider == AIServiceProvider.zhipuGLM) {
      state = state.copyWith(glmAudioModel: model);
    } else {
      state = state.copyWith(customAudioModel: model);
    }
    await _saveToPrefs();
  }

  /// 设置 GLM 模型配置
  Future<void> setGlmModels({
    String? textModel,
    String? visionModel,
    String? audioModel,
  }) async {
    state = state.copyWith(
      glmTextModel: textModel ?? state.glmTextModel,
      glmVisionModel: visionModel ?? state.glmVisionModel,
      glmAudioModel: audioModel ?? state.glmAudioModel,
    );
    await _saveToPrefs();
  }

  /// 设置自定义服务商模型配置
  Future<void> setCustomModels({
    String? textModel,
    String? visionModel,
    String? audioModel,
  }) async {
    state = state.copyWith(
      customTextModel: textModel ?? state.customTextModel,
      customVisionModel: visionModel ?? state.customVisionModel,
      customAudioModel: audioModel ?? state.customAudioModel,
    );
    await _saveToPrefs();
  }

  /// 设置执行策略
  Future<void> setStrategy(AIStrategy strategy) async {
    state = state.copyWith(strategy: strategy);
    await _saveToPrefs();
  }

  /// 设置启用状态
  Future<void> setEnabled(bool enabled) async {
    state = state.copyWith(enabled: enabled);
    await _saveToPrefs();
  }

  /// 设置是否使用视觉模型
  Future<void> setUseVision(bool useVision) async {
    state = state.copyWith(useVision: useVision);
    await _saveToPrefs();
  }

  /// 重新加载配置
  Future<void> reload() async {
    await _loadFromPrefs();
  }
}

/// AI 配置 Provider
final aiConfigProvider =
    StateNotifierProvider<AIConfigNotifier, AIConfigData>((ref) {
  return AIConfigNotifier();
});

/// AI 是否启用 Provider（简化访问）
final aiEnabledProvider = Provider<bool>((ref) {
  return ref.watch(aiConfigProvider).enabled;
});

/// AI 配置是否有效 Provider
final aiConfigValidProvider = Provider<bool>((ref) {
  return ref.watch(aiConfigProvider).isValid();
});

/// AI 是否可用 Provider（已启用且配置有效）
final aiAvailableProvider = Provider<bool>((ref) {
  final config = ref.watch(aiConfigProvider);
  return config.enabled && config.isValid();
});

// ============================================================
// 新版多服务商架构 Providers
// ============================================================

/// 能力绑定刷新 Provider
final aiCapabilityBindingRefreshProvider = StateProvider<int>((ref) => 0);

/// 能力绑定数据 Provider
final aiCapabilityBindingProvider = FutureProvider<AICapabilityBinding>((ref) async {
  ref.watch(aiCapabilityBindingRefreshProvider);
  return AIProviderManager.getCapabilityBinding();
});

/// 服务商列表刷新 Provider (供能力选择使用)
final aiProviderListForCapabilityRefreshProvider = StateProvider<int>((ref) => 0);

/// 服务商列表 Provider (供能力选择使用)
final aiProviderListForCapabilityProvider = FutureProvider<List<AIServiceProviderConfig>>((ref) async {
  ref.watch(aiProviderListForCapabilityRefreshProvider);
  return AIProviderManager.getProviders();
});
