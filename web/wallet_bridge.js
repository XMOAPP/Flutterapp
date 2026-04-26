// XMO Wallet Bridge
// Handles EIP-1193 browser wallets (MetaMask, Brave, Coinbase) + WalletConnect v1

const XMO_WC_PROJECT_ID = 'aeb4b4a85b194d2c749a857947220b2d';

window.xmoWallet = {
  account: null,
  provider: null,
  wcProvider: null,

  // ── Detect which wallets are available ──────────────────────────────────────
  detectWallets: function () {
    const wallets = [];
    if (window.ethereum) {
      const providers = window.ethereum.providers || [window.ethereum];
      providers.forEach(function (p) {
        if (p.isMetaMask) wallets.push('MetaMask');
        else if (p.isBraveWallet) wallets.push('Brave Wallet');
        else if (p.isCoinbaseWallet) wallets.push('Coinbase Wallet');
        else wallets.push('Browser Wallet');
      });
    }
    wallets.push('WalletConnect');
    return JSON.stringify(wallets);
  },

  // ── Connect a wallet by name ────────────────────────────────────────────────
  connectBrowserWallet: async function (walletName) {
    if (walletName === 'WalletConnect') {
      return await this.connectWalletConnect();
    }

    if (!window.ethereum) {
      throw new Error('No browser wallet detected. Please install MetaMask or use WalletConnect.');
    }

    let targetProvider = window.ethereum;

    if (window.ethereum.providers && window.ethereum.providers.length > 1) {
      for (const p of window.ethereum.providers) {
        if (walletName === 'MetaMask' && p.isMetaMask) { targetProvider = p; break; }
        if (walletName === 'Brave Wallet' && p.isBraveWallet) { targetProvider = p; break; }
        if (walletName === 'Coinbase Wallet' && p.isCoinbaseWallet) { targetProvider = p; break; }
      }
    }

    const accounts = await targetProvider.request({ method: 'eth_requestAccounts' });
    if (!accounts || accounts.length === 0) throw new Error('No accounts returned from wallet.');

    this.account = accounts[0];
    this.provider = targetProvider;
    return this.account;
  },

  // ── WalletConnect connection (shows QR code modal) ──────────────────────────
  connectWalletConnect: async function () {
    // Check WalletConnectProvider loaded from CDN
    const WCProvider = window.WalletConnectProvider && window.WalletConnectProvider.default
      ? window.WalletConnectProvider.default
      : window.WalletConnectProvider;

    if (!WCProvider) {
      throw new Error(
        'WalletConnect library not loaded.\n' +
        'Please check your internet connection and reload the page.'
      );
    }

    // Disconnect any existing session first
    if (this.wcProvider) {
      try { await this.wcProvider.disconnect(); } catch (_) {}
      this.wcProvider = null;
    }

    // Create a new WalletConnect provider — opens QR code modal automatically
    this.wcProvider = new WCProvider({
      projectId: XMO_WC_PROJECT_ID,
      rpc: {
        1: 'https://cloudflare-eth.com',     // Ethereum mainnet
        137: 'https://polygon-rpc.com',      // Polygon
        56: 'https://bsc-dataseed.binance.org', // BSC
      },
      qrcodeModalOptions: {
        mobileLinks: [
          'rainbow', 'metamask', 'trust', 'coinbase',
          'ledger', 'argent', 'imtoken',
        ],
      },
    });

    // .enable() shows the QR code and resolves with accounts once connected
    const accounts = await this.wcProvider.enable();
    if (!accounts || accounts.length === 0) {
      throw new Error('No accounts returned from WalletConnect.');
    }

    this.account = accounts[0];
    this.provider = this.wcProvider;
    return this.account;
  },

  // ── Sign a SIWE-style message ────────────────────────────────────────────────
  signMessage: async function (message) {
    if (!this.provider || !this.account) {
      throw new Error('No wallet connected. Please connect first.');
    }
    const signature = await this.provider.request({
      method: 'personal_sign',
      params: [message, this.account],
    });
    return signature;
  },

  // ── Disconnect ───────────────────────────────────────────────────────────────
  disconnect: async function () {
    if (this.wcProvider) {
      try { await this.wcProvider.disconnect(); } catch (_) {}
      this.wcProvider = null;
    }
    this.account = null;
    this.provider = null;
  },

  isConnected: function () { return this.account !== null; },
  getAccount: function () { return this.account || ''; },
};
