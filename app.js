import { DEFAULT_CONFIG, STORAGE_KEY } from "./config.js";
import tokenAbi from "./abi/token.json" with { type: "json" };
import registryAbi from "./abi/registry.json" with { type: "json" };
import stakingAbi from "./abi/staking.json" with { type: "json" };
import governanceAbi from "./abi/governance.json" with { type: "json" };
import treasuryAbi from "./abi/treasury.json" with { type: "json" };
import guardianAbi from "./abi/guardian.json" with { type: "json" };

const { ethers } = window;
let provider=null, signer=null, account=null, cfg=loadConfig();

const $=id=>document.getElementById(id);
const short=a=>a?`${a.slice(0,6)}…${a.slice(-4)}`:"—";
const fmt=x=>{try{return ethers.formatUnits(x,18)}catch{return String(x)}};
const addr=x=>ethers.getAddress(x.trim());
function loadConfig(){try{return {...DEFAULT_CONFIG, addresses:{...DEFAULT_CONFIG.addresses,...JSON.parse(localStorage.getItem(STORAGE_KEY)||"{}").addresses}}}catch{return structuredClone(DEFAULT_CONFIG)}}
function saveConfig(){localStorage.setItem(STORAGE_KEY,JSON.stringify(cfg));}
function toast(msg){$("toast").textContent=msg;$("toast").classList.add("show");setTimeout(()=>$("toast").classList.remove("show"),5000)}
function requireWallet(){if(!signer)throw Error("Connect your wallet first.");}
function requireAddress(key){const a=cfg.addresses[key];if(!a||!ethers.isAddress(a))throw Error(`Configure a valid ${key} contract address first.`);return a}
function c(name,key,abi){return new ethers.Contract(requireAddress(key),abi,signer||provider)}
function readC(name,key,abi){return new ethers.Contract(requireAddress(key),abi,provider)}
function list(s){return s.split(",").map(x=>x.trim()).filter(Boolean)}
function nums(s){return list(s).map(x=>BigInt(x))}
function now(){return Math.floor(Date.now()/1000)}
function stateName(i){return ["Pending","Active","Defeated","Succeeded","Queued","Executable","Expired","Executed","Cancelled"][Number(i)]??String(i)}
function recoveryState(i){return ["Pending","Timelocked","Warning","Executable","Executed","Vetoed","Expired","Invalidated"][Number(i)]??String(i)}
async function tx(label,fn,preview=""){requireWallet(); if(preview){$("modalBody").innerHTML=`<p>${preview}</p><div class="result">${label}</div>`;$("modal").classList.remove("hidden");return new Promise((resolve,reject)=>{ $("modalCancel").onclick=()=>{ $("modal").classList.add("hidden"); reject(Error("Cancelled"))}; $("modalConfirm").onclick=async()=>{ $("modal").classList.add("hidden");try{toast("Waiting for wallet approval…");const t=await fn();toast(`Submitted: ${t.hash}`);const r=await t.wait();toast(`Confirmed: ${r.hash}`);resolve(r)}catch(e){toast(errorText(e));reject(e)}}})} try{toast("Waiting for wallet approval…");const t=await fn();toast(`Submitted: ${t.hash}`);const r=await t.wait();toast(`Confirmed: ${r.hash}`);return r}catch(e){toast(errorText(e));throw e}}
function errorText(e){return e?.shortMessage||e?.reason||e?.message||"Transaction failed."}
function setStatus(id,text,cls="warn"){$(id).textContent=text;$(id).className=`badge ${cls}`}
function showTab(tab){document.querySelectorAll(".tab").forEach(x=>x.classList.toggle("active",x.id===tab));document.querySelectorAll(".nav").forEach(x=>x.classList.toggle("active",x.dataset.tab===tab))}
document.querySelectorAll(".nav").forEach(x=>x.onclick=()=>showTab(x.dataset.tab));

