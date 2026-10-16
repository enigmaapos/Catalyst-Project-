const $ = (id) => document.getElementById(id);
const cfg = window.CATALYST_CONFIG || {};
const expectedChain = BigInt(cfg.chainId || 137);

async function connectWallet() {
  if (!window.ethereum || !window.ethers) {
    $("network").textContent = "A compatible EVM wallet and browser provider are required.";
    return;
  }
  try {
    const accounts = await window.ethereum.request({ method: "eth_requestAccounts" });
    const provider = new ethers.BrowserProvider(window.ethereum);
    const network = await provider.getNetwork();
    $("wallet").textContent = accounts[0];
    $("network").textContent = `Connected chain ID ${network.chainId}. ${network.chainId === expectedChain ? "Expected Polygon chain." : "Wrong network — switch networks before any interaction."}`;
    if (network.chainId !== expectedChain) {
      $("status").textContent = "Unsupported network";
      return;
    }
    const tokenAddress = cfg.contracts?.cata;
    if (tokenAddress && ethers.isAddress(tokenAddress) && tokenAddress !== ethers.ZeroAddress) {
      const code = await provider.getCode(tokenAddress);
      if (code === "0x") {
        $("status").textContent = "Configured token address has no contract code";
        return;
      }
      const token = new ethers.Contract(tokenAddress, [
        "function balanceOf(address) view returns (uint256)",
        "function decimals() view returns (uint8)"
      ], provider);
      const [raw, decimals] = await Promise.all([token.balanceOf(accounts[0]), token.decimals()]);
      $("balance").textContent = `${ethers.formatUnits(raw, decimals)} CATA`;
      $("status").textContent = "Token code detected; full release/implementation verification still required";
    } else {
      $("balance").textContent = "Address not configured";
      $("status").textContent = "Configuration required";
    }
  } catch (err) {
    $("network").textContent = `Wallet connection failed: ${err?.shortMessage || err?.message || "unknown error"}`;
  }
}
$("connect").addEventListener("click", connectWallet);
if (window.ethereum) {
  window.ethereum.on?.("chainChanged", () => location.reload());
  window.ethereum.on?.("accountsChanged", () => location.reload());
}
