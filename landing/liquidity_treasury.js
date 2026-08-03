// ═══ LIQUIDITY TREASURY DATA MODEL ═══
const BASE_PRICE_USD = 0.001;
const CONVERSION_RATES = [100,90,80,70,60,50,40,30,20,10];
const EPOCH_MILESTONES = [
  { epoch:1, users:100 },
  { epoch:2, users:1000 },
  { epoch:3, users:10000 },
  { epoch:4, users:100000 },
  { epoch:5, users:1e6 },
  { epoch:6, users:1e7 },
  { epoch:7, users:1e8 },
  { epoch:8, users:1e9 },
  { epoch:9, users:1e10 },
  { epoch:10, users:1e11 }
];

// Each epoch's total supply = 10^(epoch+5) so Epoch 1 = 1M, Epoch 2 = 10M, etc.
// Liquidity Treasury allocation = 5% of total supply → per epoch = 10^(epoch+4)
// Per TGE = per epoch / 10 = 10^(epoch+3)
function treasuryPerTge(epoch){ return Math.pow(10, epoch+3); }
function treasuryPerEpoch(epoch){ return treasuryPerTge(epoch)*10; }

// ═══ VALUATION ENGINE (mirrors Dart ValuationService exactly) ═══
function calculateImpliedValue({totalUsers=0, totalMinted=0, totalBurned=0, currentEpoch=1, fiatGdpUsd=0, circulatingSupply=0}={}){
  const networkMultiplier = totalUsers > 0 ? Math.log10(Math.max(totalUsers,1)) / 10 : 0;
  const rawDeflation = totalMinted > 0 ? totalBurned / totalMinted : 0;
  const deflationRatio = Math.min(rawDeflation, 0.5);
  const epochScarcity = 1.0 + (Math.max(currentEpoch,1) * 0.1);
  const networkBaseline = BASE_PRICE_USD * (1.0 + networkMultiplier + deflationRatio) * epochScarcity;

  const effectiveCirculating = circulatingSupply > 0 ? circulatingSupply : Math.max(totalMinted - totalBurned, 0);
  const gdpFloorPerToken = (effectiveCirculating > 0 && fiatGdpUsd > 0) ? (fiatGdpUsd / effectiveCirculating) : 0;

  const impliedValue = networkBaseline + gdpFloorPerToken;
  const fiatGdpBoost = networkBaseline > 0 ? 1.0 + (gdpFloorPerToken / networkBaseline) : 1.0;

  return { impliedValue, networkBaseline, gdpFloorPerToken, networkMultiplier, deflationRatio, epochScarcity, fiatGdpBoost,
           totalUsers, totalMinted, totalBurned, currentEpoch, fiatGdpUsd };
}

// ═══ LIVE DATA STATE ═══
let liveData = { totalUsers:0, totalMinted:0, totalBurned:0, currentEpoch:1, fiatGdpUsd:0 };
let liveValuation = calculateImpliedValue(liveData);
let trajectoryPoints = []; // {epoch, impliedValue} pairs for chart
let projectedTrajectoryPoints = []; // {epoch, impliedValue} for $10k GDP projection

// ═══ FORMATTERS ═══
function fmtUsd(n){
  if(n>=1e12) return '$'+(n/1e12).toFixed(1)+'T';
  if(n>=1e9) return '$'+(n/1e9).toFixed(1)+'B';
  if(n>=1e6) return '$'+(n/1e6).toFixed(1)+'M';
  if(n>=1e3) return '$'+(n/1e3).toFixed(n>=1e4?0:1)+'K';
  if(n>=1) return '$'+n.toFixed(0);
  if(n>=0.01) return '$'+n.toFixed(2);
  return '$'+n.toFixed(5);
}
function fmtDsp(n){
  if(n>=1e12) return (n/1e12).toFixed(0)+'T';
  if(n>=1e9) return (n/1e9).toFixed(0)+'B';
  if(n>=1e6) return (n/1e6).toFixed(0)+'M';
  if(n>=1e3) return (n/1e3).toFixed(0)+'K';
  return n.toLocaleString();
}
function fmtPrice(v){
  if(v<0.01) return '$'+v.toFixed(5);
  if(v<1) return '$'+v.toFixed(4);
  return '$'+v.toFixed(2);
}

