// lib/data/models/ai_source_config.dart
// KanMon GO — Per-source AI configuration model
// Stores enable/disable state + all tunable parameters for Online, Bulk, Offline
// =============================================================================

import 'dart:convert';

// ── Online AI (Puter.js) config ───────────────────────────────────────────────
class OnlineAiConfig {
  bool   enabled;
  String apiKey;          // Puter.js app key (or empty for free tier)
  String selectedModel;   // e.g. "gpt-4o-mini"
  String systemPrompt;
  String personaName;
  double temperature;     // 0.0–2.0
  int    maxTokens;       // 1–8192
  double topP;            // 0.0–1.0
  double frequencyPenalty;// -2.0–2.0
  double presencePenalty; // -2.0–2.0
  bool   streamEnabled;
  int    timeoutSeconds;  // HTTP timeout
  String language;        // Response language hint ("id" / "en" / "ja" / "auto")
  bool   autoDetectLanguage;
  bool   webSearchEnabled;
  String searchEngine;    // "ddg" / "google" / "bing"
  bool   markdownEnabled;
  bool   codeHighlightEnabled;
  bool   ttsEnabled;      // Auto-read response via TTS
  String ttsVoice;        // Edge-TTS voice name

  OnlineAiConfig({
    this.enabled               = true,
    this.apiKey                = '',
    this.selectedModel         = 'gpt-4o-mini',
    this.systemPrompt          = '',
    this.personaName           = 'KanMon Assistant',
    this.temperature           = 0.7,
    this.maxTokens             = 2048,
    this.topP                  = 0.95,
    this.frequencyPenalty      = 0.0,
    this.presencePenalty       = 0.0,
    this.streamEnabled         = true,
    this.timeoutSeconds        = 30,
    this.language              = 'auto',
    this.autoDetectLanguage    = true,
    this.webSearchEnabled      = false,
    this.searchEngine          = 'ddg',
    this.markdownEnabled       = true,
    this.codeHighlightEnabled  = true,
    this.ttsEnabled            = false,
    this.ttsVoice              = 'id-ID-GadisNeural',
  });

  factory OnlineAiConfig.fromJson(Map<String, dynamic> j) => OnlineAiConfig(
    enabled              : j['enabled']              as bool?   ?? true,
    apiKey               : j['apiKey']               as String? ?? '',
    selectedModel        : j['selectedModel']         as String? ?? 'gpt-4o-mini',
    systemPrompt         : j['systemPrompt']          as String? ?? '',
    personaName          : j['personaName']           as String? ?? 'KanMon Assistant',
    temperature          : (j['temperature']          as num?)?.toDouble() ?? 0.7,
    maxTokens            : j['maxTokens']             as int?    ?? 2048,
    topP                 : (j['topP']                 as num?)?.toDouble() ?? 0.95,
    frequencyPenalty     : (j['frequencyPenalty']     as num?)?.toDouble() ?? 0.0,
    presencePenalty      : (j['presencePenalty']      as num?)?.toDouble() ?? 0.0,
    streamEnabled        : j['streamEnabled']         as bool?   ?? true,
    timeoutSeconds       : j['timeoutSeconds']        as int?    ?? 30,
    language             : j['language']              as String? ?? 'auto',
    autoDetectLanguage   : j['autoDetectLanguage']   as bool?   ?? true,
    webSearchEnabled     : j['webSearchEnabled']      as bool?   ?? false,
    searchEngine         : j['searchEngine']          as String? ?? 'ddg',
    markdownEnabled      : j['markdownEnabled']       as bool?   ?? true,
    codeHighlightEnabled : j['codeHighlightEnabled']  as bool?   ?? true,
    ttsEnabled           : j['ttsEnabled']            as bool?   ?? false,
    ttsVoice             : j['ttsVoice']              as String? ?? 'id-ID-GadisNeural',
  );

  Map<String, dynamic> toJson() => {
    'enabled'             : enabled,
    'apiKey'              : apiKey,
    'selectedModel'       : selectedModel,
    'systemPrompt'        : systemPrompt,
    'personaName'         : personaName,
    'temperature'         : temperature,
    'maxTokens'           : maxTokens,
    'topP'                : topP,
    'frequencyPenalty'    : frequencyPenalty,
    'presencePenalty'     : presencePenalty,
    'streamEnabled'       : streamEnabled,
    'timeoutSeconds'      : timeoutSeconds,
    'language'            : language,
    'autoDetectLanguage'  : autoDetectLanguage,
    'webSearchEnabled'    : webSearchEnabled,
    'searchEngine'        : searchEngine,
    'markdownEnabled'     : markdownEnabled,
    'codeHighlightEnabled': codeHighlightEnabled,
    'ttsEnabled'          : ttsEnabled,
    'ttsVoice'            : ttsVoice,
  };

