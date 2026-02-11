# JWT Generator Script

This script generates Zoom Video SDK JWT tokens from the command line using swift. Please make sure you have swift installed and you can test it out using "swift --version" in your terminal.

## Usage

### Command-line arguments

```bash
swift Scripts/JWTGenerator.swift <sessionName> <role> <sdkKey> <sdkSecret>
```

**Example:**

```bash
swift Scripts/JWTGenerator.swift TestSession12345 1 YourSDKKey YourSDKSecret
```

## Output

The script prints the JWT token to stdout (one line). You can copy it directly and add it under the JWT token field in the sample app project.

## Troubleshooting

If you get permission errors or your terminal just hangs, make sure the script is executable:

```bash
chmod +x Scripts/JWTGenerator.swift
```