// ═══ COMPUTE TRAJECTORY (implied value at each epoch milestone) ═══
function computeTrajectory(){
  trajectoryPoints = [];
  projectedTrajectoryPoints = [];
  for(let e=1; e<=10; e++){
    const m = EPOCH_MILESTONES[e-1];
    const totalSupplyAtEpoch = Math.pow(10, e+5);
    const burnRate = 0.05;
    
    // Baseline Projection
    const fiatGdp = e === 1 ? Math.max(liveData.fiatGdpUsd, 100) : Math.pow(10, e+1) * 50;
    const val = calculateImpliedValue({
      totalUsers: m.users,
      totalMinted: totalSupplyAtEpoch,
      totalBurned: Math.floor(totalSupplyAtEpoch * burnRate * Math.min(e/5, 1)),
      currentEpoch: e,
      fiatGdpUsd: fiatGdp
    });
    trajectoryPoints.push({ epoch:e, impliedValue:val.impliedValue, users:m.users });

    // Fundamental Price Floor Projection (Network Baseline + GDP / DEX Liquidity Treasury Supply)
    const circulatingSupply = treasuryPerEpoch(e);
    const projectedGdp = 10000 * Math.pow(10, e-1); // $10k starting GDP for Epoch 1 scaling 10x
    const baselineVal = BASE_PRICE_USD * (1.0 + Math.log10(m.users)/10) * (1.0 + (e*0.1));
    const combinedPriceFloor = baselineVal + (projectedGdp / circulatingSupply);
    projectedTrajectoryPoints.push({
      epoch: e,
      impliedValue: combinedPriceFloor,
      users: m.users,
      gdp: projectedGdp,
      circulating: circulatingSupply,
      baseline: baselineVal,
      gdpFloor: projectedGdp / circulatingSupply
    });
  }
  if(liveValuation.impliedValue > 0){
    trajectoryPoints[0].impliedValue = liveValuation.impliedValue;
    trajectoryPoints[0].isLive = true;
    
    // For the projected floor, we just want to show the pure math, so we don't override with live price
  }
}

// ═══ UPDATE ALL DYNAMIC ELEMENTS ═══
function updateDynamicPricing(){
  liveValuation = calculateImpliedValue(liveData);
  computeTrajectory();

  const liveEl = document.getElementById('live-dsp-price');
  if(liveEl) liveEl.textContent = fmtPrice(liveValuation.impliedValue);

  setTextById('factor-network', (liveValuation.networkMultiplier*100).toFixed(1)+'%');
  setTextById('factor-deflation', (liveValuation.deflationRatio*100).toFixed(1)+'%');
  setTextById('factor-epoch', liveValuation.epochScarcity.toFixed(2)+'×');
  setTextById('factor-gdp', '+' + fmtPrice(liveValuation.gdpFloorPerToken));
  setTextById('factor-users', liveData.totalUsers.toLocaleString());
  setTextById('factor-minted', fmtDsp(liveData.totalMinted));
  setTextById('factor-burned', fmtDsp(liveData.totalBurned));

  for(let e=1; e<=10; e++){
    const epVal = trajectoryPoints[e-1]?.impliedValue || liveValuation.impliedValue;
    const perTge = treasuryPerTge(e);
    const perEpoch = treasuryPerEpoch(e);
    const tgeCost = perTge * epVal;
    const epochCost = perEpoch * epVal;

    setTextById(`ep${e}-total-dsp`, fmtDsp(perEpoch)+' DSP');
    setTextById(`ep${e}-total-cost`, fmtUsd(epochCost)+' total');

    const avgConv = 55;
    const effectiveDspEpoch = Math.round(perEpoch * (avgConv/100));
    setTextById(`ep${e}-full-conv`, `All 10 TDEs • Avg ${avgConv}% conversion • ${fmtDsp(effectiveDspEpoch)} effective DSP`);
    setTextById(`ep${e}-full-price`, fmtUsd(epochCost));

    for(let t=1; t<=10; t++){
      const conv = CONVERSION_RATES[t-1];
      const effectiveDsp = Math.round(perTge * (conv/100));
      setTextById(`ep${e}-tge${t}-alloc`, fmtDsp(perTge));
      setTextById(`ep${e}-tge${t}-eff`, fmtDsp(effectiveDsp));
      setTextById(`ep${e}-tge${t}-price`, fmtUsd(tgeCost));
    }
  }
  drawChart('trajectory-canvas', trajectoryPoints, 'Implied DSP Value (log scale)');
  drawChart('projected-trajectory-canvas', projectedTrajectoryPoints, '$DIASPORA Price Floor (log scale)');
  buildPriceFloorTable();
}

function setTextById(id, text){
  const el = document.getElementById(id);
  if(el) el.textContent = text;
}