  OnlineAiConfig copyWith({
    bool?   enabled,
    String? apiKey,
    String? selectedModel,
    String? systemPrompt,
    String? personaName,
    double? temperature,
    int?    maxTokens,
    double? topP,
    double? frequencyPenalty,
    double? presencePenalty,
    bool?   streamEnabled,
    int?    timeoutSeconds,
    String? language,
    bool?   autoDetectLanguage,
    bool?   webSearchEnabled,
    String? searchEngine,
    bool?   markdownEnabled,
    bool?   codeHighlightEnabled,
    bool?   ttsEnabled,
    String? ttsVoice,
  }) => OnlineAiConfig(
    enabled              : enabled              ?? this.enabled,
    apiKey               : apiKey               ?? this.apiKey,
    selectedModel        : selectedModel         ?? this.selectedModel,
    systemPrompt         : systemPrompt          ?? this.systemPrompt,
    personaName          : personaName           ?? this.personaName,
    temperature          : temperature           ?? this.temperature,
    maxTokens            : maxTokens             ?? this.maxTokens,
    topP                 : topP                  ?? this.topP,
    frequencyPenalty     : frequencyPenalty      ?? this.frequencyPenalty,
    presencePenalty      : presencePenalty       ?? this.presencePenalty,
    streamEnabled        : streamEnabled         ?? this.streamEnabled,
    timeoutSeconds       : timeoutSeconds        ?? this.timeoutSeconds,
    language             : language              ?? this.language,
    autoDetectLanguage   : autoDetectLanguage    ?? this.autoDetectLanguage,
    webSearchEnabled     : webSearchEnabled      ?? this.webSearchEnabled,
    searchEngine         : searchEngine          ?? this.searchEngine,
    markdownEnabled      : markdownEnabled       ?? this.markdownEnabled,
    codeHighlightEnabled : codeHighlightEnabled  ?? this.codeHighlightEnabled,
    ttsEnabled           : ttsEnabled            ?? this.ttsEnabled,
    ttsVoice             : ttsVoice              ?? this.ttsVoice,
  );
}

// ── Bulk API config ───────────────────────────────────────────────────────────
// NOTE: BulkApiKey, BulkApiProvider, BulkLoadMode are defined in
//       lib/data/services/content/bulk_api_service.dart — imported where needed.
//       BulkAiConfig only stores the config values; key list is managed
//       by BulkApiService but mirrored here for settings persistence.
class BulkAiConfig {
  bool              enabled;
  List<dynamic>     keys;               // List<BulkApiKey> — typed as dynamic to avoid circular import
  dynamic           activeProvider;     // BulkApiProvider
  String            selectedModel;
  String            customModelOverride;
  dynamic           loadMode;           // BulkLoadMode
  int               maxRetries;
  int               timeoutSeconds;
  double            temperature;
  int               maxTokens;
  double            topP;
  double            frequencyPenalty;
  double            presencePenalty;
  bool              streamEnabled;
  bool              markdownEnabled;
  bool              codeHighlightEnabled;
  String            personaName;
  String            systemPrompt;
  String            language;
  bool              autoDetectLanguage;
  bool              ttsEnabled;
  String            ttsVoice;

  BulkAiConfig({
    this.enabled              = true,
    List<dynamic>? keys,
    this.activeProvider,
    this.selectedModel        = 'llama-3.3-70b-versatile',
    this.customModelOverride  = '',
    this.loadMode,
    this.maxRetries           = 3,
    this.timeoutSeconds       = 45,
    this.temperature          = 0.7,
    this.maxTokens            = 2048,
    this.topP                 = 0.95,
    this.frequencyPenalty     = 0.0,
    this.presencePenalty      = 0.0,
    this.streamEnabled        = true,
    this.markdownEnabled      = true,
    this.codeHighlightEnabled = true,
    this.personaName          = 'KanMon Bulk Assistant',
    this.systemPrompt         = '',
    this.language             = 'auto',
    this.autoDetectLanguage   = true,
    this.ttsEnabled           = false,
    this.ttsVoice             = 'id-ID-GadisNeural',
  }) : keys = keys ?? [];

