# upload

Upload cached binaries to S3 remote storage for sharing across team members.

## Usage

```bash
rugby upload [options]
```

## Description

The `upload` command allows you to upload your locally cached Rugby binaries to S3 remote storage. This enables team members to download pre-built binaries using the `warmup` command, significantly speeding up build times.

The command wraps the existing `rugby-s3-uploader.rb` script and provides a native Rugby CLI interface.

## Prerequisites

### Environment Variables

Before using the upload command, you must set the following environment variables:

```bash
export S3_ENDPOINT='s3.eu-west-2.amazonaws.com'
export S3_BUCKET='your-rugby-cache-bucket'
export S3_ACCESS_KEY='your-access-key'
export S3_SECRET_KEY='your-secret-key'
```

### Dependencies

The upload functionality requires the following Ruby gems:

```bash
gem install aws-sdk-s3 parallel
```

For 7zip compression (optional):
```bash
brew install p7zip
```

## Options

### Actions

- `--show`: Show current cached binaries without uploading
- `--refresh-only`: Only refresh the +latest file without uploading to S3

### Upload Options

- `--no-refresh`: Don't refresh +latest file before upload
- `--dry-run`: Show what would be done without making changes
- `--processes N`: Number of parallel upload processes (default: 15)
- `--use-seven-zip`: Use 7zip compression instead of zip (requires 7z command)

### Common Options

- `--output MODE`: Output mode (console, file, both)
- `--log-level LEVEL`: Log level (silent, error, warning, info, verbose)

## Examples

### Basic Upload

Upload all cached binaries to S3:

```bash
rugby upload
```

### Show Cached Binaries

View what binaries are available for upload:

```bash
rugby upload --show
```

### Dry Run

See what would be uploaded without actually uploading:

```bash
rugby upload --dry-run
```

### Upload with 7zip Compression

Use 7zip compression for better compression ratios:

```bash
rugby upload --use-seven-zip
```

### Upload with Custom Process Count

Use more parallel processes for faster uploads:

```bash
rugby upload --processes 20
```

### Refresh Only

Only refresh the +latest file without uploading:

```bash
rugby upload --refresh-only
```

## How It Works

1. **Binary Discovery**: Scans the `~/.rugby/bin` directory for cached binaries
2. **Latest Selection**: For each target/configuration combination, selects the most recently built binary
3. **+latest File**: Creates or updates the `~/.rugby/bin/+latest` file with the list of selected binaries
4. **Compression**: Compresses each binary using zip or 7zip
5. **Upload**: Uploads compressed binaries to S3 in parallel
6. **Cleanup**: Removes temporary compressed files

## Integration with Warmup

The uploaded binaries can be downloaded by team members using:

```bash
rugby warmup your-s3-endpoint.amazonaws.com
```

## Troubleshooting

### Missing Environment Variables

If you see an error about missing S3 configuration, ensure all required environment variables are set:

```bash
echo $S3_ENDPOINT
echo $S3_BUCKET
echo $S3_ACCESS_KEY
echo $S3_SECRET_KEY
```

### Missing Ruby Gems

Install required gems:

```bash
gem install aws-sdk-s3 parallel
```

### 7zip Not Found

If using `--use-seven-zip`, install 7zip:

```bash
brew install p7zip
```

### No Binaries to Upload

If no binaries are found, build some targets first:

```bash
rugby build
```

## See Also

- [`warmup`](warmup.md) - Download remote binaries
- [Remote Cache Guide](../remote-cache.md) - Complete remote caching setup
