#!/usr/bin/env node
/** Static regression guard for callable authentication and abuse controls. */
const fs = require("fs");
const path = require("path");

const sourceDirectory = path.join(__dirname, "..", "lib");
const publicCallables = new Map([
  ["requestWhatsAppOtp", {appCheck: true, rateLimit: true}],
  ["verifyWhatsAppOtp", {appCheck: true, rateLimit: true}],
  ["addPlayStoreTester", {appCheck: false, rateLimit: true}],
  ["submitLiquidityInterest", {appCheck: false, rateLimit: true}],
]);
const findings = [];
let audited = 0;

for (const filename of fs.readdirSync(sourceDirectory).filter((name) => name.endsWith(".js"))) {
  const source = fs.readFileSync(path.join(sourceDirectory, filename), "utf8");
  const exports = [...source.matchAll(/^exports\.([A-Za-z0-9_]+)\s*=/gm)];
  exports.forEach((match, index) => {
    const start = match.index;
    const end = index + 1 < exports.length ? exports[index + 1].index : source.length;
    const block = source.slice(start, end);
    if (!block.includes("onCall")) return;
    audited += 1;
    const name = match[1];
    const exception = publicCallables.get(name);
    const hasAppCheck = /\brequireAppCheck\s*\(/.test(block);
    const hasAuthentication = /\brequire(?:Auth|Admin)\s*\(/.test(block);
    const hasRateLimit = /\bconsumeRateLimit\s*\(/.test(block);
    if (exception) {
      if (exception.appCheck && !hasAppCheck) {
        findings.push(`${filename}:${name} is public but lacks App Check`);
      }
      if (exception.rateLimit && !hasRateLimit) {
        findings.push(`${filename}:${name} is public but lacks a persistent quota`);
      }
      return;
    }
    if (!hasAppCheck) findings.push(`${filename}:${name} lacks App Check`);
    if (!hasAuthentication) findings.push(`${filename}:${name} lacks authentication`);
  });
}

if (findings.length) {
  findings.forEach((finding) => console.error(finding));
  process.exitCode = 1;
} else {
  console.log(`Audited ${audited} callable endpoints; required controls are present.`);
}
