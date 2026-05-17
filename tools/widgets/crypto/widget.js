// Crypto widget — BTC, ETH, SOL prices via CoinGecko free API (no key)
(function () {
  const COINS = [
    { id: 'bitcoin',   symbol: 'BTC', icon: '₿',  color: '#f59e0b' },
    { id: 'ethereum',  symbol: 'ETH', icon: 'Ξ',  color: '#818cf8' },
    { id: 'solana',    symbol: 'SOL', icon: '◎',  color: '#34d399' },
    { id: 'binancecoin', symbol: 'BNB', icon: 'B', color: '#fbbf24' },
    { id: 'ripple',    symbol: 'XRP', icon: '✕',  color: '#60a5fa' },
  ];

  const app = document.getElementById('app');
  let prevPrices = {};

  function arrow(change) {
    if (change > 0) return '<span style="color:#4ade80">▲</span>';
    if (change < 0) return '<span style="color:#f87171">▼</span>';
    return '<span style="color:#94a3b8">—</span>';
  }

  function fmt(n) {
    if (n >= 1000) return '$' + n.toLocaleString('en-US', { maximumFractionDigits: 0 });
    if (n >= 1)    return '$' + n.toFixed(2);
    return '$' + n.toFixed(4);
  }

  async function load() {
    const ids = COINS.map(c => c.id).join(',');
    const url = `https://api.coingecko.com/api/v3/simple/price?ids=${ids}&vs_currencies=usd&include_24hr_change=true`;
    try {
      const data = await yoloit.fetchJson(url);
      let html = `<div style="padding:12px">
        <div style="font-size:11px;color:#475569;margin-bottom:10px;text-align:right">
          🕐 ${new Date().toLocaleTimeString()}
        </div>`;
      for (const coin of COINS) {
        const info = data[coin.id];
        if (!info) continue;
        const price = info.usd;
        const change = info.usd_24h_change;
        const changeColor = change >= 0 ? '#4ade80' : '#f87171';
        html += `
          <div style="display:flex;align-items:center;justify-content:space-between;
                      padding:10px 12px;margin-bottom:6px;border-radius:8px;
                      background:#1e293b;border:1px solid #1e3a5f">
            <div style="display:flex;align-items:center;gap:10px">
              <span style="font-size:20px;color:${coin.color};font-weight:700">${coin.icon}</span>
              <div>
                <div style="font-size:13px;font-weight:600;color:#e2e8f0">${coin.symbol}</div>
                <div style="font-size:10px;color:#64748b">${coin.id}</div>
              </div>
            </div>
            <div style="text-align:right">
              <div style="font-size:14px;font-weight:700;color:#f1f5f9">${fmt(price)}</div>
              <div style="font-size:11px;color:${changeColor}">
                ${arrow(change)} ${Math.abs(change).toFixed(2)}% (24h)
              </div>
            </div>
          </div>`;
        prevPrices[coin.id] = price;
      }
      html += `<div style="text-align:center;font-size:10px;color:#334155;margin-top:8px">
        via CoinGecko · auto-refresh 60s</div></div>`;
      app.innerHTML = html;
    } catch (e) {
      app.innerHTML = `<div style="padding:16px;color:#f87171;font-size:13px">
        ⚠️ ${e.message}<br><span style="color:#64748b;font-size:11px">Check your network</span></div>`;
    }
  }

  yoloit.panel.setTitle('Crypto Prices');
  load();
  setInterval(load, 60 * 1000);
})();
