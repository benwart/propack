#!/usr/bin/env node
/**
 * scripts/get-version.js
 * Reads the current version from package.json or calculates the next semantic version
 * based on conventional commits since the latest git tag.
 */

const { execSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const packageJsonPath = path.resolve(__dirname, '..', 'package.json');
const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
const currentVersion = packageJson.version || '0.1.0';

const mode = process.argv[2] || 'current';

if (mode === 'current') {
  process.stdout.write(currentVersion + '\n');
  process.exit(0);
}

if (mode === 'next') {
  try {
    // Find latest tag
    let latestTag = '';
    try {
      latestTag = execSync('git describe --tags --abbrev=0', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
    } catch {
      latestTag = '';
    }

    const logCmd = latestTag ? `git log ${latestTag}..HEAD --pretty=format:"%s%n%b%n---END---"` : 'git log --pretty=format:"%s%n%b%n---END---"';
    const log = execSync(logCmd, { stdio: ['ignore', 'pipe', 'ignore'] }).toString();
    const commits = log.split('---END---').map(c => c.trim()).filter(Boolean);

    let bump = 'none';
    const breakingRegex = /(BREAKING[ -]CHANGE:|^[a-zA-Z]+(?:\([^\)]+\))?!:)/m;
    const featRegex = /^feat(?:\([^\)]+\))?:/im;
    const patchRegex = /^(fix|perf|refactor|docs|style|chore|build|ci)(?:\([^\)]+\))?:/im;

    for (const commit of commits) {
      if (breakingRegex.test(commit)) {
        bump = 'major';
        break;
      } else if (featRegex.test(commit)) {
        if (bump !== 'major') bump = 'minor';
      } else if (patchRegex.test(commit)) {
        if (bump === 'none') bump = 'patch';
      }
    }

    const [major, minor, patch] = currentVersion.split('.').map(n => parseInt(n, 10) || 0);
    let nextVersion = currentVersion;
    if (bump === 'major') {
      nextVersion = `${major + 1}.0.0`;
    } else if (bump === 'minor') {
      nextVersion = `${major}.${minor + 1}.0`;
    } else if (bump === 'patch') {
      nextVersion = `${major}.${minor}.${patch + 1}`;
    }

    process.stdout.write(nextVersion + '\n');
  } catch (err) {
    process.stdout.write(currentVersion + '\n');
  }
}