async function connect(){
  if(!window.ethereum) return toast("No browser wallet detected. Open this DApp in MetaMask or another injected wallet.");
  provider=new ethers.BrowserProvider(window.ethereum); signer=await provider.getSigner(); account=await signer.getAddress();
  const net=await provider.getNetwork(); const cid=Number(net.chainId);
  $("walletAddress").textContent=account; $("networkName").textContent=`${net.name||"EVM"} (${cid})`;
  if(cid===Number(cfg.chainId)){setStatus("networkBadge","Polygon Amoy","ok");$("safetyBanner").classList.add("hidden")}
  else {setStatus("networkBadge",`Wrong network: ${cid}`,"bad");$("safetyBanner").textContent=`Fail-closed: configured for chain ${cfg.chainId}, connected to ${cid}. Switch networks before signing.`;$("safetyBanner").classList.remove("hidden")}
  await refresh();
}
$("connectBtn").onclick=()=>connect().catch(e=>toast(errorText(e)));

async function refresh(){
  if(!provider||!account)return;
  try{const t=readC("token","token",tokenAbi);const b=await t.balanceOf(account);$("cataBalance").textContent=fmt(b);$("heroBalance").textContent=fmt(b)}
  catch(e){$("cataBalance").textContent="—"}
  try{$("stakedCount").textContent=String(await readC("staking","staking",stakingAbi).walletStakedCount(account))}catch{$("stakedCount").textContent="—"}
  try{$("globalCapacity").textContent=String(await readC("staking","staking",stakingAbi).remainingGlobalCapacity())}catch{$("globalCapacity").textContent="—"}
  try{$("treasuryBalance").textContent=fmt(await readC("treasury","treasury",treasuryAbi).availableCATABalance());$("treasuryRead").textContent=fmt(await readC("treasury","treasury",treasuryAbi).availableCATABalance())}catch{}
  await integrity();
  try{const block=await provider.getBlockNumber();$("latestBlock").textContent=block;const g=readC("governance","governance",governanceAbi);$("votingUnits").textContent=fmt(await g.getVotingUnitsAt(account,block))}catch{}
  await loadGuardians();
}
async function integrity(){
  const rows=[["Token",cfg.addresses.token],["Registry",cfg.addresses.registry],["Staking",cfg.addresses.staking],["Governance",cfg.addresses.governance],["Treasury",cfg.addresses.treasury],["Guardian",cfg.addresses.guardian]];
  $("integrityList").innerHTML="";
  let good=true;
  for(const [n,a] of rows){let ok=false;if(ethers.isAddress(a)){try{ok=(await provider.getCode(a))!=="0x"}catch{}}good&&=ok;const d=document.createElement("div");d.className="status-row";d.innerHTML=`<span>${n}</span><strong>${ok?"✓ Code detected":"✕ Not verified"}</strong>`;$("integrityList").appendChild(d)}
  setStatus("integrityStatus",good?"Contract code detected":"Configuration incomplete",good?"ok":"warn");
}
async function loadGuardians(){
  try{const g=readC("guardian","guardian",guardianAbi);$("activeGuardians").innerHTML=(await g.getActiveGuardians()).map((a,i)=>`<div class="address">${i+1}. ${a}</div>`).join("");$("standbyGuardians").innerHTML=(await g.getStandbyGuardians()).map((a,i)=>`<div class="address">${i+1}. ${a}</div>`).join("")}catch{}
}

function bind(id,fn){$(id).onclick=()=>fn().catch(e=>toast(errorText(e)))}
bind("saveConfigBtn",async()=>{cfg.chainId=Number($("cfgChainId").value||80002);cfg.addresses.token=$("cfgToken").value.trim();cfg.addresses.registry=$("cfgRegistry").value.trim();cfg.addresses.staking=$("cfgStaking").value.trim();cfg.addresses.governance=$("cfgGovernance").value.trim();cfg.addresses.treasury=$("cfgTreasury").value.trim();cfg.addresses.guardian=$("cfgGuardian").value.trim();saveConfig();toast("Deployment configuration saved.");if(provider)await refresh()});
bind("clearConfigBtn",async()=>{localStorage.removeItem(STORAGE_KEY);cfg=structuredClone(DEFAULT_CONFIG);fillConfig();toast("Deployment configuration cleared.")});
function fillConfig(){ $("cfgChainId").value=cfg.chainId;$("cfgToken").value=cfg.addresses.token||"";$("cfgRegistry").value=cfg.addresses.registry||"";$("cfgStaking").value=cfg.addresses.staking||"";$("cfgGovernance").value=cfg.addresses.governance||"";$("cfgTreasury").value=cfg.addresses.treasury||"";$("cfgGuardian").value=cfg.addresses.guardian||""} fillConfig();

