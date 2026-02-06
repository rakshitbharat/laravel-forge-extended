# WordPress Password Reset Helper

A lightweight, silent PHP script that resets WordPress admin passwords by directly accessing the database. Perfect for emergency situations when you've lost admin credentials.

## Features

- ✅ **Zero Dependencies**: Parses `wp-config.php` using regex - no WordPress environment needed
- ✅ **Silent Operation**: Returns `1` for success, `0` for failure
- ✅ **Smart Handling**: Updates existing users or creates new admin accounts
- ✅ **Simple Configuration**: Just two constants to set

## Usage

### 1. Upload the Script

Place `wp-password-reset.php` in your WordPress root directory (next to `wp-config.php`).

### 2. Configure Credentials

Edit the constants at the top of the file:

```php
define('RESET_USERNAME', 'admin');      // Username to update/create
define('RESET_PASSWORD', 'Admin1#');    // New password
```

### 3. Run the Script

Access via browser:
```
https://your-site.com/wp-password-reset.php
```

### 4. Check Response

- **`1`** = Success (password updated or user created)
- **`0`** = Failure (config error, DB error, etc.)

### 5. Delete the Script

**CRITICAL**: Remove the script immediately after use:
```bash
rm wp-password-reset.php
```

## How It Works

1. **Parses** `wp-config.php` to extract database credentials
2. **Connects** to MySQL using PDO
3. **Checks** if the username exists in `wp_users`
4. **Updates** password if user exists, **OR**
5. **Creates** new admin user with full capabilities if user doesn't exist
6. **Returns** `1` or `0` based on outcome

## Security Notes

> [!CAUTION]
> This script provides direct database access. Delete it immediately after use.

- Store it temporarily only when needed
- Use strong passwords in the constants
- Never commit this file with real credentials to version control
- Consider IP whitelisting if you need to keep it for development

## Technical Details

- **Password Hashing**: Uses MD5 initially (WordPress auto-upgrades to phpass on first login)
- **Table Prefix**: Automatically detected from `wp-config.php`
- **Admin Capabilities**: New users get full administrator role
- **Error Handling**: All exceptions return `0` silently

## Example Scenarios

**Scenario 1: Reset existing admin password**
```php
define('RESET_USERNAME', 'admin');
define('RESET_PASSWORD', 'NewSecurePass123!');
// Result: admin's password updated → returns 1
```

**Scenario 2: Create emergency admin account**
```php
define('RESET_USERNAME', 'emergency_admin');
define('RESET_PASSWORD', 'TempPass456!');
// Result: new admin user created → returns 1
```

**Scenario 3: Configuration error**
```php
// wp-config.php not found or DB connection fails
// Result: returns 0
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Returns `0` | Check `wp-config.php` exists in same directory |
| Returns `0` | Verify database credentials in `wp-config.php` |
| Returns `0` | Ensure MySQL PDO extension is enabled |
| Blank page | Check PHP error logs for syntax/parsing errors |

## License

Open source - use at your own risk.
