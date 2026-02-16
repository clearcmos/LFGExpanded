# LFGFilter - CI/CD Deployment Guide

This guide explains how to set up automated releases to CurseForge (and optionally WoWInterface/Wago) using GitHub Actions.

## Overview

The recommended tool is [BigWigsMods/packager](https://github.com/marketplace/actions/wow-packager) - a GitHub Action that automatically:
- Packages your addon into a distributable zip
- Detects version from Git tags
- Generates changelogs from commits
- Uploads to CurseForge, WoWInterface, and Wago

## Setup Instructions

### 1. Get Your CurseForge Project ID

1. Go to your addon page on CurseForge
2. Look in the "About Project" section on the right sidebar
3. Find the **Project ID** (a number like `123456`)

### 2. Generate a CurseForge API Token

1. Go to: https://authors-old.curseforge.com/account/api-tokens
2. Click "Generate Token"
3. Copy the token (you won't see it again!)

### 3. Add Secrets to GitHub Repository

1. Go to your repo on GitHub
2. Navigate to **Settings > Secrets and variables > Actions**
3. Add these repository secrets:
   - `CF_API_KEY` - Your CurseForge API token
   - `CURSEFORGE_PROJECT_ID` - Your addon's project ID

### 4. Create the GitHub Actions Workflow

The workflow file is already at `.github/workflows/release.yml`.

### 5. How to Release

1. **Update your version** in `LFGFilter.toc`:
   ```
   ## Version: 1.0.1
   ```

2. **Update CHANGELOG.md** with the new version's changes

3. **Commit your changes**:
   ```bash
   git add .
   git commit -m "chore: bump version to 1.0.1"
   ```

4. **Create and push a tag**:
   ```bash
   git tag v1.0.1
   git push origin main --tags
   ```

5. The GitHub Action will automatically:
   - Package your addon
   - Create a GitHub Release
   - Upload to CurseForge

## Game Version Detection

The packager automatically detects game versions from your `.toc` file's `## Interface:` line:
- `20505` - TBC Classic / Anniversary Edition

## Resources

- [BigWigsMods/packager Documentation](https://github.com/BigWigsMods/packager)
- [WoW Packager GitHub Action](https://github.com/marketplace/actions/wow-packager)
- [CurseForge API Tokens](https://authors-old.curseforge.com/account/api-tokens)
