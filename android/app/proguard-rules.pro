# Firebase discovers these implementations by class name and reflection.
# Keep only ComponentRegistrar implementations and their public constructors;
# the rest of the application remains eligible for R8 shrinking/obfuscation.
-keep,allowoptimization public class * implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}
