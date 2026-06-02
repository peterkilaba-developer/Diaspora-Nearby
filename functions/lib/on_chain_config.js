/**
 * Centralized on-chain configuration with **fail-loud** semantics.
 *
 * Lesson from 2026-06-02: a missing `secrets: ["BACKEND_SIGNER_PRIVATE_KEY"]`
 * binding on `initializeUserPoints` caused `BACKEND_SIGNER_KEY` to be `null`
 * at module load. The downstream conditional `if (BACKEND_SIGNER_KEY && ...)`
 * silently skipped the entire on-chain distribution. Users got off-chain DSP
 * but no on-chain $DIASPORA, and the function returned 200.
 *
 * This module replaces the silent-skip pattern with explicit assertions:
 *
 *   const cfg = require("./on_chain_config").assertOnChainConfig("welcomeBonus");
 *   const { backendSignerKey, tokenAddress, tgeControllerAddress, walletFactoryAddress, rpcUrl } = cfg;
 *
 * If any required value is missing, `assertOnChainConfig` throws a clear
 * Error naming the missing variable and the calling context. The function
 * fails loudly instead of producing a phantom success.
 *
 * Every Cloud Function that touches on-chain state MUST:
 *   1. Declare `secrets: ["BACKEND_SIGNER_PRIVATE_KEY"]` in its `.runWith({...})`
 *   2. Call `assertOnChainConfig(scopeLabel)` at the top of the on-chain block
 */

const REQUIRED_FIELDS = {
  backendSignerKey: "BACKEND_SIGNER_PRIVATE_KEY",
  tokenAddress: "TOKEN_ADDRESS",
  tgeControllerAddress: "TGE_CONTROLLER_ADDRESS",
  walletFactoryAddress: "WALLET_FACTORY_ADDRESS",
  rpcUrl: "RPC_URL",
};

/**
 * @param {string} scope - human-readable label for error messages
 *   (e.g. "initializeUserPoints/welcomeBonus", "transferDiaspora", "performTGE")
 * @param {string[]} required - subset of keys to require. Defaults to all.
 *   Pass e.g. ["backendSignerKey","tgeControllerAddress","tokenAddress"]
 *   if a function doesn't need the wallet factory.
 * @returns {{backendSignerKey, tokenAddress, tgeControllerAddress, walletFactoryAddress, rpcUrl}}
 * @throws {Error} if any required env var is missing/empty.
 */
function assertOnChainConfig(scope, required = Object.keys(REQUIRED_FIELDS)) {
  const cfg = {};
  const missing = [];
  for (const key of required) {
    const envName = REQUIRED_FIELDS[key];
    if (!envName) throw new Error(`assertOnChainConfig: unknown field "${key}"`);
    const value = process.env[envName];
    if (!value || value.trim() === "") {
      missing.push(envName);
    } else {
      cfg[key] = value;
    }
  }
  if (missing.length > 0) {
    throw new Error(
      `[on_chain_config:${scope}] FAIL-LOUD: missing required env var(s): ` +
        missing.join(", ") +
        ". Did the function declare `.runWith({ secrets: ['BACKEND_SIGNER_PRIVATE_KEY'] })`? " +
        "And is functions/.env present with TOKEN_ADDRESS / TGE_CONTROLLER_ADDRESS / WALLET_FACTORY_ADDRESS / RPC_URL?"
    );
  }
  return cfg;
}

module.exports = { assertOnChainConfig, REQUIRED_FIELDS };