bind("stakeTermBtn",()=>tx("Stake Term",()=>c("staking","staking",stakingAbi).stakeTerm(addr($("stakeCollection").value),$("stakeTokenId").value),`Stake ${$("stakeTokenId").value} as Term NFT.`));
bind("stakePermanentBtn",()=>tx("Stake Permanent",()=>c("staking","staking",stakingAbi).stakePermanent(addr($("stakeCollection").value),$("stakeTokenId").value),`Stake ${$("stakeTokenId").value} permanently.`));
bind("batchTermBtn",()=>tx("Batch Term",()=>c("staking","staking",stakingAbi).batchStakeTerm(list($("batchCollections").value).map(addr),nums($("batchTokenIds").value)),"Batch term staking will custody the listed NFTs."));
bind("batchPermanentBtn",()=>tx("Batch Permanent",()=>c("staking","staking",stakingAbi).batchStakePermanent(list($("batchCollections").value).map(addr),nums($("batchTokenIds").value)),"Batch permanent staking will custody the listed NFTs."));
bind("harvestBtn",()=>tx("Harvest",()=>c("staking","staking",stakingAbi).harvest($("positionId").value),"Harvest accrued rewards. Exact fee allocation is enforced by the contract."));
bind("unstakeBtn",()=>tx("Unstake",()=>c("staking","staking",stakingAbi).unstake($("positionId").value),"Unstake and return the NFT subject to protocol rules."));
bind("batchHarvestBtn",()=>tx("Batch Harvest",()=>c("staking","staking",stakingAbi).batchHarvest(nums($("batchPositionIds").value)),"Batch harvest selected positions."));
bind("batchUnstakeBtn",()=>tx("Batch Unstake",()=>c("staking","staking",stakingAbi).batchUnstake(nums($("batchPositionIds").value)),"Batch unstake selected positions."));
bind("positionReadBtn",async()=>{requireWallet();const p=await readC("staking","staking",stakingAbi).getPosition($("positionId").value);const r=await readC("staking","staking",stakingAbi).pendingRewards($("positionId").value);$("positionResult").textContent=`Owner: ${p[0]}\nCollection: ${p[1]}\nToken ID: ${p[2]}\nType: ${Number(p[3])===0?"TERM":"PERMANENT"}\nStaked: ${new Date(Number(p[4])*1000).toLocaleString()}\nUnlock: ${Number(p[5])?new Date(Number(p[5])*1000).toLocaleString():"No scheduled end"}\nActive: ${p[7]}\nPending reward: ${fmt(r)} CATA`});

bind("tierReadBtn",async()=>{const a=addr($("tierCollection").value);const r=readC("registry","registry",registryAbi);const tier=["Unregistered","Unverified","Verified","Blue-Chip"][Number(await r.getCollectionTier(a))]||"Unknown";const m=await r.getCollectionMetrics(a);$("tierResult").textContent=`Tier: ${tier}\nDistinct wallets: ${m[0]}\nStake-days: ${m[1]}\nCATA burns (90d): ${fmt(m[2])}\nUnresolved incident: ${m[3]}\nEscrow deadline: ${Number(m[4])?new Date(Number(m[4])*1000).toLocaleString():"—"}\nEscrow settled: ${m[5]}`});
bind("blueFeeBtn",()=>tx("Blue-Chip wallet fee",async()=>{const token=c("token","token",tokenAbi);const reg=requireAddress("registry");const fee=await readC("registry","registry",registryAbi).BLUE_CHIP_WALLET_FEE();const allowance=await token.allowance(account,reg);if(allowance<fee){toast("Approval required first…");await (await token.approve(reg,fee)).wait()}return c("registry","registry",registryAbi).payBlueChipWalletFee(addr($("blueCollection").value))},`This spends the configured Blue-Chip wallet fee (50 CATA in v1.2).`));