// ═══ BUILD CONVERSION BARS ═══
function buildConversionBars(){
  const c=document.getElementById('conversion-bars');
  if(!c) return;
  CONVERSION_RATES.forEach((r,i)=>{
    const bar=document.createElement('div');
    bar.className='conv-bar-item';
    bar.innerHTML=`<span class="conv-bar-label">TDE ${i+1}</span><div class="conv-bar-track"><div class="conv-bar-fill" style="width:${r}%;opacity:${0.4+r/166}"></div></div><span class="conv-bar-val">${r}%</span>`;
    c.appendChild(bar);
  });
}

// ═══ BUILD EPOCH TABLES ═══
function buildEpochTables(){
  const container=document.getElementById('epoch-tables');
  if(!container) return;

  EPOCH_MILESTONES.forEach((m,idx)=>{
    const e = m.epoch || idx+1;
    const isFirst=idx===0;
    const section=document.createElement('div');
    section.id=`epoch-${e}`;
    section.className='epoch-block'+(isFirst?' open':'');

    const statusHtml=e<=5?'<span class="badge live"><span class="dot"></span> Open</span>':'<span class="badge upcoming">Upcoming</span>';

    const hdr=document.createElement('div');
    hdr.className='epoch-header';
    hdr.onclick=()=>section.classList.toggle('open');
    hdr.innerHTML=`
      <div class="epoch-header-left">
        <i data-lucide="chevron-right" class="epoch-chevron"></i>
        <strong>Epoch ${e}</strong>
        ${statusHtml}
      </div>
      <div class="epoch-header-right">
        <span class="epoch-meta" id="ep${e}-total-dsp">—</span>
        <span class="epoch-meta" id="ep${e}-total-cost">—</span>
      </div>`;

    const body=document.createElement('div');
    body.className='epoch-body';

    const fullEpochRow=`
      <div class="full-epoch-offer">
        <div class="feo-info">
          <strong><i data-lucide="layers" style="width:14px;height:14px;vertical-align:-2px;"></i> Full Epoch ${e}</strong>
          <span class="fg-muted" id="ep${e}-full-conv">—</span>
        </div>
        <div class="feo-price" id="ep${e}-full-price">—</div>
        <button class="btn btn-orange btn-sm btn-notify" onclick="openNotifyModal(${e},0,'epoch')"><i data-lucide="bell" style="width:14px;height:14px"></i> Notify Me</button>
      </div>`;

    let tgeRows='';
    for(let t=1;t<=10;t++){
      const conv=CONVERSION_RATES[t-1];
      const convClass=`c${conv}`;
      tgeRows+=`<tr>
        <td><strong>TDE ${t}</strong></td>
        <td><span class="conv-badge ${convClass}">${conv}%</span></td>
        <td id="ep${e}-tge${t}-alloc">—</td>
        <td><strong id="ep${e}-tge${t}-eff">—</strong></td>
        <td id="ep${e}-tge${t}-price">—</td>
        <td><button class="btn-notify-sm" onclick="openNotifyModal(${e},${t},'tge')"><i data-lucide="bell" style="width:12px;height:12px"></i> Notify</button></td>
      </tr>`;
    }

    body.innerHTML=fullEpochRow+`
      <div style="overflow-x:auto;margin-top:16px;">
        <table class="lt-table">
          <thead><tr><th>TDE</th><th>Conversion</th><th>Pool Size</th><th>Effective DSP</th><th>Initial Token Price</th><th></th></tr></thead>
          <tbody>${tgeRows}</tbody>
        </table>
      </div>`;

    section.appendChild(hdr);
    section.appendChild(body);
    container.appendChild(section);
  });
  lucide.createIcons();
}

function drawCharts(){
  drawChart('trajectory-canvas', trajectoryPoints, 'Initial $DIASPORA Token Price (log scale)');
  drawChart('projected-trajectory-canvas', projectedTrajectoryPoints, '$DIASPORA Price Floor (log scale)');
}

