/**
 * DSP Transfer module.
 * Handles peer-to-peer DSP transfers and corridors.
 * All token transfers use Smart Wallets — no EOA/private key access.
 */
const { functions, admin, db } = require("./shared");
const { requireAppCheck, requireAuth, consumeRateLimit } = require("./security");
const { recordCorridorActivity } = require("./corridor_activity");

/**
 * Transfers Diaspora (DSP) points between users.
 * Currently updates Firestore ledger. Future: On-chain transfer.
 */
exports.transferDiaspora = functions
  .runWith({ secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
  requireAppCheck(context);
  const fromUserId = requireAuth(context);
  await consumeRateLimit('asset-transfer', fromUserId, 60, 60 * 60 * 1000);
  const { toUserId, amount, assetType, idempotencyKey } = data || {};
  const type = assetType || 'points'; // Default to points

  if (typeof toUserId !== 'string' || toUserId.length < 1 ||
      toUserId.length > 128 || toUserId === fromUserId ||
      typeof amount !== 'number' || !Number.isSafeInteger(amount) ||
      amount <= 0 || amount > 1000000000 ||
      typeof idempotencyKey !== 'string' ||
      !/^[a-zA-Z0-9_-]{16,128}$/.test(idempotencyKey)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid recipient or amount.');
  }
  const requestRef = db.collection('transfer_requests')
    .doc(`${fromUserId}_${idempotencyKey}`);

  try {
    if (type === 'points') {
      throw new functions.https.HttpsError(
        'permission-denied',
        'DSP points transfers between users are disabled to preserve Proof of Community Trust (PCT) conversion integrity. DSP points are non-transferable earned social capital.',
      );
    }

    if (type === 'token') {
      // --- TOKEN ($DIASPORA) TRANSFER LOGIC ---
      // All transfers via Smart Wallet (Account Abstraction) — no EOA path.
      const { ethers } = require('ethers');

      const senderUserRef = db.collection('users').doc(fromUserId);
      const recipientUserRef = db.collection('users').doc(toUserId);
      const [existingRequest, senderUserSnap, recipientUserSnap] = await db.getAll(
        requestRef,
        senderUserRef,
        recipientUserRef,
      );
      if (existingRequest.exists) {
        if (existingRequest.data().status === 'succeeded') {
          return { success: true, duplicate: true, txHash: existingRequest.data().txHash || null };
        }
        throw new functions.https.HttpsError(
          'already-exists',
          'This transfer is already being processed or requires support review.',
        );
      }

      if (!senderUserSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Sender user not found.');
      }

      const senderData = senderUserSnap.data();
      const senderWalletAddress = senderData.walletAddress;

      if (!senderWalletAddress) {
        throw new functions.https.HttpsError('failed-precondition', 'Sender wallet not initialized.');
      }

      if (senderData.walletType !== 'smart') {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Legacy EOA wallets are no longer supported. Please migrate to a smart wallet first.'
        );
      }

      if (!recipientUserSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Recipient user not found.');
      }

      const toAddress = recipientUserSnap.data().walletAddress;
      if (!toAddress) {
        throw new functions.https.HttpsError('failed-precondition', 'Recipient does not have a wallet address.');
      }

      await requestRef.create({
        userId: fromUserId,
        toUserId,
        amount,
        assetType: type,
        status: 'processing',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      let txHash = null;
      let settlementMode = 'simulated_test';
      let testReference = `test_transfer_${Date.now()}`;
      const rpcUrl = process.env.RPC_URL;
      const tokenContractAddress = process.env.DIASPORA_TOKEN_ADDRESS || process.env.TOKEN_ADDRESS;

      // Fail-loud: previously, if rpcUrl OR tokenContractAddress was missing,
      // this silently dropped into a "simulating" else-branch and recorded the
      // transfer as success=true with no on-chain effect. That risked Firestore
      // showing successful transfers that never moved real tokens.
      const { assertOnChainConfig } = require('./on_chain_config');
      const cfg = assertOnChainConfig('transferDiaspora', [
        'backendSignerKey',
        'walletFactoryAddress',
        'tokenAddress',
        'rpcUrl',
      ]);
      {
        try {
          // ── SMART WALLET TRANSFER ──
          // Use the backend signer to call transferToken on the smart wallet
          const BACKEND_SIGNER_KEY = cfg.backendSignerKey;
          const WALLET_FACTORY_ADDRESS = cfg.walletFactoryAddress;

          const provider = new ethers.JsonRpcProvider(rpcUrl);
          const signer = new ethers.Wallet(BACKEND_SIGNER_KEY, provider);

          const senderCode = await provider.getCode(senderWalletAddress);
          if (!senderCode || senderCode === '0x') {
            if (!senderData.walletPhoneHash) {
              throw new Error('Sender smart wallet is not deployed on-chain and missing walletPhoneHash.');
            }
            console.log(`[SmartWallet Transfer] Deploying pending smart wallet for sender ${fromUserId} (${senderWalletAddress})...`);
            const factory = new ethers.Contract(
              WALLET_FACTORY_ADDRESS,
              ["function createWallet(bytes32 phoneHash) returns (address)"],
              signer
            );
            const deployTx = await factory.createWallet(senderData.walletPhoneHash);
            await deployTx.wait();
            await senderUserRef.set({ walletDeploymentPending: false }, { merge: true });
          }

          const { transferTokenFromSmartWallet } = require('./wallet');
          const tokenAmount = ethers.parseEther(amount.toString());
          const tokenContract = new ethers.Contract(
            tokenContractAddress,
            ["function balanceOf(address account) view returns (uint256)"],
            provider
          );
          const senderBalance = await tokenContract.balanceOf(senderWalletAddress);
          if (senderBalance < tokenAmount) {
            const formattedBal = ethers.formatUnits(senderBalance, 18);
            throw new functions.https.HttpsError(
              'failed-precondition',
              `Insufficient $DIASPORA balance (available: ${formattedBal}, requested: ${amount}).`
            );
          }

          const receipt = await transferTokenFromSmartWallet({
            provider,
            signer,
            walletAddress: senderWalletAddress,
            tokenAddress: tokenContractAddress,
            toAddress,
            amountWei: tokenAmount,
          });
          txHash = receipt.hash;
          settlementMode = 'on_chain';
          testReference = null;
          console.log(`[SmartWallet Transfer] Token transfer via smart wallet: ${txHash}`);
        } catch (txError) {
          console.error('[Token Transfer] Blockchain Error:', txError);
          await requestRef.set({
            status: 'failed',
            error: (txError.message || 'unknown').slice(0, 500),
            failedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true }).catch(() => {});
          if (txError instanceof functions.https.HttpsError) throw txError;
          throw new functions.https.HttpsError('aborted', 'On-chain transaction failed.', txError.message);
        }
      }

      // 4. Log Transactions (one for sender, one for receiver — matches DSP pattern)
      const batch = db.batch();

      // Sender record
      const senderTxRef = db.collection('points_transactions').doc();
      batch.set(senderTxRef, {
        userId: fromUserId,
        type: 'transfer',
        action: 'token_transfer_sent',
        assetType: 'token',
        points: -amount, // negative for display consistency
        fromUserId,
        toUserId,
        fromAddress: senderWalletAddress,
        toAddress,
        amount,
        txHash,
        settlementMode,
        testReference,
        walletType: 'smart',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: 'success',
        metadata: {
          description: `Sent ${amount} $DIASPORA`,
          toUserId,
          settlementMode,
          testReference,
        },
      });

      // Receiver record
      const receiverTxRef = db.collection('points_transactions').doc();
      batch.set(receiverTxRef, {
        userId: toUserId,
        type: 'transfer',
        action: 'token_transfer_received',
        assetType: 'token',
        points: amount,
        fromUserId,
        toUserId,
        fromAddress: senderWalletAddress,
        toAddress,
        amount,
        txHash,
        settlementMode,
        testReference,
        walletType: 'smart',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: 'success',
        metadata: {
          description: `Received ${amount} $DIASPORA`,
          fromUserId,
          settlementMode,
          testReference,
        },
      });
      batch.set(requestRef, {
        status: 'succeeded',
        txHash,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      await batch.commit();

      return {
        success: true,
        message: settlementMode === 'on_chain'
          ? `Successfully transferred ${amount} $DIASPORA.`
          : `Recorded simulated test transfer of ${amount} $DIASPORA.`,
        txHash,
        settlementMode,
        testReference,
      };
    } else {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid asset type. Must be "points" or "token".');
    }

  } catch (error) {
    console.error('Transfer failed:', error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError('internal', 'Transfer failed', error);
  }
});

/**
 * Gets the $DIASPORA token balance for a wallet address on-chain.
 * When called with data.walletAddress, reads that address directly (for treasuries).
 * When called without, reads the authenticated user's smart wallet address from Firestore.
 */
exports.getTokenBalance = functions
  .https.onCall(async (data, context) => {
  requireAppCheck(context);
  const authenticatedUid = requireAuth(context);
  await consumeRateLimit('token-balance', authenticatedUid, 120, 60 * 60 * 1000);

  try {
    let walletAddress = data?.walletAddress || null;

    // If no address provided, look up the authenticated user's wallet
    if (!walletAddress) {
      const userId = authenticatedUid;
      const userDoc = await db.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        return { balance: '0', formatted: '0' };
      }
      walletAddress = userDoc.data().walletAddress;
    }

    if (!walletAddress) {
      return { balance: '0', formatted: '0' };
    }
    if (!/^0x[a-fA-F0-9]{40}$/.test(walletAddress)) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'A valid wallet address is required.',
      );
    }

    // Read on-chain balance. Fail loud if config missing -- previously this
    // returned `{ balance: '0' }` which would mislead a user into thinking
    // they had zero tokens when the function was misconfigured.
    const { assertOnChainConfig } = require('./on_chain_config');
    const { rpcUrl, tokenAddress: tokenContractAddress } = assertOnChainConfig(
      'getTokenBalance',
      ['rpcUrl', 'tokenAddress']
    );

    const { ethers } = require('ethers');
    const provider = new ethers.JsonRpcProvider(rpcUrl);

    const ERC20_ABI = [
      "function balanceOf(address account) view returns (uint256)",
    ];

    const tokenContract = new ethers.Contract(tokenContractAddress, ERC20_ABI, provider);
    const rawBalance = await tokenContract.balanceOf(walletAddress);
    // $DIASPORA uses 18 decimals (standard ERC-20), hardcode to avoid extra RPC call
    const formatted = ethers.formatUnits(rawBalance, 18);

    console.log(`[getTokenBalance] Wallet=${walletAddress}, Balance=${formatted}`);

    return {
      balance: rawBalance.toString(),
      formatted,
      walletAddress,
    };
  } catch (error) {
    console.error('[getTokenBalance] Error:', error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError(
      'unavailable',
      'Token balance is temporarily unavailable.',
    );
  }
});

/**
 * Gets all treasury wallet $DIASPORA balances in a single RPC call using Multicall3.
 * Multicall3 (0xcA11bde05977b3631167028862bE2a173976CA11) is deployed on all
 * EVM chains including Base. It batches all balanceOf reads into ONE RPC request,
 * completely avoiding rate-limit issues.
 */
exports.getBatchTokenBalances = functions
  .https.onCall(async (data, context) => {
  requireAppCheck(context);
  const authenticatedUid = requireAuth(context);
  await consumeRateLimit('batch-token-balances', authenticatedUid, 60, 60 * 60 * 1000);

  try {
    // Fail loud on missing config — previously returned `{ balances: {} }`
    // which is indistinguishable from "every treasury has zero balance" and
    // would mask a misconfigured deploy. Treasury balance UI would show all-zero.
    const { assertOnChainConfig } = require('./on_chain_config');
    const { rpcUrl, tokenAddress: tokenContractAddress } = assertOnChainConfig(
      'getBatchTokenBalances',
      ['rpcUrl', 'tokenAddress']
    );

    // 1. Read only the fixed reserves and the authenticated user's community
    // treasuries. A global governance scan makes this user-facing request
    // progressively slower and more expensive as the network grows.
    const userId = authenticatedUid;
    const userDoc = await db.collection('users').doc(userId).get();
    const memberships = userDoc.exists &&
      Array.isArray(userDoc.data().communityMemberships) ?
      userDoc.data().communityMemberships.slice(0, 50) : [];
    const governanceIds = new Set(['founders', 'liquidity', 'burn', 'global_community']);
    for (const communityId of memberships) {
      if (typeof communityId !== 'string' || communityId.length > 256) continue;
      governanceIds.add(communityId.includes('_') ?
        communityId.substring(communityId.indexOf('_') + 1) : communityId);
    }
    const governanceRefs = [...governanceIds]
      .map((id) => db.collection('governance').doc(id));
    const govDocs = governanceRefs.length > 0 ? await db.getAll(...governanceRefs) : [];
    const walletMap = {};
    for (const doc of govDocs) {
      const d = doc.data();
      if (d && d.walletAddress) {
        walletMap[doc.id] = d.walletAddress;
      }
    }

    // Also get the authenticated user's personal wallet
    const userWallet = userDoc.exists ? userDoc.data().walletAddress : null;

    // 2. Build Multicall3 aggregate call
    const { ethers } = require('ethers');
    const provider = new ethers.JsonRpcProvider(rpcUrl);

    // Multicall3 canonical address (same on every EVM chain)
    const MULTICALL3 = '0xcA11bde05977b3631167028862bE2a173976CA11';
    const multicallAbi = [
      'function aggregate3(tuple(address target, bool allowFailure, bytes callData)[] calls) view returns (tuple(bool success, bytes returnData)[])',
    ];
    const multicall = new ethers.Contract(MULTICALL3, multicallAbi, provider);

    // Encode balanceOf(address) for each wallet
    const erc20Iface = new ethers.Interface(['function balanceOf(address) view returns (uint256)']);

    // Build ordered list: governance wallets first, then user wallet. Ignore
    // malformed legacy addresses instead of failing the entire batch.
    const orderedKeys = Object.keys(walletMap)
      .filter((govId) => ethers.isAddress(walletMap[govId]));
    const calls = orderedKeys.map((govId) => ({
      target: tokenContractAddress,
      allowFailure: true,
      callData: erc20Iface.encodeFunctionData('balanceOf', [walletMap[govId]]),
    }));

    // Append user wallet call if present
    if (userWallet) {
      calls.push({
        target: tokenContractAddress,
        allowFailure: true,
        callData: erc20Iface.encodeFunctionData('balanceOf', [userWallet]),
      });
    }

    // 3. Execute single RPC call — all balances in one request
    const results = await multicall.aggregate3(calls);

    // 4. Parse results
    const balances = {};
    let totalDistributed = 0n;

    for (let i = 0; i < orderedKeys.length; i++) {
      const govId = orderedKeys[i];
      const { success, returnData } = results[i];
      if (success && returnData !== '0x') {
        try {
          const decoded = erc20Iface.decodeFunctionResult('balanceOf', returnData);
          const rawBalance = decoded[0];
          const formatted = ethers.formatUnits(rawBalance, 18);
          balances[govId] = {
            walletAddress: walletMap[govId],
            balance: rawBalance.toString(),
            formatted,
          };
          totalDistributed += rawBalance;
        } catch (decodeErr) {
          console.warn(`[getBatchTokenBalances] Decode error for ${govId}: ${decodeErr.message}`);
          balances[govId] = { walletAddress: walletMap[govId], balance: '0', formatted: '0' };
        }
      } else {
        console.warn(`[getBatchTokenBalances] Multicall failed for ${govId} (${walletMap[govId]})`);
        balances[govId] = { walletAddress: walletMap[govId], balance: '0', formatted: '0' };
      }
    }

    // Parse user wallet result (last element if present)
    let userBalance = '0';
    if (userWallet) {
      const userResult = results[orderedKeys.length];
      if (userResult.success && userResult.returnData !== '0x') {
        try {
          const decoded = erc20Iface.decodeFunctionResult('balanceOf', userResult.returnData);
          const raw = decoded[0];
          userBalance = ethers.formatUnits(raw, 18);
          totalDistributed += raw;
        } catch (e) {
          console.warn(`[getBatchTokenBalances] Decode error for user wallet: ${e.message}`);
        }
      }
    }

    const totalFormatted = ethers.formatUnits(totalDistributed, 18);
    const successCount = Object.values(balances).filter((b) => b.balance !== '0').length;
    console.log(`[getBatchTokenBalances] Multicall3: ${successCount}/${orderedKeys.length} balances. Total: ${totalFormatted}`);

    return {
      balances,
      userBalance,
      totalDistributed: totalFormatted,
    };
  } catch (error) {
    console.error('[getBatchTokenBalances] Error:', error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError(
      'unavailable',
      'Treasury balances are temporarily unavailable.',
    );
  }
});

