<?php
/**
 * WordPress Emergency Password Reset
 * Silent mode - outputs 1 for success, 0 for failure
 */

// --- CONFIGURATION ---
define('RESET_USERNAME', 'admin');
define('RESET_PASSWORD', 'Admin1#');
// ---------------------

function parse_wp_config($file_path) {
    if (!file_exists($file_path)) {
        return false;
    }

    $content = file_get_contents($file_path);
    $config = [];

    // Regex for constants: define('NAME', 'VALUE');
    $patterns = [
        'db_name' => "/define\s*\(\s*['\"]DB_NAME['\"]\s*,\s*['\"](.*?)['\"]\s*\)\s*;/i",
        'db_user' => "/define\s*\(\s*['\"]DB_USER['\"]\s*,\s*['\"](.*?)['\"]\s*\)\s*;/i",
        'db_password' => "/define\s*\(\s*['\"]DB_PASSWORD['\"]\s*,\s*['\"](.*?)['\"]\s*\)\s*;/i",
        'db_host' => "/define\s*\(\s*['\"]DB_HOST['\"]\s*,\s*['\"](.*?)['\"]\s*\)\s*;/i",
    ];

    foreach ($patterns as $key => $pattern) {
        if (preg_match($pattern, $content, $matches)) {
            $config[$key] = $matches[1];
        }
    }

    // Regex for table prefix: $table_prefix = 'wp_';
    if (preg_match("/\\\$table_prefix\s*=\s*['\"](.*?)['\"]\s*;/i", $content, $matches)) {
        $config['prefix'] = $matches[1];
    } else {
        $config['prefix'] = 'wp_'; // Default
    }

    return $config;
}

try {
    $config = parse_wp_config(__DIR__ . '/wp-config.php');

    if (!$config || !isset($config['db_name'])) {
        die('0');
    }

    $dsn = "mysql:host=" . $config['db_host'] . ";dbname=" . $config['db_name'] . ";charset=utf8mb4";
    $pdo = new PDO($dsn, $config['db_user'], $config['db_password'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);

    $users_table = $config['prefix'] . 'users';
    $new_password_hashed = md5(RESET_PASSWORD);

    // Check if user exists
    $stmt = $pdo->prepare("SELECT ID FROM $users_table WHERE user_login = ?");
    $stmt->execute([RESET_USERNAME]);
    $user = $stmt->fetch();

    if ($user) {
        // Update existing user password
        $stmt = $pdo->prepare("UPDATE $users_table SET user_pass = ? WHERE user_login = ?");
        $stmt->execute([$new_password_hashed, RESET_USERNAME]);
        die('1');
    } else {
        // User doesn't exist
        die('0');
    }
} catch (Exception $e) {
    die('0');
}
