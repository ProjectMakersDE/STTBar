## [1.2.2](https://github.com/ProjectMakersDE/STTBar/compare/v1.2.1...v1.2.2) (2026-07-24)

### Bug Fixes

* **audio:** survive input device changes after sleep or display swaps ([88ad476](https://github.com/ProjectMakersDE/STTBar/commit/88ad4761dec433651958c4a8f639d3a6030f4edf))
* **core:** resolve confirmed findings from full-app review ([702a731](https://github.com/ProjectMakersDE/STTBar/commit/702a7311fe739561fd062d0410e3f97d8a3091e1))
* **core:** resolve second batch of verified review findings ([e03820c](https://github.com/ProjectMakersDE/STTBar/commit/e03820c7b1020f23e37fb71fe5575407079d95a2))
* **paste,hud:** unblock the main thread during paste and surface the LLM phase ([c53b54c](https://github.com/ProjectMakersDE/STTBar/commit/c53b54c37e3e539108d8111742af9ba98d2d0a78))

## [1.2.1](https://github.com/ProjectMakersDE/STTBar/compare/v1.2.0...v1.2.1) (2026-07-11)

### Bug Fixes

* **paste:** wait for held hotkey modifiers before injecting text ([1c8e00e](https://github.com/ProjectMakersDE/STTBar/commit/1c8e00e01eff47a4f2b7a0fc3add10c939b2dbab))

## [1.2.0](https://github.com/ProjectMakersDE/STTBar/compare/v1.1.3...v1.2.0) (2026-06-25)

### Features

* **app-store:** add privacy manifest, drop unused Apple Events + dead UI for 1.0 ([369b799](https://github.com/ProjectMakersDE/STTBar/commit/369b799692b84e0d0ebda30343471ccfc12e6046))
* **app-store:** add WhisperKit 1.0.0 (MIT) dependency for local transcription ([16718ab](https://github.com/ProjectMakersDE/STTBar/commit/16718ab19e7ef8d986394ee4c86f0fafadcdcb58))
* **app-store:** declare ITSAppUsesNonExemptEncryption=false ([8a50311](https://github.com/ProjectMakersDE/STTBar/commit/8a50311de835a8067f3fd1a74483b083c44e0d95))
* **app-store:** drive transcription via a backend seam, drop shell spawning in SttRunner ([4d2da08](https://github.com/ProjectMakersDE/STTBar/commit/4d2da08295fbfb490567ac71c2a69d8b7dbd64e8))
* **app-store:** enable app-sandbox and network.client entitlements ([c21ef02](https://github.com/ProjectMakersDE/STTBar/commit/c21ef026d6ba9b45ae9bdbdc927be7322b0a5f08))
* **app-store:** local WhisperKit transcription via Transcriber abstraction, routed by source ([bd4efa7](https://github.com/ProjectMakersDE/STTBar/commit/bd4efa7211e1b4cc82ca4eddffe8fef8c1cf9c34))
* **app-store:** move runtime files into the sandbox container ([3322b2b](https://github.com/ProjectMakersDE/STTBar/commit/3322b2bc2b0feba3eec9b6978b008e7271346f6a))
* **app-store:** native record/transcribe/cleanup pipeline (WhisperClient, LLMClient, AudioRecorder, NativeBackend) ([ed3f681](https://github.com/ProjectMakersDE/STTBar/commit/ed3f6817bad6e3bd6adb670d926c7065db85d8b0))
* **app-store:** Phase 3 settings UI — source picker, local model controls + RAM hint, self-host guide, acknowledgements ([30768d9](https://github.com/ProjectMakersDE/STTBar/commit/30768d94ba68060fc65e72aa97f429c83cc5142a))
* **app-store:** remove in-app self-updater and its UI (App Store handles updates) ([64ac46a](https://github.com/ProjectMakersDE/STTBar/commit/64ac46ab534a32fa0fad627efdd9d4bb10bca359))
* **app-store:** remove remaining shell spawns from settings + health checks ([1621904](https://github.com/ProjectMakersDE/STTBar/commit/16219040b01310afa4f81a0e343b57c014774c93))
* **app-store:** replace LaunchAgent plist with SMAppService login item ([580724f](https://github.com/ProjectMakersDE/STTBar/commit/580724f890be0b7d7ebfd21d26904c05e23ca2e1))
* **app-store:** staged paste (AX direct -> Unicode typing -> clipboard fallback with save/restore) ([7eb2b04](https://github.com/ProjectMakersDE/STTBar/commit/7eb2b046933022f138462e8ee6301a27475ca351))
* **app-store:** wire NativeBackend into the app, snapshot replacements in config, request microphone ([a7b78e4](https://github.com/ProjectMakersDE/STTBar/commit/a7b78e4b2b2aca9078e28413d4a875e59eba5f9a))
* **hud,audio:** audio input picker + HUD placement/size/element controls + waveform styles ([7e35238](https://github.com/ProjectMakersDE/STTBar/commit/7e35238db8284e3571e52b678b43bc0ecbcded00))
* **onboarding:** first-run setup wizard with self-heal gating ([10df328](https://github.com/ProjectMakersDE/STTBar/commit/10df3287a0b794772fe8797610f323ccc9199a0c))

### Bug Fixes

* **app-store:** apply entitlements in dev + ad-hoc signing so the sandbox engages locally ([32e1c89](https://github.com/ProjectMakersDE/STTBar/commit/32e1c8970577d4aaea995e5063a6712ec5afb49d))
* **app-store:** store config in the sandbox container, not ~/.local/share/stt ([79791ef](https://github.com/ProjectMakersDE/STTBar/commit/79791efe1ba0a4ab061830def7e721595c7fb0a8))
* **hotkey:** capture space-based chords in the recorder ([058d474](https://github.com/ProjectMakersDE/STTBar/commit/058d474c436e62035047e84719b26bb8fad3efe0))

## [1.1.3](https://github.com/ProjectMakersDE/STTBar/compare/v1.1.2...v1.1.3) (2026-06-20)

### Bug Fixes

* **update:** keep macOS permissions stable across in-app updates ([1eafd51](https://github.com/ProjectMakersDE/STTBar/commit/1eafd51fb2c194692601e576af2b3ad00ccfc9c0))

## [1.1.2](https://github.com/ProjectMakersDE/STTBar/compare/v1.1.1...v1.1.2) (2026-06-20)

### Bug Fixes

* **hotkey:** make start/stop a single authoritative state machine ([69648d3](https://github.com/ProjectMakersDE/STTBar/commit/69648d338d6b218f4c1c0b44d9b74691e468cae2))

## [1.1.1](https://github.com/ProjectMakersDE/STTBar/compare/v1.1.0...v1.1.1) (2026-06-18)

### Bug Fixes

* **release:** sign + notarize releases with Developer ID ([3a04258](https://github.com/ProjectMakersDE/STTBar/commit/3a042584ea6ec425984243cc047b445a17959aa4))

## [1.1.0](https://github.com/ProjectMakersDE/STTBar/compare/v1.0.0...v1.1.0) (2026-06-18)

### Features

* **macos:** in-app updater + localized settings, language picker, footer & links ([b40a552](https://github.com/ProjectMakersDE/STTBar/commit/b40a5528c4b418abac26d2d43ea5f31ba24a32f3))
* **macos:** live language switching + single-instance guard ([fa84986](https://github.com/ProjectMakersDE/STTBar/commit/fa84986fc361dfe3d5ef3d6e67ae1d8ce32f1cc6))
* **macos:** localize menu bar + SttMode labels, add DE/EN submenu ([dc9ca39](https://github.com/ProjectMakersDE/STTBar/commit/dc9ca3910f39698a178354f336344a315d68b5ef))
* **macos:** localize prompt editor, status window, windows and diagnostics ([9df897f](https://github.com/ProjectMakersDE/STTBar/commit/9df897ffc967b0f6d337f0e9e4eb0680b49ca328))
* **macos:** parse release assets and track update state ([fd4c1b4](https://github.com/ProjectMakersDE/STTBar/commit/fd4c1b48b806cb3e13623312451f5a64223dc547))
* **macos:** runtime DE/EN localization core + language coupling ([c28c192](https://github.com/ProjectMakersDE/STTBar/commit/c28c1926c7ed532d225ee39af8155ddab39b42a6))

## 1.0.0 (2026-06-18)

### Features

* add audio recording helper using sox ([32582ee](https://github.com/ProjectMakersDE/STTBar/commit/32582ee5ff99e031f49cd10166891800bc8df0ae))
* add configurable STT postprocessing ([20d6f58](https://github.com/ProjectMakersDE/STTBar/commit/20d6f58969a8f2354b3bfe42952b99b38662dc80))
* add docker-compose for speaches whisper server (CUDA) ([0da5bb2](https://github.com/ProjectMakersDE/STTBar/commit/0da5bb29f83528bbdd86e29aea0660e4663efd51))
* add install/uninstall script ([c29dc84](https://github.com/ProjectMakersDE/STTBar/commit/c29dc8429922313c6971270f1aae4089e2260a88))
* add STT_MODEL_TTL to keep whisper model in VRAM ([b3cc408](https://github.com/ProjectMakersDE/STTBar/commit/b3cc408444edc80be05427b64dd4796662a0c682))
* add system-wide STT toggle script for X11 ([cd92b94](https://github.com/ProjectMakersDE/STTBar/commit/cd92b94a740832d32bd6b32b67ea0359a62e6649))
* add transcription helper using curl/jq ([bae6b9d](https://github.com/ProjectMakersDE/STTBar/commit/bae6b9d3fb2e78ced1e9a459a518d97d81039691))
* add ZSH plugin with ZLE widget for speech-to-text ([286e002](https://github.com/ProjectMakersDE/STTBar/commit/286e00252c97c528fb8c6c6ddb40fb0429e60b69))
* install global STT hotkey with GNOME shortcut support ([70a5168](https://github.com/ProjectMakersDE/STTBar/commit/70a51684148c0cd1862ff4e06adc8d26c70c9bc5))
* **macos:** add Hammerspoon STT HUD ([773b40c](https://github.com/ProjectMakersDE/STTBar/commit/773b40c32bc21d9bcf43650cfa61e470373b8315))
* **macos:** audio levels, HUD anchors, hotkey + settings model ([9e15348](https://github.com/ProjectMakersDE/STTBar/commit/9e153483a862639287965215c9357c5a54b435f9))
* **macos:** configurable HUD background color+alpha, per-state left icon ([61ae15c](https://github.com/ProjectMakersDE/STTBar/commit/61ae15ce5ebbaff78fc7082543fea1ddc4fb8fb9))
* **macos:** EnvStore for comment-preserving .env edits ([6efa445](https://github.com/ProjectMakersDE/STTBar/commit/6efa4457186cadebd875c30e13fd55c3ce27b853))
* **macos:** hotkey manager, STT runner, menu bar wiring ([44502e4](https://github.com/ProjectMakersDE/STTBar/commit/44502e4574957c2c093adc0046c9388e568e737a))
* **macos:** install STTBar.app + LaunchAgent, stand Hammerspoon down ([25d7a60](https://github.com/ProjectMakersDE/STTBar/commit/25d7a60709d0426e218b686ac6a39587927d38a9))
* **macos:** native HUD overlay (waveform + spinner + anchors) ([127a1ac](https://github.com/ProjectMakersDE/STTBar/commit/127a1ac15ae720f9bb8cc86143c7122a8b14d468))
* **macos:** PromptStore with active-prompt.txt mirroring ([8dac1fa](https://github.com/ProjectMakersDE/STTBar/commit/8dac1fa6aeaaea2a5d39d4e8eed99730a03136b0))
* **macos:** scaffold STTBar SwiftPM executable ([e72b345](https://github.com/ProjectMakersDE/STTBar/commit/e72b345b9fa69f5fe2afdc0138f363ee4144a426))
* **macos:** SwiftUI settings, prompt editor, hotkey recorder ([35537d2](https://github.com/ProjectMakersDE/STTBar/commit/35537d2ed7da879b0a3c259e8a53c152c1aef0fb))
* **postprocess:** agent-optimized German cleanup prompt ([952810f](https://github.com/ProjectMakersDE/STTBar/commit/952810f22f6082d711449416c2e85dbbf27b374a))
* **postprocess:** read prompt from STT_POSTPROCESS_PROMPT_FILE ([e9ceb6e](https://github.com/ProjectMakersDE/STTBar/commit/e9ceb6e30535923ca60816ecabc284851d515fcd))
* **release:** prepare STTBar public release ([64333c7](https://github.com/ProjectMakersDE/STTBar/commit/64333c7391ee83580227154f0fbf8497892e0636))
* **stt:** raw/english hotkey modes + softer cleanup prompt ([7258b42](https://github.com/ProjectMakersDE/STTBar/commit/7258b42182f96d4d6d46c1e486b4190a2ed22b14))
* system-wide STT hotkey + whisper model persistence ([3cd5d84](https://github.com/ProjectMakersDE/STTBar/commit/3cd5d84f4a3fd3156d8916d6bb9af04dd25f5429))

### Bug Fixes

* address code review issues — file handoff, error handling, portability ([3a9f28a](https://github.com/ProjectMakersDE/STTBar/commit/3a9f28ab404ec3e7fd3474a506cf3a1031df4bd1))
* handle "auto" language by omitting parameter for auto-detection ([121a165](https://github.com/ProjectMakersDE/STTBar/commit/121a1659aa0f6e01ace29921945817837f97aaaa))
* **macos:** avoid bluetooth headset audio switch ([092e014](https://github.com/ProjectMakersDE/STTBar/commit/092e014036e520b825f63ad1a0a71e77937d9dd1))
* **macos:** install STTBar.app to /Applications when writable ([debe718](https://github.com/ProjectMakersDE/STTBar/commit/debe71836ed5a4742d4347a8585908fe72ef28f0))
* **macos:** move English STT mode to Shift+Option+Space ([262411c](https://github.com/ProjectMakersDE/STTBar/commit/262411c7f0ca2ff64f136f2bebda4cfc89dc1f84))
* **macos:** per-permission buttons + non-fatal paste fallback ([bb5f318](https://github.com/ProjectMakersDE/STTBar/commit/bb5f318da7714e191d25c401a771c2cec34aee0a))
* preload whisper model on container start + configurable port ([dcd2721](https://github.com/ProjectMakersDE/STTBar/commit/dcd2721d338dfdb1f391e25dddb63313ea4e1c76))
* **stt:** raw mode actually skips the LLM ([deeb412](https://github.com/ProjectMakersDE/STTBar/commit/deeb4124df76a822e7cff204580604bd9c0a2f2b))
* use clipboard paste (ctrl+v) for faster text injection ([33aa814](https://github.com/ProjectMakersDE/STTBar/commit/33aa81489cc6e069d68cfd76dd4c51de33590165))
* use xdotool type instead of clipboard paste for text injection ([22215a1](https://github.com/ProjectMakersDE/STTBar/commit/22215a18e7e312e7574d1d4c2a3db3e3196ff9f0))
