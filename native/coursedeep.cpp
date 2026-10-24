extern "C" {
unsigned long coursedeep_hash(const char* s) {
    unsigned long h = 5381;
    while (*s) h = ((h << 5) + h) + (unsigned char)(*s++);
    return h;
}
const char* coursedeep_version() {
    return "CourseDeep-native-1.0";
}
}