// ═══ TRAJECTORY CHART (Canvas) ═══
function drawChart(canvasId, points, titleLabel = 'Initial $DIASPORA Token Price (log scale)'){
  const canvas = document.getElementById(canvasId);
  if(!canvas || !points || points.length === 0) return;
  const parent = canvas.parentElement;
  if(!parent) return;
  
  const ctx = canvas.getContext('2d');
  const dpr = window.devicePixelRatio || 1;

  // Use clientWidth (excludes padding/border) to prevent canvas overflow
  const computedStyle = window.getComputedStyle(parent);
  const paddingLeft = parseFloat(computedStyle.paddingLeft) || 16;
  const paddingRight = parseFloat(computedStyle.paddingRight) || 16;
  const W = Math.max(parent.clientWidth - paddingLeft - paddingRight, 260);
  const H = W < 500 ? 280 : 340;

  canvas.width = W * dpr;
  canvas.height = H * dpr;
  canvas.style.width = W + 'px';
  canvas.style.height = H + 'px';
  ctx.scale(dpr, dpr);

  ctx.clearRect(0,0,W,H);

  const isMobile = W < 580;
  const pad = {
    t: 35,
    r: isMobile ? 25 : 55,
    b: isMobile ? 55 : 65,
    l: isMobile ? 45 : 65
  };
  const cW = W - pad.l - pad.r;
  const cH = H - pad.t - pad.b;

  const values = points.map(p=>p.impliedValue);
  const minVal = Math.min(...values) * 0.8;
  const maxVal = Math.max(...values) * 1.3;
  const logMin = Math.log10(Math.max(minVal, 0.0001));
  const logMax = Math.log10(maxVal);

  function xPos(i){ return pad.l + (i / Math.max(points.length - 1, 1)) * cW; }
  function yPos(v){
    const logV = Math.log10(Math.max(v, 0.0001));
    return pad.t + cH - ((logV - logMin) / (logMax - logMin)) * cH;
  }

  // Grid lines & Y Axis Ticks
  ctx.strokeStyle = 'rgba(255,255,255,0.08)';
  ctx.lineWidth = 1;
  for(let i = 0; i < points.length; i++){
    const x = xPos(i);
    ctx.beginPath(); ctx.moveTo(x, pad.t); ctx.lineTo(x, pad.t + cH); ctx.stroke();
  }

  const yTicks = [];
  for(let exp = Math.floor(logMin); exp <= Math.ceil(logMax); exp++){
    yTicks.push(Math.pow(10, exp));
  }
  ctx.font = (isMobile ? '10px' : '11px') + ' Inter, sans-serif';
  ctx.fillStyle = '#8c8f9e';
  ctx.textAlign = 'right';
  yTicks.forEach(v => {
    const y = yPos(v);
    if(y >= pad.t - 5 && y <= pad.t + cH + 5){
      ctx.beginPath(); ctx.moveTo(pad.l, y); ctx.lineTo(pad.l + cW, y); ctx.stroke();
      ctx.fillText(fmtPrice(v), pad.l - 6, y + 4);
    }
  });

  // Area Fill
  const grad = ctx.createLinearGradient(0, pad.t, 0, pad.t + cH);
  grad.addColorStop(0, 'rgba(229,147,58,0.28)');
  grad.addColorStop(1, 'rgba(229,147,58,0.02)');
  ctx.beginPath();
  ctx.moveTo(xPos(0), pad.t + cH);
  points.forEach((p, i) => ctx.lineTo(xPos(i), yPos(p.impliedValue)));
  ctx.lineTo(xPos(points.length - 1), pad.t + cH);
  ctx.closePath();
  ctx.fillStyle = grad;
  ctx.fill();

  // Line
  ctx.beginPath();
  ctx.strokeStyle = '#e5933a';
  ctx.lineWidth = isMobile ? 2 : 3;
  ctx.lineJoin = 'round';
  points.forEach((p, i) => {
    if(i === 0) ctx.moveTo(xPos(i), yPos(p.impliedValue));
    else ctx.lineTo(xPos(i), yPos(p.impliedValue));
  });
  ctx.stroke();

  // Points & Labels
  points.forEach((p, i) => {
    const x = xPos(i), y = yPos(p.impliedValue);
    ctx.beginPath(); ctx.arc(x, y, p.isLive ? 6 : (isMobile ? 3 : 4), 0, Math.PI * 2);
    ctx.fillStyle = p.isLive ? '#4caf50' : '#e5933a';
    ctx.fill();
    if(p.isLive){
      ctx.strokeStyle = '#4caf50'; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(x, y, 9, 0, Math.PI * 2); ctx.stroke();
    }

    // On mobile, show labels for key milestones (0, 4, 9, or live) to avoid overlapping text
    const showText = !isMobile || (i === 0 || i === 4 || i === 9 || p.isLive);
    if(showText){
      ctx.fillStyle = p.isLive ? '#4caf50' : '#e5933a';
      ctx.font = (isMobile ? 'bold 9px' : 'bold 10px') + ' Inter, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(fmtPrice(p.impliedValue), x, y - 8);
    }
    
    ctx.fillStyle = '#e5933a';
    ctx.font = (isMobile ? '9px' : '10px') + ' Inter, sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('E' + p.epoch, x, pad.t + cH + 16);

    if(p.gdp && p.circulating && showText){
      ctx.font = '8px Inter, sans-serif';
      ctx.fillStyle = '#8c8f9e';
      ctx.fillText(fmtUsd(p.gdp), x, pad.t + cH + 27);
    }
  });

  // Title & Live Badge
  ctx.fillStyle = '#8c8f9e';
  ctx.font = (isMobile ? '10px' : '11px') + ' Inter, sans-serif';
  ctx.textAlign = 'left';
  ctx.fillText(titleLabel, pad.l, pad.t - 12);

  if(trajectoryPoints[0]?.isLive && canvasId === 'trajectory-canvas'){
    ctx.fillStyle = '#4caf50';
    ctx.font = 'bold 10px Inter, sans-serif';
    ctx.textAlign = 'right';
    ctx.fillText('● LIVE', W - pad.r, pad.t - 12);
  }
}

