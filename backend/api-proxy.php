<?php
/**
 * CourseDeep PHP gateway (optional, for shared hosting).
 * Forwards chat requests to the Supabase edge function in non-streaming mode, so the app
 * can use it as a backup route (kFallbackUrl in app/lib/config.dart).
 * Env vars: SUPABASE_FN_URL (required), APP_SHARED_SECRET (optional)
 */
declare(strict_types=1);
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, x-app-key');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');

function fail(int $code, string $msg) {
    http_response_code($code);
    echo json_encode(['error' => $msg], JSON_UNESCAPED_UNICODE);
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') { http_response_code(204); exit; }
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'GET') { echo json_encode(['ok' => true, 'gateway' => 'php']); exit; }

$fn = getenv('SUPABASE_FN_URL') ?: '';
if ($fn === '') fail(500, 'SUPABASE_FN_URL is not set on the PHP host.');

// tiny per-IP rate limit (40 req/min) using the temp dir — no database needed
$ip   = preg_replace('/[^0-9a-f:.]/i', '', $_SERVER['REMOTE_ADDR'] ?? 'x');
$file = sys_get_temp_dir() . '/cd_rl_' . md5($ip);
$now  = time();
$d    = is_file($file) ? json_decode((string)file_get_contents($file), true) : null;
if (!is_array($d) || ($d['r'] ?? 0) < $now) $d = ['n' => 0, 'r' => $now + 60];
if (++$d['n'] > 40) fail(429, 'Too many requests — please wait a minute.');
@file_put_contents($file, json_encode($d), LOCK_EX);

$raw = file_get_contents('php://input') ?: '';
if (strlen($raw) > 14000000) fail(413, 'Attachments are too large.');
$body = json_decode($raw, true);
if (!is_array($body)) fail(400, 'Invalid JSON body.');
$body['stream'] = false;

$headers = ['Content-Type: application/json'];
$secret = getenv('APP_SHARED_SECRET') ?: '';
if ($secret !== '') $headers[] = 'x-app-key: ' . $secret;

$ch = curl_init($fn);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST           => true,
    CURLOPT_HTTPHEADER     => $headers,
    CURLOPT_POSTFIELDS     => json_encode($body, JSON_UNESCAPED_UNICODE),
    CURLOPT_CONNECTTIMEOUT => 8,
    CURLOPT_TIMEOUT        => 60,
]);
$resp = curl_exec($ch);
$err  = curl_error($ch);
$code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($resp === false) fail(502, 'Upstream unreachable: ' . $err);
http_response_code($code ?: 502);
echo $resp;

