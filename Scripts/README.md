# JWT Generator Script

This script generates Zoom Video SDK JWT tokens from the command line using swift. Please make sure you have swift installed and you can test it out using "swift --version" in your terminal.

## Usage

You can choose to either add the information needed to create the JWT tokens using .env file or through arguments.

### Comment-line with .env variables

In the .env file, ensure that these 4 variables are filled up.

```bash
SESSION_NAME=
ROLE=
SDK_KEY=
SDK_SECRET=
```

To generate JWT Token:

```bash
swift Scripts/JWTGenerator.swift
```

### Command-line with arguments

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
