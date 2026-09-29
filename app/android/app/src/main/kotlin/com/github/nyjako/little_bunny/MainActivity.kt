package com.github.nyjako.little_bunny

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) -- local_auth's BiometricPrompt
// needs a FragmentActivity to host its dialog fragment (M7.4, app-lock).
class MainActivity : FlutterFragmentActivity()
