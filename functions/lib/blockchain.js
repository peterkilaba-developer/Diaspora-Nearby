/**
 * Blockchain query module.
 * Fetches on-chain ERC-20 transfer data using:
 *   1. Blockscout Base API (fast, reliable, free on Base)
 *   2. Direct RPC eth_getLogs as fallback
 */
const { functions, admin, db } = require("./shared");
const { requireAppCheck, requireAuth, consumeRateLimit } = require("./security");

/**
 * Gets ERC-20 Transfer events for a wallet address from the $DIASPORA token contract.
 * Uses Blockscout Base API first, then falls back to RPC.
 *
 * Returns an array of transfer objects sorted by block number descending.
 */
exports.getTokenTransfers = functions
    .runWith({ timeoutSeconds: 60, memory: '256MB' })
    .https.onCall(async (data, context) => {
        requireAppCheck(context);
        const authenticatedUid = requireAuth(context);
        await consumeRateLimit('token-transfers', authenticatedUid, 60, 60 * 60 * 1000);

        try {
            const userId = authenticatedUid;
            let walletAddress = null;

            // Look up user wallet
            const userDoc = await db.collection('users').doc(userId).get();
            if (!userDoc.exists) return { transfers: [] };
            walletAddress = userDoc.data().walletAddress;

            if (!walletAddress) return { transfers: [] };

            const { assertOnChainConfig } = require('./on_chain_config');
            const { tokenAddress: tokenContractAddress } = assertOnChainConfig(
                'getTokenTransfers',
                ['tokenAddress']
            );

            console.log(`[getTokenTransfers] Fetching transfers for ${walletAddress}`);

            // ── Strategy 1: Blockscout Base Explorer API ──
            const explorerTransfers = await fetchFromExplorer(walletAddress, tokenContractAddress);
            if (explorerTransfers !== null) {
                console.log(`[getTokenTransfers] Explorer returned ${explorerTransfers.length} transfers`);
                return { transfers: explorerTransfers, walletAddress };
            }

            // ── Strategy 2: Direct RPC fallback ──
            console.log('[getTokenTransfers] Trying direct RPC approach...');
            const rpcTransfers = await fetchFromRpc(walletAddress, tokenContractAddress);
            console.log(`[getTokenTransfers] RPC returned ${rpcTransfers.length} transfers`);
            return { transfers: rpcTransfers, walletAddress };

        } catch (error) {
            console.error('[getTokenTransfers] Error:', error);
            return { transfers: [], error: error.message };
        }
    });

/**
 * Fetch token transfers using Blockscout Base API.
 * Returns null if the API is unavailable, [] if no transfers found.
 */
async function fetchFromExplorer(walletAddress, tokenContractAddress) {
    try {
        const url = `https://base.blockscout.com/api?module=account&action=tokentx&contractaddress=${tokenContractAddress}&address=${walletAddress}&startblock=0&endblock=99999999&sort=desc`;
        console.log(`[getTokenTransfers] Calling Base Explorer API...`);

        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 10000);

        const response = await fetch(url, {
            signal: controller.signal,
            headers: { 'User-Agent': 'DiasporaNearby/1.0' },
        });
        clearTimeout(timeoutId);

        if (!response.ok) {
            console.warn(`[getTokenTransfers] Explorer API HTTP ${response.status}`);
            return null;
        }

        const json = await response.json();
        const rawList = Array.isArray(json.result) ? json.result : [];

        if (rawList.length === 0) {
            if (json.status === '0' && json.message === 'No transactions found') {
                return [];
            }
            if (json.message === 'OK' || json.status === '1') {
                return [];
            }
            return null;
        }

        const { ethers } = require('ethers');

        return rawList.map(tx => ({
            txHash: tx.hash,
            blockNumber: parseInt(tx.blockNumber),
            timestamp: parseInt(tx.timeStamp) * 1000,
            from: tx.from,
            to: tx.to,
            amount: ethers.formatUnits(tx.value, parseInt(tx.tokenDecimal) || 18),
            direction: tx.to.toLowerCase() === walletAddress.toLowerCase() ? 'in' : 'out',
        }));

    } catch (err) {
        console.warn(`[getTokenTransfers] Explorer exception: ${err.message}`);
        return null;
    }
}

