# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Keep all classes that might be accessed via reflection
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider
-keep public class * extends android.app.backup.BackupAgentHelper
-keep public class * extends android.preference.Preference

# Keep - Applications. Keep all application classes
-keep public class * extends android.app.Application {
    public <init>();
    public void onCreate();
}

# Keep - Activities. Keep all activities
-keep public class * extends android.app.Activity {
    public <init>();
    public void onCreate(android.os.Bundle);
}

# Keep - Services. Keep all services
-keep public class * extends android.app.Service {
    public <init>();
    public void onCreate();
}

# Keep - Broadcast receivers. Keep all broadcast receivers
-keep public class * extends android.content.BroadcastReceiver {
    public <init>();
    public void onReceive(android.content.Context, android.content.Intent);
}

# Keep - Content providers. Keep all content providers
-keep public class * extends android.content.ContentProvider {
    public <init>();
    public void onCreate();
}

# Keep - Native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep - Enum classes
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep - Serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep - Parcelable classes
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# Keep - R classes
-keep class **.R$* {
    *;
}

# Keep - View classes and methods
-keep public class * extends android.view.View {
    public <init>(android.content.Context);
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
    public void set*(...);
}

# Keep - WebView classes
-keep class * extends android.webkit.WebViewClient {
    public boolean shouldOverrideUrlLoading(android.webkit.WebView, java.lang.String);
}

# Keep - GSON specific classes
-keep class com.google.gson.** { *; }
-keep class com.google.** { *; }

# Keep - Retrofit specific classes
-keep class retrofit2.** { *; }
-keepclasseswithmembers class * {
    @retrofit2.http.* <methods>;
}

# Keep - OkHttp specific classes
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# Keep - Jackson specific classes
-keep class com.fasterxml.jackson.** { *; }

# Keep - Kotlin specific classes
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }

# Keep - AndroidX specific classes
-keep class androidx.** { *; }

# Keep - Support library specific classes
-keep class android.support.** { *; }

# Keep - Google Play Services specific classes
-keep class com.google.android.gms.** { *; }
-keep interface com.google.android.gms.** { *; }

# Keep - Firebase specific classes
-keep class com.google.firebase.** { *; }
-keep interface com.google.firebase.** { *; }

# Keep - Flutter specific classes
-keep class io.flutter.** { *; }
-keep interface io.flutter.** { *; }

# Keep - Play Core Split Install classes (for dynamic features)
-keep class com.google.android.play.core.** { *; }
-keep interface com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }

# Suppress warnings for Play Core classes (from missing_rules.txt)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
-dontwarn java.lang.reflect.AnnotatedType

# Keep - Method annotations
-keepattributes *Annotation*

# Keep - Source file names and line numbers
-keepattributes SourceFile,LineNumberTable

# Keep - Inner classes
-keepattributes InnerClasses

# Keep - Enclosing method attribute
-keepattributes EnclosingMethod

# Keep - Exceptions
-keepattributes Exceptions

# Keep - Signature attribute for generics
-keepattributes Signature

# Keep - Deprecated methods
-keepattributes Deprecated

# Keep - Synthetic accessor methods
-keepattributes Synthetic

# Keep - Bridge methods
-keepattributes Bridge

# Keep - Varargs
-keepattributes Varargs

# Keep - Local variable table
-keepattributes LocalVariableTable

# Keep - Local variable type table
-keepattributes LocalVariableTypeTable

# Keep - Method parameters
-keepattributes MethodParameters

# Keep - Runtime visible annotations
-keepattributes RuntimeVisibleAnnotations

# Keep - Runtime invisible annotations
-keepattributes RuntimeInvisibleAnnotations

# Keep - Runtime visible parameter annotations
-keepattributes RuntimeVisibleParameterAnnotations

# Keep - Runtime invisible parameter annotations
-keepattributes RuntimeVisibleParameterAnnotations

# Keep - Annotation default values
-keepattributes AnnotationDefault

# Keep - Stack map frames
-keepattributes StackMapTable

# Keep - Throws clauses
-keepattributes Exceptions

# Keep - All constructors
-keepclassmembers class * {
    public <init>();
}

# Keep - All methods with @Keep annotation
-keep @androidx.annotation.Keep class * { *; }
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <methods>;
}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <fields>;
}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <init>(...);
}
