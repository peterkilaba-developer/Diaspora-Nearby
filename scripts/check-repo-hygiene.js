#!/usr/bin/env node

const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..');

function listTrackedFiles() {
  const output = execFileSync('git', ['ls-files', '-z'], {
    cwd: repoRoot,
    encoding: 'buffer',
  });

  return output
    .toString('utf8')
    .split('\0')
    .filter(Boolean)
    .map((file) => file.replace(/\\/g, '/'));
}

const trackedFiles = listTrackedFiles();
const failures = [];

const forbiddenPathPatterns = [
  { pattern: /(^|\/)\.env($|\.)/, reason: 'environment files must stay local; commit .env.example only' },
  { pattern: /google-services\.json$/i, reason: 'Firebase Android config must be injected outside source control' },
  { pattern: /GoogleService-Info\.plist$/i, reason: 'Firebase iOS config must be injected outside source control' },
  { pattern: /service-account.*\.json$/i, reason: 'service-account keys are production secrets' },
  { pattern: /upload_certificate\.pem$/i, reason: 'signing certificates must not be committed' },
  { pattern: /\.(keystore|jks|p12|mobileprovision)$/i, reason: 'signing material must not be committed' },
  { pattern: /(^|\/)node_modules\//, reason: 'vendor dependency directories must not be committed' },
  { pattern: /(^|\/)(build|coverage|\.dart_tool|\.firebase)\//, reason: 'generated build/cache output must not be committed' },
  { pattern: /(^|\/)(analyze|analysis|output|dump|diff|logcat|web_build|build_log|ferr|final_)[^/]*\.(txt|log)$/i, reason: 'local diagnostic dumps must stay out of the repo' },
  { pattern: /(^|\/)(fix_emojis|fix_debug_emojis|fix_final_line).*$/i, reason: 'one-off repair scripts must stay in scratch or be promoted intentionally' },
];

for (const file of trackedFiles) {
  const absolute = path.join(repoRoot, file);
  if (!fs.existsSync(absolute)) {
    continue;
  }

  if (/\.env\.example$/i.test(file) || /\.env\.[^.]+\.example$/i.test(file)) {
    continue;
  }

  for (const { pattern, reason } of forbiddenPathPatterns) {
    if (pattern.test(file)) {
      failures.push(`${file}: ${reason}`);
      break;
    }
  }
}

const textFileExtensions = new Set([
  '.dart',
  '.js',
  '.json',
  '.md',
  '.yaml',
  '.yml',
  '.html',
  '.css',
  '.xml',
  '.gradle',
  '.kts',
  '.rules',
]);

const suspiciousContentPatterns = [
  { pattern: /-----BEGIN PRIVATE KEY-----/, reason: 'private key block' },
  { pattern: /"private_key"\s*:\s*"-----BEGIN PRIVATE KEY-----/, reason: 'Firebase service-account private key' },
];

for (const file of trackedFiles) {
  const absolute = path.join(repoRoot, file);
  const extension = path.extname(file);

  if (!textFileExtensions.has(extension) || !fs.existsSync(absolute)) {
    continue;
  }

  const stats = fs.statSync(absolute);
  if (stats.size > 1024 * 1024) {
    continue;
  }

  const content = fs.readFileSync(absolute, 'utf8');
  for (const { pattern, reason } of suspiciousContentPatterns) {
    if (pattern.test(content)) {
      failures.push(`${file}: contains ${reason}`);
      break;
    }
  }
}

if (failures.length > 0) {
  console.error('Repository hygiene check failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log(`Repository hygiene check passed (${trackedFiles.length} tracked files scanned).`);