  factory BulkAiConfig.fromJson(Map<String, dynamic> j) => BulkAiConfig(
    enabled              : j['enabled']              as bool?   ?? true,
    // keys are managed by BulkApiService (SharedPreferences), not stored here
    selectedModel        : j['selectedModel']        as String? ?? 'llama-3.3-70b-versatile',
    customModelOverride  : j['customModelOverride']  as String? ?? '',
    maxRetries           : j['maxRetries']           as int?    ?? 3,
    timeoutSeconds       : j['timeoutSeconds']       as int?    ?? 45,
    temperature          : (j['temperature']         as num?)?.toDouble() ?? 0.7,
    maxTokens            : j['maxTokens']            as int?    ?? 2048,
    topP                 : (j['topP']                as num?)?.toDouble() ?? 0.95,
    frequencyPenalty     : (j['frequencyPenalty']    as num?)?.toDouble() ?? 0.0,
    presencePenalty      : (j['presencePenalty']     as num?)?.toDouble() ?? 0.0,
    streamEnabled        : j['streamEnabled']        as bool?   ?? true,
    markdownEnabled      : j['markdownEnabled']      as bool?   ?? true,
    codeHighlightEnabled : j['codeHighlightEnabled'] as bool?   ?? true,
    personaName          : j['personaName']          as String? ?? 'KanMon Bulk Assistant',
    systemPrompt         : j['systemPrompt']         as String? ?? '',
    language             : j['language']             as String? ?? 'auto',
    autoDetectLanguage   : j['autoDetectLanguage']   as bool?   ?? true,
    ttsEnabled           : j['ttsEnabled']           as bool?   ?? false,
    ttsVoice             : j['ttsVoice']             as String? ?? 'id-ID-GadisNeural',
  );

  Map<String, dynamic> toJson() => {
    'enabled'              : enabled,
    'selectedModel'        : selectedModel,
    'customModelOverride'  : customModelOverride,
    'maxRetries'           : maxRetries,
    'timeoutSeconds'       : timeoutSeconds,
    'temperature'          : temperature,
    'maxTokens'            : maxTokens,
    'topP'                 : topP,
    'frequencyPenalty'     : frequencyPenalty,
    'presencePenalty'      : presencePenalty,
    'streamEnabled'        : streamEnabled,
    'markdownEnabled'      : markdownEnabled,
    'codeHighlightEnabled' : codeHighlightEnabled,
    'personaName'          : personaName,
    'systemPrompt'         : systemPrompt,
    'language'             : language,
    'autoDetectLanguage'   : autoDetectLanguage,
    'ttsEnabled'           : ttsEnabled,
    'ttsVoice'             : ttsVoice,
  };

  BulkAiConfig copyWith({
    bool?          enabled,
    List<dynamic>? keys,
    dynamic        activeProvider,
    String?        selectedModel,
    String?        customModelOverride,
    dynamic        loadMode,
    int?           maxRetries,
    int?           timeoutSeconds,
    double?        temperature,
    int?           maxTokens,
    double?        topP,
    double?        frequencyPenalty,
    double?        presencePenalty,
    bool?          streamEnabled,
    bool?          markdownEnabled,
    bool?          codeHighlightEnabled,
    String?        personaName,
    String?        systemPrompt,
    String?        language,
    bool?          autoDetectLanguage,
    bool?          ttsEnabled,
    String?        ttsVoice,
  }) => BulkAiConfig(
    enabled              : enabled              ?? this.enabled,
    keys                 : keys                 ?? this.keys,
    activeProvider       : activeProvider       ?? this.activeProvider,
    selectedModel        : selectedModel        ?? this.selectedModel,
    customModelOverride  : customModelOverride  ?? this.customModelOverride,
    loadMode             : loadMode             ?? this.loadMode,
    maxRetries           : maxRetries           ?? this.maxRetries,
    timeoutSeconds       : timeoutSeconds       ?? this.timeoutSeconds,
    temperature          : temperature          ?? this.temperature,
    maxTokens            : maxTokens            ?? this.maxTokens,
    topP                 : topP                 ?? this.topP,
    frequencyPenalty     : frequencyPenalty     ?? this.frequencyPenalty,
    presencePenalty      : presencePenalty      ?? this.presencePenalty,
    streamEnabled        : streamEnabled        ?? this.streamEnabled,
    markdownEnabled      : markdownEnabled      ?? this.markdownEnabled,
    codeHighlightEnabled : codeHighlightEnabled ?? this.codeHighlightEnabled,
    personaName          : personaName          ?? this.personaName,
    systemPrompt         : systemPrompt         ?? this.systemPrompt,
    language             : language             ?? this.language,
    autoDetectLanguage   : autoDetectLanguage   ?? this.autoDetectLanguage,
    ttsEnabled           : ttsEnabled           ?? this.ttsEnabled,
    ttsVoice             : ttsVoice             ?? this.ttsVoice,
  );
}

