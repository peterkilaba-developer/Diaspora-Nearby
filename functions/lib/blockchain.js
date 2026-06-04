/**
 * Blockchain query module.
 * Fetches on-chain ERC-20 transfer data using:
 *   1. Routescan API (etherscan-compatible, free for Base)
 *   2. Direct RPC eth_getLogs with 800-block chunks as fallback
 */
const { functions, admin, db } = require("./shared");

/**
 * Gets ERC-20 Transfer events for a wallet address from the $DIASPORA token contract.
 * Uses Routescan etherscan-compatible API first, then falls back to RPC.
 *
 * Returns an array of transfer objects sorted by block number descending.
 */
exports.getTokenTransfers = functions
    .runWith({ timeoutSeconds: 120, memory: '256MB' })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
        }

        try {
            const userId = context.auth.uid;
            let walletAddress = data?.walletAddress || null;

            // If no address provided, look up user wallet
            if (!walletAddress) {
                const userDoc = await db.collection('users').doc(userId).get();
                if (!userDoc.exists) return { transfers: [] };
                walletAddress = userDoc.data().walletAddress;
            }

            if (!walletAddress) return { transfers: [] };

            // Fail loud on missing config. Previously this returned
            // `{ transfers: [] }`, which is indistinguishable from "user has
            // never transacted" — would mask a misconfigured deploy and make
            // users think they have no transaction history.
            const { assertOnChainConfig } = require('./on_chain_config');
            const { tokenAddress: tokenContractAddress } = assertOnChainConfig(
                'getTokenTransfers',
                ['tokenAddress']
            );

            console.log(`[getTokenTransfers] Fetching transfers for ${walletAddress}`);

            // ── Strategy 1: Routescan API (etherscan-compatible, free for Base) ──
            const routescanTransfers = await fetchFromRoutescan(walletAddress, tokenContractAddress);
            if (routescanTransfers !== null && routescanTransfers.length > 0) {
                console.log(`[getTokenTransfers] Routescan returned ${routescanTransfers.length} transfers`);
                return { transfers: routescanTransfers, walletAddress };
            }

            // ── Strategy 2: Direct RPC with small chunks ──
            // Covers all transfers including internal contract-to-contract transfers
            // that block explorer APIs sometimes miss
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
 * Fetch token transfers using Routescan API (etherscan-compatible, free for Base).
 * Returns null if the API is unavailable, [] if no transfers found.
 */
async function fetchFromRoutescan(walletAddress, tokenContractAddress) {
    try {
        const baseUrl = 'https://api.routescan.io/v2/network/mainnet/evm/8453/etherscan/api';

        const params = new URLSearchParams({
            module: 'account',
            action: 'tokentx',
            contractaddress: tokenContractAddress,
            address: walletAddress,
            page: '1',
            offset: '100',
            startblock: '0',
            endblock: '99999999',
            sort: 'desc',
        });

        const url = `${baseUrl}?${params.toString()}`;
        console.log(`[getTokenTransfers] Calling Routescan API...`);

        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 15000);

        const response = await fetch(url, {
            signal: controller.signal,
            headers: { 'User-Agent': 'DiasporaNearby/1.0' },
        });
        clearTimeout(timeoutId);

        if (!response.ok) {
            console.warn(`[getTokenTransfers] Routescan API HTTP ${response.status}`);
            return null;
        }

        const json = await response.json();
        console.log(`[getTokenTransfers] Routescan status: ${json.status}, message: ${json.message}`);

        if (json.status === '0' && json.message === 'No transactions found') {
            console.log('[getTokenTransfers] Routescan: No transactions found (may be internal transfers)');
            return []; // Valid response — no external token transfers
        }

        if (json.status !== '1' || !Array.isArray(json.result)) {
            console.warn(`[getTokenTransfers] Routescan error: ${json.message}, result: ${JSON.stringify(json.result)}`);
            return null;
        }

        const { ethers } = require('ethers');

        return json.result.map(tx => ({
            txHash: tx.hash,
            blockNumber: parseInt(tx.blockNumber),
            timestamp: parseInt(tx.timeStamp) * 1000,
            from: tx.from,
            to: tx.to,
            amount: ethers.formatUnits(tx.value, parseInt(tx.tokenDecimal) || 18),
            direction: tx.to.toLowerCase() === walletAddress.toLowerCase() ? 'in' : 'out',
        }));

    } catch (err) {
        console.warn(`[getTokenTransfers] Routescan exception: ${err.message}`);
        return null;
    }
}

/**
 * Fetch token transfers using direct RPC eth_getLogs.
 * This catches ALL Transfer events including internal contract calls
 * that block explorer APIs may miss.
 *
 * Uses 800-block chunks to stay under all known RPC provider limits.
 * Looks back ~100k blocks (~4 days on Base).
 */
async function fetchFromRpc(walletAddress, tokenContractAddress) {
    const RPC_URLS = [
        'https://base-mainnet.public.blastapi.io',
        'https://1rpc.io/base',
        'https://mainnet.base.org',
    ];

    const { ethers } = require('ethers');

    // Find a working provider
    let provider = null;
    let providerUrl = '';
    for (const url of RPC_URLS) {
        try {
            const p = new ethers.JsonRpcProvider(url);
            await Promise.race([
                p.getBlockNumber(),
                new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), 5000)),
            ]);
            provider = p;
            providerUrl = url;
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

    // Look back 100k blocks (~4 days on Base at 2s/block)
    // Use 800-block chunks to stay under all RPC limits (some cap at 1k)
    const CHUNK_SIZE = 800;
    const TOTAL_LOOKBACK = 100000;
    const startBlock = Math.max(0, currentBlock - TOTAL_LOOKBACK);
    const MAX_RUNTIME_MS = 100000; // 100s max
    const startTime = Date.now();

    console.log(`[getTokenTransfers] RPC scanning blocks ${startBlock} to ${currentBlock} (${Math.ceil(TOTAL_LOOKBACK / CHUNK_SIZE)} chunks)`);

    const allLogs = [];
    let chunksOk = 0;
    let chunksFail = 0;

    for (let from = startBlock; from <= currentBlock; from += CHUNK_SIZE) {
        // Time guard
        if (Date.now() - startTime > MAX_RUNTIME_MS) {
            console.log(`[getTokenTransfers] Time limit reached after ${chunksOk} chunks`);
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
            chunksOk++;

            // Log progress every 25 chunks
            if (chunksOk % 25 === 0) {
                console.log(`[getTokenTransfers] Progress: ${chunksOk} chunks done, ${allLogs.length} logs found, block ${to}`);
            }
        } catch (err) {
            chunksFail++;
            // If too many consecutive failures, try switching provider
            if (chunksFail > 5 && chunksFail % 5 === 0) {
                console.warn(`[getTokenTransfers] ${chunksFail} chunk failures, may need different provider`);
            }
        }

        // Small delay between chunks to avoid rate limiting (100ms)
        await new Promise(r => setTimeout(r, 100));
    }

    console.log(`[getTokenTransfers] RPC scan done: ${chunksOk} ok, ${chunksFail} failed, ${allLogs.length} logs found`);

    if (allLogs.length === 0) return [];

    const iface = new ethers.Interface([
        'event Transfer(address indexed from, address indexed to, uint256 value)',
    ]);

    // Batch-fetch timestamps for unique blocks (5 at a time)
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