// ═══ BUILD PRICE FLOOR BREAKDOWN TABLE ═══
function buildPriceFloorTable(){
  const container = document.getElementById('price-floor-table-container');
  if(!container || projectedTrajectoryPoints.length === 0) return;

  let rows = '';
  projectedTrajectoryPoints.forEach(p => {
    rows += `<tr>
      <td><strong>Epoch ${p.epoch}</strong></td>
      <td>${fmtUsd(p.gdp)}</td>
      <td>${fmtDsp(p.circulating)} $DIASPORA</td>
      <td><strong style="color:var(--orange);">${fmtPrice(p.impliedValue)} / token</strong></td>
    </tr>`;
  });

  container.innerHTML = `
    <div style="margin-top:20px;">
      <h4 style="font-size:14px; margin-bottom:12px; color:var(--fg-muted); text-align:center;">Formula: Dynamic Price Floor = Network Implied Baseline + (Platform Real GDP ÷ DEX Liquidity Treasury $DIASPORA Supply)</h4>
      <table class="lt-table" style="width:100%;">
        <thead>
          <tr>
            <th>Epoch</th>
            <th>Platform Real GDP</th>
            <th>DEX $DIASPORA Supply</th>
            <th>Price Floor ($DIASPORA)</th>
          </tr>
        </thead>
        <tbody>
          ${rows}
        </tbody>
      </table>
    </div>
  `;
}

// ═══ NOTIFICATION MODAL LOGIC ═══
let currentSelection={epoch:0,tge:0,type:''};