// ── Offline AI (Llama.cpp) config ──────────────────────────────────────────────
class OfflineAiConfig {
  bool         enabled;
  String       activeModelPath;
  int          contextSize;
  int          gpuLayers;
  double       temperature;
  double       topP;
  int          topK;
  double       minP;
  double       tfsZ;
  double       typicalP;
  double       repeatPenalty;
  int          repeatLastN;
  bool         penalizeNl;
  int          maxNewTokens;
  int          mirostatMode;
  double       mirostatTau;
  double       mirostatEta;
  int          seed;
  List<String> stopSequences;
  bool         forceOffline;
  bool         streamEnabled;
  bool         markdownEnabled;
  bool         codeHighlightEnabled;
  bool         ttsEnabled;
  String       ttsVoice;
  double       ttsRate;
  double       ttsVolume;
  String       personaName;
  String       systemPrompt;
  String       chatTemplate;

  OfflineAiConfig({
    this.enabled              = false,
    this.activeModelPath      = '',
    this.contextSize          = 2048,
    this.gpuLayers            = 0,
    this.temperature          = 0.7,
    this.topP                 = 0.9,
    this.topK                 = 40,
    this.minP                 = 0.05,
    this.tfsZ                 = 1.0,
    this.typicalP             = 1.0,
    this.repeatPenalty        = 1.1,
    this.repeatLastN          = 64,
    this.penalizeNl           = false,
    this.maxNewTokens         = 1024,
    this.mirostatMode         = 0,
    this.mirostatTau          = 5.0,
    this.mirostatEta          = 0.1,
    this.seed                 = -1,
    this.stopSequences        = const [],
    this.forceOffline         = false,
    this.streamEnabled        = true,
    this.markdownEnabled      = true,
    this.codeHighlightEnabled = true,
    this.ttsEnabled           = false,
    this.ttsVoice             = 'id-ID-GadisNeural',
    this.ttsRate              = 0,
    this.ttsVolume            = 0,
    this.personaName          = 'KanMon Offline Assistant',
    this.systemPrompt         = '',
    this.chatTemplate         = 'auto',
  });

  factory OfflineAiConfig.fromJson(Map<String, dynamic> j) => OfflineAiConfig(
    enabled              : j['enabled']              as bool?   ?? false,
    activeModelPath      : j['activeModelPath']      as String? ?? '',
    contextSize          : j['contextSize']          as int?    ?? 2048,
    gpuLayers            : j['gpuLayers']            as int?    ?? 0,
    temperature          : (j['temperature']         as num?)?.toDouble() ?? 0.7,
    topP                 : (j['topP']                as num?)?.toDouble() ?? 0.9,
    topK                 : j['topK']                 as int?    ?? 40,
    minP                 : (j['minP']                as num?)?.toDouble() ?? 0.05,
    tfsZ                 : (j['tfsZ']                as num?)?.toDouble() ?? 1.0,
    typicalP             : (j['typicalP']            as num?)?.toDouble() ?? 1.0,
    repeatPenalty        : (j['repeatPenalty']       as num?)?.toDouble() ?? 1.1,
    repeatLastN          : j['repeatLastN']          as int?    ?? 64,
    penalizeNl           : j['penalizeNl']           as bool?   ?? false,
    maxNewTokens         : j['maxNewTokens']         as int?    ?? 1024,
    mirostatMode         : j['mirostatMode']         as int?    ?? 0,
    mirostatTau          : (j['mirostatTau']         as num?)?.toDouble() ?? 5.0,
    mirostatEta          : (j['mirostatEta']         as num?)?.toDouble() ?? 0.1,
    seed                 : j['seed']                 as int?    ?? -1,
    stopSequences        : (j['stopSequences'] as List<dynamic>?)
                              ?.map((e) => e as String).toList() ?? [],
    forceOffline         : j['forceOffline']         as bool?   ?? false,
    streamEnabled        : j['streamEnabled']        as bool?   ?? true,
    markdownEnabled      : j['markdownEnabled']      as bool?   ?? true,
    codeHighlightEnabled : j['codeHighlightEnabled'] as bool?   ?? true,
    ttsEnabled           : j['ttsEnabled']           as bool?   ?? false,
    ttsVoice             : j['ttsVoice']             as String? ?? 'id-ID-GadisNeural',
    ttsRate              : (j['ttsRate']             as num?)?.toDouble() ?? 0,
    ttsVolume            : (j['ttsVolume']           as num?)?.toDouble() ?? 0,
    personaName          : j['personaName']          as String? ?? 'KanMon Offline Assistant',
    systemPrompt         : j['systemPrompt']         as String? ?? '',
    chatTemplate         : j['chatTemplate']         as String? ?? 'auto',
  );

