<?php
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");

$API_KEY = getenv('AI_API_KEY') ?: '';
$body    = json_decode(file_get_contents('php://input'), true) ?: [];
$msg     = $body['message'] ?? 'hello';

if ($API_KEY === '') {
    http_response_code(500);
    echo json_encode(["error" => "AI_API_KEY not set"]);
    exit;
}

$ch = curl_init('https://api.groq.com/openai/v1/chat/completions');
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST           => true,
    CURLOPT_HTTPHEADER     => [
        "Authorization: Bearer $API_KEY",
        "Content-Type: application/json"
    ],
    CURLOPT_POSTFIELDS => json_encode([
        "model"    => "openai/gpt-oss-120b",
        "messages" => [
            ["role" => "system", "content" => "You are CourseDeep, a helpful AI assistant."],
            ["role" => "user",   "content" => $msg]
        ]
    ])
]);
$resp = curl_exec($ch);
$err  = curl_error($ch);
if ($err) { http_response_code(502); echo json_encode(["error" => $err]); exit; }
echo $resp;
?>