bind("proposalReadBtn",async()=>{const g=readC("governance","governance",governanceAbi),id=$("proposalId").value,p=await g.getProposal(id);$("proposalResult").textContent=`State: ${stateName(await g.state(id))}\nProposer: ${p[1]}\nDescription: ${p[5]}\nSnapshot block: ${p[6]}\nSnapshot units: ${p[7]}\nStart: ${new Date(Number(p[8])*1000).toLocaleString()}\nEnd: ${new Date(Number(p[9])*1000).toLocaleString()}\nFor: ${p[10]}\nAgainst: ${p[11]}\nQueued: ${p[12]}\nExecutable: ${p[13]}\nDeadline: ${p[14]}\nExecuted: ${p[15]}\nCancelled: ${p[16]}`});
bind("voteForBtn",()=>tx("Vote For",()=>c("governance","governance",governanceAbi).vote($("proposalId").value,true),"Vote For is irreversible once confirmed."));
bind("voteAgainstBtn",()=>tx("Vote Against",()=>c("governance","governance",governanceAbi).vote($("proposalId").value,false),"Vote Against is irreversible once confirmed."));
bind("queueBtn",()=>tx("Queue Proposal",()=>c("governance","governance",governanceAbi).queue($("proposalId").value),"Queue only after the proposal has succeeded."));
bind("executeBtn",()=>tx("Execute Proposal",()=>c("governance","governance",governanceAbi).execute($("proposalId").value),"Execute only when the governance timelock and execution window permit it."));
bind("proposeBtn",()=>tx("Create Proposal",()=>c("governance","governance",governanceAbi).propose(list($("propTargets").value).map(addr),nums($("propValues").value),list($("propCalldata").value),$("propDescription").value),"Governance proposal submission."));
bind("recoveryReadBtn",async()=>{const g=readC("guardian","guardian",guardianAbi),id=$("recoveryId").value,p=await g.getRecovery(id);$("recoveryResult").textContent=`State: ${recoveryState(await g.getRecoveryState(id))}\nProposer: ${p[1]}\nTarget: ${p[2]}\nCalldata hash: ${p[3]}\nChain ID: ${p[4]}\nCouncil: ${p[5]}\nNonce: ${p[6]}\nCreation block: ${p[7]}\nTimelock: ${new Date(Number(p[9])*1000).toLocaleString()}\nWarning: ${p[10]?new Date(Number(p[10])*1000).toLocaleString():"—"}\nExpiry: ${new Date(Number(p[11])*1000).toLocaleString()}\nApprovals: ${p[12]}\nExecuted: ${p[13]}\nVetoed: ${p[14]}\nInvalidated: ${p[15]}\nData: ${p[16]}`});
bind("recoveryApproveBtn",()=>tx("Approve Recovery",()=>c("guardian","guardian",guardianAbi).approveRecovery($("recoveryId").value),"Guardian approval may advance the recovery threshold state."));
bind("recoveryExecuteBtn",()=>tx("Execute Recovery",()=>c("guardian","guardian",guardianAbi).executeRecovery($("recoveryId").value),"Ordinary recovery cannot bypass the mandatory four-hour timelock."));
bind("recoveryVetoBtn",()=>tx("Veto Recovery",()=>c("guardian","guardian",guardianAbi).vetoRecovery($("recoveryId").value),"Veto is an irreversible recovery action."));
bind("recoveryExpireBtn",()=>tx("Mark Expired",()=>c("guardian","guardian",guardianAbi).markExpired($("recoveryId").value),"Mark a recovery proposal expired when its rules permit."));
bind("recoveryProposeBtn",()=>tx("Propose Recovery",()=>c("guardian","guardian",guardianAbi).proposeRecovery(addr($("recoveryTarget").value),$("recoveryData").value),"Recovery proposal payload will be bound to its target, calldata hash, chain ID, council and nonce."));

bind("treasuryRefreshBtn",async()=>{$("treasuryRead").textContent=fmt(await readC("treasury","treasury",treasuryAbi).availableCATABalance());toast("Treasury refreshed.")});
