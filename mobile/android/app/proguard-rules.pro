# Flutter / Dart 引擎与插件保留规则
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# 忽略部分库缺失类的告警，避免 R8 失败
-dontwarn org.webrtc.**
-dontwarn org.chromium.**
-dontwarn com.google.android.exoplayer2.**

# 保留注解与签名信息
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations,Signature,InnerClasses,EnclosingMethod

# ===== 应用原生代码：必须保留，否则 MethodChannel / PlatformView 失效 =====
# MainActivity 注册了 epickle/system_proxy、epickle/browser_http 等 4 个通道，
# 以及 StripchatLiveView(PlatformView)、BrowserRenderRequest 等自定义类。
-keep class com.epickle.player.** { *; }
-keep class com.epickle.player.MainActivity { *; }
-keepclassmembers class com.epickle.player.** { *; }