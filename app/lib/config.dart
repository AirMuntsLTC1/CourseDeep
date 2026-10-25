
// Live Supabase Edge Function endpoint (streams answers).
const String kBackendUrl = 'https://zbwmmmstzlgjmhhoceiv.supabase.co/functions/v1/coursedeep-ai';

// Login (six-digit email code) endpoint.
const String kEmailCodeUrl = 'https://zbwmmmstzlgjmhhoceiv.supabase.co/functions/v1/email-code';

// Optional backup route: your PHP gateway (backend/api-proxy.php). Leave '' to disable.
const String kFallbackUrl = '';

// Optional: same value as the APP_SHARED_SECRET Supabase secret. Leave '' if you did not set one.
const String kAppKey = '';

// Shown in Settings and compared with the latest GitHub release.
// Injected by the GitHub build (pubspec version + build number, e.g. 2.1.0.4).
const String kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '2.3.0.7');
const String kReleasesApi = 'https://api.github.com/repos/AirMuntsLTC1/CourseDeep/releases/latest';
const String kReleasesPage = 'https://github.com/AirMuntsLTC1/CourseDeep/releases';