function openNotifyModal(epoch,tge,type){
  currentSelection={epoch,tge,type};

  const modal=document.getElementById('notify-modal');
  const title=document.getElementById('modal-title');
  const subtitle=document.getElementById('modal-subtitle');
  const preview=document.getElementById('notify-preview');
  const epVal = trajectoryPoints[epoch-1]?.impliedValue || liveValuation.impliedValue;

  if(type==='epoch'){
    const cost = treasuryPerEpoch(epoch) * epVal;
    title.textContent=`Get Notified: Epoch ${epoch}`;
    subtitle.textContent=`All 10 TDEs — ${fmtDsp(treasuryPerEpoch(epoch))} DSP total pool`;
    preview.innerHTML=`
      <div class="contract-line"><span>Pool Type</span><strong>Full Epoch ${epoch} — All 10 TDEs</strong></div>
      <div class="contract-line"><span>Total Pool Size</span><strong>${fmtDsp(treasuryPerEpoch(epoch))} DSP</strong></div>
      <div class="contract-line"><span>Avg Conversion</span><strong>55% (decile: 100%→10%)</strong></div>
      <div class="contract-line"><span>Initial Pool Value</span><strong>${fmtUsd(cost)}</strong></div>
      <div class="contract-line"><span>Initial DEX Token Price</span><strong>${fmtPrice(epVal)}</strong></div>
      <div class="contract-line"><span>Trading Pairs</span><strong>$DIASPORA/USDC • $DIASPORA/ETH</strong></div>
      <div class="contract-line"><span>DEX</span><strong>Aerodrome DEX on Base</strong></div>
      <div class="contract-line"><span>Lot Size</span><strong>Any amount — no minimum</strong></div>`;
  } else {
    const conv=CONVERSION_RATES[tge-1];
    const perTge = treasuryPerTge(epoch);
    const eff=Math.round(perTge*(conv/100));
    const cost = perTge * epVal;
    title.textContent=`Get Notified: Epoch ${epoch}, TDE ${tge}`;
    subtitle.textContent=`${conv}% conversion — ${fmtDsp(eff)} effective DSP in the pool`;
    preview.innerHTML=`
      <div class="contract-line"><span>TDE Drop</span><strong>Epoch ${epoch}, TDE ${tge}</strong></div>
      <div class="contract-line"><span>Pool Size</span><strong>${fmtDsp(perTge)} DSP</strong></div>
      <div class="contract-line"><span>Conversion Rate</span><strong>${conv}%</strong></div>
      <div class="contract-line"><span>Effective DSP</span><strong>${fmtDsp(eff)} DSP</strong></div>
      <div class="contract-line"><span>Initial Pool Value</span><strong>${fmtUsd(cost)}</strong></div>
      <div class="contract-line"><span>Initial DEX Token Price</span><strong>${fmtPrice(epVal)}</strong></div>
      <div class="contract-line"><span>Trading Pairs</span><strong>$DIASPORA/USDC • $DIASPORA/ETH</strong></div>
      <div class="contract-line"><span>DEX</span><strong>Aerodrome DEX on Base</strong></div>
      <div class="contract-line"><span>Lot Size</span><strong>Any amount — no minimum</strong></div>`;
  }

  // Reset form
  const emailInput = document.getElementById('notify-email');
  const agreeCheck = document.getElementById('notify-agree');
  const notifyBtn = document.getElementById('notify-btn');
  if(emailInput) emailInput.value = '';
  if(agreeCheck) agreeCheck.checked = false;
  if(notifyBtn) notifyBtn.disabled = true;

  document.getElementById('modal-step-1').style.display='';
  document.getElementById('modal-step-2').style.display='none';
  modal.classList.add('active');
  document.body.style.overflow='hidden';
  lucide.createIcons();
}

function validateNotifyForm(){
  const email = document.getElementById('notify-email')?.value?.trim();
  const agreed = document.getElementById('notify-agree')?.checked;
  const btn = document.getElementById('notify-btn');
  const valid = email && email.includes('@') && email.includes('.') && agreed;
  if(btn) btn.disabled = !valid;
}

function submitNotification(){
  const btn = document.getElementById('notify-btn');
  const email = document.getElementById('notify-email')?.value?.trim();
  if(!email) return;

  btn.innerHTML='<i data-lucide="loader" style="width:16px;height:16px;animation:spin 1s linear infinite;"></i> Registering...';
  btn.disabled = true;
  lucide.createIcons();

  // Write to Firestore
  const sel = currentSelection;
  const interestType = sel.type === 'epoch' ? `Epoch ${sel.epoch} (Full)` : `Epoch ${sel.epoch}, TDE ${sel.tge}`;

  if(typeof window._firestoreDb !== 'undefined' && window._firestoreDb){
    import('https://www.gstatic.com/firebasejs/10.12.0/firebase-firestore.js').then(({collection, addDoc, serverTimestamp})=>{
      addDoc(collection(window._firestoreDb, 'liquidity_interest'), {
        email: email,
        interest: interestType,
        epoch: sel.epoch,
        tge: sel.tge || 0,
        type: sel.type,
        createdAt: serverTimestamp(),
        source: 'landing_page'
      }).then(()=>showSuccess(email)).catch(()=>showSuccess(email));
    }).catch(()=>showSuccess(email));
  } else {
    // Fallback — just show success (Firebase not initialized yet)
    setTimeout(()=>showSuccess(email), 800);
  }
}

function showSuccess(email){
  document.getElementById('confirmed-email').textContent = email;
  document.getElementById('modal-step-1').style.display='none';
  document.getElementById('modal-step-2').style.display='';
  lucide.createIcons();
}

function closeModal(){
  document.getElementById('notify-modal').classList.remove('active');
  document.body.style.overflow='';
}

document.getElementById('notify-modal')?.addEventListener('click',function(e){ if(e.target===this) closeModal(); });

// ═══ INIT & RESIZE OBSERVER ═══
buildEpochTables();
computeTrajectory();
updateDynamicPricing();

if(typeof ResizeObserver !== 'undefined'){
  const chartObserver = new ResizeObserver(() => {
    requestAnimationFrame(drawCharts);
  });
  document.querySelectorAll('.chart-container').forEach(el => chartObserver.observe(el));
} else {
  window.addEventListener('resize', () => drawCharts());
}

