/**
 * DSP Transfer module.
 * Handles peer-to-peer DSP transfers and corridors.
 * All token transfers use Smart Wallets — no EOA/private key access.
 */
const { functions, admin, db } = require("./shared");

/**
 * Transfers Diaspora (DSP) points between users.
 * Currently updates Firestore ledger. Future: On-chain transfer.
 */
exports.transferDiaspora = functions
  .runWith({ secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
  }

  const fromUserId = context.auth.uid;
  const { toUserId, amount, assetType } = data;
  const type = assetType || 'points'; // Default to points

  if (!toUserId || !amount || amount <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid recipient or amount.');
  }

  try {
    if (type === 'points') {
      // --- POINTS (DSP) TRANSFER LOGIC ---
      await db.runTransaction(async (transaction) => {
        // 1. Get Sender Data
        const fromRef = db.collection('user_points').doc(fromUserId);
        const fromSnap = await transaction.get(fromRef);
        if (!fromSnap.exists) {
          throw new functions.https.HttpsError('not-found', 'Sender wallet not found.');
        }
        const fromData = fromSnap.data();
        const currentBalance = fromData.availablePoints || 0;

        if (currentBalance < amount) {
          throw new functions.https.HttpsError('failed-precondition', 'Insufficient DSP funds.');
        }

        // 2. Get Recipient Data
        const toRef = db.collection('user_points').doc(toUserId);
        const toSnap = await transaction.get(toRef);
        const toData = toSnap ? toSnap.data() : null;

        // 3. Get Country Data for Corridors
        const fromUserDoc = await transaction.get(db.collection('users').doc(fromUserId));
        const toUserDoc = await transaction.get(db.collection('users').doc(toUserId));

        const senderCountry = fromUserDoc.data()?.homeCountryCode || 'XX';
        const receiverCountry = toUserDoc.data()?.homeCountryCode || 'XX';
        const corridorId = `${senderCountry}_${receiverCountry}`;

        // 4. Landing-page contract: DSP transfers carry no user fee or burn.
        const burnAmount = 0;
        const netAmount = amount;

        // 5. Update Balances
        // Deduct full amount from sender (availablePoints only, totalPoints tracks lifetime earned)
        transaction.update(fromRef, {
          availablePoints: admin.firestore.FieldValue.increment(-amount),
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Add net amount to recipient (both totalPoints and availablePoints)
        if (toSnap.exists) {
          transaction.update(toRef, {
            totalPoints: admin.firestore.FieldValue.increment(netAmount),
            availablePoints: admin.firestore.FieldValue.increment(netAmount),
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
          });
        } else {
          transaction.set(toRef, {
            userId: toUserId,
            totalPoints: netAmount,
            availablePoints: netAmount,
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        // 6. Record Internal GDP (Global, Community, Corridor)
        const treasuryRef = db.collection('system_stats').doc('treasury');
        transaction.set(treasuryRef, {
          totalInternalGdp: admin.firestore.FieldValue.increment(amount),
          totalBurnedUtility: admin.firestore.FieldValue.increment(burnAmount),
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        // Update Corridor
        const corridorRef = db.collection('corridors').doc(corridorId);
        transaction.set(corridorRef, {
          id: corridorId,
          senderCountry,
          receiverCountry,
          cumulativeGdp: admin.firestore.FieldValue.increment(amount),
          transactionCount: admin.firestore.FieldValue.increment(1),
          lastTransactionAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        // Update Communities (Home and Host for both if applicable)
        // For simplicity, we track against receiver's Home Country community
        if (receiverCountry !== 'XX') {
          const communityRef = db.collection('communities').doc(`home_country_${receiverCountry.toLowerCase()}`);
          transaction.set(communityRef, {
            cumulativeGdp: admin.firestore.FieldValue.increment(amount),
          }, { merge: true });
        }

        // 7. Log Transaction for SENDER (negative points)
        const senderTxRef = db.collection('points_transactions').doc();
        transaction.set(senderTxRef, {
          userId: fromUserId,
          type: 'transfer',
          action: 'dsp_transfer_sent',
          points: -amount,
          assetType: 'points',
          fromUserId,
          toUserId,
          amount,
          burnAmount,
          netAmount,
          senderCountry,
          receiverCountry,
          corridorId,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          status: 'success',
          metadata: {
            description: `Sent ${amount} DSP`,
            toUserId,
            burnAmount,
          },
        });

        // 8. Log Transaction for RECEIVER (positive points)
        const receiverTxRef = db.collection('points_transactions').doc();
        transaction.set(receiverTxRef, {
          userId: toUserId,
          type: 'transfer',
          action: 'dsp_transfer_received',
          points: netAmount,
          assetType: 'points',
          fromUserId,
          toUserId,
          amount,
          burnAmount,
          netAmount,
          senderCountry,
          receiverCountry,
          corridorId,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          status: 'success',
          metadata: {
            description: `Received ${netAmount} DSP`,
            fromUserId,
            burnAmount,
          },
        });
      });

      return { success: true, message: `Successfully transferred ${amount} DSP.` };

    } else if (type === 'token') {
      // --- TOKEN ($DIASPORA) TRANSFER LOGIC ---
      // All transfers via Smart Wallet (Account Abstraction) — no EOA path.
      const { ethers } = require('ethers');

      // 1. Get Sender and Recipient Info
      const senderUserRef = db.collection('users').doc(fromUserId);
      const senderUserSnap = await senderUserRef.get();

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

      const recipientUserRef = db.collection('users').doc(toUserId);
      const recipientUserSnap = await recipientUserRef.get();

      if (!recipientUserSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Recipient user not found.');
      }

      const toAddress = recipientUserSnap.data().walletAddress;
      if (!toAddress) {
        throw new functions.https.HttpsError('failed-precondition', 'Recipient does not have a wallet address.');
      }

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

          const SMART_WALLET_ABI = [
            "function transferToken(address token, address to, uint256 amount) returns (bool)",
          ];

          const smartWallet = new ethers.Contract(senderWalletAddress, SMART_WALLET_ABI, signer);
          const tokenAmount = ethers.parseEther(amount.toString());

          const tx = await smartWallet.transferToken(tokenContractAddress, toAddress, tokenAmount);
          const receipt = await tx.wait();
          txHash = receipt.hash;
          settlementMode = 'on_chain';
          testReference = null;
          console.log(`[SmartWallet Transfer] Token transfer via smart wallet: ${txHash}`);
        } catch (txError) {
          console.error('[Token Transfer] Blockchain Error:', txError);
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
    throw new functions.https.HttpsError('internal', 'Transfer failed', error);
  }
});

/**
 * Gets the $DIASPORA token balance for a wallet address on-chain.
 * When called with data.walletAddress, reads that address directly (for treasuries).
 * When called without, reads the authenticated user's smart wallet address from Firestore.
 */
exports.getTokenBalance = functions
  .runWith({ secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
  }

  try {
    let walletAddress = data?.walletAddress || null;

    // If no address provided, look up the authenticated user's wallet
    if (!walletAddress) {
      const userId = context.auth.uid;
      const userDoc = await db.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        return { balance: '0', formatted: '0' };
      }
      walletAddress = userDoc.data().walletAddress;
    }

    if (!walletAddress) {
      return { balance: '0', formatted: '0' };
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
    return { balance: '0', formatted: '0', error: error.message };
  }
});

/**
 * Gets all treasury wallet $DIASPORA balances in a single RPC call using Multicall3.
 * Multicall3 (0xcA11bde05977b3631167028862bE2a173976CA11) is deployed on all
 * EVM chains including Base. It batches all balanceOf reads into ONE RPC request,
 * completely avoiding rate-limit issues.
 */
exports.getBatchTokenBalances = functions
  .runWith({ secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
  }

  try {
    // Fail loud on missing config — previously returned `{ balances: {} }`
    // which is indistinguishable from "every treasury has zero balance" and
    // would mask a misconfigured deploy. Treasury balance UI would show all-zero.
    const { assertOnChainConfig } = require('./on_chain_config');
    const { rpcUrl, tokenAddress: tokenContractAddress } = assertOnChainConfig(
      'getBatchTokenBalances',
      ['rpcUrl', 'tokenAddress']
    );

    // 1. Read all governance docs to get wallet addresses
    const govSnap = await db.collection('governance').get();
    const walletMap = {};
    for (const doc of govSnap.docs) {
      const d = doc.data();
      if (d.walletAddress) {
        walletMap[doc.id] = d.walletAddress;
      }
    }

    // Also get the authenticated user's personal wallet
    const userId = context.auth.uid;
    const userDoc = await db.collection('users').doc(userId).get();
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

    // Build ordered list: governance wallets first, then user wallet
    const orderedKeys = Object.keys(walletMap);
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
    return { balances: {}, totalDistributed: '0', error: error.message };
  }
});