/**
 * Fetch token transfers using direct RPC eth_getLogs.
 * Looks back to contract deployment block.
 */
async function fetchFromRpc(walletAddress, tokenContractAddress) {
    const RPC_URLS = [
        'https://mainnet.base.org',
        'https://1rpc.io/base',
        'https://base-mainnet.public.blastapi.io',
    ];

    const { ethers } = require('ethers');

    // Find a working provider
    let provider = null;
    for (const url of RPC_URLS) {
        try {
            const p = new ethers.JsonRpcProvider(url);
            await Promise.race([
                p.getBlockNumber(),
                new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), 5000)),
            ]);
            provider = p;
            console.log(`[getTokenTransfers] RPC using: ${url}`);
            break;
        } catch (e) {
            console.warn(`[getTokenTransfers] RPC ${url} unavailable: ${e.message}`);
        }
    }

    if (!provider) {
        console.error('[getTokenTransfers] All RPC providers down');
        return [];
    }

    const TRANSFER_TOPIC = ethers.id('Transfer(address,address,uint256)');
    const paddedAddress = ethers.zeroPadValue(walletAddress.toLowerCase(), 32);
    const currentBlock = await provider.getBlockNumber();

    const DEPLOY_BLOCK = 44546025;
    const startBlock = Math.max(DEPLOY_BLOCK, currentBlock - 2000000);
    const CHUNK_SIZE = 5000;
    const MAX_RUNTIME_MS = 25000;
    const startTime = Date.now();

    const allLogs = [];

    for (let from = startBlock; from <= currentBlock; from += CHUNK_SIZE) {
        if (Date.now() - startTime > MAX_RUNTIME_MS) {
            console.log('[getTokenTransfers] RPC time limit reached');
            break;
        }

        const to = Math.min(from + CHUNK_SIZE - 1, currentBlock);
        try {
            const [inLogs, outLogs] = await Promise.all([
                provider.getLogs({
                    address: tokenContractAddress,
                    topics: [TRANSFER_TOPIC, null, paddedAddress],
                    fromBlock: from,
                    toBlock: to,
                }),
                provider.getLogs({
                    address: tokenContractAddress,
                    topics: [TRANSFER_TOPIC, paddedAddress, null],
                    fromBlock: from,
                    toBlock: to,
                }),
            ]);
            for (const l of inLogs) allLogs.push({ ...l, dir: 'in' });
            for (const l of outLogs) allLogs.push({ ...l, dir: 'out' });
        } catch (err) {
            console.warn(`[getTokenTransfers] RPC chunk ${from}-${to} error: ${err.message}`);
        }
    }

    if (allLogs.length === 0) return [];

    const iface = new ethers.Interface([
        'event Transfer(address indexed from, address indexed to, uint256 value)',
    ]);

    const uniqueBlocks = [...new Set(allLogs.map(l => l.blockNumber))];
    const blockTimestamps = {};
    for (let i = 0; i < uniqueBlocks.length; i += 5) {
        const batch = uniqueBlocks.slice(i, i + 5);
        await Promise.all(batch.map(async (bn) => {
            try {
                const block = await provider.getBlock(bn);
                blockTimestamps[bn] = block ? block.timestamp * 1000 : Date.now();
            } catch {
                blockTimestamps[bn] = Date.now();
            }
        }));
    }

    const transfers = [];
    for (const log of allLogs) {
        try {
            const parsed = iface.parseLog({ topics: log.topics, data: log.data });
            transfers.push({
                txHash: log.transactionHash,
                blockNumber: log.blockNumber,
                timestamp: blockTimestamps[log.blockNumber] || Date.now(),
                from: parsed.args[0],
                to: parsed.args[1],
                amount: ethers.formatUnits(parsed.args[2], 18),
                direction: log.dir,
            });
        } catch { }
    }

    transfers.sort((a, b) => b.blockNumber - a.blockNumber);
    return transfers;
}
