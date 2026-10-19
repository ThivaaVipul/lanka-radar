# flutter_local_notifications keeps scheduled notifications (the holiday
# reminders) as JSON through Gson, which reads its model classes' fields by
# reflection: R8 must not rename or drop them in release builds.
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-keepattributes Signature
