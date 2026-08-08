# XMO release R8 rules.
# Flutter, Firebase, and AndroidX publish their own consumer rules. Keeping all
# of those namespaces would effectively disable shrinking and obfuscation.

# Flutter calls the generated registrant from the embedding.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Native/reflective plugin surfaces used by XMO.
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

-keep class com.walletconnect.** { *; }
-keep class com.reown.** { *; }
-dontwarn com.walletconnect.**
-dontwarn com.reown.**

-keep class com.ryanheise.** { *; }
-dontwarn com.ryanheise.**

-keep class io.flutter.plugins.videoplayer.** { *; }
-keep class com.luck.picture.** { *; }
-dontwarn com.luck.picture.**

-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class io.flutter.plugins.localauth.** { *; }
-keep class io.flutter.plugins.camera.** { *; }

# Preserve metadata used by serializers and reflection-based libraries.
-keepattributes RuntimeVisibleAnnotations,RuntimeInvisibleAnnotations
-keepattributes AnnotationDefault,Signature,InnerClasses,EnclosingMethod

-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
