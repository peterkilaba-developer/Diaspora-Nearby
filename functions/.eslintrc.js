module.exports = {
  root: true,
  env: {
    es2022: true,
    node: true,
  },
  parserOptions: {
    ecmaVersion: 2022,
    sourceType: "script",
  },
  extends: ["eslint:recommended"],
  ignorePatterns: ["node_modules/"],
  rules: {
    // Correctness-focused gate. Style is intentionally not enforced so the
    // gate catches real bugs (undefined vars, unreachable code, dupes)
    // without a mass reformat of the existing codebase.
    "no-unused-vars": ["warn", {args: "none", ignoreRestSiblings: true}],
    "no-empty": ["error", {allowEmptyCatch: true}],
    // `while (true)` pagination loops with explicit breaks are intentional.
    "no-constant-condition": ["error", {checkLoops: false}],
  },
};
