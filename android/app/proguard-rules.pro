# ================================================================ Flutter
# Flutter 引擎自己的规则由 flutter-gradle-plugin 注入，这里只补第三方库的。

# ================================================================ flutter_secure_storage / androidx.security
# androidx.security:security-crypto 依赖 Tink；Tink 的注解（errorprone / javax.annotation）与
# KeysDownloader 依赖的 google-http-client / joda-time 都是 compileOnly，运行时并不存在，
# 不补 dontwarn 会在 minifyRelease 阶段直接失败。
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn com.google.api.client.**
-dontwarn org.joda.time.**

# EncryptedSharedPreferences 通过反射构造 Tink 原语，整包保留（体积约 +1MB，可接受）。
-keep class com.google.crypto.tink.** { *; }
-keep class androidx.security.crypto.** { *; }
-keepclassmembers class androidx.security.crypto.** { *; }
