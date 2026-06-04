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
function calculateImpliedValue({totalUsers=0, totalMinted=0, totalBurned=0, currentEpoch=1, fiatGdpUsd=0}={}){
  const networkMultiplier = totalUsers > 0 ? Math.log10(Math.max(totalUsers,1)) / 10 : 0;
  const rawDeflation = totalMinted > 0 ? totalBurned / totalMinted : 0;
  const deflationRatio = Math.min(rawDeflation, 0.5);
  const epochScarcity = 1.0 + (Math.max(currentEpoch,1) * 0.1);
  const fiatGdpBoost = fiatGdpUsd > 0 ? 1.0 + Math.log10(Math.max(fiatGdpUsd,1)) / 10 : 1.0;
  const impliedValue = BASE_PRICE_USD * (1.0 + networkMultiplier + deflationRatio) * epochScarcity * fiatGdpBoost;
  return { impliedValue, networkMultiplier, deflationRatio, epochScarcity, fiatGdpBoost,
           totalUsers, totalMinted, totalBurned, currentEpoch, fiatGdpUsd };
}

// ═══ LIVE DATA STATE ═══
let liveData = { totalUsers:0, totalMinted:0, totalBurned:0, currentEpoch:1, fiatGdpUsd:0 };
let liveValuation = calculateImpliedValue(liveData);
let trajectoryPoints = []; // {epoch, impliedValue} pairs for chart

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
  for(let e=1; e<=10; e++){
    const m = EPOCH_MILESTONES[e-1];
    const totalSupplyAtEpoch = Math.pow(10, e+5);
    const burnRate = 0.05;
    const fiatGdp = e === 1 ? Math.max(liveData.fiatGdpUsd, 100) : Math.pow(10, e+1) * 50;
    const val = calculateImpliedValue({
      totalUsers: m.users,
      totalMinted: totalSupplyAtEpoch,
      totalBurned: Math.floor(totalSupplyAtEpoch * burnRate * Math.min(e/5, 1)),
      currentEpoch: e,
      fiatGdpUsd: fiatGdp
    });
    trajectoryPoints.push({ epoch:e, impliedValue:val.impliedValue, users:m.users });
  }
  if(liveValuation.impliedValue > 0){
    trajectoryPoints[0].impliedValue = liveValuation.impliedValue;
    trajectoryPoints[0].isLive = true;
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
  setTextById('factor-gdp', liveValuation.fiatGdpBoost.toFixed(3)+'×');
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
    setTextById(`ep${e}-full-conv`, `All 10 TGEs • Avg ${avgConv}% conversion • ${fmtDsp(effectiveDspEpoch)} effective DSP`);
    setTextById(`ep${e}-full-price`, fmtUsd(epochCost));

    for(let t=1; t<=10; t++){
      const conv = CONVERSION_RATES[t-1];
      const effectiveDsp = Math.round(perTge * (conv/100));
      setTextById(`ep${e}-tge${t}-alloc`, fmtDsp(perTge));
      setTextById(`ep${e}-tge${t}-eff`, fmtDsp(effectiveDsp));
      setTextById(`ep${e}-tge${t}-price`, fmtUsd(tgeCost));
    }
  }
  drawTrajectoryChart();
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
    bar.innerHTML=`<span class="conv-bar-label">TGE ${i+1}</span><div class="conv-bar-track"><div class="conv-bar-fill" style="width:${r}%;opacity:${0.4+r/166}"></div></div><span class="conv-bar-val">${r}%</span>`;
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
        <td><strong>TGE ${t}</strong></td>
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
          <thead><tr><th>TGE</th><th>Conversion</th><th>Pool Size</th><th>Effective DSP</th><th>Implied Value</th><th></th></tr></thead>
          <tbody>${tgeRows}</tbody>
        </table>
      </div>`;

    section.appendChild(hdr);
    section.appendChild(body);
    container.appendChild(section);
  });
  lucide.createIcons();
}

// ═══ TRAJECTORY CHART (Canvas) ═══
function drawTrajectoryChart(){
  const canvas = document.getElementById('trajectory-canvas');
  if(!canvas || trajectoryPoints.length === 0) return;
  const ctx = canvas.getContext('2d');
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.parentElement.getBoundingClientRect();
  const W = rect.width;
  const H = 300;
  canvas.width = W * dpr;
  canvas.height = H * dpr;
  canvas.style.width = W + 'px';
  canvas.style.height = H + 'px';
  ctx.scale(dpr, dpr);

  ctx.clearRect(0,0,W,H);

  const pad = {t:30, r:60, b:50, l:70};
  const cW = W - pad.l - pad.r;
  const cH = H - pad.t - pad.b;

  const values = trajectoryPoints.map(p=>p.impliedValue);
  const minVal = Math.min(...values) * 0.8;
  const maxVal = Math.max(...values) * 1.3;
  const logMin = Math.log10(Math.max(minVal, 0.0001));
  const logMax = Math.log10(maxVal);

  function xPos(i){ return pad.l + (i/(trajectoryPoints.length-1))*cW; }
  function yPos(v){ const logV = Math.log10(Math.max(v, 0.0001)); return pad.t + cH - ((logV-logMin)/(logMax-logMin))*cH; }

  ctx.strokeStyle = 'rgba(150,150,150,0.15)';
  ctx.lineWidth = 1;
  for(let i=0;i<trajectoryPoints.length;i++){
    const x = xPos(i);
    ctx.beginPath(); ctx.moveTo(x, pad.t); ctx.lineTo(x, pad.t+cH); ctx.stroke();
  }
  const yTicks = [];
  for(let exp=Math.floor(logMin);exp<=Math.ceil(logMax);exp++){
    yTicks.push(Math.pow(10, exp));
  }
  ctx.font = '11px Inter, sans-serif';
  ctx.fillStyle = '#999';
  ctx.textAlign = 'right';
  yTicks.forEach(v=>{
    const y = yPos(v);
    if(y >= pad.t && y <= pad.t+cH){
      ctx.beginPath(); ctx.moveTo(pad.l, y); ctx.lineTo(pad.l+cW, y); ctx.stroke();
      ctx.fillText(fmtPrice(v), pad.l-8, y+4);
    }
  });

  const grad = ctx.createLinearGradient(0, pad.t, 0, pad.t+cH);
  grad.addColorStop(0, 'rgba(229,147,58,0.25)');
  grad.addColorStop(1, 'rgba(229,147,58,0.02)');
  ctx.beginPath();
  ctx.moveTo(xPos(0), pad.t+cH);
  trajectoryPoints.forEach((p,i)=> ctx.lineTo(xPos(i), yPos(p.impliedValue)));
  ctx.lineTo(xPos(trajectoryPoints.length-1), pad.t+cH);
  ctx.closePath();
  ctx.fillStyle = grad;
  ctx.fill();

  ctx.beginPath();
  ctx.strokeStyle = '#e5933a';
  ctx.lineWidth = 3;
  ctx.lineJoin = 'round';
  trajectoryPoints.forEach((p,i)=>{
    if(i===0) ctx.moveTo(xPos(i), yPos(p.impliedValue));
    else ctx.lineTo(xPos(i), yPos(p.impliedValue));
  });
  ctx.stroke();

  trajectoryPoints.forEach((p,i)=>{
    const x = xPos(i), y = yPos(p.impliedValue);
    ctx.beginPath(); ctx.arc(x, y, p.isLive?6:4, 0, Math.PI*2);
    ctx.fillStyle = p.isLive ? '#4caf50' : '#e5933a';
    ctx.fill();
    if(p.isLive){
      ctx.strokeStyle = '#4caf50'; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(x, y, 10, 0, Math.PI*2); ctx.stroke();
    }
    if(i===0||i===trajectoryPoints.length-1||i%2===0){
      ctx.fillStyle = p.isLive?'#4caf50':'#e5933a';
      ctx.font = 'bold 10px Inter, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(fmtPrice(p.impliedValue), x, y-12);
    }
  });

  ctx.fillStyle = '#999';
  ctx.font = '11px Inter, sans-serif';
  ctx.textAlign = 'center';
  trajectoryPoints.forEach((p,i)=>{
    ctx.fillText('E'+p.epoch, xPos(i), pad.t+cH+18);
  });

  ctx.fillStyle = '#666';
  ctx.font = '10px Inter, sans-serif';
  ctx.textAlign = 'left';
  ctx.fillText('Implied DSP Value (log scale)', pad.l, pad.t-12);

  if(trajectoryPoints[0]?.isLive){
    ctx.fillStyle = '#4caf50';
    ctx.font = 'bold 10px Inter, sans-serif';
    ctx.textAlign = 'right';
    ctx.fillText('● LIVE', W-pad.r, pad.t-12);
  }
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
    subtitle.textContent=`All 10 TGEs — ${fmtDsp(treasuryPerEpoch(epoch))} DSP total pool`;
    preview.innerHTML=`
      <div class="contract-line"><span>Pool Type</span><strong>Full Epoch ${epoch} — All 10 TGEs</strong></div>
      <div class="contract-line"><span>Total Pool Size</span><strong>${fmtDsp(treasuryPerEpoch(epoch))} DSP</strong></div>
      <div class="contract-line"><span>Avg Conversion</span><strong>55% (decile: 100%→10%)</strong></div>
      <div class="contract-line"><span>Implied Pool Value</span><strong>${fmtUsd(cost)}</strong></div>
      <div class="contract-line"><span>Unit Price (live)</span><strong>${fmtPrice(epVal)}</strong></div>
      <div class="contract-line"><span>Trading Pairs</span><strong>$DIASPORA/USDC • $DIASPORA/ETH</strong></div>
      <div class="contract-line"><span>DEX</span><strong>Uniswap V3 & Aerodrome on Base</strong></div>
      <div class="contract-line"><span>Lot Size</span><strong>Any amount — no minimum</strong></div>`;
  } else {
    const conv=CONVERSION_RATES[tge-1];
    const perTge = treasuryPerTge(epoch);
    const eff=Math.round(perTge*(conv/100));
    const cost = perTge * epVal;
    title.textContent=`Get Notified: Epoch ${epoch}, TGE ${tge}`;
    subtitle.textContent=`${conv}% conversion — ${fmtDsp(eff)} effective DSP in the pool`;
    preview.innerHTML=`
      <div class="contract-line"><span>TGE Drop</span><strong>Epoch ${epoch}, TGE ${tge}</strong></div>
      <div class="contract-line"><span>Pool Size</span><strong>${fmtDsp(perTge)} DSP</strong></div>
      <div class="contract-line"><span>Conversion Rate</span><strong>${conv}%</strong></div>
      <div class="contract-line"><span>Effective DSP</span><strong>${fmtDsp(eff)} DSP</strong></div>
      <div class="contract-line"><span>Implied Pool Value</span><strong>${fmtUsd(cost)}</strong></div>
      <div class="contract-line"><span>Unit Price (live)</span><strong>${fmtPrice(epVal)}</strong></div>
      <div class="contract-line"><span>Trading Pairs</span><strong>$DIASPORA/USDC • $DIASPORA/ETH</strong></div>
      <div class="contract-line"><span>DEX</span><strong>Uniswap V3 & Aerodrome on Base</strong></div>
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
  const interestType = sel.type === 'epoch' ? `Epoch ${sel.epoch} (Full)` : `Epoch ${sel.epoch}, TGE ${sel.tge}`;

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

// ═══ INIT ═══
buildConversionBars();
buildEpochTables();
computeTrajectory();
updateDynamicPricing();

// Handle resize for chart
window.addEventListener('resize', ()=>{ drawTrajectoryChart(); });
