# Publishing to pub.dev

This document explains how to set up automated publishing to pub.dev using GitHub Actions.

## Setup (One-time)

### 1. Enable Automated Publishing on pub.dev

1. Go to [pub.dev](https://pub.dev)
2. Log in with your Google account
3. Go to your package page: https://pub.dev/packages/zenoh_dart
4. Click on the **Admin** tab
5. Under **Automated publishing**, click **Enable publishing from GitHub Actions**
6. Select your repository: `harunkurtdev/zenoh_dart`
7. Save the settings

### 2. Repository Settings

No secrets are required! pub.dev uses OIDC (OpenID Connect) tokens which are automatically provided by GitHub Actions.

The workflow already has the required permission:
```yaml
permissions:
  id-token: write  # Required for OIDC authentication
```

## How to Publish

### Automatic (Recommended)

1. Update the version in `pubspec.yaml`:
   ```yaml
   version: 0.3.1
   ```

2. Update `CHANGELOG.md` with the new version details

3. Commit and push changes:
   ```bash
   git add .
   git commit -m "chore: prepare release 0.3.1"
   git push
   ```

4. Create and push a tag:
   ```bash
   git tag v0.3.1
   git push origin v0.3.1
   ```

5. The GitHub Action will automatically:
   - Run tests
   - Analyze code
   - Publish to pub.dev

### Manual

You can also trigger the publish workflow manually:

1. Go to **Actions** tab in your GitHub repository
2. Select **Publish to pub.dev** workflow
3. Click **Run workflow**
4. Select the branch and click **Run workflow**

## Versioning Guidelines

Follow [Semantic Versioning](https://semver.org/):

- **MAJOR** (1.0.0): Breaking API changes
- **MINOR** (0.1.0): New features, backward compatible
- **PATCH** (0.0.1): Bug fixes, backward compatible

### Pre-release versions

```bash
git tag v0.3.0-beta.1
git tag v0.3.0-rc.1
```

## Troubleshooting

### "Package validation found potential issue"

Run locally to check:
```bash
dart pub publish --dry-run
```

### "Authentication failed"

1. Ensure automated publishing is enabled on pub.dev
2. Check that the repository name matches exactly
3. Verify the workflow has `id-token: write` permission

### "Version already exists"

You cannot republish the same version. Bump the version number.

## CI/CD Workflow Overview

```
Push to main/master/develop
         │
         ▼
    ┌─────────┐
    │ Analyze │ ← Format check, static analysis
    └────┬────┘
         │
         ▼
    ┌─────────┐
    │  Test   │ ← Unit tests, coverage
    └────┬────┘
         │
         ▼
    ┌─────────┐
    │  Build  │ ← Android, iOS, macOS, Linux, Windows
    └─────────┘

Push tag (v*.*.*)
         │
         ▼
    ┌─────────┐
    │ Publish │ ← Analyze, test, publish to pub.dev
    └─────────┘
```