  Map<String, dynamic> toJson() => {
    'enabled'              : enabled,
    'activeModelPath'      : activeModelPath,
    'contextSize'          : contextSize,
    'gpuLayers'            : gpuLayers,
    'temperature'          : temperature,
    'topP'                 : topP,
    'topK'                 : topK,
    'minP'                 : minP,
    'tfsZ'                 : tfsZ,
    'typicalP'             : typicalP,
    'repeatPenalty'        : repeatPenalty,
    'repeatLastN'          : repeatLastN,
    'penalizeNl'           : penalizeNl,
    'maxNewTokens'         : maxNewTokens,
    'mirostatMode'         : mirostatMode,
    'mirostatTau'          : mirostatTau,
    'mirostatEta'          : mirostatEta,
    'seed'                 : seed,
    'stopSequences'        : stopSequences,
    'forceOffline'         : forceOffline,
    'streamEnabled'        : streamEnabled,
    'markdownEnabled'      : markdownEnabled,
    'codeHighlightEnabled' : codeHighlightEnabled,
    'ttsEnabled'           : ttsEnabled,
    'ttsVoice'             : ttsVoice,
    'ttsRate'              : ttsRate,
    'ttsVolume'            : ttsVolume,
    'personaName'          : personaName,
    'systemPrompt'         : systemPrompt,
    'chatTemplate'         : chatTemplate,
  };

  OfflineAiConfig copyWith({
    bool?         enabled,
    String?       activeModelPath,
    int?          contextSize,
    int?          gpuLayers,
    double?       temperature,
    double?       topP,
    int?          topK,
    double?       minP,
    double?       tfsZ,
    double?       typicalP,
    double?       repeatPenalty,
    int?          repeatLastN,
    bool?         penalizeNl,
    int?          maxNewTokens,
    int?          mirostatMode,
    double?       mirostatTau,
    double?       mirostatEta,
    int?          seed,
    List<String>? stopSequences,
    bool?         forceOffline,
    bool?         streamEnabled,
    bool?         markdownEnabled,
    bool?         codeHighlightEnabled,
    bool?         ttsEnabled,
    String?       ttsVoice,
    double?       ttsRate,
    double?       ttsVolume,
    String?       personaName,
    String?       systemPrompt,
    String?       chatTemplate,
  }) => OfflineAiConfig(
    enabled              : enabled              ?? this.enabled,
    activeModelPath      : activeModelPath      ?? this.activeModelPath,
    contextSize          : contextSize          ?? this.contextSize,
    gpuLayers            : gpuLayers            ?? this.gpuLayers,
    temperature          : temperature          ?? this.temperature,
    topP                 : topP                 ?? this.topP,
    topK                 : topK                 ?? this.topK,
    minP                 : minP                 ?? this.minP,
    tfsZ                 : tfsZ                 ?? this.tfsZ,
    typicalP             : typicalP             ?? this.typicalP,
    repeatPenalty        : repeatPenalty        ?? this.repeatPenalty,
    repeatLastN          : repeatLastN          ?? this.repeatLastN,
    penalizeNl           : penalizeNl           ?? this.penalizeNl,
    maxNewTokens         : maxNewTokens         ?? this.maxNewTokens,
    mirostatMode         : mirostatMode         ?? this.mirostatMode,
    mirostatTau          : mirostatTau          ?? this.mirostatTau,
    mirostatEta          : mirostatEta          ?? this.mirostatEta,
    seed                 : seed                 ?? this.seed,
    stopSequences        : stopSequences        ?? this.stopSequences,
    forceOffline         : forceOffline         ?? this.forceOffline,
    streamEnabled        : streamEnabled        ?? this.streamEnabled,
    markdownEnabled      : markdownEnabled      ?? this.markdownEnabled,
    codeHighlightEnabled : codeHighlightEnabled ?? this.codeHighlightEnabled,
    ttsEnabled           : ttsEnabled           ?? this.ttsEnabled,
    ttsVoice             : ttsVoice             ?? this.ttsVoice,
    ttsRate              : ttsRate              ?? this.ttsRate,
    ttsVolume            : ttsVolume            ?? this.ttsVolume,
    personaName          : personaName          ?? this.personaName,
    systemPrompt         : systemPrompt         ?? this.systemPrompt,
    chatTemplate         : chatTemplate         ?? this.chatTemplate,
  );
}
